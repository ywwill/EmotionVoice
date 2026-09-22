//
//  PurchaseRecord.swift
//  EmotionVoice
//
//  购买记录模型
//

import Foundation

/// 购买记录
struct PurchaseRecord: Identifiable, Hashable {
    let id: Int64
    /// 购买时间
    let createdAt: Date
    /// 购买数量（积分）
    let quantity: Int
    
    /// 格式化积分
    var formattedQuantity: String {
        return "+\(quantity)"
    }
}
