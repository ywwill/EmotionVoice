//
//  EmotionTokenStyle.swift
//  EmotionVoice
//
//  Created by young on 2026/9/1.
//
//  Emotion Token 的视觉样式。从原来的 EmotionHighlightedTextEditor 抽出，
//  适配 AppColor / DesignSystem 风格。
//
//  设计要点：
//   * 每个 token 的「身份」(EmotionTokenIdentity) 只描述 基础色 + 家族，
//     真正的颜色在 *绘制时* 结合当前外观（明 / 暗）实时解析。
//     这样切换系统外观时 token 配色会自动跟随，无需手动切换 darkStyle()。
//   * 几何参数（字体 / 内边距 / 删除按钮）集中放在 `.default`，
//     绘制用的 `resolved(...)` 会沿用这些几何值，只覆盖颜色与家族相关标记，
//     保证 cellSize() 计算出的尺寸与 drawPill() 实际布局完全一致。
//

import AppKit

/// 一个 token 的「身份」：决定它的基础色与家族。
/// 绘制时据此 + 当前 appearance 解析出最终颜色。
struct EmotionTokenIdentity: Equatable, Hashable {
    let baseColor: NSColor
    let category: EmotionCategory
}

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

    /// Emoji 与情绪色点之间的间距
    var emojiToDotSpacing: CGFloat = 5

    /// 情绪色点（8px）与 label 之间的间距
    var dotToLabelSpacing: CGFloat = 6

    /// 是否显示前置的「情绪色点」（极简色点标签的核心元素）
    var showColorDot: Bool = true

    /// 情绪色点直径
    var colorDotDiameter: CGFloat = 8

    /// 删除按钮宽度
    var deleteButtonWidth: CGFloat = 14

    /// label 跟 × 之间的间隙
    var labelToDeleteGap: CGFloat = 2

    /// 是否显示右上角的 × 删除按钮
    var showsDeleteButton: Bool = true

    // MARK: - 颜色（绘制时由 identity + appearance 解析覆盖；这里只作兜底）
    //
    // 这些兜底值为中性灰（极简色点风格），仅在 identity 缺失时生效，
    // 不影响正常路径（正常路径走 `resolved(for:dark:)`，其中只把情绪色落在 dotColor 上）。

    /// 填充色（背景）—— 兜底用中性深灰，真实路径由 resolved 按外观覆盖
    var fillColor: NSColor = NSColor(white: 1.0, alpha: 0.05)
    /// 描边色 —— 中性
    var strokeColor: NSColor = NSColor(white: 1.0, alpha: 0.10)
    /// 文本颜色 —— 中性（低彩噪：颜色只交给情绪色点）
    var textColor: NSColor = NSColor(white: 0.92, alpha: 1.0)

    /// hover / 选中时的高亮填充色
    var fillColorHovered: NSColor = NSColor(white: 1.0, alpha: 0.09)
    var strokeColorHovered: NSColor = NSColor(white: 1.0, alpha: 0.16)

    /// 情绪色点颜色（极简色点标签的核心著色处）。默认沿用琥珀金兜底，真实路径由 resolved 按外观覆盖。
    var dotColor: NSColor = fallbackBaseColor

    // MARK: - 几何

    /// 圆角半径。0 表示自动取半高。
    var cornerRadius: CGFloat = 0

    // MARK: - 家族 / 交互

    /// 拟声类（richLanguage）用虚线描边，与「语气」类的实线描边区分开。
    var dashedBorder: Bool = false

    // MARK: - 默认值

    static let `default` = EmotionTokenStyle()

    /// 兜底基础色：当 identity 缺失时使用，沿用原有琥珀金，保证旧数据不崩。
    static let fallbackBaseColor = NSColor(red: 0.95, green: 0.75, blue: 0.53, alpha: 1.0)

    // MARK: - 基础色板

    /// 英文 tag → 基础色。覆盖 App 中常见的语气 / 拟声标签；
    /// 未命中的 tag 走「确定性色相回退」，保证多样性且不过于刺眼。
    private static let colorMap: [String: NSColor] = [
        // 语气 / 情感控制类
        "sad":                    NSColorFromHex(0x6B8BC9),
        "crying":                 NSColorFromHex(0x6B8BC9),
        "trembling":              NSColorFromHex(0x8A6BC9),
        "panicked":               NSColorFromHex(0xD96D6D),
        "angry":                  NSColorFromHex(0xD96D6D),
        "scornful":               NSColorFromHex(0xC97B5B),
        "reluctantly":            NSColorFromHex(0xA8A0B0),
        "excited":                NSColorFromHex(0xE89E5F),
        "amazed":                 NSColorFromHex(0x9B7BD9),
        "curious":                NSColorFromHex(0x7BB6A0),
        "calm":                   NSColorFromHex(0x8AA5A0),
        "like dracula":           NSColorFromHex(0x9B7BD9),
        "bored":                  NSColorFromHex(0x9AA0AB),
        "tired":                  NSColorFromHex(0x7E8AA0),
        "serious":                NSColorFromHex(0x9AA0AB),
        "very fast":              NSColorFromHex(0xE8705F),
        "very slowly":            NSColorFromHex(0x6B8BC9),
        "mischievously":          NSColorFromHex(0xB07BD9),
        "sarcastic":              NSColorFromHex(0xD9B36B),
        "whispers":               NSColorFromHex(0x8FA3C0),
        // 富语言 / 拟声类
        "asmr":                   NSColorFromHex(0xD98FB0),
        "shouting":               NSColorFromHex(0xE8705F),
        "deep and loud shouting": NSColorFromHex(0xE8705F),
        "laughing":               NSColorFromHex(0xF0B45F),
        "giggles":                NSColorFromHex(0xF0B45F),
        "sighing":                NSColorFromHex(0x8FA3C0),
        "gasp":                   NSColorFromHex(0x8FA3C0),
        "clears throat":          NSColorFromHex(0xA8A0B0),
        "cough":                  NSColorFromHex(0xA8A0B0),
        "snorts":                 NSColorFromHex(0xC97B5B)
    ]

    /// 根据英文 tag（无则中文 label）取基础色。
    static func baseColor(for key: String) -> NSColor {
        if let c = colorMap[key] { return c }
        // 确定性色相回退：基于字符串自身内容哈希，进程间稳定（不依赖 Swift 随机化 hash）。
        return NSColor(hue: stableHue(key), saturation: 0.55, brightness: 0.85, alpha: 1.0)
    }

    /// 稳定的字符串 → 色相（0~1）。用乘法哈希保证同一字符串每次结果一致。
    private static func stableHue(_ s: String) -> CGFloat {
        var h: UInt32 = 0
        for c in s.unicodeScalars {
            h = h &* 31 &+ c.value
        }
        return CGFloat(h % 360) / 360.0
    }

    // MARK: - 解析（绘制时调用）

    /// 由 identity + 当前外观解析出最终样式。
    /// 几何沿用 `.default`，仅覆盖颜色与家族相关标记，确保与 cellSize() 一致。
    static func resolved(for identity: EmotionTokenIdentity, dark: Bool) -> EmotionTokenStyle {
        var s = EmotionTokenStyle.default
        let base = identity.baseColor
        s.dashedBorder = (identity.category == .richLanguage)

        if dark {
            // 极简色点（低彩噪）：胶囊本体走中性灰，颜色只落在 8px 情绪色点上。
            s.textColor = NSColor(white: 0.92, alpha: 1.0)
            s.fillColor = NSColor(white: 1.0, alpha: 0.05)
            s.strokeColor = NSColor(white: 1.0, alpha: 0.10)
            s.fillColorHovered = NSColor(white: 1.0, alpha: 0.09)
            s.strokeColorHovered = NSColor(white: 1.0, alpha: 0.16)
            s.dotColor = base
        } else {
            // 亮色背景：中性深灰胶囊 + 略压暗的情绪色点，保证可读性。
            s.textColor = NSColor(white: 0.18, alpha: 1.0)
            s.fillColor = NSColor(white: 0.0, alpha: 0.04)
            s.strokeColor = NSColor(white: 0.0, alpha: 0.10)
            s.fillColorHovered = NSColor(white: 0.0, alpha: 0.07)
            s.strokeColorHovered = NSColor(white: 0.0, alpha: 0.16)
            s.dotColor = base.darkened(by: 0.12)
        }
        return s
    }

    /// 判断某个外观是否为暗色。
    static func isDarkAppearance(_ appearance: NSAppearance) -> Bool {
        return appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
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

/// 把 0xRRGGBB 转成 sRGB 的 NSColor（alpha 默认 1）。

private func NSColorFromHex(_ hex: UInt32) -> NSColor {
    let r = CGFloat((hex >> 16) & 0xFF) / 255.0
    let g = CGFloat((hex >> 8) & 0xFF) / 255.0
    let b = CGFloat(hex & 0xFF) / 255.0
    return NSColor(colorSpace: .sRGB, components: [r, g, b, 1.0], count: 4)
}

extension NSColor {

    /// 向黑色混合 fraction（0~1），用于亮色模式下把基础色压暗以保证可读性。
    func darkened(by fraction: CGFloat) -> NSColor {
        let f = max(0, min(1, fraction))

        guard let rgb = usingColorSpace(.sRGB) else { return self }

        let r = rgb.redComponent * (1 - f)
        let g = rgb.greenComponent * (1 - f)
        let b = rgb.blueComponent * (1 - f)
        return NSColor(colorSpace: .sRGB, components: [r, g, b, rgb.alphaComponent], count: 4)
    }
}
