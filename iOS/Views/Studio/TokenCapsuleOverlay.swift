//
//  TokenCapsuleOverlay.swift
//  iOSEmora
//
//  情感标签的绘制层：语气 = 整段同色胶囊 + 左上角徽章；拟声 = 行内虚线 pill。
//
//  为什么是独立一层而不是 NSTextAttachmentCell：
//  `NSTextAttachmentCell` 是 AppKit 专属，iOS 上没有对应物。这里把 overlay 作为
//  `UITextView` 的 subview 插入 —— UIScrollView 的子视图本身就跟着 contentOffset 滚动，
//  不需要额外同步滚动位置。
//
//  ⚠️ `hitTest` 只吞掉「×」那一小块：返回 nil 时触摸穿透到下面的 UITextView，
//  打字与选词不受影响。
//

import UIKit
import SwiftUI

final class TokenCapsuleOverlay: UIView {

    struct Config {
        var marks: [EmotionMark] = []
        var editable: Bool = true
        /// 当前深浅色（决定情感色是否压暗）
        var isDark: Bool = false
        /// 语气胶囊：填充 14% / 1px 内描边 42% / 圆角 9 / 内边距 6×8
        var capsuleFillAlpha: CGFloat = 0.14
        var capsuleStrokeAlpha: CGFloat = 0.42
        var capsuleCorner: CGFloat = 9
        var capsulePadX: CGFloat = 8
        var capsulePadY: CGFloat = 6
        /// 徽章（emoji + 名称）压在胶囊左上角
        var badgeHeight: CGFloat = 15
        var badgeFont = UIFont.systemFont(ofSize: 10.5, weight: .bold)
        /// 拟声 pill：虚线描边 + 10% 底，圆角 6
        var pillCorner: CGFloat = 6
        var pillFillAlpha: CGFloat = 0.10
        var pillFont = UIFont.systemFont(ofSize: 12, weight: .medium)

        var badgeBackground: UIColor = .secondarySystemBackground
        var primaryText: UIColor = .label
        var onRemove: ((UUID) -> Void)? = nil
    }

    weak var textView: UITextView?
    var config = Config()

    /// 本次绘制产出的「×」热区（命中测试用）
    private var removeTargets: [(rect: CGRect, id: UUID)] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        isOpaque = false
        backgroundColor = .clear
        contentMode = .redraw
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layoutSubviews() {
        super.layoutSubviews()
        // 覆盖整个可滚动内容区，随 text view 一起滚
        if let tv = textView {
            let h = max(tv.contentSize.height, tv.bounds.height)
            if abs(frame.height - h) > 0.5 || abs(frame.width - tv.bounds.width) > 0.5 {
                frame = CGRect(x: 0, y: 0, width: tv.bounds.width, height: h)
                setNeedsDisplay()
            }
        }
    }

    // MARK: - 命中测试

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard config.editable, let tv = textView else { return nil }
        let p = convert(point, from: tv)
        for target in removeTargets where target.rect.insetBy(dx: -6, dy: -6).contains(p) {
            return self
        }
        return nil
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let tv = textView, let touch = touches.first else { return }
        let p = convert(touch.location(in: tv), from: tv)
        for target in removeTargets where target.rect.insetBy(dx: -8, dy: -8).contains(p) {
            config.onRemove?(target.id)
            return
        }
        super.touchesEnded(touches, with: event)
    }

    // MARK: - 绘制

    override func draw(_ rect: CGRect) {
        guard let tv = textView else { return }
        let lm = tv.layoutManager
        let tc = tv.textContainer
        let inset = tv.textContainerInset
        let docLength = (tv.text as NSString).length

        removeTargets = []

        // 先画语气胶囊（含徽章），再画拟声 pill，保证 pill 压在胶囊之上
        let ordered = config.marks.sorted { $0.location < $1.location }

        for mark in ordered where mark.token.category == .emotion {
            let start = min(max(mark.location, 0), docLength)
            let end = min(max(TokenDocument.scopeEnd(of: mark, in: config.marks, docLength: docLength), start), docLength)
            let length = end - start
            guard length > 0 else { continue }
            drawCapsule(for: mark,
                        charRange: NSRange(location: start, length: length),
                        layoutManager: lm, container: tc, inset: inset)
        }

        for mark in ordered where mark.token.category == .richLanguage {
            let loc = min(max(mark.location, 0), max(docLength - 1, 0))
            drawPill(for: mark,
                     charRange: NSRange(location: loc, length: 1),
                     layoutManager: lm, container: tc, inset: inset)
        }
    }

    // MARK: 语气胶囊

    private func drawCapsule(for mark: EmotionMark,
                             charRange: NSRange,
                             layoutManager lm: NSLayoutManager,
                             container tc: NSTextContainer,
                             inset: UIEdgeInsets) {
        let lineRects = Self.lineRects(charRange: charRange, layoutManager: lm, container: tc)
        guard !lineRects.isEmpty else { return }

        let base = UIColor(Self.emotionColor(for: mark.token, dark: config.isDark))
        let fill = base.withAlphaComponent(config.capsuleFillAlpha)
        let stroke = base.withAlphaComponent(config.capsuleStrokeAlpha)

        // 一条 Path 一次填充：逐行 fill 会在长文本上产生几十次绘制调用
        let path = UIBezierPath()
        var firstRect: CGRect = .zero
        var isFirst = true
        for r in lineRects {
            let shifted = r.offsetBy(dx: inset.left, dy: inset.top)
            let capsule = shifted.insetBy(dx: -config.capsulePadX, dy: -config.capsulePadY)
            path.append(UIBezierPath(roundedRect: capsule, cornerRadius: config.capsuleCorner))
            if isFirst { firstRect = capsule; isFirst = false }
        }
        fill.setFill()
        path.fill()
        stroke.setStroke()
        path.lineWidth = 1
        path.stroke()

        drawBadge(for: mark, at: firstRect, color: base)
    }

    private func drawBadge(for mark: EmotionMark, at capsule: CGRect, color: UIColor) {
        let label = mark.token.label
        let emoji = mark.token.emoji
        let text = emoji.isEmpty ? label : "\(emoji) \(label)"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: config.badgeFont,
            .foregroundColor: color
        ]
        var textW = (text as NSString).size(withAttributes: attrs).width
        textW = ceil(textW)

        // × 热区：常显（iOS 没有 hover），命中区外扩到 44pt 见方的手感
        let xSize: CGFloat = config.editable ? 15 : 0
        let w = textW + 7 + 3 + xSize + 5
        let h = config.badgeHeight
        // 徽章压在胶囊左上角：底边略微压进胶囊上沿
        let rect = CGRect(x: capsule.minX + config.capsulePadX - 4,
                          y: capsule.minY - h + 2,
                          width: w,
                          height: h)

        // 徽章底色 = 编辑器背景，用来「切断」胶囊上沿
        let bg = UIBezierPath(roundedRect: rect, cornerRadius: h / 2)
        config.badgeBackground.setFill()
        bg.fill()

        let textRect = CGRect(x: rect.minX + 5, y: rect.minY, width: textW, height: h)
        (text as NSString).draw(in: textRect, withAttributes: attrs)

        if config.editable {
            let xRect = CGRect(x: rect.maxX - xSize - 3, y: rect.minY + (h - xSize) / 2,
                               width: xSize, height: xSize)
            let xPath = UIBezierPath(ovalIn: xRect)
            color.withAlphaComponent(0.18).setFill()
            xPath.fill()
            let glyph = "×"
            let gAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 11, weight: .bold),
                .foregroundColor: color
            ]
            let gSize = (glyph as NSString).size(withAttributes: gAttrs)
            (glyph as NSString).draw(
                at: CGPoint(x: xRect.midX - gSize.width / 2, y: xRect.midY - gSize.height / 2),
                withAttributes: gAttrs
            )
            removeTargets.append((rect: xRect, id: mark.id))
        }
    }

    // MARK: 拟声 pill

    private func drawPill(for mark: EmotionMark,
                          charRange: NSRange,
                          layoutManager lm: NSLayoutManager,
                          container tc: NSTextContainer,
                          inset: UIEdgeInsets) {
        let lineRects = Self.lineRects(charRange: charRange, layoutManager: lm, container: tc)
        guard let r = lineRects.first else { return }

        let base = UIColor(Self.emotionColor(for: mark.token, dark: config.isDark))
        let rect = r.offsetBy(dx: inset.left, dy: inset.top)

        let path = UIBezierPath(roundedRect: rect, cornerRadius: config.pillCorner)
        base.withAlphaComponent(config.pillFillAlpha).setFill()
        path.fill()
        base.withAlphaComponent(0.55).setStroke()
        path.setLineDash([3, 2], count: 2, phase: 0)
        path.lineWidth = 1
        path.stroke()

        let label = mark.token.label
        let attrs: [NSAttributedString.Key: Any] = [
            .font: config.pillFont,
            .foregroundColor: base
        ]
        let xSize: CGFloat = config.editable ? 14 : 0
        let textRect: CGRect = CGRect(x: rect.minX + 7, y: rect.minY,
                              width: max(rect.width - 7 - xSize - 4, 0),
                              height: rect.height)
        // ⚠️ 不能写 `draw(in:with:)`：UIKit 的 NSString 扩展里同时有
        // `draw(in:withFont:)`，编译器会优先选中它然后报类型不符。
        label.draw(with: textRect,
                   options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
                   attributes: attrs,
                   context: nil)

        if config.editable {
            let xRect = CGRect(x: rect.maxX - xSize - 2,
                               y: rect.midY - xSize / 2,
                               width: xSize, height: xSize)
            let glyph = "×"
            let gAttrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 11, weight: .bold),
                .foregroundColor: base
            ]
            let gSize = (glyph as NSString).size(withAttributes: gAttrs)
            (glyph as NSString).draw(
                at: CGPoint(x: xRect.midX - gSize.width / 2, y: xRect.midY - gSize.height / 2),
                withAttributes: gAttrs
            )
            removeTargets.append((rect: xRect, id: mark.id))
        }
    }

    // MARK: - 工具

    /// 一个字符区间落在各行上的矩形（处理换行：同一作用域跨行会切成多个胶囊）
    static func lineRects(charRange: NSRange,
                          layoutManager lm: NSLayoutManager,
                          container tc: NSTextContainer) -> [CGRect] {
        let glyphRange = lm.glyphRange(forCharacterRange: charRange, actualCharacterRange: nil)
        guard glyphRange.length > 0 else { return [] }

        var result: [CGRect] = []
        lm.enumerateLineFragments(forGlyphRange: glyphRange) { _, usedRect, textContainer, fragRange, _ in
            let inter = NSIntersectionRange(fragRange, glyphRange)
            guard inter.length > 0 else { return }
            var r = lm.boundingRect(forGlyphRange: inter, in: textContainer)
            // 同一行用统一行高，保证胶囊上下沿齐平
            r.origin.y = usedRect.origin.y
            r.size.height = usedRect.height
            result.append(r)
        }
        return result
    }

    /// 情感色（沿用 macOS 的 30 色 mapping）
    static func emotionColor(for token: EmotionToken, dark: Bool = false) -> Color {
        EmotionPalette.color(forTag: token.englishTag, scheme: dark ? .dark : .light)
    }
}

// MARK: - 拟声占位附件

/// 只为拟声标签占出一块行内矩形，自己不画任何东西（pill 由 overlay 画）。
final class SoundPlaceholderAttachment: NSTextAttachment {

    let wantedWidth: CGFloat
    let wantedHeight: CGFloat
    /// 基线偏移：让 pill 与正文视觉居中
    let baselineOffset: CGFloat

    init(width: CGFloat, height: CGFloat, baselineOffset: CGFloat) {
        self.wantedWidth = width
        self.wantedHeight = height
        self.baselineOffset = baselineOffset
        super.init(data: nil, ofType: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func attachmentBounds(for textContainer: NSTextContainer?,
                                   proposedLineFragment lineFrag: CGRect,
                                   glyphPosition position: CGPoint,
                                   characterIndex charIndex: Int) -> CGRect {
        CGRect(x: 0, y: baselineOffset, width: wantedWidth, height: wantedHeight)
    }
}
