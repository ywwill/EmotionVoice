//
//  EmotionTokenAttachmentCell.swift
//  EmotionVoice
//
//  Created by young on 2026/9/1.
//
//  v13 · 两类标签的绘制：
//    · .emotion（语气）：标记是 1×1 的**不可见占位**，什么都不画。
//      作用域的视觉（整段胶囊 + 左上角徽章）全部由 EmotionTokenTextView 自绘——
//      胶囊必须画在字形下面、徽章必须画在字形上面，只有文本视图拿得到那个时机。
//    · .richLanguage（拟声）：在当前位置绘制一个声音标记（虚线框 + 名称 +
//      悬停时正中浮出的 × 圆钮），不代表任何文本，是一个点插入的声音事件。
//
//  设计要点：
//    * cellSize() 必须精确，否则附件高度会和普通文本不一致，破坏行高。
//    * cellBaselineOffset() 让 baseline 与 body font 对齐。
//    * 删除逻辑统一由 EmotionTokenTextView.mouseDown 命中（cell 只负责「命中本体 → 选中」）。
//

import AppKit

/// 单字符位的 attachment cell。NSTextStorage 中一个 character index 占一个 token。
final class EmotionTokenAttachmentCell: NSTextAttachmentCell {

    /// 通过 `EmotionTokenAttachment.makeAttachment` 时会设置。
    /// 这些字段在 attachment 构造完成后即不再变更，因此 `nonisolated(unsafe)` 安全。
    /// `cellSize()` / `cellBaselineOffset()` 在 AppKit 中是 `nonisolated` 派生的，
    /// 必须能脱离 main actor 读取这些尺寸输入。
    nonisolated(unsafe) var tokenLabel: String = ""
    nonisolated(unsafe) var tokenEmoji: String = ""
    /// 标签家族（语气 / 拟声），驱动 cellSize / 绘制分支（nonisolated 安全，构造后不变）。
    nonisolated(unsafe) var tokenCategory: EmotionCategory = .emotion
    /// 所属文本容器（text container）的宽度。由 `EmotionTokenTextView` 在布局 / 尺寸变化时写入。
    /// 之所以要外部写入：AppKit 绘制文本附件时 `controlView` 传的是 nil，取不到容器。
    /// v13 起语气徽章的定位改由文本视图用 `textContainer.size.width` 直接算，这里仅作保留。
    nonisolated(unsafe) var containerMaxX: CGFloat = CGFloat.greatestFiniteMagnitude

    // MARK: - 尺寸

    nonisolated override func cellSize() -> NSSize {
        if tokenCategory == .richLanguage {
            return soundCellSize()
        }
        return toneCellSize()
    }

    /// v13（胶囊版）：语气标记彻底变成**不可见占位**。
    /// 作用域的视觉由「整段胶囊 + 左上角徽章」承担，两者都由 EmotionTokenTextView 自绘，
    /// cell 不再画任何东西，也不再因为要挂标注而额外撑高行高。
    /// 宽度取 `toneMarkerWidth`（5pt）而不是 1pt：
    /// 这是相邻两个语气作用域之间唯一的物理间距，靠它 `resolveCapsuleSeams` 才切得出
    /// 真正的 `capsuleSeamGap` 间隙（1pt 时两段文本几乎贴死，两侧 8pt 内边距必然重叠）。
    private nonisolated func toneCellSize() -> NSSize {
        NSSize(width: EmotionTokenStyle.default.toneMarkerWidth, height: 1)
    }

    private nonisolated func soundCellSize() -> NSSize {
        let style = EmotionTokenStyle.default
        let f = NSFont.systemFont(ofSize: style.soundFontSize, weight: .medium)
        let name = tokenLabel as NSString
        let nameSize = name.size(withAttributes: [.font: f])
        // v5：去掉播放三角（点击并不真的播放，图标会误导），只剩名称
        let width = ceil(style.soundHorizontalPadding * 2 + nameSize.width)
        let emH = ceil(f.ascender - f.descender)
        let height = emH + style.soundVerticalPadding * 2
        return NSSize(width: max(width, 1), height: height)
    }

    nonisolated override func cellBaselineOffset() -> NSPoint {
        let style = EmotionTokenStyle.default
        if tokenCategory == .richLanguage {
            let f = NSFont.systemFont(ofSize: style.soundFontSize, weight: .medium)
            return NSPoint(x: 0, y: f.descender - style.soundVerticalPadding - 1)
        }
        // 语气标记：1×1 的不可见占位，基线直接对齐正文即可。
        return .zero
    }

    // MARK: - 绘制分发

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?) {
        drawToken(in: cellFrame, controlView: controlView)
    }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?, characterIndex charIndex: Int) {
        drawToken(in: cellFrame, controlView: controlView)
    }

    private func drawToken(in frame: NSRect, controlView: NSView?) {
        guard let att = attachment else { return }
        let identity = kEmotionAttachmentIdentity[ObjectIdentifier(att)]
            ?? EmotionTokenIdentity(baseColor: EmotionTokenStyle.fallbackBaseColor, category: .emotion)
        let style = resolvedStyle(for: controlView)
        if identity.category == .richLanguage {
            drawSound(in: frame, controlView: controlView, style: style)
        }
        // 语气标记：不可见占位，什么都不画（见 drawToneMarker）
    }

    // MARK: - 语气标记：不可见占位

    // MARK: - 拟声效果：声音标记

    private func drawSound(in frame: NSRect, controlView: NSView?, style: EmotionTokenStyle) {
        let hovered = (attachment.map { $0 === kEmotionAttachmentHovered } ?? false)
        let selected = (attachment.flatMap { kEmotionAttachmentSelectionStates[ObjectIdentifier($0)] } ?? false)
        let dark = EmotionTokenStyle.isDarkAppearance(controlView?.effectiveAppearance ?? NSApp.effectiveAppearance)

        // 左右各内缩 soundEdgeInset：给两边的语气胶囊留出收尾空间，
        // 否则胶囊的 8pt 内边距会压到 pill 底下，从 pill 半透明的填充里透出一道重叠的描边。
        let box = frame.insetBy(dx: style.soundEdgeInset, dy: 0)
        let radius = style.soundCornerRadius
        let path = NSBezierPath(roundedRect: box.insetBy(dx: 0.5, dy: 0.5),
                                xRadius: radius, yRadius: radius)

        // 填充
        (hovered || selected ? style.fillColorHovered : style.fillColor).setFill()
        path.fill()

        // 描边（拟声 = 虚线）
        let stroke = selected ? style.textColor : (hovered ? style.strokeColorHovered : style.strokeColor)
        stroke.setStroke()
        path.lineWidth = selected ? 1.5 : 1.0
        if style.dashedBorder {
            path.setLineDash([3, 2.5], count: 2, phase: 0)
            path.stroke()
            path.setLineDash([], count: 0, phase: 0)
        } else {
            path.stroke()
        }

        // 选中态：情绪色外圈彩环
        if selected {
            let halo = NSBezierPath(roundedRect: box.insetBy(dx: -1.5, dy: -1.5),
                                    xRadius: radius + 1.5, yRadius: radius + 1.5)
            style.textColor.withAlphaComponent(0.9).setStroke()
            halo.lineWidth = 2.0
            halo.stroke()
        }

        // 名称（v5：不再有播放三角）。pill 内缩过，所以名称按内缩后的盒子**居中**排，
        // 左右留白才对称（仍按内边距起排的话右边只剩 1pt）。
        let lf = NSFont.systemFont(ofSize: style.soundFontSize, weight: .medium)
        let labelStr = tokenLabel as NSString
        let lsize = labelStr.size(withAttributes: [.font: lf, .foregroundColor: style.textColor])
        labelStr.draw(at: NSPoint(x: box.midX - lsize.width / 2, y: box.midY - lsize.height / 2),
                      withAttributes: [.font: lf, .foregroundColor: style.textColor])

        // 居中 × 圆钮：v5 起仅悬停时绘制；v9 位置改到整个标签正中间（叠在名称上不再外挂）。
        // 因为压在文字上，填充给足不透明度 + 加一圈描边，保证 × 依然清晰可辨。
        guard hovered else { return }
        let d = style.soundDeleteButtonDiameter
        let cx = frame.midX
        let cyx = frame.midY
        let circle = NSBezierPath(ovalIn: NSRect(x: cx - d / 2, y: cyx - d / 2, width: d, height: d))
        let xfill: NSColor = dark ? NSColor(white: 0.16, alpha: 1.0) : NSColor.white
        let xstroke: NSColor = dark ? NSColor(white: 1.0, alpha: 0.18) : NSColor(white: 0.0, alpha: 0.18)
        xfill.setFill()
        circle.fill()
        xstroke.setStroke()
        circle.lineWidth = 1.0
        circle.stroke()

        let xg = "×" as NSString
        let xga: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12, weight: .bold),
            .foregroundColor: dark ? NSColor.white : NSColor(white: 0.2, alpha: 1.0)
        ]
        let xgs = xg.size(withAttributes: xga)
        xg.draw(at: NSPoint(x: cx - xgs.width / 2, y: cyx - xgs.height / 2), withAttributes: xga)
    }

    /// 由 attachment 的身份 + 当前外观解析最终样式（几何沿用 .default）。
    private func resolvedStyle(for view: NSView?) -> EmotionTokenStyle {
        guard let att = attachment else { return .default }
        let identity = kEmotionAttachmentIdentity[ObjectIdentifier(att)]
            ?? EmotionTokenIdentity(baseColor: EmotionTokenStyle.fallbackBaseColor, category: .emotion)
        let appearance = view?.effectiveAppearance ?? NSApp.effectiveAppearance
        return EmotionTokenStyle.resolved(for: identity,
                                         dark: EmotionTokenStyle.isDarkAppearance(appearance))
    }

    // MARK: - Mouse tracking

    override func wantsToTrackMouse() -> Bool { true }

    override func trackMouse(with event: NSEvent,
                             in cellFrame: NSRect,
                             of controlView: NSView?,
                             untilMouseUp flag: Bool) -> Bool {
        guard let view = controlView as? EmotionTokenTextView,
              let storage = view.textStorage else {
            return false
        }
        guard let target = self.attachment else { return false }

        // 找到 attachment 在 storage 中对应的 range
        var tokenRange: NSRange?
        storage.enumerateAttributes(in: NSRange(location: 0, length: storage.length)) { attrs, range, stop in
            if let att = attrs[.attachment] as? NSTextAttachment, att === target {
                tokenRange = range
                stop.pointee = true
            }
        }
        guard let range = tokenRange else { return false }

        // v6：删除逻辑统一由 EmotionTokenTextView.mouseDown 处理。
        // 之前这里也做了一份 × 命中，但 cellFrame 是 container 坐标系、
        // 事件坐标是 view 坐标系，两者差一个 textContainerOrigin，
        // 保留第二份只会引入偏移的误删风险。这里只负责「命中本体 → 选中」。
        view.setSelectedRange(range)
        return true
    }
}
