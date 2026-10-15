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

    /// key -> 展示名 的缓存。列表行与播放详情过去是 `fetchAll().first(where:)`，
    /// 每次 body 求值都做一次全表扫描 + 全量排序；播放详情 10Hz 重绘时这会把主线程打满。
    private let nameCache = NSCache<NSString, NSString>()

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

    /// 按分类获取
    func fetch(by category: VoiceCategory) -> [Voice] {
        fetchAll().filter { category.matches($0) }
    }

    // MARK: - 分页查询（按分类 + 搜索文本）

    /// 按分类+搜索文本查询总数
    func count(category: VoiceCategory?, searchText: String) -> Int {
        do {
            var query = db.voices
            if let pred = predicate(category: category) {
                query = query.filter(pred)
            }
            let all = try db.db.prepare(query).map { Self.rowToVoice($0, db: db) }
            return all.filter { Self.matchesSearch($0, searchText) }.count
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
            let query: SQLite.QueryType
            if showingFavorites {
                query = db.voices.filter(db.voiceIsFavorite == true)
            } else if let pred = predicate(category: category) {
                query = db.voices.filter(pred)
            } else {
                query = db.voices
            }

            let rows = try db.db.prepare(query).map { Self.rowToVoice($0, db: db) }
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

    /// 按收藏+搜索文本查询总数
    func countFavorites(searchText: String) -> Int {
        do {
            let query = db.voices.filter(db.voiceIsFavorite == true)
            let all = try db.db.prepare(query).map { Self.rowToVoice($0, db: db) }
            return all.filter { Self.matchesSearch($0, searchText) }.count
        } catch {
            Log(message: "VoiceService.countFavorites error: \(error)")
            return 0
        }
    }

    // MARK: - WHERE 子句构造

    /// 构造分类的 WHERE 子句（仅语义 code，与语言无关）
    /// - Returns: nil 表示无过滤条件；Expression<Bool>(value: false) 表示永远无匹配
    ///
    /// 注：搜索不再下推到 SQL —— 文案列已从库里移除，搜索在内存中对本地化后的
    /// 名 / 特质 / 场景 / 语种做匹配（见 matchesSearch），这样还能顺手支持拼音搜索。
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

        case .chinese:
            return db.voiceLangCode == VoiceLangCode.zh.rawValue
        case .english:
            return db.voiceLangCode == VoiceLangCode.en.rawValue

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
    /// 分别读取中英文，烘焙进 Voice —— 因为项目约定跟随系统语言、无 App 内切换，
    /// 启动时读一次即可，切换语言需重启。
    private static func rowToVoice(_ row: Row, db: DatabaseManager) -> Voice {
        let rawAge = row[db.voiceAge]
        let audio = row[db.voiceAudio]
        let stem = (audio as NSString).deletingPathExtension

        let nameZh = VoiceCatalog.localizedVoiceName(stem: stem, language: .zh)
        let nameEn = VoiceCatalog.localizedVoiceName(stem: stem, language: .en)
        let featZhRaw = VoiceCatalog.localizedVoiceFeature(stem: stem, language: .zh)
        let featEnRaw = VoiceCatalog.localizedVoiceFeature(stem: stem, language: .en)
        // 中文特质去掉冗余的"音"字
        let featZh = featZhRaw.hasSuffix("音") ? String(featZhRaw.dropLast()) : featZhRaw

        return Voice(
            key: row[db.voiceKey],
            name: nameZh,
            nameEn: nameEn,
            desc: featZh,
            descEn: featEnRaw,
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
            return newValue
        } catch {
            Log(message: "VoiceService.toggleFavorite error: \(error)")
            return false
        }
    }
}
