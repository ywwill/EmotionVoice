//
//  Voice.swift
//  EmotionVoice
//
//  Created by young on 2026/8/8.
//

import Foundation

/// 音色分类
enum VoiceCategory: String, CaseIterable, Identifiable {
    case premium = "premium"
    case basic = "basic"
    case child = "child"
    case role = "role"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .premium: return "旗舰音色"
        case .basic: return "基础音色"
        case .child: return "儿童音色"
        case .role: return "角色音色"
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
    /// 分类
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

/// 年龄分组（用于 UI 筛选）
enum AgeBucket: String, CaseIterable, Identifiable {
    case any = "any"
    case child = "child"
    case teen = "teen"
    case young = "young"
    case middle = "middle"
    case senior = "senior"
    case unknown = "unknown"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .any:     return "全部"
        case .child:   return "儿童"
        case .teen:    return "青少年"
        case .young:   return "青年"
        case .middle:  return "中年"
        case .senior:  return "老年"
        case .unknown: return "未知"
        }
    }

    var rangeDescription: String {
        switch self {
        case .any:     return "不限"
        case .child:   return "≤12"
        case .teen:    return "13–17"
        case .young:   return "18–35"
        case .middle:  return "36–59"
        case .senior:  return "≥60"
        case .unknown: return "—"
        }
    }
}
