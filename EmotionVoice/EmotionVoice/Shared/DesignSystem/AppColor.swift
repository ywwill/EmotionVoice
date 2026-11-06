//
//  AppColor.swift
//  EmotionVoice
//
//  Created by young on 2026/8/8.
//

import SwiftUI

/// Cold Luxury 配色方案
/// 冷调深色 + 琥珀金强调色
enum AppColor {

    // MARK: - 背景层
    static let bgPrimary = Color(hex: 0x0E0F12)
    static let bgSecondary = Color(hex: 0x15171B)
    static let bgTertiary = Color(hex: 0x1C1F24)
    static let bgElevated = Color(hex: 0x22262D)
    static let bgSidebar = Color(hex: 0x0E0F12)

    // MARK: - 强调色（琥珀金）
    static let accentPrimary = Color(hex: 0xE8A968)
    static let accentSecondary = Color(hex: 0xD49B5B)
    static let accentGlow = Color(hex: 0xF2C088)

    // MARK: - 文字层级
    static let textPrimary = Color(hex: 0xF5F5F7)
    static let textSecondary = Color(hex: 0xA8ABB4)
    static let textTertiary = Color(hex: 0x6B6E76)

    // MARK: - 状态色
    static let statusSuccess = Color(hex: 0x6BB87A)
    static let statusWarning = Color(hex: 0xE8A968)
    static let statusError = Color(hex: 0xD96D6D)
    static let statusInfo = Color(hex: 0x6B8BC9)

    // MARK: - 情感色
    static let emotionHappy = Color(hex: 0xF5C36D)
    static let emotionSad = Color(hex: 0x6B8BC9)
    static let emotionAngry = Color(hex: 0xD96D6D)
    static let emotionExcited = Color(hex: 0xE89E5F)
    static let emotionCalm = Color(hex: 0x8AA5A0)

    // MARK: - 边框
    static let borderSubtle = Color.white.opacity(0.08)
    static let borderMedium = Color.white.opacity(0.15)
    static let borderStrong = Color.white.opacity(0.25)
}

extension Color {
    /// 通过十六进制整数创建颜色
    init(hex: UInt32, opacity: Double = 1.0) {
        let r = Double((hex >> 16) & 0xFF) / 255.0
        let g = Double((hex >> 8) & 0xFF) / 255.0
        let b = Double(hex & 0xFF) / 255.0
        self.init(.sRGB, red: r, green: g, blue: b, opacity: opacity)
    }
}

// MARK: - 音色头像确定性渐变（macOS / iOS 共用，保证同音色同色）

/// 音色头像配色：由 seed 确定性生成渐变，同一音色永远同色。
///
/// 两端（macOS `AvatarView` / iOS `VoiceAvatar`）都调用这里，避免各写一套导致同音色异色。
/// - 色相：黄金角 137.508° 步进散开，相邻哈希值必落色环两端；
///   跳过 8°–85° 的橙棕/黄绿死区（白字压成土黄/橄榄），整体偏冷调、更贴近 Aurora 紫粉品牌调性。
/// - 饱和度 0.80–0.95（比旧版更鲜明），明度按 `brightnessCurve` 抖动 → 保证白字可读（对比度 ≈ 3.3:1）。
/// - 599 个音色可得到近 600 种互不相同的中点色，列表里不再出现大块同色方块。
enum VoiceAvatarPalette {
    /// 手动覆盖：特定音色不走算法，直接指定渐变（用于算法落点不好看的个别旗舰音色）。
    /// key 即 `Voice.key`（同时也是 macOS/iOS 两端的种子）。
    private static let overrides: [String: [Color]] = [
        // 旗舰「龙安灵心」原算法落在紫，反馈不好看 → 改青绿→松石渐变
        "longanlingxin": [
            Color(hue: 172/360, saturation: 0.70, brightness: 0.95),
            Color(hue: 192/360, saturation: 0.82, brightness: 0.80),
        ],
    ]

    static func gradient(for seed: String) -> [Color] {
        if let o = overrides[seed] { return o }
        let h = fingerprint(seed)
        let hue = baseHue(for: Double(h % 1024) / 1024)
        let sat = 0.80 + Double((h >> 10) % 16) * 0.01
        let bri = min(max(baseBrightness(for: hue) + Double((h >> 20) % 7) * 0.01 - 0.03, 0.62), 0.88)
        // 上浅下深：顶部降饱和提亮、底部加饱和压暗，色相各偏 5° 让渐变有层次
        return [
            Color(hue: wrap(hue - 5) / 360, saturation: sat * 0.84, brightness: min(bri + 0.11, 1)),
            Color(hue: wrap(hue + 5) / 360, saturation: sat, brightness: bri),
        ]
    }

    /// 0…1 均匀取值 → 色相，跳过 8°–85° 的橙棕/黄绿死区
    private static func baseHue(for unit: Double) -> Double {
        let skipLow = 8.0, skipHigh = 85.0
        let split = skipLow / (360 - (skipHigh - skipLow))
        if unit < split { return unit / split * skipLow }
        return skipHigh + (unit - split) / (1 - split) * (360 - skipHigh)
    }

    /// 色相 0°、15° … 345° 共 24 档底座明度，档间线性插值
    private static let brightnessCurve: [Double] = [
        1.00, 0.88, 0.74, 0.70, 0.60, 0.58, 0.58, 0.58,
        0.59, 0.58, 0.58, 0.57, 0.58, 0.69, 0.89, 1.00,
        1.00, 1.00, 1.00, 1.00, 0.94, 0.97, 1.00, 1.00,
    ]

    private static func baseBrightness(for hue: Double) -> Double {
        let step = hue / 15
        let i = min(Int(step), brightnessCurve.count - 1)
        let j = (i + 1) % brightnessCurve.count
        let t = step - Double(i)
        return brightnessCurve[i] + (brightnessCurve[j] - brightnessCurve[i]) * t
    }

    private static func wrap(_ hue: Double) -> Double {
        (hue + 360).truncatingRemainder(dividingBy: 360)
    }

    /// FNV-1a：跨进程稳定的 64 位哈希。`hashValue` 每次启动都变，不能拿来上色
    private static func fingerprint(_ seed: String) -> UInt64 {
        var hash: UInt64 = 1469598103934665603
        for byte in seed.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1099511628211
        }
        return hash
    }
}