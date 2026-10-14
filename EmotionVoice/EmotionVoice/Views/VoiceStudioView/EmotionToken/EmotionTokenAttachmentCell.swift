//
//  EmotionTokenAttachmentCell.swift
//  EmotionVoice
//
//  Created by young on 2026/9/1.
//
//  负责把 Emotion Token 绘制成 Pill/Capsule 样式：
//    ┌─────────────────┐
//    │ 😊 开心     ×  │
//    └─────────────────┘
//
// 设计要点：
//   * `cellSize()` 必须精确，否则附件高度会和普通文本不一致，破坏行高。
//   * `cellBaselineOffset()` 让 baseline 与 body font 对齐。
//   * `trackMouse(with:in:of:untilMouseUp:)` 负责 × 按钮点击 → 删除整个 attachment。
//

import AppKit

/// 单字符位的 attachment cell。NSTextStorage 中一个 character index 占一个 token。
final class EmotionTokenAttachmentCell: NSTextAttachmentCell {

    /// 通过 `EmotionTokenAttachment.makeAttachment` 时会设置。
    /// 这里只是冗余存储（FileWrapper 也存了一份）以便在渲染时直接拿到 label / emoji。
    ///
    /// 这两个字段在 attachment 构造完成后即不再变更，因此 `nonisolated(unsafe)` 安全。
    /// `NSTextAttachmentCell.cellSize()` / `cellBaselineOffset()` 在 AppKit 中是
    /// `nonisolated` 派生的，必须能脱离 main actor 读取这些尺寸输入。
    nonisolated(unsafe) var tokenLabel: String = ""
    nonisolated(unsafe) var tokenEmoji: String = ""

    // MARK: - 尺寸

    nonisolated override func cellSize() -> NSSize {
        let style = EmotionTokenStyle.default
        let labelString = tokenLabel as NSString
        let emojiWidth: CGFloat = tokenEmoji.isEmpty
            ? 0
            : (tokenEmoji as NSString).size(withAttributes: [.font: style.emojiFont]).width

        let labelSize = labelString.size(withAttributes: [.font: style.font])

        let deleteExtra: CGFloat = style.showsDeleteButton
            ? (style.labelToDeleteGap + style.deleteButtonWidth)
            : 0

        // 用 ascender-descender 决定高度，避免 NSString.size 引入行间距破坏 lineHeight。
        let emHeight = ceil(style.font.ascender - style.font.descender)
        let emojiGap: CGFloat = emojiWidth > 0 ? style.emojiToDotSpacing : 0
        let dotExtra: CGFloat = style.showColorDot
            ? (style.colorDotDiameter + style.dotToLabelSpacing)
            : 0
        let innerWidth = emojiWidth
            + emojiGap
            + dotExtra
            + labelSize.width
            + deleteExtra
        let width = ceil(style.horizontalPadding * 2 + innerWidth)

        return NSSize(
            width: max(width, 1),
            height: emHeight + style.verticalPadding * 2 + 2
        )
    }

    nonisolated override func cellBaselineOffset() -> NSPoint {
        let style = EmotionTokenStyle.default
        // pill 略高于 baseline 一点，使 emoji 中线和文本中线对齐
        return NSPoint(x: 0, y: style.font.descender - style.verticalPadding - 1)
    }

    // MARK: - 绘制

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?) {
        drawPill(in: cellFrame, controlView: controlView)
    }

    override func draw(withFrame cellFrame: NSRect, in controlView: NSView?, characterIndex charIndex: Int) {
        drawPill(in: cellFrame, controlView: controlView)
    }

    private func drawPill(in frame: NSRect, controlView: NSView?) {
        let style = resolvedStyle(for: controlView)
        let isDeleteHovered = (attachment.map { $0 === kEmotionAttachmentHovered } ?? false)
        let isSelected = (attachment.flatMap { kEmotionAttachmentSelectionStates[ObjectIdentifier($0)] } ?? false)

        let fill = (isDeleteHovered || isSelected) ? style.fillColorHovered : style.fillColor

        // 圆形胶囊
        let radius = style.cornerRadius > 0 ? style.cornerRadius : frame.height / 2
        let path = NSBezierPath(roundedRect: frame.insetBy(dx: 0.5, dy: 0.5),
                                xRadius: radius,
                                yRadius: radius)
        fill.setFill()
        path.fill()

        // 选中态：用情绪色描边 + 外圈 2px 彩环（对应设计稿 box-shadow 0 0 0 2px）；
        // 其余状态为中性描边，emoji / 文字保持中性，整体维持「低彩噪」。
        let mainStroke: NSColor
        let mainLineWidth: CGFloat
        if isSelected {
            mainStroke = style.dotColor
            mainLineWidth = 1.5
        } else {
            mainStroke = isDeleteHovered ? style.strokeColorHovered : style.strokeColor
            mainLineWidth = 1.0
        }

        if isSelected {
            let halo = NSBezierPath(roundedRect: frame.insetBy(dx: -1.5, dy: -1.5),
                                    xRadius: radius + 1.5,
                                    yRadius: radius + 1.5)
            style.dotColor.withAlphaComponent(0.9).setStroke()
            halo.lineWidth = 2.0
            halo.stroke()
        }

        mainStroke.setStroke()
        path.lineWidth = mainLineWidth
        if style.dashedBorder {
            // 拟声类（富语言）：虚线描边，和「语气」类的实线区分开
            path.setLineDash([3, 2.5], count: 2, phase: 0)
            path.stroke()
            path.setLineDash([], count: 0, phase: 0)
        } else {
            path.stroke()
        }

        // 计算 label 区域
        let emojiWidth: CGFloat = tokenEmoji.isEmpty
            ? 0
            : ((tokenEmoji as NSString).size(withAttributes: [.font: style.emojiFont]).width)

        let contentRect = NSRect(
            x: frame.minX + style.horizontalPadding,
            y: frame.minY,
            width: frame.width - style.horizontalPadding * 2 - (style.showsDeleteButton
                ? (style.labelToDeleteGap + style.deleteButtonWidth)
                : 0),
            height: frame.height
        )

        // 绘制 emoji（中性色，情绪色交给下方色点）
        var cursorX = contentRect.minX
        if !tokenEmoji.isEmpty {
            let emojiString = tokenEmoji as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: style.emojiFont,
                .foregroundColor: style.textColor
            ]
            let size = emojiString.size(withAttributes: attrs)
            emojiString.draw(in: NSRect(
                x: cursorX,
                y: frame.minY + (frame.height - size.height) / 2,
                width: size.width,
                height: size.height
            ), withAttributes: attrs)
            cursorX += emojiWidth + (emojiWidth > 0 ? style.emojiToDotSpacing : 0)
        }

        // 绘制情绪色点（极简色点标签的核心：仅 8px 圆点承载情绪色，界面保持低彩噪）
        if style.showColorDot {
            let dotSize = style.colorDotDiameter
            let dotRect = NSRect(x: cursorX,
                                 y: frame.minY + (frame.height - dotSize) / 2,
                                 width: dotSize,
                                 height: dotSize)
            style.dotColor.setFill()
            NSBezierPath(ovalIn: dotRect).fill()
            cursorX += dotSize + style.dotToLabelSpacing
        }

        // 绘制 label
        let labelString = tokenLabel as NSString
        let labelAttrs: [NSAttributedString.Key: Any] = [
            .font: style.font,
            .foregroundColor: style.textColor
        ]
        let labelSize = labelString.size(withAttributes: labelAttrs)
        let labelWidth = min(labelSize.width, contentRect.maxX - cursorX)
        if labelWidth > 0 {
            labelString.draw(in: NSRect(
                x: cursorX,
                y: frame.minY + (frame.height - labelSize.height) / 2,
                width: labelWidth,
                height: labelSize.height
            ), withAttributes: labelAttrs)
        }

        // 删除按钮：仅在可编辑时绘制。默认即清晰可见（不再依赖悬停才出现），
        // 悬停 / 选中时再提亮为满色。
        let editable = (controlView as? NSTextView)?.isEditable ?? false
        if style.showsDeleteButton && editable {
            let deleteColor: NSColor = (isDeleteHovered || isSelected)
                ? style.textColor
                : style.textColor.withAlphaComponent(0.55)

            let deleteAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 11, weight: .bold),
                .foregroundColor: deleteColor
            ]
            let deleteStr = "×" as NSString
            let deleteSize = deleteStr.size(withAttributes: deleteAttrs)
            let deleteX = frame.maxX - style.deleteButtonWidth + (style.deleteButtonWidth - deleteSize.width) / 2 - 1
            deleteStr.draw(in: NSRect(
                x: deleteX,
                y: frame.minY + (frame.height - deleteSize.height) / 2 - 1,
                width: deleteSize.width,
                height: deleteSize.height
            ), withAttributes: deleteAttrs)
        }
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

    // MARK: - Mouse tracking（让 × 按钮可点击）

    override func wantsToTrackMouse() -> Bool { true }

    override func trackMouse(with event: NSEvent,
                             in cellFrame: NSRect,
                             of controlView: NSView?,
                             untilMouseUp flag: Bool) -> Bool {
        guard let view = controlView as? EmotionTokenTextView,
              let storage = view.textStorage else {
            return false
        }
        let locationInView = view.convert(event.locationInWindow, from: nil)
        let style = resolvedStyle(for: controlView)

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

        if style.showsDeleteButton {
            let deleteRect = emotionTokenDeleteHitRect(for: cellFrame, style: style)
            if deleteRect.contains(locationInView) {
                // 删整个 attachment（连同前面的分隔空格，避免遗留 orphan / 双空格）
                _ = view.removeToken(at: range)
                return true
            }
        }

        // 击中 token 本体：选中它（这样用户 Backspace / Forward Delete 会整体删除）
        view.setSelectedRange(range)
        return true
    }
}
