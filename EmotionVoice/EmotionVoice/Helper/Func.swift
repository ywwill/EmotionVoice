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

// MARK: - 字节 / 时长格式化

/// 千分位 + 两位小数的数值格式化器（用于「已接收 / 速率」大数字）
let receivedNumberFormatter: NumberFormatter = {
    let f = NumberFormatter()
    f.numberStyle = .decimal
    f.usesGroupingSeparator = true
    f.groupingSeparator = ","
    f.minimumFractionDigits = 2
    f.maximumFractionDigits = 2
    return f
}()

/// 字节数 → 自动选择单位（B / KB / MB / GB），返回（带千分位的数值, 单位）。
///
/// 接收时数据可能很大（几十上百 MB），只显示 KB 会变成天文数字，
/// 所以按 1000 进制自适应在 B / KB / MB / GB 之间切换。
func autoByteUnit(_ bytes: Double) -> (value: String, unit: String) {
    let b = max(0, bytes)
    if b < 1000 {
        return (Int(b).description, "B")
    }
    let divisor: Double
    let unit: String
    if b < 1_000_000 {
        divisor = 1000
        unit = "KB"
    } else if b < 1_000_000_000 {
        divisor = 1_000_000
        unit = "MB"
    } else {
        divisor = 1_000_000_000
        unit = "GB"
    }
    let v = b / divisor
    let str = receivedNumberFormatter.string(from: NSNumber(value: v)) ?? String(format: "%.2f", v)
    return (str, unit)
}

/// 文件大小（1000 进制，与 App 内其它位置口径一致），GB 兜底
func formatDataSize(_ bytes: Int) -> String {
    let value = max(0, bytes)
    if value < 1000 {
        return "\(value) B"
    } else if value < 1000 * 1000 {
        return String(format: "%.1f KB", Double(value) / 1000.0)
    } else if value < 1000 * 1000 * 1000 {
        return String(format: "%.2f MB", Double(value) / (1000.0 * 1000.0))
    } else {
        return String(format: "%.2f GB", Double(value) / (1000.0 * 1000.0 * 1000.0))
    }
}

/// 时长格式化（秒 → "mm:ss"，超过一小时为 "hh:mm:ss"，全部零填充）。
/// 例：32 → "00:32"；90 → "01:30"；3725 → "01:02:05"
func formatDuration(_ seconds: Double) -> String {
    let total = Int(max(0, seconds))
    let h = total / 3600
    let m = (total % 3600) / 60
    let s = total % 60
    if h > 0 {
        return String(format: "%02d:%02d:%02d", h, m, s)
    }
    return String(format: "%02d:%02d", m, s)
}
