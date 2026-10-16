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

    // MARK: - 语气标签（整段胶囊）

    /// 语气作用域的整段文本包进一个同色胶囊：填充 = 情绪色 13%、1px 内描边 42%、圆角 9。
    /// 颜色本身就是「这段用什么语气」的信号，信息量比单一下划线更大。
    var capsuleCornerRadius: CGFloat = 9
    /// 胶囊水平内边距：文本左右各留这么多
    var capsuleHorizontalPadding: CGFloat = 8
    /// 相邻两块（胶囊↔胶囊、胶囊↔拟声 pill）之间要留出的净间隙。
    var capsuleSeamGap: CGFloat = 2
    /// 接缝收敛时每侧至少保留的内边距。
    ///
    /// 0 = 允许胶囊边缘贴到文字的 advance 边界。CJK / 拉丁字形本身有约 0.6pt 的左右边距，
    /// 所以贴边也不会压到笔画；再小就会切进字形了。
    var capsuleSeamMinPadding: CGFloat = 0
    /// 语气标记在文本流里占的宽度。
    ///
    /// 标记本身不可见，但它是相邻两个语气作用域之间**唯一**的物理间距：
    /// 文档里两段作用域文本只隔这一个字符位，两侧各 8px 的内边距必然互相压进去，
    /// 再怎么收敛都留不出缝隙。把它加宽到 5px（≈1/3 个汉字）后，
    /// `resolveCapsuleSeams` 才能在接缝处切出真正的 `capsuleSeamGap` 间隙。
    /// 设计稿里这一步是 CSS 的 `margin: 0 4px`（两段之间共 8px），这里是 AppKit 版的等价物。
    var toneMarkerWidth: CGFloat = 5
    /// 胶囊垂直内边距：文本上下各留这么多（v12 由 4 → 6，文本不再贴着描边）
    var capsuleVerticalPadding: CGFloat = 6
    /// 胶囊填充不透明度：常态 0.13，悬停抬到 0.20
    var capsuleFillAlpha: CGFloat = 0.13
    var capsuleFillAlphaHovered: CGFloat = 0.20
    /// 胶囊 1px 内描边的不透明度
    var capsuleStrokeAlpha: CGFloat = 0.42
    /// 选中态：胶囊外再套一圈 2px 情绪色光环
    var capsuleSelectionRingAlpha: CGFloat = 0.90
    /// 作用域为空（标签后面还没输入文字）时，兜底画一个最小宽度的空胶囊，
    /// 否则徽章无处安放，标签会变成看不见也删不掉的幽灵。
    var capsuleEmptyWidth: CGFloat = 20

    // MARK: - 左上角徽章（emoji + 名称）

    /// 徽章字号（加粗，压在胶囊左上角）
    var badgeFontSize: CGFloat = 10.5
    /// 徽章字体
    var badgeFont: NSFont { NSFont.systemFont(ofSize: badgeFontSize, weight: .bold) }
    var badgeCornerRadius: CGFloat = 5
    var badgeHorizontalPadding: CGFloat = 6
    var badgeVerticalPadding: CGFloat = 3
    /// 徽章文字与右侧 × 之间的间隙
    var badgeToCloseGap: CGFloat = 3
    /// 徽章相对胶囊左上角：向上探出的距离（需要 textContainerInset 留出等量 + 余量的顶部空间）
    var badgeTopOffset: CGFloat = 14
    /// 徽章相对胶囊左上角：向右的偏移
    var badgeLeftOffset: CGFloat = 6
    /// 徽章描边不透明度（底色取编辑器背景，保证压在任何文本上都读得清）
    var badgeStrokeAlpha: CGFloat = 0.5
    /// 徽章右侧 × 的宽度。常态也占位（只是不绘制），避免悬停时徽章变宽跳动。
    var badgeCloseWidth: CGFloat = 13

    // MARK: - 拟声效果（点插入声音标记）

    /// 声音标记圆角（v12：8 → 6，更轻）
    var soundCornerRadius: CGFloat = 6
    /// 声音标记内边距（v12：9 / 3 → 7 / 1.5，不再撑行）
    var soundHorizontalPadding: CGFloat = 7
    var soundVerticalPadding: CGFloat = 1.5
    /// 拟声 pill 的绘制 / 接缝内缩。
    ///
    /// cell 的 advance 宽度不变，但 pill 只画在中间：左右各让出 3pt 给两边的语气胶囊收尾，
    /// 否则胶囊的 8px 内边距会直接压到 pill 底下（pill 画在上层，看得见一道重叠的描边）。
    var soundEdgeInset: CGFloat = 3
    /// 声音标记名称字号（v12：13 → 12）
    var soundFontSize: CGFloat = 12
    /// 居中浮出的 × 圆钮直径（v12：16 → 14）
    var soundDeleteButtonDiameter: CGFloat = 14

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

        // 胶囊由文本视图自绘（用 scope.color + capsuleFillAlpha 等），
        // 这里的 fillColor / strokeColor 只服务拟声标记：v12 起整体减淡，
        // 常态不抢正文注意力，悬停才抬到 0.18。
        if dark {
            s.textColor = base
            s.fillColor = base.withAlphaComponent(0.10)
            s.strokeColor = base.withAlphaComponent(0.45)
            s.fillColorHovered = base.withAlphaComponent(0.18)
            s.strokeColorHovered = base.withAlphaComponent(0.70)
        } else {
            let t = base.darkened(by: 0.40)
            s.textColor = t
            s.fillColor = base.withAlphaComponent(0.10)
            s.strokeColor = base.withAlphaComponent(0.45)
            s.fillColorHovered = base.withAlphaComponent(0.18)
            s.strokeColorHovered = base.withAlphaComponent(0.70)
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

/// 语气标签「左上角徽章」的布局结果（绘制与命中测试共用同一份，避免两边错位）。
struct ToneBadgeLayout {
    /// 徽章本体（含左右内边距 + 右侧 × 的预留位）
    let rect: NSRect
    /// 徽章文字（emoji + 名称）的绘制原点
    let textOrigin: NSPoint
    /// 右侧 × 的命中区（比徽章略高，好点）
    let closeRect: NSRect
}

/// 语气标签：徽章挂在作用域**首块胶囊的左上角**（向上探出 `badgeTopOffset`）。
/// 绘制与命中都走这一份，鼠标移到看得见的「😮 惊叹」上才可能触发 hover。
///
/// `maxX` 是文本容器的右边界：**作用域起点贴着行尾时，徽章会画到容器外面被裁掉**，
/// 这时把整个徽章（连同它的 ×）一起左移，保证完整可见。
/// `minY` 是容器顶部的下界（= `-textContainerOrigin.y`）：徽章压在首行胶囊上沿之外，
/// 顶部留白不够时会被容器裁掉一半——这里兜底把它压回可见区域，宁可多盖一点胶囊也不能缺一块。
/// × 的位置常态也占位，只是不绘制，避免悬停时徽章宽度跳动。
func toneBadgeLayout(forCapsule capsule: NSRect,
                     label: String,
                     emoji: String,
                     style: EmotionTokenStyle,
                     maxX: CGFloat = CGFloat.greatestFiniteMagnitude,
                     minY: CGFloat = -CGFloat.greatestFiniteMagnitude) -> ToneBadgeLayout? {
    let s = (emoji.isEmpty ? "" : emoji + " ") + label
    if s.isEmpty { return nil }
    let f = style.badgeFont
    let size = (s as NSString).size(withAttributes: [.font: f])
    guard size.width > 0 else { return nil }

    let textW = ceil(size.width)
    let textH = ceil(f.ascender - f.descender)
    let h = textH + style.badgeVerticalPadding * 2
    let w = style.badgeHorizontalPadding * 2 + textW + style.badgeToCloseGap + style.badgeCloseWidth

    var x = capsule.minX + style.badgeLeftOffset
    var y = capsule.minY - style.badgeTopOffset
    if maxX.isFinite, x + w > maxX { x = max(0, maxX - w) }
    if minY.isFinite { y = max(y, minY) }

    return ToneBadgeLayout(
        rect: NSRect(x: x, y: y, width: w, height: h),
        textOrigin: NSPoint(x: x + style.badgeHorizontalPadding,
                            y: y + style.badgeVerticalPadding),
        closeRect: NSRect(x: x + style.badgeHorizontalPadding + textW + style.badgeToCloseGap,
                          y: y - 2,
                          width: style.badgeCloseWidth,
                          height: h + 4)
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
