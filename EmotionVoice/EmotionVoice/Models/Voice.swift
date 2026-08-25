//
//  Voice.swift
//  EmotionVoice
//
//  Created by young on 2026/8/8.
//

import Foundation

/// 音色分类（用于顶部 Chip 筛选；同一首音色可在多个分类下被命中）
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

    /// Chip 显示标题
    var displayName: String {
        switch self {
        case .premium: return "旗舰音色"
        case .chinese: return "中文"
        case .english: return "英文"

        case .sceneDaily:      return "日常对话"
        case .sceneCompanion:  return "情感陪伴"
        case .sceneCustomer:   return "客服"
        case .sceneReading:    return "有声阅读"
        case .sceneSocial:     return "社交互动"
        case .sceneAnime:      return "动漫配音"
        case .sceneNews:       return "新闻播报"
        case .sceneLive:       return "电商直播"
        case .sceneClassic:    return "古风有声书"
        case .sceneSports:     return "体育解说"
        case .sceneAudiobook:  return "有声书配音"
        case .sceneRadio:      return "深夜电台"
        case .sceneKnowledge:  return "知识分享"
        case .sceneComedy:     return "娱乐搞笑"
        case .sceneBusiness:   return "商务汇报"
        case .sceneAssistant:  return "智能助手"
        case .sceneSpeech:     return "演讲朗诵"

        case .roleAnime:    return "动漫角色"
        case .roleLive:     return "直播角色"
        case .roleClassic:  return "古风角色"
        case .roleRadio:    return "电台角色"

        case .ageChild:  return "儿童"
        case .ageTeen:   return "青少年"
        case .ageYoung:  return "青年"
        case .ageMiddle: return "中年"
        case .ageSenior: return "老年"
        }
    }

    /// 该分类对应的场景字符串（用于匹配 Voice.scene）
    var sceneKey: String? {
        switch self {
        case .sceneDaily:      return "日常对话"
        case .sceneCompanion:  return "情感陪伴"
        case .sceneCustomer:   return "客服"
        case .sceneReading:    return "有声阅读"
        case .sceneSocial:     return "社交互动"
        case .sceneAnime:      return "动漫配音"
        case .sceneNews:       return "新闻播报"
        case .sceneLive:       return "电商直播"
        case .sceneClassic:    return "古风有声书"
        case .sceneSports:     return "体育解说"
        case .sceneAudiobook:  return "有声书配音"
        case .sceneRadio:      return "深夜电台"
        case .sceneKnowledge:  return "知识分享"
        case .sceneComedy:     return "娱乐搞笑"
        case .sceneBusiness:   return "商务汇报"
        case .sceneAssistant:  return "智能助手"
        case .sceneSpeech:     return "演讲朗诵"
        default: return nil
        }
    }

    /// 判断一个音色是否命中此分类
    func matches(_ voice: Voice) -> Bool {
        switch dimension {
        case .premium:
            return voice.isPremium
        case .language:
            switch self {
            case .chinese: return voice.lang.contains("中文")
            case .english: return voice.lang.contains("英文")
            default: return false
            }
        case .scene:
            guard let key = sceneKey else { return false }
            return voice.scene == key
        case .role:
            switch self {
            case .roleAnime:    return voice.scene.contains("动漫配音")
            case .roleLive:     return voice.scene.contains("电商直播")
            case .roleClassic:  return voice.scene.contains("古风有声书")
            case .roleRadio:    return voice.scene.contains("深夜电台")
            default: return false
            }
        case .age:
            guard let age = voice.age else { return false }
            switch self {
            case .ageChild:  return age < 13
            case .ageTeen:   return age >= 13 && age < 18
            case .ageYoung:  return age >= 18 && age < 36
            case .ageMiddle: return age >= 36 && age < 60
            case .ageSenior: return age >= 60
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
        case .premium:  return "旗舰"
        case .language: return "语言"
        case .scene:    return "适用场景"
        case .role:     return "角色"
        case .age:      return "年龄阶段"
        }
    }
}

/// 音色
struct Voice: Identifiable, Hashable {
    /// 音色参数名（如 longanlingxin）
    let key: String
    /// 显示名（如 龙安灵心）
    let name: String
    /// 描述
    let desc: String
    /// 单字头像
    let avatar: String
    /// 分类（primary）
    let category: VoiceCategory
    /// 是否收藏
    var isFavorite: Bool
    /// 适用场景（如 日常对话、有声阅读）
    var scene: String = ""
    /// 年龄（数字；无法解析时为 nil）
    var age: Int? = nil
    /// 性别（男 / 女 / 空）
    var gender: String = ""
    /// 预览音频文件名（如 longanlingxin.m4a）
    var audio: String = ""
    /// 语种（中文 / 英文）
    var lang: String = ""

    var id: String { key }

    var isPremium: Bool { category == .premium }

    /// 年龄桶（用于分组筛选）
    var ageBucket: AgeBucket {
        guard let a = age else { return .unknown }
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
    case unknown = "unknown"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .child:   return "儿童"
        case .teen:    return "青少年"
        case .young:   return "青年"
        case .middle:  return "中年"
        case .senior:  return "老年"
        case .unknown: return "未知"
        }
    }
}
