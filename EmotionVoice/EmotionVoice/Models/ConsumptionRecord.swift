//
//  ConsumptionRecord.swift
//  EmotionVoice
//
//  消耗记录模型
//

import Foundation

/// 消耗记录
struct ConsumptionRecord: Identifiable, Hashable {
    let id: Int64
    /// 使用的音色名称
    let voiceName: String
    /// 音色 key
    let voiceKey: String
    /// 生成音频的时长（秒）
    let audioDuration: Double
    /// 使用的积分数量
    let points: Int
    /// 使用时间
    let createdAt: Date
    
    /// 格式化音频时长
    var formattedDuration: String {
        let minutes = Int(audioDuration) / 60
        let seconds = Int(audioDuration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }
    
    /// 格式化积分
    var formattedPoints: String {
        return "-\(points)"
    }
}
