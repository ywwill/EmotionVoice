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

// MARK: - 积分格式化（全项目唯一入口）

/// 积分展示统一口径：**走 `NumberFormatter`，按系统地区本地化**。
///
///  - 本地化依据是 `Locale.current`（系统「语言与地区」），分组符与小数点都交给它：
///    en_US `2,300` / `12.5`、de_DE `2.300` / `12,5`、fr_FR `2 300` / `12,5`；
///  - 中文地区按阅读习惯不分组：`zh_*` → `2300` / `12.5`；
///  - 整数不带小数点、最多 2 位小数且去掉末尾的 0，由 formatter 的
///    `minimumFractionDigits = 0` / `maximumFractionDigits = 2` 负责。
///
/// ⚠️ 所有积分数字（余额 / 消耗 / 套餐面额 / 记录 / 滚动动画）都必须走这里：
///  - 不要写 `Text("\(intValue)")`：`LocalizedStringKey` 插值会绕开统一口径；
///  - 不要各自新建 `NumberFormatter()`：分组规则会不一致；
///  - 不要退回 `String(format: "%.2f", ...)`：那会把小数点锁成英文的 `.`。
///
/// 返回的是 `String`，直接传给 `Text` 是 verbatim，不会被 SwiftUI 二次格式化。
/// `nonisolated`：纯计算，日志/后台线程拼文案也能调（项目默认 MainActor 隔离）。
nonisolated func formatCredits(_ value: Double) -> String {
    guard value.isFinite else { return "0" }
    // 与 CreditPrecision.normalize 同口径，压掉 0.30000000000000004 这类浮点尾数
    let normalized = (value * 100).rounded() / 100
    if abs(normalized) < 0.005 { return "0" }
    return makeCreditDisplayFormatter().string(from: NSNumber(value: normalized)) ?? "0"
}

/// Int 版（套餐面额 / 到账积分）：统一走同一入口。
nonisolated func formatCredits(_ value: Int) -> String {
    formatCredits(Double(value))
}

/// 积分数字格式化器：`formatCredits` 与 `AnimatedCreditText` 共用的唯一配置。
///
/// 每次返回新实例：`NumberFormatter` 非线程安全且不共享；包内部还会 `copy()` 一份。
/// ⚠️ 不设死 `en_US_POSIX`：那会把所有地区的小数点 / 分组符锁成英文，失去本地化。
/// ⚠️ 不覆盖 `groupingSeparator` / `decimalSeparator`：让 locale 自己决定。
nonisolated func makeCreditDisplayFormatter() -> NumberFormatter {
    let f = NumberFormatter()
    f.locale = Locale.current
    f.numberStyle = .decimal
    f.minimumFractionDigits = 0
    f.maximumFractionDigits = 2
    f.roundingMode = .halfUp
    // 中文地区不分组；其它地区保留该 locale 的默认分组符
    f.usesGroupingSeparator = !Locale.current.identifier.hasPrefix("zh")
    return f
}

// MARK: - 文件名清洗

/// 路径分隔符：`/` `\` `:`
///
/// macOS 在 POSIX 层允许它们出现在文件名里，但 Finder、iCloud、跨平台工具
/// （以及导出到 U 盘 / Windows）都会当成路径或卷名分隔符处理，必须挡掉。
private let pathSeparatorCharacters = CharacterSet(charactersIn: "/\\:")

/// 直接删掉的字符：`*` `?` `"` `<` `>` `|` 与控制字符
private let forbiddenFileNameCharacters = CharacterSet(charactersIn: "*?\"<>|")
    .union(.controlCharacters)

/// 把任意字符串洗成能直接当文件名的样子
///
/// 用户输入的台词是自由的，直接拿来当文件名会踩到一堆雷：
/// - 换行 / 制表符 / 全角空格：先折叠成单个普通空格，否则截取开头若干字符时可能全是回车
/// - 路径分隔符（`/` `\` `:`）：替换成 `-`，既是非法字符，也贴合用户本来想表达的分隔意图
///   （"10:30 开会" → "10-30 开会"）
/// - 其余非法字符与控制字符：直接删掉
/// - 连续 `-` 合并成一个，首尾的 `-` 与空白裁掉（否则出现 "-abc-" 这种名字）
///
/// 中文、全角标点（，。！？、（））都是合法文件名字符，一律保留。
func sanitizeFileName(_ raw: String) -> String {
    var text = raw.replacingOccurrences(
        of: "[\\s\u{3000}]+",
        with: " ",
        options: .regularExpression
    )
    text = text.components(separatedBy: pathSeparatorCharacters).joined(separator: "-")
    text = text.components(separatedBy: forbiddenFileNameCharacters).joined()
    text = text.replacingOccurrences(of: "-{2,}", with: "-", options: .regularExpression)
    return text.trimmingCharacters(in: CharacterSet(charactersIn: "-").union(.whitespaces))
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
