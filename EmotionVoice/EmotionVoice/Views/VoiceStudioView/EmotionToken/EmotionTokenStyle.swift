//
//  EmotionTokenStyle.swift
//  EmotionVoice
//
//  Created by young on 2026/9/1.
//
//  Emotion Token 的视觉样式。从原来的 EmotionHighlightedTextEditor 抽出，
//  适配 AppColor / DesignSystem 风格。
//
//  设计要点（v3 · 两类标签）：
//   * 每个 token 的「身份」(EmotionTokenIdentity) 只描述 基础色 + 家族，
//     真正的颜色在 *绘制时* 结合当前外观（明 / 暗）实时解析。
//   * 两种家族两种视觉语言：
//       - .emotion      （语气）：后续文本段加彩色下划线，标记位置下方画 emoji+文字标注。
//       - .richLanguage （拟声）：在当前位置点插入一个声音标记（虚线框 + 播放三角 + 名称 + 右上角外置 ×）。
//   * 几何参数集中放在 `.default`，绘制用的 `resolved(...)` 沿用几何，只覆盖颜色与家族相关标记，
//     保证 cellSize() 计算出的尺寸与绘制布局一致。
//

import AppKit

/// 一个 token 的「身份」：决定它的基础色与家族。
/// 绘制时据此 + 当前 appearance 解析出最终颜色。
struct EmotionTokenIdentity: Equatable, Hashable {
    let baseColor: NSColor
    let category: EmotionCategory
}

/// Emotion Tag 的视觉样式
struct EmotionTokenStyle {

    // MARK: - 字体

    /// 正文字号：cell 尺寸、body 属性、下划线基准线计算共用，改一处即可。
    static let bodyFontSize: CGFloat = 14
    /// 正文字体
    static var bodyFont: NSFont { NSFont.systemFont(ofSize: bodyFontSize) }

    /// Tag 文本字体
    var font: NSFont = NSFont.systemFont(ofSize: 13, weight: .medium)
    /// Emoji 字体（一般保持 system）
    var emojiFont: NSFont = NSFont.systemFont(ofSize: 13)

    // MARK: - 内边距 / 间距

    var horizontalPadding: CGFloat = 8
    var verticalPadding: CGFloat = 3

    /// 删除按钮宽度
    var deleteButtonWidth: CGFloat = 14

    /// label 跟 × 之间的间隙
    var labelToDeleteGap: CGFloat = 2

    /// 是否显示删除按钮
    var showsDeleteButton: Bool = true

    // MARK: - 语气标签（下划线 + 下方标注）

    /// 下划线粗细（v4 加粗：由 2 → 2.5，接近设计稿的强调感）
    var underlineThickness: CGFloat = 2.5
    /// 下划线与正文之间的间距：以「正文字体的降部底线」为基准再往下留出的空隙。
    /// AppKit 内置 underline 属性无法控制这个间距，因此下划线改为自绘。
    var underlineGap: CGFloat = 2
    /// 两个语气作用域「接缝处」额外让出的间距。
    /// 相邻两个语气标签只隔着一个 1pt 宽的标记，下划线几乎会连成一条；
    /// 在接缝的上一作用域尾端与下一作用域首端各内缩这么多，视觉上才分得开。
    var underlineJointGap: CGFloat = 3
    /// 下方标注字号
    var annotationFontSize: CGFloat = 10.5
    /// 下方标注与正文降部底线之间的间距。
    ///
    /// 注意与自绘下划线的关系：标注顶端 = 基线 + |descender| + annotationGap，
    /// 下划线占据基线 + |descender| + underlineGap 起、厚 underlineThickness。
    /// 下划线加粗并留间距后底部到了基线 +7.45，因此这里取 7（标注顶端 ≈ 基线 +9.95），
    /// 给下划线留出约 2.5pt 的净空，避免两者叠在一起。
    var annotationGap: CGFloat = 7
    /// 下方标注中 emoji 与文字之间的间距
    var annotationEmojiToLabel: CGFloat = 3

    // MARK: - 拟声效果（点插入声音标记）

    /// 声音标记圆角
    var soundCornerRadius: CGFloat = 8
    /// 声音标记内边距
    var soundHorizontalPadding: CGFloat = 9
    var soundVerticalPadding: CGFloat = 3
    /// 声音标记名称字号
    var soundFontSize: CGFloat = 13
    /// 右上角外置 × 圆钮直径
    var soundDeleteButtonDiameter: CGFloat = 16

    // MARK: - 颜色（绘制时由 identity + appearance 解析覆盖；这里只作兜底）

    /// 填充色（背景）
    var fillColor: NSColor = NSColor(white: 1.0, alpha: 0.05)
    /// 描边色
    var strokeColor: NSColor = NSColor(white: 1.0, alpha: 0.10)
    /// 文本颜色
    var textColor: NSColor = NSColor(white: 0.92, alpha: 1.0)

    /// hover / 选中时的高亮填充色
    var fillColorHovered: NSColor = NSColor(white: 1.0, alpha: 0.09)
    var strokeColorHovered: NSColor = NSColor(white: 1.0, alpha: 0.16)

    /// 下划线颜色（语气标签作用域）
    var underlineColor: NSColor = fallbackBaseColor

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

    /// 英文 tag → 基础色。覆盖 Constants.emotions + Constants.richLanguageTags 全部 30 个标签。
    ///
    /// v5 重排：旧色板里多个 tag 共用一个色值（sad/crying/very slowly 同蓝，amazed/like dracula 同紫），
    /// 且 empathetic 没收录、落到哈希兜底，导致「惊叹」和「共情」撞在同一段紫色里难以分辨。
    /// 现在每个标签单独配色：色相铺满色环，同色系之间再用明度 / 饱和度拉开。
    /// 生成时用 CIE Lab ΔE 校验过两两距离：暗色模式最小 ΔE ≈ 13.7、亮色（压暗 40%）≈ 9。
    private static let colorMap: [String: NSColor] = [
        // 语气 / 情感控制类
        "sad":                    NSColorFromHex(0x6697D6),
        "amazed":                 NSColorFromHex(0xC07EE7),
        "deep and loud shouting": NSColorFromHex(0xE0493E),
        "trembling":              NSColorFromHex(0x51C0D6),
        "angry":                  NSColorFromHex(0xEB7633),
        "excited":                NSColorFromHex(0xF2CC36),
        "sarcastic":              NSColorFromHex(0x8EB238),
        "curious":                NSColorFromHex(0x45C485),
        "like dracula":           NSColorFromHex(0x9F4197),
        "bored":                  NSColorFromHex(0x7889A1),
        "tired":                  NSColorFromHex(0x4F8492),
        "scornful":               NSColorFromHex(0xAE6C3D),
        "shouting":               NSColorFromHex(0xE65673),
        "asmr":                   NSColorFromHex(0xDF86C1),
        "panicked":               NSColorFromHex(0xD83177),
        "mischievously":          NSColorFromHex(0x31B99E),
        "empathetic":             NSColorFromHex(0x64C760),
        "whispers":               NSColorFromHex(0x9A9ED6),
        "reluctantly":            NSColorFromHex(0x8978B0),
        "crying":                 NSColorFromHex(0x98CAEB),
        "serious":                NSColorFromHex(0xC9CCCF),
        "very slowly":            NSColorFromHex(0x8C79D8),
        "very fast":              NSColorFromHex(0xF6EF28),
        // 富语言 / 拟声类
        "laughing":               NSColorFromHex(0xF39E49),
        "giggles":                NSColorFromHex(0xE694A8),
        "sighing":                NSColorFromHex(0xC9A9D1),
        "gasp":                   NSColorFromHex(0x8ED7D1),
        "clears throat":          NSColorFromHex(0xC6BA8B),
        "cough":                  NSColorFromHex(0xA27967),
        "snorts":                 NSColorFromHex(0xAE4329)
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
    /// v3：语气 / 拟声都走情绪色（暗 = 原色；亮 = 压暗约 40% 保可读）。
    static func resolved(for identity: EmotionTokenIdentity, dark: Bool) -> EmotionTokenStyle {
        var s = EmotionTokenStyle.default
        let base = identity.baseColor
        s.dashedBorder = (identity.category == .richLanguage)

        if dark {
            s.textColor = base
            s.fillColor = base.withAlphaComponent(0.12)
            s.strokeColor = base.withAlphaComponent(0.60)
            s.fillColorHovered = base.withAlphaComponent(0.22)
            s.strokeColorHovered = base.withAlphaComponent(0.90)
            s.underlineColor = base
        } else {
            let t = base.darkened(by: 0.40)
            s.textColor = t
            s.fillColor = base.withAlphaComponent(0.10)
            s.strokeColor = base.withAlphaComponent(0.45)
            s.fillColorHovered = base.withAlphaComponent(0.20)
            s.strokeColorHovered = base.withAlphaComponent(0.80)
            s.underlineColor = t
        }
        return s
    }

    /// 判断某个外观是否为暗色。
    static func isDarkAppearance(_ appearance: NSAppearance) -> Bool {
        return appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}

/// 在 frame 内计算「× close 按钮」的命中区域（旧胶囊内删除，保留以兼容）
func emotionTokenDeleteHitRect(for frame: NSRect, style: EmotionTokenStyle) -> NSRect {
    guard style.showsDeleteButton else { return .zero }
    return NSRect(
        x: frame.maxX - style.deleteButtonWidth - 2,
        y: frame.minY,
        width: style.deleteButtonWidth + 4,
        height: frame.height
    )
}

/// 拟声声音标记：外置 × 圆钮的命中区域。
/// v9：位置改为**整个标签的正中间**（叠在名称文字上也可以），点击目标最大、最难误触到别的元素。
func soundDeleteHitRect(for frame: NSRect, style: EmotionTokenStyle) -> NSRect {
    let cx = frame.midX
    let cy = frame.midY
    let r = style.soundDeleteButtonDiameter + 6
    return NSRect(x: cx - r / 2, y: cy - r / 2, width: r, height: r)
}

/// 语气标签下方标注的布局结果（绘制与命中测试共用同一份，避免两边错位）。
struct ToneAnnotationLayout {
    /// 标注文字（emoji + 名称）的绘制原点
    let textOrigin: NSPoint
    /// 标注的悬停命中区（含留白）
    let textRect: NSRect
    /// 右侧 × 的命中区
    let closeRect: NSRect
}

/// 语气标签：下方标注的整体布局。
/// 标注画在 glyph 矩形之外（一行里属于它的只有 1px 宽的标记），不并入命中区的话，
/// 鼠标移到看得见的「😮 惊叹」上根本不会触发 hover，× 也就不会出现。
///
/// `maxX` 是文本容器的右边界：**标签插在行尾时，标注会画到容器外面被裁掉**，
/// 这时把整个标注（连同它的 ×）一起左移，保证完整可见。
/// 留白给得比字号多一点：标注是 10.5pt 的小字，紧贴边缘很难瞄。
func toneAnnotationLayout(for frame: NSRect,
                          label: String,
                          emoji: String,
                          style: EmotionTokenStyle,
                          maxX: CGFloat = CGFloat.greatestFiniteMagnitude) -> ToneAnnotationLayout? {
    let s = (emoji.isEmpty ? "" : emoji + " ") + label
    if s.isEmpty { return nil }
    let f = NSFont.systemFont(ofSize: style.annotationFontSize, weight: .medium)
    let size = (s as NSString).size(withAttributes: [.font: f])
    guard size.width > 0 else { return nil }

    let h = ceil(f.ascender - f.descender)
    let y = frame.maxY - h - 1
    let padX: CGFloat = 4
    let padY: CGFloat = 3
    let closeW: CGFloat = 18
    // 标注 + × 一起占据的总宽度
    let total = padX + size.width + 2 + closeW + padX

    var x = frame.minX - padX
    if maxX.isFinite, x + total > maxX { x = maxX - total }
    if x < 0 { x = 0 }

    return ToneAnnotationLayout(
        textOrigin: NSPoint(x: x + padX, y: y),
        textRect: NSRect(x: x, y: y - padY, width: size.width + padX * 2, height: h + padY * 2),
        closeRect: NSRect(x: x + padX + size.width + 1, y: y - 3, width: closeW, height: h + 6)
    )
}

/// 语气标签：下方标注的悬停命中区（container 坐标）
func toneAnnotationRect(for frame: NSRect, label: String, emoji: String, style: EmotionTokenStyle,
                        maxX: CGFloat = CGFloat.greatestFiniteMagnitude) -> NSRect? {
    toneAnnotationLayout(for: frame, label: label, emoji: emoji, style: style, maxX: maxX)?.textRect
}

/// 语气标签：下方标注里 × 的命中区域（× 绘制在 glyph 矩形之外，需由文本视图层命中）
func toneAnnotationCloseRect(for frame: NSRect, label: String, emoji: String, style: EmotionTokenStyle,
                             maxX: CGFloat = CGFloat.greatestFiniteMagnitude) -> NSRect? {
    toneAnnotationLayout(for: frame, label: label, emoji: emoji, style: style, maxX: maxX)?.closeRect
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
