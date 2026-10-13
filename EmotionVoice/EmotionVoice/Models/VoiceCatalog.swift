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

    /// 读取指定语种的 VoiceCatalog.strings 词条；缺失时回退到 key 本身
    static func string(_ key: String, language: VoiceLangCode) -> String {
        guard let path = Bundle.main.path(forResource: language == .zh ? "zh-Hans" : "en",
                                          ofType: "lproj"),
              let bundle = Bundle(path: path) else { return key }
        let value = NSLocalizedString(key, tableName: "VoiceCatalog", bundle: bundle,
                                     value: key, comment: "")
        return value.isEmpty ? key : value
    }

    /// 音色名（指定语种）
    static func localizedVoiceName(stem: String, language: VoiceLangCode) -> String {
        string("voice.\(stem).name", language: language)
    }

    /// 音色特质（指定语种，未做"音"字裁剪）
    static func localizedVoiceFeature(stem: String, language: VoiceLangCode) -> String {
        string("voice.\(stem).feature", language: language)
    }
}
