//
//  VoiceCatalog.swift
//  EmotionVoice
//
//  音色目录的语义枚举层。
//
//  设计原则：JSON / SQLite 中只存稳定的语义 code（如 "female"、"companion"），
//  展示文案一律由本文件的枚举在运行时提供，并通过 .localized() 走 Localizable.strings。
//  这样筛选逻辑与界面语言彻底解耦——切语言不会影响任何 SQL 谓词。
//

import Foundation

// MARK: - 当前界面语言

enum AppLanguage {

    /// 当前界面是否为简体中文（依据 App 自身可用本地化与系统偏好语言）
    static var isChinese: Bool {
        let preferred = Bundle.main.preferredLocalizations.first
            ?? Locale.current.language.languageCode?.identifier
            ?? "en"
        return preferred.hasPrefix("zh")
    }

    /// 当前界面是否为繁体中文（zh-HK / zh-Hant / zh-TW）
    ///
    /// 先看 App 自身命中的本地化（已支持 zh-HK），再退到系统偏好语言列表。
    static var prefersTraditionalChinese: Bool {
        let tags = Bundle.main.preferredLocalizations + Locale.preferredLanguages
        for tag in tags {
            let id = tag.lowercased().replacingOccurrences(of: "_", with: "-")
            if id.hasPrefix("zh-hant") || id.hasPrefix("zh-hk") || id.hasPrefix("zh-tw") {
                return true
            }
            if id.hasPrefix("zh") || id.hasPrefix("en") {
                // 明确命中简体 / 非中文，结束判断
                return false
            }
        }
        return false
    }

    /// 当前界面语言对应的 `VoiceCatalog.strings` 目录名。
    ///
    /// 取值固定为工程里 8 份 VoiceCatalog 的 .lproj 名；与 `isChinese` /
    /// `prefersTraditionalChinese` 同源。界面语言与音色语种（`VoiceLangCode`
    /// 只有 zh / en）是两件事：音色名按界面语言挑「哪一套重新命名」，
    /// 而不是按音色能说什么语言。未知语言一律回落 en。
    static var catalogLocale: String {
        let preferred = Bundle.main.preferredLocalizations.first
            ?? Locale.current.language.languageCode?.identifier
            ?? "en"
        let id = preferred.lowercased().replacingOccurrences(of: "_", with: "-")
        if id.hasPrefix("zh") {
            return prefersTraditionalChinese ? "zh-HK" : "zh-Hans"
        }
        for loc in ["fr", "de", "ja", "ko", "ru"] where id.hasPrefix(loc) {
            return loc
        }
        return "en"
    }
}

// MARK: - 音色层级

/// 音色层级：旗舰 / 基础
enum VoiceTier: String, Codable, CaseIterable, Hashable {
    case premium = "premium"
    case basic = "basic"

    /// 兜底：未知 code 一律按基础音色处理，保证脏数据不会崩
    init(code: String) {
        self = VoiceTier(rawValue: code) ?? .basic
    }

    var displayName: String {
        switch self {
        case .premium: return "旗舰".localized()
        case .basic:   return "基础".localized()
        }
    }
}

// MARK: - 语种

/// 音色语种（与音色可合成的语种一一对应）
enum VoiceLangCode: String, Codable, CaseIterable, Hashable {
    case zh = "zh"
    case en = "en"

    init(code: String) {
        self = VoiceLangCode(rawValue: code) ?? .zh
    }

    var displayName: String {
        switch self {
        case .zh: return "中文".localized()
        case .en: return "英文".localized()
        }
    }
}

// MARK: - 性别

/// 音色性别。unknown 用于兼容源数据中的缺失/异常值
enum VoiceGenderCode: String, Codable, CaseIterable, Hashable {
    case female = "female"
    case male = "male"
    case unknown = "unknown"

    init(code: String) {
        self = VoiceGenderCode(rawValue: code) ?? .unknown
    }

    var displayName: String {
        switch self {
        case .female: return "女".localized()
        case .male:   return "男".localized()
        case .unknown: return ""
        }
    }
}

// MARK: - 适用场景

/// 适用场景。rawValue 与 basic_voices.json 的 scene 字段保持一致
enum VoiceSceneCode: String, Codable, CaseIterable, Hashable {
    case daily = "daily"
    case companion = "companion"
    case reading = "reading"
    case customerService = "customer_service"
    case social = "social"
    case anime = "anime"
    case news = "news"
    case liveStream = "live_stream"
    case classicAudiobook = "classic_audiobook"
    case sports = "sports"
    case audiobook = "audiobook"
    case radio = "radio"
    case knowledge = "knowledge"
    case comedy = "comedy"
    case business = "business"
    case assistant = "assistant"
    case speech = "speech"

    init(code: String) {
        self = VoiceSceneCode(rawValue: code) ?? .daily
    }

    var displayName: String {
        switch self {
        case .daily:            return "日常对话".localized()
        case .companion:        return "情感陪伴".localized()
        case .reading:          return "有声阅读".localized()
        case .customerService:  return "客服".localized()
        case .social:           return "社交互动".localized()
        case .anime:            return "动漫配音".localized()
        case .news:             return "新闻播报".localized()
        case .liveStream:       return "电商直播".localized()
        case .classicAudiobook: return "古风有声书".localized()
        case .sports:           return "体育解说".localized()
        case .audiobook:        return "有声书配音".localized()
        case .radio:            return "深夜电台".localized()
        case .knowledge:        return "知识分享".localized()
        case .comedy:           return "娱乐搞笑".localized()
        case .business:         return "商务汇报".localized()
        case .assistant:        return "智能助手".localized()
        case .speech:           return "演讲朗诵".localized()
        }
    }
}

// MARK: - 音色文案（VoiceCatalog.strings）

/// 音色名 / 特质的本地化读取。
///
/// 文案按 `voice.<stem>.name` / `voice.<stem>.feature` 存放于 VoiceCatalog.strings，
/// 与界面语言无关、独立于系统语言：这里强制按指定语种加载对应的 .lproj，
/// 保证 zh / en 两份文案都能稳定取到（而非依赖运行时的系统语言）。
enum VoiceCatalog {

    /// 词条结果缓存。
    ///
    /// ⚠️ `string()` 原本每次都要走 `Bundle.main.path` → `Bundle(path:)` →
    /// `NSLocalizedString`，即一次文件系统查找 + 一次 Bundle 构造。而
    /// `VoiceService.rowToVoice` 全表约 900 行、每行 4 次读取，搜索与切分类时
    /// 一遍遍重跑就是几千次，是音色库首屏 / 搜索卡顿的隐藏大头。
    /// key 里带上 lproj 候选链（含繁简字形），语言切换会自动落到不同条目。
    private static let stringCache = NSCache<NSString, NSString>()

    /// 按「音色语种」读取词条；缺失时回退到 key 本身。
    /// 只用于需要显式拿中文 / 英文两套文案的场景；界面展示请用 `stringForInterface`。
    static func string(_ key: String, language: VoiceLangCode) -> String {
        string(key, lprojs: lprojCandidates(for: language))
    }

    /// 按「界面语言」读取词条：fr / de / ja / ko / ru 各读自己的目录，缺词条回落 en。
    static func stringForInterface(_ key: String) -> String {
        string(key, lprojs: interfaceLprojCandidates())
    }

    private static func string(_ key: String, lprojs: [String]) -> String {
        // cacheKey 带上整条候选链，切界面语言自然落到不同条目，无需手动清缓存
        let cacheKey = (lprojs.joined(separator: "|") + "#" + key) as NSString
        if let hit = stringCache.object(forKey: cacheKey) {
            return String(hit)
        }
        var result = key
        for lproj in lprojs {
            guard let path = Bundle.main.path(forResource: lproj, ofType: "lproj"),
                  let bundle = Bundle(path: path) else { continue }
            let value = NSLocalizedString(key, tableName: "VoiceCatalog", bundle: bundle,
                                         value: key, comment: "")
            // 取不到（返回 key 本身）就往下个候选退，最终兜底仍是 key
            if !value.isEmpty, value != key {
                result = value
                break
            }
        }
        stringCache.setObject(result as NSString, forKey: cacheKey)
        return result
    }

    /// 音色语种候选链：只用来显式取中文 / 英文两套文案。
    /// 中文按界面语言挑简繁字形，英文固定 en。
    private static func lprojCandidates(for language: VoiceLangCode) -> [String] {
        guard language == .zh else { return ["en"] }
        return AppLanguage.prefersTraditionalChinese
            ? ["zh-HK", "zh-Hant", "zh-Hans"]
            : ["zh-Hans"]
    }

    /// 界面语言候选链：8 份 VoiceCatalog 各自对应一种界面语言。
    /// 中文按简繁字形挑，法德日韩俄优先本地目录、缺词条回落英文，英文固定 en。
    /// ⚠️ 音色名是「按语种重新命名」而非翻译，所以这里选的是哪一套命名，不是翻译目标。
    static func interfaceLprojCandidates() -> [String] {
        switch AppLanguage.catalogLocale {
        case "zh-Hans": return ["zh-Hans"]
        case "zh-HK":   return ["zh-HK", "zh-Hans"]
        case "en":      return ["en"]
        case let loc:   return [loc, "en"]
        }
    }

    /// 音色名（指定语种）
    static func localizedVoiceName(stem: String, language: VoiceLangCode) -> String {
        string("voice.\(stem).name", language: language)
    }

    /// 音色特质（指定语种，未做"音"字裁剪）
    static func localizedVoiceFeature(stem: String, language: VoiceLangCode) -> String {
        string("voice.\(stem).feature", language: language)
    }

    /// 音色名（当前界面语言）
    static func localizedVoiceNameForInterface(stem: String) -> String {
        stringForInterface("voice.\(stem).name")
    }

    /// 音色特质（当前界面语言，未做"音"字裁剪）
    static func localizedVoiceFeatureForInterface(stem: String) -> String {
        stringForInterface("voice.\(stem).feature")
    }
}
