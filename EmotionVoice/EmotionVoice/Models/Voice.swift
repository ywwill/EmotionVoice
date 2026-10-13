//
//  Voice.swift
//  EmotionVoice
//
//  Created by young on 2026/8/8.
//

import Foundation

/// 音色分类（用于顶部 Chip 筛选；同一首音色可在多个分类下被命中）
///
/// 说明：分类只是「筛选视图」，不是音色自身的属性。
/// 音色真正存的是 tier / lang / scene / age / gender 语义字段，
/// 命中判定统一走 `VoiceCategory.matches(_:)` 与 `VoiceService.categoryPredicate(_:)`。
enum VoiceCategory: String, CaseIterable, Identifiable, Hashable {
    // MARK: - 维度分组

    /// 旗舰音色
    case premium = "premium"
    /// 中文
    case chinese = "chinese"
    /// 英文
    case english = "english"

    // 适用场景
    case sceneDaily = "scene_daily"
    case sceneCompanion = "scene_companion"
    case sceneCustomer = "scene_customer"
    case sceneReading = "scene_reading"
    case sceneSocial = "scene_social"
    case sceneAnime = "scene_anime"
    case sceneNews = "scene_news"
    case sceneLive = "scene_live"
    case sceneClassic = "scene_classic"
    case sceneSports = "scene_sports"
    case sceneAudiobook = "scene_audiobook"
    case sceneRadio = "scene_radio"
    case sceneKnowledge = "scene_knowledge"
    case sceneComedy = "scene_comedy"
    case sceneBusiness = "scene_business"
    case sceneAssistant = "scene_assistant"
    case sceneSpeech = "scene_speech"

    // 角色
    case roleAnime = "role_anime"
    case roleLive = "role_live"
    case roleClassic = "role_classic"
    case roleRadio = "role_radio"

    // 年龄阶段
    case ageChild = "age_child"
    case ageTeen = "age_teen"
    case ageYoung = "age_young"
    case ageMiddle = "age_middle"
    case ageSenior = "age_senior"

    var id: String { rawValue }

    /// 分类维度
    var dimension: VoiceCategoryDimension {
        switch self {
        case .premium: return .premium
        case .chinese, .english: return .language
        case .sceneDaily, .sceneCompanion, .sceneCustomer, .sceneReading,
             .sceneSocial, .sceneAnime, .sceneNews, .sceneLive, .sceneClassic,
             .sceneSports, .sceneAudiobook, .sceneRadio, .sceneKnowledge,
             .sceneComedy, .sceneBusiness, .sceneAssistant, .sceneSpeech:
            return .scene
        case .roleAnime, .roleLive, .roleClassic, .roleRadio:
            return .role
        case .ageChild, .ageTeen, .ageYoung, .ageMiddle, .ageSenior:
            return .age
        }
    }

    /// Chip 显示标题（走 Localizable.strings，中文原文为 key）
    var displayName: String {
        switch self {
        case .premium: return "旗舰音色".localized()
        case .chinese: return "中文".localized()
        case .english: return "英文".localized()

        case .sceneDaily:      return VoiceSceneCode.daily.displayName
        case .sceneCompanion:  return VoiceSceneCode.companion.displayName
        case .sceneCustomer:   return VoiceSceneCode.customerService.displayName
        case .sceneReading:    return VoiceSceneCode.reading.displayName
        case .sceneSocial:     return VoiceSceneCode.social.displayName
        case .sceneAnime:      return VoiceSceneCode.anime.displayName
        case .sceneNews:       return VoiceSceneCode.news.displayName
        case .sceneLive:       return VoiceSceneCode.liveStream.displayName
        case .sceneClassic:    return VoiceSceneCode.classicAudiobook.displayName
        case .sceneSports:     return VoiceSceneCode.sports.displayName
        case .sceneAudiobook:  return VoiceSceneCode.audiobook.displayName
        case .sceneRadio:      return VoiceSceneCode.radio.displayName
        case .sceneKnowledge:  return VoiceSceneCode.knowledge.displayName
        case .sceneComedy:     return VoiceSceneCode.comedy.displayName
        case .sceneBusiness:   return VoiceSceneCode.business.displayName
        case .sceneAssistant:  return VoiceSceneCode.assistant.displayName
        case .sceneSpeech:     return VoiceSceneCode.speech.displayName

        case .roleAnime:    return "动漫角色".localized()
        case .roleLive:     return "直播角色".localized()
        case .roleClassic:  return "古风角色".localized()
        case .roleRadio:    return "电台角色".localized()

        case .ageChild:  return "儿童".localized()
        case .ageTeen:   return "青少年".localized()
        case .ageYoung:  return "青年".localized()
        case .ageMiddle: return "中年".localized()
        case .ageSenior: return "老年".localized()
        }
    }

    /// 分类图标（Emoji），用于卡片区域标题与 chip 标识
    var icon: String {
        switch self {
        case .premium:    return "⭐"
        case .chinese:    return "🌐"
        case .english:    return "🌍"
        case .sceneDaily:      return "💬"
        case .sceneCompanion:  return "💝"
        case .sceneCustomer:   return "🎧"
        case .sceneReading:    return "📖"
        case .sceneSocial:     return "🎈"
        case .sceneAnime:      return "🎌"
        case .sceneNews:       return "📰"
        case .sceneLive:       return "🛒"
        case .sceneClassic:    return "🏯"
        case .sceneSports:     return "🏆"
        case .sceneAudiobook:  return "📚"
        case .sceneRadio:      return "🌙"
        case .sceneKnowledge:  return "💡"
        case .sceneComedy:     return "😄"
        case .sceneBusiness:   return "💼"
        case .sceneAssistant:  return "🤖"
        case .sceneSpeech:     return "🎤"
        case .roleAnime:    return "🦸"
        case .roleLive:     return "📡"
        case .roleClassic:  return "👘"
        case .roleRadio:    return "🎙️"
        case .ageChild:  return "👶"
        case .ageTeen:   return "🧒"
        case .ageYoung:  return "🧑"
        case .ageMiddle: return "👨"
        case .ageSenior: return "👴"
        }
    }

    /// 该分类对应的场景 code（用于匹配 Voice.scene）
    var sceneCode: VoiceSceneCode? {
        switch self {
        case .sceneDaily:      return .daily
        case .sceneCompanion:  return .companion
        case .sceneCustomer:   return .customerService
        case .sceneReading:    return .reading
        case .sceneSocial:     return .social
        case .sceneAnime:      return .anime
        case .sceneNews:       return .news
        case .sceneLive:       return .liveStream
        case .sceneClassic:    return .classicAudiobook
        case .sceneSports:     return .sports
        case .sceneAudiobook:  return .audiobook
        case .sceneRadio:      return .radio
        case .sceneKnowledge:  return .knowledge
        case .sceneComedy:     return .comedy
        case .sceneBusiness:   return .business
        case .sceneAssistant:  return .assistant
        case .sceneSpeech:     return .speech
        default: return nil
        }
    }

    /// 角色类分类：由场景 code 派生，不额外占用存储字段
    private var roleSceneCode: VoiceSceneCode? {
        switch self {
        case .roleAnime:   return .anime
        case .roleLive:    return .liveStream
        case .roleClassic: return .classicAudiobook
        case .roleRadio:   return .radio
        default: return nil
        }
    }

    /// 判断一个音色是否命中此分类（与 VoiceService.categoryPredicate 行为保持一致）
    func matches(_ voice: Voice) -> Bool {
        switch dimension {
        case .premium:
            return voice.isPremium
        case .language:
            switch self {
            case .chinese: return voice.lang == .zh
            case .english: return voice.lang == .en
            default: return false
            }
        case .scene:
            guard let code = sceneCode else { return false }
            return voice.scene == code
        case .role:
            guard let code = roleSceneCode else { return false }
            return voice.scene == code
        case .age:
            guard let bucket = voice.ageBucket else { return false }
            switch self {
            case .ageChild:  return bucket == .child
            case .ageTeen:   return bucket == .teen
            case .ageYoung:  return bucket == .young
            case .ageMiddle: return bucket == .middle
            case .ageSenior: return bucket == .senior
            default: return false
            }
        }
    }

    /// 当前应展示的分组维度（按维度顺序展示所有分类）
    static var displayOrder: [VoiceCategoryDimension] {
        [.premium, .language, .scene, .role, .age]
    }

    /// 按维度分组的分类列表（用于 chip 横向滚动展示）
    static func grouped() -> [(VoiceCategoryDimension, [VoiceCategory])] {
        displayOrder.map { dim in
            (dim, allCases.filter { $0.dimension == dim })
        }
    }

    /// 第一行已固定的分类（收藏 / 全部由视图层独立渲染）
    static let primaryRow: Set<VoiceCategory> = [.premium, .chinese, .english]

    /// 第二行展示的分类：除 primaryRow 之外的全部 case，按维度顺序排列
    static var secondaryDisplayOrder: [VoiceCategory] {
        var result: [VoiceCategory] = []
        for dim in displayOrder {
            result.append(contentsOf: allCases.filter { $0.dimension == dim && !primaryRow.contains($0) })
        }
        return result
    }
}

/// 音色分类维度
enum VoiceCategoryDimension: String, CaseIterable, Hashable {
    case premium = "premium"
    case language = "language"
    case scene = "scene"
    case role = "role"
    case age = "age"

    var displayName: String {
        switch self {
        case .premium:  return "旗舰".localized()
        case .language: return "语言".localized()
        case .scene:    return "适用场景".localized()
        case .role:     return "角色".localized()
        case .age:      return "年龄阶段".localized()
        }
    }
}

/// 音色
struct Voice: Identifiable, Hashable {
    /// 音色参数名（如 longanlingxin / qwen-audio-3.0-tts-plus-longcanzhuyue）
    let key: String
    /// 中文名（如 龙安灵心）
    let name: String
    /// 英文名（如 Lynn）
    let nameEn: String
    /// 中文特质描述（如 电台质感）
    let desc: String
    /// 英文特质描述（如 Radio）
    let descEn: String
    /// 层级：旗舰 / 基础
    let tier: VoiceTier
    /// 是否收藏
    var isFavorite: Bool
    /// 适用场景
    var scene: VoiceSceneCode
    /// 年龄（无法解析时为 nil）
    var age: Int? = nil
    /// 性别
    var gender: VoiceGenderCode = .unknown
    /// 预览音频文件名（如 longanlingxin.m4a）
    var audio: String = ""
    /// 语种
    var lang: VoiceLangCode = .zh

    var id: String { key }

    var isPremium: Bool { tier == .premium }

    // MARK: - 本地化展示

    /// 当前语言下的音色名
    var localizedName: String {
        AppLanguage.isChinese ? name : (nameEn.isEmpty ? name : nameEn)
    }

    /// 当前语言下的特质描述
    var localizedDesc: String {
        AppLanguage.isChinese ? desc : (descEn.isEmpty ? desc : descEn)
    }

    /// 当前语言下的头像字（中文取末字，英文取首字母）
    var localizedAvatar: String {
        if AppLanguage.isChinese {
            return name.isEmpty ? "" : String(name.suffix(1))
        }
        let base = nameEn.isEmpty ? name : nameEn
        return String(base.prefix(1)).uppercased()
    }

    /// 当前语言下的场景名
    var localizedScene: String { scene.displayName }

    /// 当前语言下的性别
    var localizedGender: String { gender.displayName }

    /// 排序键：始终用当前语言的展示名，保证中英文下排序都自然
    var sortKey: String { localizedName }

    /// 兼容旧调用：派生出的「分类视图」（旗舰 > 语言）
    var category: VoiceCategory {
        if isPremium { return .premium }
        return lang == .en ? .english : .chinese
    }

    /// 年龄桶（用于分组筛选）；未知年龄返回 nil
    var ageBucket: AgeBucket? {
        guard let a = age else { return nil }
        switch a {
        case ..<13: return .child
        case 13..<18: return .teen
        case 18..<36: return .young
        case 36..<60: return .middle
        default: return .senior
        }
    }
}

/// 年龄分组
enum AgeBucket: String, CaseIterable, Identifiable, Hashable {
    case child = "child"
    case teen = "teen"
    case young = "young"
    case middle = "middle"
    case senior = "senior"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .child:   return "儿童".localized()
        case .teen:    return "青少年".localized()
        case .young:   return "青年".localized()
        case .middle:  return "中年".localized()
        case .senior:  return "老年".localized()
        }
    }
}
