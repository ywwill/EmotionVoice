//
//  EmotionTokenStyle.swift
//  EmotionVoice
//
//  Created by young on 2026/9/1.
//
//  Emotion Token 的视觉样式。从原来的 EmotionHighlightedTextEditor 抽出，
// 适配 AppColor / DesignSystem 风格。
//

import AppKit

/// Emotion Tag 胶囊的视觉样式
struct EmotionTokenStyle {

    // MARK: - 字体

    /// Tag 文本字体
    var font: NSFont = NSFont.systemFont(ofSize: 13, weight: .medium)
    /// Emoji 字体（一般保持 system）
    var emojiFont: NSFont = NSFont.systemFont(ofSize: 13)

    // MARK: - 内边距

    var horizontalPadding: CGFloat = 8
    var verticalPadding: CGFloat = 2

    /// Emoji 与 label 之间的间距
    var emojiToLabelSpacing: CGFloat = 4

    /// 删除按钮宽度
    var deleteButtonWidth: CGFloat = 14

    /// label 跟 × 之间的间隙
    var labelToDeleteGap: CGFloat = 2

    /// 是否显示右上角的 × 删除按钮
    var showsDeleteButton: Bool = true

    // MARK: - 颜色（Token 自己的颜色，不依赖 AppColor，避免循环依赖）

    /// 填充色（背景）
    var fillColor: NSColor = NSColor(red: 0.95, green: 0.75, blue: 0.53, alpha: 0.18)
    /// 描边色
    var strokeColor: NSColor = NSColor(red: 0.95, green: 0.75, blue: 0.53, alpha: 0.55)
    /// 文本颜色
    var textColor: NSColor = NSColor(red: 0.95, green: 0.75, blue: 0.53, alpha: 1.0)

    /// hover 时的高亮填充色
    var fillColorHovered: NSColor = NSColor(red: 0.95, green: 0.75, blue: 0.53, alpha: 0.28)
    var strokeColorHovered: NSColor = NSColor(red: 0.95, green: 0.75, blue: 0.53, alpha: 0.85)

    // MARK: - 几何

    /// 圆角半径。0 表示自动取半高。
    var cornerRadius: CGFloat = 0

    // MARK: - 默认值

    static let `default` = EmotionTokenStyle()

    /// dark mode 下会提升一点亮度
    static func darkStyle() -> EmotionTokenStyle {
        var s = EmotionTokenStyle()
        s.fillColor = NSColor(red: 0.98, green: 0.78, blue: 0.55, alpha: 0.20)
        s.strokeColor = NSColor(red: 0.98, green: 0.78, blue: 0.55, alpha: 0.65)
        s.textColor = NSColor(red: 0.98, green: 0.78, blue: 0.55, alpha: 1.0)
        return s
    }
}

/// 在 frame 内计算「× close 按钮」的命中区域
func emotionTokenDeleteHitRect(for frame: NSRect, style: EmotionTokenStyle) -> NSRect {
    guard style.showsDeleteButton else { return .zero }
    return NSRect(
        x: frame.maxX - style.deleteButtonWidth - 2,
        y: frame.minY,
        width: style.deleteButtonWidth + 4,
        height: frame.height
    )
}
