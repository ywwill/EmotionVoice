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