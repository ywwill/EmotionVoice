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

    var id: String { key }

    var isPremium: Bool { category == .premium }
}