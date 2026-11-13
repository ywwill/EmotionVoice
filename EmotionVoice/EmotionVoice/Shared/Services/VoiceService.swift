//
//  VoiceService.swift
//  EmotionVoice
//
//  Created by young on 2026/8/8.
//

import Foundation
import SQLite

/// 音色数据服务
///
/// 筛选一律基于语义 code 列（tier / lang_code / scene_key / age / gender_code），
/// 与界面语言无关；搜索则同时覆盖中英文字段，保证两种语言下都能搜到。
final class VoiceService {

    static let shared = VoiceService()

    private let db = DatabaseManager.shared

    private init() {
        // 音色表被重建后缓存必须失效，否则会一直读到旧对象（尤其是 isFavorite）
        NotificationCenter.default.addObserver(
            forName: .voicesDidReload,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.invalidateVoiceCache()
        }
    }

    /// key -> 展示名 的缓存。列表行与播放详情过去是 `fetchAll().first(where:)`，
    /// 每次 body 求值都做一次全表扫描 + 全量排序；播放详情 10Hz 重绘时这会把主线程打满。
    private let nameCache = NSCache<NSString, NSString>()

    /// key -> Voice 对象 的缓存（`NSCache` 只装类，故包一层）。
    ///
    /// ⚠️ `VoiceStudioViewModel.voice` 过去是 `fetchAll().first(where:)`，
    /// 而它是 SwiftUI body 里的计算属性 —— 每一次 body 求值（打字、切标签、任何
    /// `@Published` 写入）都会全表扫描 + 全量排序一遍。音色表约 100 行时单次几毫秒，
    /// 但叠在每一帧上就是肉眼可见的卡顿。
    private let voiceCache = NSCache<NSString, VoiceBox>()

    /// 查询签名 -> 「过滤 + 排序」后的有序 key 列表（进程级）。
    ///
    /// 把结果缓存到服务层：VM 只持有 [String] 切片，翻页 / 切分类 / 切页回来都直接命中，
    /// 不重复跑全表读取 + 本地化排序（约 900 行、全在主线程同步）。
    /// 缓存有效性由 `cacheGeneration()` 自动判定（表行数 / 收藏数 / 语言任一变化即失效）。
    /// 无搜索词时由 `orderedKeysWithoutSearch` 计算，避免构造完整 Voice 对象。
    private var orderedKeysCache: [String: [String]] = [:]
    private var orderedKeysGeneration: String = ""
    /// `cacheGeneration()` 的结果缓存。它本身是 2 次 SQL COUNT + 一次 Bundle 查询，
    /// 每次 `cachedOrderedKeys` / `cachedCategoryCounts` 都重算没必要；
    /// 失效统一由 `invalidateVoiceCache()` 负责（表重建 / 收藏变更都会调到）。
    private var generationCache: String = ""

    /// 全量 chip 计数快照（分类计数恒为全量、与搜索词无关）。
    /// 首屏 `reloadChipCounts()` 原本要跑「1 次全部 + 每个分类 1 次 + 收藏 1 次」
    /// 约 29 次 SQL COUNT，每次都可能全表扫描，且全部在主线程同步。
    /// 计数只随表重建 / 收藏变化，进程级缓存一次即可。
    private var chipCountsSnapshot: (generation: String, all: Int, favorites: Int, counts: [String: Int])?

    private func cacheGeneration() -> String {
        if !generationCache.isEmpty { return generationCache }
        let total = (try? db.db.scalar(db.voices.count)) ?? -1
        let favorites = (try? db.db.scalar(db.voices.filter(db.voiceIsFavorite == true).count)) ?? -1
        let language = Bundle.main.preferredLocalizations.joined(separator: ",")
        let result = "\(total)/\(favorites)/\(language)"
        generationCache = result
        return result
    }

    /// 启动空闲期预热音色库数据缓存。
    ///
    /// 与视图是否可见完全无关，因此即使 `VoicesLibraryView.onAppear` 因
    /// `opacity(0)` 未如预期触发，首次真正进入时最贵的两步也已算完：
    /// - 「全部」有序 key 列表（全表读最小列 + 本地化排序，顺带把 VoiceCatalog
    ///   词条缓存填热，后续构造 Voice 对象不再反复查 Bundle）；
    /// - 全量 chip 计数（约 29 次 SQL COUNT）。
    /// VM 的 `load()` 到这里只剩「取当前页这一窗 Voice 对象」。
    func warmUpVoiceLibraryCache() {
        _ = cachedOrderedKeys(showingFavorites: false, category: nil, searchText: "")
        _ = cachedCategoryCounts()
    }

    /// 音色库 chip 的全量计数（一次算齐，之后命中缓存零 SQL）。
    /// 由 `VoicesLibraryViewModel.reloadChipCounts()` 调用；收藏数单独保留在返回值里，
    /// 但 VM 的 `toggleFavorite` 仍走 `countFavorites()` 单次查询以拿最新值。
    func cachedCategoryCounts() -> (all: Int, favorites: Int, counts: [String: Int]) {
        let generation = cacheGeneration()
        if let hit = chipCountsSnapshot, hit.generation == generation {
            return (hit.all, hit.favorites, hit.counts)
        }
        let all = count(category: nil, searchText: "")
        let favorites = countFavorites()
        var counts: [String: Int] = [:]
        counts.reserveCapacity(VoiceCategory.allCases.count)
        for cat in VoiceCategory.allCases {
            counts[cat.rawValue] = count(category: cat, searchText: "")
        }
        chipCountsSnapshot = (generation, all, favorites, counts)
        return (all, favorites, counts)
    }

    /// 供分页 VM 使用：只返回有序 key 列表，不构造 Voice 对象。
    func cachedOrderedKeys(showingFavorites: Bool, category: VoiceCategory?, searchText: String) -> [String] {
        let generation = cacheGeneration()
        if generation != orderedKeysGeneration {
            orderedKeysCache.removeAll(keepingCapacity: true)
            orderedKeysGeneration = generation
        }
        let needle = searchText.trimmingCharacters(in: .whitespaces)
        let key = "\(showingFavorites ? 1 : 0)|\(category?.rawValue ?? "__all__")|\(needle)"
        if let hit = orderedKeysCache[key] { return hit }
        // 无搜索词（首屏 / 切分类 / 翻页的绝大多数情况）走快路径：
        // 不构造 Voice 对象，只读排序所需的最小列。
        let keys = needle.isEmpty
            ? orderedKeysWithoutSearch(showingFavorites: showingFavorites, category: category)
            : orderedVoices(showingFavorites: showingFavorites,
                            category: category,
                            searchText: needle).map(\.key)
        orderedKeysCache[key] = keys
        return keys
    }

    /// 构造「收藏 / 分类」基础查询（搜索在内存中做，见 matchesSearch）
    private func baseQuery(showingFavorites: Bool, category: VoiceCategory?) -> SQLite.QueryType {
        if showingFavorites {
            return db.voices.filter(db.voiceIsFavorite == true)
        }
        if let pred = predicate(category: category) {
            return db.voices.filter(pred)
        }
        return db.voices
    }

    /// 无搜索词时的「有序 key 列表」快路径。
    ///
    /// ⚠️ 不要走 `rowToVoice`：它每行要读 4 次 VoiceCatalog 文案并构造完整 Voice
    /// （还要解析 scene / lang / gender 枚举），而这里只需要 key 与排序依据
    /// （旗舰优先、当前语言展示名字典序）。音色表约 900 行时，省掉一半查表与
    /// 全部对象分配 —— 这是首屏同步加载最主要的耗时。
    /// 有搜索词必须回退 `orderedVoices`，因为 matchesSearch 还要比对特质 / 场景 / 语种。
    private func orderedKeysWithoutSearch(showingFavorites: Bool, category: VoiceCategory?) -> [String] {
        do {
            let rows = try db.db.prepare(baseQuery(showingFavorites: showingFavorites,
                                                   category: category))
                .map { row -> (key: String, premium: Bool, sortName: String) in
                    let stem = (row[db.voiceAudio] as NSString).deletingPathExtension
                    // 直接按界面语言取名，与 Voice.localizedName 的展示名同源：
                    // 原本这里只排中 / 英两套，五语言界面下排序会与实际显示不一致。
                    // 顺带少读一次 VoiceCatalog 词条。
                    let sortName = VoiceCatalog.localizedVoiceNameForInterface(stem: stem)
                    return (row[db.voiceKey],
                            row[db.voiceTier] == VoiceTier.premium.rawValue,
                            sortName)
                }
            return rows.sorted { a, b in
                if a.premium != b.premium { return a.premium }
                return a.sortName.localizedStandardCompare(b.sortName) == .orderedAscending
            }.map(\.key)
        } catch {
            Log(message: "VoiceService.orderedKeysWithoutSearch error: \(error)")
            return []
        }
    }

    // MARK: - 按 key 取展示名（带缓存）

    /// 取单个音色的展示名。
    /// - Parameter key: 音色 key（AudioItem.voice 存的就是它）
    /// - Returns: 当前语言的展示名；key 为空或查不到时返回 nil
    func displayName(forKey key: String) -> String? {
        guard !key.isEmpty else { return nil }
        let cacheKey = key as NSString
        if let cached = nameCache.object(forKey: cacheKey) {
            return cached as String
        }
        guard let voice = fetchByKeys([key]).first else { return nil }
        nameCache.setObject(voice.localizedName as NSString, forKey: cacheKey)
        return voice.localizedName
    }

    // MARK: - 全量

    /// 获取所有音色（按当前语言的展示名排序）
    func fetchAll() -> [Voice] {
        do {
            let rows = try db.db.prepare(db.voices).map { Self.rowToVoice($0, db: db) }
            return Self.sorted(rows)
        } catch {
            Log(message: "VoiceService.fetchAll error: \(error)")
            return []
        }
    }

    /// 按 key 取单个音色（带缓存）。
    ///
    /// 给 SwiftUI body 里的计算属性用：命中缓存后是常数时间，不再每次重绘全表扫描。
    func voice(forKey key: String) -> Voice? {
        guard !key.isEmpty else { return nil }
        let cacheKey = key as NSString
        if let hit = voiceCache.object(forKey: cacheKey) { return hit.value }
        guard let voice = fetchByKeys([key]).first else { return nil }
        voiceCache.setObject(VoiceBox(voice), forKey: cacheKey)
        return voice
    }

    /// 音色数据变了（表重建 / 收藏变更）后清空缓存
    func invalidateVoiceCache() {
        voiceCache.removeAllObjects()
        nameCache.removeAllObjects()
        orderedKeysCache.removeAll(keepingCapacity: true)
        orderedKeysGeneration = ""
        generationCache = ""
        chipCountsSnapshot = nil
    }

    /// 按分类获取
    func fetch(by category: VoiceCategory) -> [Voice] {
        fetchAll().filter { category.matches($0) }
    }

    // MARK: - 分页查询（按分类 + 搜索文本）

    /// 按分类+搜索文本查询总数
    ///
    /// ⚠️ 无搜索词时直接下推 SQL COUNT。旧实现 `prepare(query).map { rowToVoice }`
    /// 把整张音色表读成对象再在应用层 `.filter.count`：`rowToVoice` 每行要做 4 次
    /// VoiceCatalog 本地化查表，音色库首屏一轮 chip 计数会跑 ~29 次全表对象化，
    /// 全部在主线程同步执行 —— 这是切到音色库时 CPU / 内存尖峰的主要来源。
    /// 搜索词非空时仍走内存匹配（要覆盖当前语言的名 / 特质 / 场景 / 语种，无法直接下推 SQL）。
    func count(category: VoiceCategory?, searchText: String) -> Int {
        do {
            var query = db.voices
            if let pred = predicate(category: category) {
                query = query.filter(pred)
            }
            let needle = searchText.trimmingCharacters(in: .whitespaces)
            if needle.isEmpty {
                return Int(try db.db.scalar(query.count))
            }
            let all = try db.db.prepare(query).map { Self.rowToVoice($0, db: db) }
            return all.filter { Self.matchesSearch($0, needle) }.count
        } catch {
            Log(message: "VoiceService.count error: \(error)")
            return 0
        }
    }

    /// 返回「过滤 + 排序」后的完整有序数组（不做 LIMIT/OFFSET 切片）。
    ///
    /// 排序规则统一为「旗舰优先，其次按当前语言的展示名」：
    /// SQLite 无法按「当前语言的展示名」排序，因此先取命中集合、内存排序后一次性返回。
    /// 分页 VM 会缓存此结果，翻页时只做切片，避免每次翻页都全表重查 + 全量排序
    /// （快速连点翻页时这正是 CPU / 内存飙升的根因）。
    func orderedVoices(showingFavorites: Bool, category: VoiceCategory?, searchText: String) -> [Voice] {
        do {
            let rows = try db.db.prepare(baseQuery(showingFavorites: showingFavorites,
                                                   category: category))
                .map { Self.rowToVoice($0, db: db) }
            let filtered = rows.filter { Self.matchesSearch($0, searchText) }
            return Self.sorted(filtered)
        } catch {
            Log(message: "VoiceService.orderedVoices error: \(error)")
            return []
        }
    }

    /// 仅按 key 列表取对应的 Voice 对象，并**严格保持传入 keys 的顺序**。
    /// 用于分页：翻页只取当前这一窗（pageSize 个）的对象，上一页的对象不被保留，内存稳定。
    func fetchByKeys(_ keys: [String]) -> [Voice] {
        guard !keys.isEmpty else { return [] }
        do {
            let rows = try db.db.prepare(db.voices.filter(keys.contains(db.voiceKey)))
                .map { Self.rowToVoice($0, db: db) }
            let dict = Dictionary(uniqueKeysWithValues: rows.map { ($0.key, $0) })
            return keys.compactMap { dict[$0] }
        } catch {
            Log(message: "VoiceService.fetchByKeys error: \(error)")
            return []
        }
    }

    /// 展示顺序：旗舰音色优先，其余按当前语言的展示名字典序
    private static func sorted(_ voices: [Voice]) -> [Voice] {
        voices.sorted { a, b in
            if a.isPremium != b.isPremium { return a.isPremium }
            return a.sortKey.localizedStandardCompare(b.sortKey) == .orderedAscending
        }
    }

    // MARK: - 收藏

    /// 收藏总数
    func countFavorites() -> Int {
        countFavorites(searchText: "")
    }

    /// 按收藏+搜索文本查询总数（无搜索词时同样下推 SQL COUNT）
    func countFavorites(searchText: String) -> Int {
        do {
            let query = db.voices.filter(db.voiceIsFavorite == true)
            let needle = searchText.trimmingCharacters(in: .whitespaces)
            if needle.isEmpty {
                return Int(try db.db.scalar(query.count))
            }
            let all = try db.db.prepare(query).map { Self.rowToVoice($0, db: db) }
            return all.filter { Self.matchesSearch($0, needle) }.count
        } catch {
            Log(message: "VoiceService.countFavorites error: \(error)")
            return 0
        }
    }

    // MARK: - WHERE 子句构造

    /// 构造分类的 WHERE 子句（仅语义 code，与语言无关）
    /// - Returns: nil 表示无过滤条件；Expression<Bool>(value: false) 表示永远无匹配
    ///
    /// 注：搜索不再下推到 SQL —— 文案列已从库里移除，搜索在内存中对「当前语言」的
    /// 名 / 特质 / 场景 / 语种做匹配（见 matchesSearch）。仅做字符串包含匹配，
    private func predicate(category: VoiceCategory?) -> SQLite.Expression<Bool>? {
        guard let category = category else { return nil }
        guard let pred = categoryPredicate(category) else {
            return SQLite.Expression<Bool>(value: false)
        }
        return pred
    }

    /// 内存搜索：命中当前语言的名 / 特质，或场景 / 语种的中文名
    private static func matchesSearch(_ v: Voice, _ searchText: String) -> Bool {
        let needle = searchText.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return true }
        if v.localizedName.localizedCaseInsensitiveContains(needle) { return true }
        if v.localizedDesc.localizedCaseInsensitiveContains(needle) { return true }
        if v.scene.displayName.localizedCaseInsensitiveContains(needle) { return true }
        if v.lang.displayName.localizedCaseInsensitiveContains(needle) { return true }
        return false
    }

    /// 将 VoiceCategory 翻译为 SQL 谓词（与 VoiceCategory.matches(_:) 行为对齐）
    private func categoryPredicate(_ category: VoiceCategory) -> SQLite.Expression<Bool>? {
        switch category {
        case .premium:
            return db.voiceTier == VoiceTier.premium.rawValue

        // 场景：直接比 code
        case .sceneDaily:      return db.voiceSceneKey == VoiceSceneCode.daily.rawValue
        case .sceneCompanion:  return db.voiceSceneKey == VoiceSceneCode.companion.rawValue
        case .sceneReading:    return db.voiceSceneKey == VoiceSceneCode.reading.rawValue
        case .sceneCustomer:   return db.voiceSceneKey == VoiceSceneCode.customerService.rawValue
        case .sceneSocial:     return db.voiceSceneKey == VoiceSceneCode.social.rawValue
        case .sceneAnime:      return db.voiceSceneKey == VoiceSceneCode.anime.rawValue
        case .sceneNews:       return db.voiceSceneKey == VoiceSceneCode.news.rawValue
        case .sceneLive:       return db.voiceSceneKey == VoiceSceneCode.liveStream.rawValue
        case .sceneClassic:    return db.voiceSceneKey == VoiceSceneCode.classicAudiobook.rawValue
        case .sceneSports:     return db.voiceSceneKey == VoiceSceneCode.sports.rawValue
        case .sceneAudiobook:  return db.voiceSceneKey == VoiceSceneCode.audiobook.rawValue
        case .sceneRadio:      return db.voiceSceneKey == VoiceSceneCode.radio.rawValue
        case .sceneKnowledge:  return db.voiceSceneKey == VoiceSceneCode.knowledge.rawValue
        case .sceneComedy:     return db.voiceSceneKey == VoiceSceneCode.comedy.rawValue
        case .sceneBusiness:   return db.voiceSceneKey == VoiceSceneCode.business.rawValue
        case .sceneAssistant:  return db.voiceSceneKey == VoiceSceneCode.assistant.rawValue
        case .sceneSpeech:     return db.voiceSceneKey == VoiceSceneCode.speech.rawValue

        // 角色：由场景 code 派生
        case .roleAnime:   return db.voiceSceneKey == VoiceSceneCode.anime.rawValue
        case .roleLive:    return db.voiceSceneKey == VoiceSceneCode.liveStream.rawValue
        case .roleClassic: return db.voiceSceneKey == VoiceSceneCode.classicAudiobook.rawValue
        case .roleRadio:   return db.voiceSceneKey == VoiceSceneCode.radio.rawValue

        // 年龄区间
        case .ageChild:  return db.voiceAge < 13
        case .ageTeen:   return db.voiceAge >= 13 && db.voiceAge < 18
        case .ageYoung:  return db.voiceAge >= 18 && db.voiceAge < 36
        case .ageMiddle: return db.voiceAge >= 36 && db.voiceAge < 60
        case .ageSenior: return db.voiceAge >= 60
        }
    }

    // MARK: - Row 映射

    /// 将 SQLite Row 转为 Voice
    ///
    /// 文案（名 / 特质）已从库里移除，这里按 audio 文件名的 stem 从 VoiceCatalog.strings
    /// 读取「中文」与「当前界面语言」两套，烘焙进 Voice —— 项目约定跟随系统语言、
    /// 无 App 内切换，切语言需重启，因此进程内读一次即可。
    ///
    /// ⚠️ `nameEn` / `descEn` 沿用旧字段名，实际装的是「当前界面语言的非中文文案」：
    /// 英文界面取 en，法 / 德 / 日 / 韩 / 俄界面取各自的重新命名与特质译文。
    /// `Voice.localizedName` 仍按 `isChinese ? name : nameEn` 二值切换，下游无需改动。
    private static func rowToVoice(_ row: Row, db: DatabaseManager) -> Voice {
        let rawAge = row[db.voiceAge]
        let audio = row[db.voiceAudio]
        let stem = (audio as NSString).deletingPathExtension

        let nameZh = VoiceCatalog.localizedVoiceName(stem: stem, language: .zh)
        let nameLocalized = VoiceCatalog.localizedVoiceNameForInterface(stem: stem)
        let featZhRaw = VoiceCatalog.localizedVoiceFeature(stem: stem, language: .zh)
        let featLocalized = VoiceCatalog.localizedVoiceFeatureForInterface(stem: stem)
        // 中文特质去掉冗余的"音"字
        let featZh = featZhRaw.hasSuffix("音") ? String(featZhRaw.dropLast()) : featZhRaw

        return Voice(
            key: row[db.voiceKey],
            name: nameZh,
            nameEn: nameLocalized,
            desc: featZh,
            descEn: featLocalized,
            tier: VoiceTier(code: row[db.voiceTier]),
            isFavorite: row[db.voiceIsFavorite],
            scene: VoiceSceneCode(code: row[db.voiceSceneKey]),
            age: rawAge > 0 ? rawAge : nil,
            gender: VoiceGenderCode(code: row[db.voiceGenderCode]),
            audio: audio,
            lang: VoiceLangCode(code: row[db.voiceLangCode])
        )
    }

    /// 切换收藏
    @discardableResult
    func toggleFavorite(key: String) -> Bool {
        do {
            let row = try db.db.pluck(db.voices.filter(db.voiceKey == key))
            guard let row else { return false }
            let newValue = !row[db.voiceIsFavorite]
            try db.db.run(db.voices.filter(db.voiceKey == key).update(db.voiceIsFavorite <- newValue))
            invalidateVoiceCache()
            return newValue
        } catch {
            Log(message: "VoiceService.toggleFavorite error: \(error)")
            return false
        }
    }
}

// MARK: - 缓存装箱

/// `NSCache` 只接受类，`Voice` 是结构体，故包一层
private final class VoiceBox {
    let value: Voice
    init(_ value: Voice) { self.value = value }
}
