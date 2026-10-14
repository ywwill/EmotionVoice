//
//  EmotionTokenAttachmentCell.swift
//  EmotionVoice
//
//  Created by young on 2026/9/1.
//
//  v3 · 两类标签的绘制：
//    · .emotion（语气）：标记是「零宽高占位」，在其下方绘制 emoji + 文字标注；
//      真正的语气作用域由文本下划线（EmotionTokenTextView.applyToneScopes）承担。
//    · .richLanguage（拟声）：在当前位置绘制一个声音标记（虚线框 + 播放三角 + 名称 +
//      右上角外置 × 圆钮），不代表任何文本，是一个点插入的声音事件。
//
//  设计要点：
//    * cellSize() 必须精确，否则附件高度会和普通文本不一致，破坏行高。
//    * cellBaselineOffset() 让 baseline 与 body font 对齐。
//    * trackMouse 负责 × 点击 → 删除整个 attachment。
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
    /// 所属文本容器（text container）的宽度。由 `EmotionTokenTextView` 在布局 / 尺寸变化时写入，
    /// 用于「标签在行尾时把下方标注左移，避免画到容器外被裁掉」。
    /// 之所以要外部写入：AppKit 绘制文本附件时 `controlView` 传的是 nil，取不到容器。
    nonisolated(unsafe) var containerMaxX: CGFloat = CGFloat.greatestFiniteMagnitude

    // MARK: - 尺寸

    nonisolated override func cellSize() -> NSSize {
        if tokenCategory == .richLanguage {
            return soundCellSize()
        }
        return toneCellSize()
    }

    private nonisolated func toneCellSize() -> NSSize {
        let style = EmotionTokenStyle.default
        let bodyFont = NSFont.systemFont(ofSize: 14)
        let bodyH = ceil(bodyFont.ascender - bodyFont.descender)
        let annoFont = NSFont.systemFont(ofSize: style.annotationFontSize, weight: .medium)
        let annoH = ceil(annoFont.ascender - annoFont.descender)
        // 标记自身只占 1px 宽；高度 = 正文高度 + 标注所需的下方留白，让标注落在该行下方、不压下一行。
        let height = bodyH + style.annotationGap + annoH + 2
        return NSSize(width: 1, height: height)
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
        // 语气标记：基线对齐正文，下方留出标注高度。
        let bodyFont = NSFont.systemFont(ofSize: 14)
        let annoFont = NSFont.systemFont(ofSize: style.annotationFontSize, weight: .medium)
        let annoH = ceil(annoFont.ascender - annoFont.descender)
        return NSPoint(x: 0, y: bodyFont.descender - style.annotationGap - annoH - 1)
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
        } else {
            drawToneAnnotation(in: frame, controlView: controlView, style: style)
        }
    }

    // MARK: - 语气标签：下方标注

    private nonisolated func toneAnnotationString() -> String {
        (tokenEmoji.isEmpty ? "" : tokenEmoji + " ") + tokenLabel
    }

    private nonisolated func toneAnnotationTextHeight(style: EmotionTokenStyle) -> CGFloat {
        let f = NSFont.systemFont(ofSize: style.annotationFontSize, weight: .medium)
        return ceil(f.ascender - f.descender)
    }

    private nonisolated func toneAnnotationSize(style: EmotionTokenStyle) -> CGSize {
        let s = toneAnnotationString()
        if s.isEmpty { return .zero }
        let f = NSFont.systemFont(ofSize: style.annotationFontSize, weight: .medium)
        return (s as NSString).size(withAttributes: [.font: f])
    }

    private func drawToneAnnotation(in frame: NSRect, controlView: NSView?, style: EmotionTokenStyle) {
        let hovered = (attachment.map { $0 === kEmotionAttachmentHovered } ?? false)
        let _ = (attachment.flatMap { kEmotionAttachmentSelectionStates[ObjectIdentifier($0)] } ?? false)

        let s = toneAnnotationString()
        if s.isEmpty { return }
        // 容器右边界：标签在行尾时标注要整体左移，否则会画到容器外被裁掉。
        // 注意不能从 controlView 取——**AppKit 绘制文本附件时传进来的 controlView 是 nil**（实测），
        // 所以这个值由 EmotionTokenTextView 在布局 / 尺寸变化时写进来。
        let maxX = min(containerMaxX,
                       (controlView as? NSTextView)?.textContainer?.size.width
                        ?? CGFloat.greatestFiniteMagnitude)
        guard let layout = toneAnnotationLayout(for: frame,
                                                label: tokenLabel,
                                                emoji: tokenEmoji,
                                                style: style,
                                                maxX: maxX) else { return }

        let f = NSFont.systemFont(ofSize: style.annotationFontSize, weight: .medium)
        let attrs: [NSAttributedString.Key: Any] = [.font: f, .foregroundColor: style.textColor]
        (s as NSString).draw(at: layout.textOrigin, withAttributes: attrs)

        // 删除 ×：悬停时出现（标注右侧）
        if hovered {
            let xStr = "×" as NSString
            let xAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 11, weight: .bold),
                .foregroundColor: style.textColor
            ]
            xStr.draw(at: NSPoint(x: layout.closeRect.minX + 2, y: layout.textOrigin.y),
                      withAttributes: xAttrs)
        }
    }

    // MARK: - 拟声效果：声音标记

    private func drawSound(in frame: NSRect, controlView: NSView?, style: EmotionTokenStyle) {
        let hovered = (attachment.map { $0 === kEmotionAttachmentHovered } ?? false)
        let selected = (attachment.flatMap { kEmotionAttachmentSelectionStates[ObjectIdentifier($0)] } ?? false)
        let dark = EmotionTokenStyle.isDarkAppearance(controlView?.effectiveAppearance ?? NSApp.effectiveAppearance)

        let radius = style.soundCornerRadius
        let path = NSBezierPath(roundedRect: frame.insetBy(dx: 0.5, dy: 0.5),
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
            let halo = NSBezierPath(roundedRect: frame.insetBy(dx: -1.5, dy: -1.5),
                                    xRadius: radius + 1.5, yRadius: radius + 1.5)
            style.textColor.withAlphaComponent(0.9).setStroke()
            halo.lineWidth = 2.0
            halo.stroke()
        }

        // 名称（v5：不再有播放三角，名称直接从内边距起排）
        let cy = frame.midY
        let lf = NSFont.systemFont(ofSize: style.soundFontSize, weight: .medium)
        let labelStr = tokenLabel as NSString
        let lsize = labelStr.size(withAttributes: [.font: lf, .foregroundColor: style.textColor])
        labelStr.draw(at: NSPoint(x: frame.minX + style.soundHorizontalPadding, y: cy - lsize.height / 2),
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
