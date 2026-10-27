//
//  EmotionPalette.swift
//  iOSEmora
//
//  情感标签色板：30 个 tag，沿用 macOS 的 mapping，不随主色改动。
//  浅色模式下统一向 #1B1533 压暗，保证在白底可读。
//

import SwiftUI

/// 情感标签配色
///
/// key 是英文 tag（与 `Constants.emotions` / `Constants.richLanguageTags` 的 tag 一致）。
/// 色值取自 macOS `EmotionTokenStyle.colorMap`，iOS 不改。
enum EmotionPalette {

    /// 30 个 tag 的基色
    private static let map: [String: UInt32] = [
        "excited":                 0xF2CC36,
        "mischievously":           0x31B99E,
        "empathetic":              0x64C760,
        "curious":                 0x45C485,
        "amazed":                  0xC07EE7,
        "serious":                 0xC9CCCF,
        "asmr":                    0xDF86C1,
        "whispers":                0x9A9ED6,
        "deep and loud shouting":  0xE0493E,
        "shouting":                0xE65673,
        "very fast":               0xF6EF28,
        "very slowly":             0x8C79D8,
        "sarcastic":               0x8EB238,
        "scornful":                0xAE6C3D,
        "reluctantly":             0x8978B0,
        "bored":                   0x7889A1,
        "tired":                   0x4F8492,
        "trembling":               0x51C0D6,
        "panicked":                0xD83177,
        "angry":                   0xEB7633,
        "like dracula":            0x9F4197,
        "crying":                  0x98CAEB,
        "sad":                     0x6697D6,
        "laughing":                0xF39E49,
        "giggles":                 0xE694A8,
        "sighing":                 0xC9A9D1,
        "gasp":                    0x8ED7D1,
        "clears throat":           0xC6BA8B,
        "cough":                   0xA27967,
        "snorts":                  0xAE4329,
    ]

    /// 兜底色（未命中任何已知 tag 时走确定性色相哈希，保证同一 tag 每次同色）
    private static let fallback: UInt32 = 0xF2BF87

    /// 浅色模式压暗比例（保留 62% 亮度）
    private static let lightDarkenFraction: CGFloat = 0.38

    /// 情感基色（已按主题校正）
    static func color(forTag tag: String, scheme: ColorScheme) -> Color {
        let hex = map[tag] ?? stableHex(for: tag)
        let base = Color(hex: hex)
        return scheme == .dark ? base : base.darkened(fraction: lightDarkenFraction)
    }

    /// 未命中时的确定性色相哈希（与 macOS `stableHue` 同思路：同一 tag 永远同色）
    private static func stableHex(for tag: String) -> UInt32 {
        var hash: UInt64 = 1469598103934665603
        for byte in tag.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1099511628211
        }
        let hue = Double(hash % 360) / 360.0
        return hsvToHex(hue: hue, saturation: 0.55, brightness: 0.85)
    }

    private static func hsvToHex(hue: Double, saturation: Double, brightness: Double) -> UInt32 {
        let i = Int(hue * 6)
        let f = hue * 6 - Double(i)
        let p = brightness * (1 - saturation)
        let q = brightness * (1 - f * saturation)
        let t = brightness * (1 - (1 - f) * saturation)
        let (r, g, b): (Double, Double, Double)
        switch i % 6 {
        case 0: (r, g, b) = (brightness, t, p)
        case 1: (r, g, b) = (q, brightness, p)
        case 2: (r, g, b) = (p, brightness, t)
        case 3: (r, g, b) = (p, q, brightness)
        case 4: (r, g, b) = (t, p, brightness)
        default: (r, g, b) = (brightness, p, q)
        }
        let ri = UInt32(min(max(r, 0), 1) * 255)
        let gi = UInt32(min(max(g, 0), 1) * 255)
        let bi = UInt32(min(max(b, 0), 1) * 255)
        return (ri << 16) | (gi << 8) | bi
    }
}

// MARK: - 标签视觉规格

/// 语气胶囊 / 拟声 pill 的几何规格（与 macOS v13 胶囊版一致）
enum EmotionTokenMetrics {
    /// 语气胶囊：填充 14%、1px 内描边 42%、圆角 9、内边距 6×8
    static let capsuleFillOpacity: Double = 0.14
    static let capsuleStrokeOpacity: Double = 0.42
    static let capsuleCorner: CGFloat = 9
    static let capsulePaddingY: CGFloat = 6
    static let capsulePaddingX: CGFloat = 8

    /// 徽章（emoji + 名称）压在胶囊左上角
    static let badgeFont = Font.system(size: 10.5, weight: .bold)
    static let badgeHeight: CGFloat = 15
    static let badgeGap: CGFloat = 6

    /// 拟声 pill：虚线描边 + 10% 底，圆角 6
    static let pillFillOpacity: Double = 0.10
    static let pillCorner: CGFloat = 6
    static let pillPaddingY: CGFloat = 1.5
    static let pillPaddingX: CGFloat = 7
    static let pillFont = Font.system(size: 12, weight: .medium)
}
