//
//  Transaction.swift
//  EmotionVoice
//
//  Created by young on 2026/8/8.
//

import Foundation

/// 交易类型
enum TransactionType: String, CaseIterable, Identifiable {
    case purchase = "purchase"
    case consume = "consume"
    case refund = "refund"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .purchase: return "购买"
        case .consume: return "消费"
        case .refund: return "返还"
        }
    }

    var icon: String {
        switch self {
        case .purchase: return "+"
        case .consume: return "▶"
        case .refund: return "↺"
        }
    }

    var isPositive: Bool {
        self == .purchase || self == .refund
    }
}

/// 交易记录
struct TransactionRecord: Identifiable, Hashable {
    let id: Int64
    let type: TransactionType
    let title: String
    let amount: Int
    let meta: String?
    let createdAt: Date
}

/// 月度统计
struct MonthlyStats: Hashable {
    let month: String          // YYYY-MM
    let pointsUsed: Int
    let audioCount: Int
    let voiceCount: Int
}

/// 积分套餐
struct CreditsPackage: Identifiable, Hashable {
    let id: String
    let icon: String
    let name: String
    let price: Double
    let points: Int
    let unitPrice: Double
    let features: [String]
    let isRecommended: Bool
}