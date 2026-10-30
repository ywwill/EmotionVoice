//
//  AppFont.swift
//  EmotionVoice
//
//  Created by young on 2026/8/8.
//

import SwiftUI

/// 字体系统
/// 使用 SF Pro Display / SF Pro Text / SF Mono
enum AppFont {

    // MARK: - Display
    static let displayXL = Font.system(size: 42, weight: .bold, design: .default)
    static let displayLarge = Font.system(size: 32, weight: .semibold)
    static let displayMedium = Font.system(size: 24, weight: .semibold)
    static let displaySmall = Font.system(size: 20, weight: .medium)

    // MARK: - Body
    static let bodyLarge = Font.system(size: 16, weight: .regular)
    static let bodyMedium = Font.system(size: 14, weight: .regular)
    static let bodySmall = Font.system(size: 12, weight: .regular)

    // MARK: - Mono（数字、字符数、积分）
    static let monoLarge = Font.system(size: 16, weight: .medium, design: .monospaced)
    static let monoMedium = Font.system(size: 13, weight: .regular, design: .monospaced)
    static let monoSmall = Font.system(size: 11, weight: .regular, design: .monospaced)

    // MARK: - Caption / Label
    static let caption = Font.system(size: 11, weight: .medium)
    static let label = Font.system(size: 10, weight: .semibold)
}