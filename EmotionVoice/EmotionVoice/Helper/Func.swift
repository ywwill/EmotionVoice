//
//  Func.swift
//  EmotionVoice
//
//  Created by young on 2026/8/9.
//

import Foundation

// MARK: 日志打印

nonisolated
func Log<T>(messageType: String? = nil, message: T, fileName: String = #file, methodName: String = #function, lineNumber: Int = #line) {
#if DEBUG
    //获取当前时间
    let now = Date()
    // 创建一个日期格式器
    let dformatter = DateFormatter()
    dformatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
    // 要把路径最后的字符串截取出来
    let lastName = ((fileName as NSString).pathComponents.last!)

    var msg = "\(message)"
    if let messageType = messageType {
        msg = "----\(messageType)--->\(msg)"
    }
    print("\(dformatter.string(from: now)) [\(lastName)][第\(lineNumber)行] \n\t\t \(msg)")
#endif
}

// MARK: - 积分格式化

/// 格式化积分显示（整数显示整数，一位小数显示一位，最多两位小数）
/// - Parameter value: 积分值
/// - Returns: 格式化的字符串，如 "100"、"12.5" 或 "12.34"
func formatCredits(_ value: Double) -> String {
    if value.truncatingRemainder(dividingBy: 1) == 0 {
        // 整数
        return String(format: "%.0f", value)
    } else {
        // 检测是否只有一位小数
        let oneDecimal = (value * 10).rounded() / 10
        if abs(value - oneDecimal) < 0.001 {
            return String(format: "%.1f", value)
        } else {
            return String(format: "%.2f", value)
        }
    }
}
