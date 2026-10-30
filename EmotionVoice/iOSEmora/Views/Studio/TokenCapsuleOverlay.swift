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
        /// 相邻两段胶囊之间留出的缝隙（两侧 `capsulePadX` 会互相压进去 16pt，必须收敛）
        var capsuleSeamGap: CGFloat = 2
        /// 收敛时每侧至少要给文字留的内边距：宁可留一点重叠，也不切到字形
        var capsuleSeamMinPadding: CGFloat = 3
        /// 徽章（emoji + 名称）压在胶囊左上角
        var badgeHeight: CGFloat = 15
        var badgeFont = UIFont.systemFont(ofSize: 10.5, weight: .bold)
        /// 拟声 pill：只留虚线描边，**不铺底色**（铺底会在标签文字后面形成一块背景），圆角 6
        var pillCorner: CGFloat = 6
        /// 拟声 pill 的固定高度。⚠️ 不能拿行高当高度：正文 lineSpacing = 26，
        /// 行片段矩形会被撑到 45pt 上下，画出来就是一条和整行一样高的色块。
        var pillHeight: CGFloat = 20
        var pillFont = UIFont.systemFont(ofSize: 12, weight: .medium)

        /// 空作用域（标签后面还没有文字 / 标签在文末）时兜底胶囊的最小宽度。
        /// ⚠️ 没有这个兜底，在文末点一个语气标签会画出一条 0 宽的胶囊 —— 徽章也没处安放，
        /// 标签就变成「看不见又删不掉」的幽灵（macOS 侧同样有这条规则）。
        var emptyScopeWidth: CGFloat = 34
        var fallbackLineHeight: CGFloat = 19

        /// 正文的 `NSParagraphStyle.lineSpacing`。
        /// ⚠️ TextKit 把它算进了 `lineFragmentUsedRect`：16pt 正文 + 26 行距 →
        /// usedRect 高 45pt，而字形只贴在它顶部那 19pt。直接把 usedRect 当胶囊高度，
        /// 换行后上下两块必然叠在一起。绘制前必须减掉它还原成真实字高。
        var lineSpacing: CGFloat = 26

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

    // ⚠️ `hitTest` 的 point 已经在**自己的** bounds 里，removeTargets 也是同一套坐标
    // （overlay 的 frame.origin 恒为 (0,0)，且挂在 UIScrollView 下随内容滚动），
    // 所以不需要再做 convert —— 早年多转一次反而把触摸点挪偏了。
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        guard config.editable, textView != nil else { return nil }
        for target in removeTargets where target.rect.insetBy(dx: -6, dy: -6).contains(point) {
            return self
        }
        return nil
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard textView != nil, let touch = touches.first else { return }
        let p = touch.location(in: self)
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

        let ordered = TokenDocument.orderedMarks(config.marks)
        guard !ordered.isEmpty else { return }

        var boxes: [SeamBox] = []

        // 1) 拟声 pill 先量好：它们是实心块，语气胶囊要给它们让位
        let soundLocations = Set(ordered
            .filter { $0.token.category == .richLanguage }
            .map { min(max($0.location, 0), max(docLength - 1, 0)) })

        for mark in ordered where mark.token.category == .richLanguage {
            let loc = min(max(mark.location, 0), max(docLength - 1, 0))
            guard let m = Self.pillRect(charRange: NSRange(location: loc, length: 1),
                                        layoutManager: lm, container: tc,
                                        pillHeight: config.pillHeight,
                                        lineSpacing: config.lineSpacing,
                                        fallbackLineHeight: config.fallbackLineHeight) else { continue }
            let r = m.rect.offsetBy(dx: inset.left, dy: inset.top)
            boxes.append(SeamBox(rect: r, textRect: r,
                                 lineMinY: m.lineMinY + inset.top, isSolid: true, mark: nil))
        }

        // 2) 语气胶囊：作用域按拟声占位切成多段
        for (i, mark) in ordered.enumerated() where mark.token.category == .emotion {
            let start = min(max(mark.location, 0), docLength)
            let end = min(max(TokenDocument.scopeEnd(at: i, in: ordered, docLength: docLength), start), docLength)

            var rects: [CGRect] = []
            if end > start {
                for piece in TokenDocument.scopePieces(start: start, end: end, soundLocations: soundLocations) {
                    rects.append(contentsOf: Self.lineRects(charRange: piece,
                                                            layoutManager: lm, container: tc,
                                                            lineSpacing: config.lineSpacing,
                                                            fallbackLineHeight: config.fallbackLineHeight))
                }
            }
            if rects.isEmpty {
                // 空作用域（标签后还没文字 / 标签在文末）：补一个最小宽度的兜底胶囊，
                // 否则标签既看不见也点不掉
                let anchor = Self.emptyScopeRect(characterIndex: start,
                                                 layoutManager: lm, container: tc,
                                                 docLength: docLength,
                                                 lineSpacing: config.lineSpacing,
                                                 fallbackLineHeight: config.fallbackLineHeight)
                rects = [Self.expand(anchor, toMinWidth: config.emptyScopeWidth)]
            }

            for r in rects {
                let capsule = r.insetBy(dx: -config.capsulePadX, dy: -config.capsulePadY)
                    .offsetBy(dx: inset.left, dy: inset.top)
                let clamped = Self.clampX(capsule,
                                          minX: inset.left,
                                          maxX: inset.left + tc.size.width)
                boxes.append(SeamBox(rect: clamped,
                                     textRect: r.offsetBy(dx: inset.left, dy: inset.top),
                                     lineMinY: r.minY + inset.top,
                                     isSolid: false, mark: mark))
            }
        }

        // 3) 接缝收敛：相邻两段之间留 gap，拟声 pill 单方面不让位
        resolveSeams(&boxes, gap: config.capsuleSeamGap, minPad: config.capsuleSeamMinPadding)

        // 4) 先画胶囊（含徽章），再画 pill，保证 pill 压在最上层
        var grouped: [(mark: EmotionMark, rects: [CGRect])] = []
        for b in boxes where !b.isSolid {
            guard let mark = b.mark else { continue }
            if let idx = grouped.lastIndex(where: { $0.mark.id == mark.id }) {
                grouped[idx].rects.append(b.rect)
            } else {
                grouped.append((mark, [b.rect]))
            }
        }
        for g in grouped { drawCapsule(for: g.mark, rects: g.rects) }

        for mark in ordered where mark.token.category == .richLanguage {
            let loc = min(max(mark.location, 0), max(docLength - 1, 0))
            if let m = Self.pillRect(charRange: NSRange(location: loc, length: 1),
                                     layoutManager: lm, container: tc,
                                     pillHeight: config.pillHeight,
                                     lineSpacing: config.lineSpacing,
                                     fallbackLineHeight: config.fallbackLineHeight) {
                drawPill(for: mark, rect: m.rect.offsetBy(dx: inset.left, dy: inset.top))
            }
        }
    }

    // MARK: 接缝收敛

    /// 接缝收敛用的盒子：一段胶囊（可让位）或一个拟声 pill（实心，不让位）
    private struct SeamBox {
        var rect: CGRect
        /// 盒子里文字（或 pill）的真实范围 —— 收敛时不能切到它
        var textRect: CGRect
        var lineMinY: CGFloat
        var isSolid: Bool
        var mark: EmotionMark?
    }

    /// 相邻两段在文档里只隔一个标记位，两侧的 `capsulePadX` 内边距必然互相压进去
    /// （实测重叠 16pt）。这里按「行 → x」排序后两两收敛：在重叠区中点切开，
    /// 但每侧至少保留 `minPad` —— 宁可留一点重叠，也绝不让胶囊边缘切到文字。
    ///
    /// 实心（拟声 pill）不让位：那一侧的间隙由胶囊单方面让出来，
    /// 于是胶囊背景在 pill 处自然断开，pill 不会压在同色底上。
    private func resolveSeams(_ boxes: inout [SeamBox], gap: CGFloat, minPad: CGFloat) {
        guard boxes.count > 1 else { return }
        boxes.sort { a, b in
            if abs(a.lineMinY - b.lineMinY) > 1 { return a.lineMinY < b.lineMinY }
            return a.rect.minX < b.rect.minX
        }
        for i in 0..<(boxes.count - 1) {
            let j = i + 1
            // 不同行之间不存在水平接缝
            guard abs(boxes[i].lineMinY - boxes[j].lineMinY) <= 1 else { continue }
            guard boxes[i].rect.maxX > boxes[j].rect.minX - gap else { continue }
            let mid = (boxes[i].rect.maxX + boxes[j].rect.minX) / 2

            var aMax = mid - gap / 2
            var bMin = mid + gap / 2
            if boxes[j].isSolid {
                aMax = boxes[j].rect.minX - gap
            } else if boxes[i].isSolid {
                bMin = boxes[i].rect.maxX + gap
            }

            if !boxes[i].isSolid {
                let floorX = boxes[i].textRect.maxX + minPad
                let target = min(boxes[i].rect.maxX, max(aMax, floorX))
                boxes[i].rect.size.width = max(target - boxes[i].rect.minX, 4)
            }
            if !boxes[j].isSolid {
                let ceilX = boxes[j].textRect.minX - minPad
                let target = max(boxes[j].rect.minX, min(bMin, ceilX))
                let right = boxes[j].rect.maxX
                let clampedMin = min(target, right - 4)
                boxes[j].rect.origin.x = clampedMin
                boxes[j].rect.size.width = right - clampedMin
            }
        }
    }

    // MARK: 语气胶囊

    private func drawCapsule(for mark: EmotionMark, rects: [CGRect]) {
        guard !rects.isEmpty else { return }

        let base = UIColor(Self.emotionColor(for: mark.token, dark: config.isDark))
        let fill = base.withAlphaComponent(config.capsuleFillAlpha)
        let stroke = base.withAlphaComponent(config.capsuleStrokeAlpha)

        // 一条 Path 一次填充：逐段 fill 会在长文本上产生几十次绘制调用
        let path = UIBezierPath()
        for r in rects {
            path.append(UIBezierPath(roundedRect: r, cornerRadius: config.capsuleCorner))
        }
        fill.setFill()
        path.fill()
        stroke.setStroke()
        path.lineWidth = 1
        path.stroke()

        drawBadge(for: mark, at: rects[0], color: base)
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

    private func drawPill(for mark: EmotionMark, rect: CGRect) {
        let base = UIColor(Self.emotionColor(for: mark.token, dark: config.isDark))

        // 只有虚线描边，不 fill —— 铺底会在标签文字后面压出一块「背景图」
        let path = UIBezierPath(roundedRect: rect, cornerRadius: config.pillCorner)
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

    /// 行片段里「真正有字形」的那一条（container 坐标系）。
    ///
    /// ⚠️ TextKit 把 `lineSpacing` 算进了 `lineFragmentUsedRect`：16pt 正文 + 26 行距 →
    /// usedRect 高 45pt，字形只贴在它顶部那 19pt。拿 usedRect 当胶囊高度，
    /// 换行后上下两块会直接叠在一起（每块都比整行还高）。这里减掉行距还原成字高。
    /// 段落最后一行没有行距，减完会小于字高 —— 用 `fallbackHeight` 兜回来。
    static func textLineBox(glyphIndex: Int,
                            layoutManager lm: NSLayoutManager,
                            container tc: NSTextContainer,
                            lineSpacing: CGFloat,
                            fallbackHeight: CGFloat) -> CGRect {
        let line = lm.lineFragmentUsedRect(forGlyphAt: glyphIndex, effectiveRange: nil)
        let h = min(max(line.height - lineSpacing, fallbackHeight), max(line.height, fallbackHeight))
        return CGRect(x: line.minX, y: line.minY, width: line.width, height: h)
    }

    /// 一个字符区间落在各行上的矩形（处理换行：同一作用域跨行会切成多个胶囊）
    static func lineRects(charRange: NSRange,
                          layoutManager lm: NSLayoutManager,
                          container tc: NSTextContainer,
                          lineSpacing: CGFloat,
                          fallbackLineHeight: CGFloat) -> [CGRect] {
        let glyphRange = lm.glyphRange(forCharacterRange: charRange, actualCharacterRange: nil)
        guard glyphRange.length > 0 else { return [] }

        var result: [CGRect] = []
        lm.enumerateLineFragments(forGlyphRange: glyphRange) { _, _, textContainer, fragRange, _ in
            let inter = NSIntersectionRange(fragRange, glyphRange)
            guard inter.length > 0 else { return }
            var r = lm.boundingRect(forGlyphRange: inter, in: textContainer)
            let box = Self.textLineBox(glyphIndex: inter.location,
                                       layoutManager: lm, container: tc,
                                       lineSpacing: lineSpacing,
                                       fallbackHeight: fallbackLineHeight)
            // 同一行用统一行高，保证胶囊上下沿齐平
            r.origin.y = box.minY
            r.size.height = box.height
            result.append(r)
        }
        return result
    }

    /// 空作用域的锚点矩形（container 坐标系）。
    ///
    /// 标签后面还没有文字（或标签就在文末）时，作用域长度是 0，`lineRects` 拿不到任何矩形。
    /// 这里退回到「标记所在位置那个点」：取**前一个字符的右边缘**，
    /// 与 macOS 的「空作用域锚点取标记右边缘」保持一致 —— 取左边缘会和上一段文本末尾重合。
    static func emptyScopeRect(characterIndex: Int,
                               layoutManager lm: NSLayoutManager,
                               container tc: NSTextContainer,
                               docLength: Int,
                               lineSpacing: CGFloat,
                               fallbackLineHeight: CGFloat) -> CGRect {
        let zero = CGRect(x: 0, y: 0, width: 0, height: fallbackLineHeight)
        guard lm.numberOfGlyphs > 0 else { return zero }

        let idx = min(max(characterIndex, 0), docLength)
        if idx > 0 {
            let prev = idx - 1
            let gRange = lm.glyphRange(forCharacterRange: NSRange(location: prev, length: 1),
                                       actualCharacterRange: nil)
            guard gRange.length > 0 else { return zero }
            let glyphRect = lm.boundingRect(forGlyphRange: gRange, in: tc)
            let box = Self.textLineBox(glyphIndex: gRange.location,
                                       layoutManager: lm, container: tc,
                                       lineSpacing: lineSpacing,
                                       fallbackHeight: fallbackLineHeight)
            return CGRect(x: glyphRect.maxX, y: box.origin.y, width: 0, height: box.height)
        }

        // 文档开头：锚在第 0 个字形所在行的行首
        let glyphRect = lm.boundingRect(forGlyphRange: NSRange(location: 0, length: 1), in: tc)
        let box = Self.textLineBox(glyphIndex: 0,
                                   layoutManager: lm, container: tc,
                                   lineSpacing: lineSpacing,
                                   fallbackHeight: fallbackLineHeight)
        return CGRect(x: glyphRect.minX, y: box.origin.y, width: 0, height: box.height)
    }

    /// 拟声 pill 的矩形（container 坐标系，**不含** `textContainerInset`，调用方自行偏移）。
    ///
    /// ⚠️ 用附件自身的真实矩形，而不是 `lineRects` 归一化后的「整行」矩形；
    /// 高度固定 `pillHeight`，并以**字高**那一块垂直居中（`boundingRect` 的 y/height
    /// 含 `lineSpacing`，直接取 `midY` 会让 pill 掉到行间的空档里）。
    static func pillRect(charRange: NSRange,
                         layoutManager lm: NSLayoutManager,
                         container tc: NSTextContainer,
                         pillHeight: CGFloat,
                         lineSpacing: CGFloat,
                         fallbackLineHeight: CGFloat) -> (rect: CGRect, lineMinY: CGFloat)? {
        let gRange = lm.glyphRange(forCharacterRange: charRange, actualCharacterRange: nil)
        guard gRange.length > 0 else { return nil }
        let raw = lm.boundingRect(forGlyphRange: gRange, in: tc)
        let box = Self.textLineBox(glyphIndex: gRange.location,
                                   layoutManager: lm, container: tc,
                                   lineSpacing: lineSpacing,
                                   fallbackHeight: fallbackLineHeight)
        let rect = CGRect(x: raw.minX,
                          y: box.midY - pillHeight / 2,
                          width: raw.width,
                          height: pillHeight)
        return (rect, box.minY)
    }

    /// 把胶囊夹进容器宽度内：行首 / 行尾没有额外空间，不夹会被容器裁掉一角
    static func clampX(_ rect: CGRect, minX: CGFloat, maxX: CGFloat) -> CGRect {
        let lo = max(minX, rect.minX)
        let hi = min(maxX, rect.maxX)
        guard hi > lo else { return rect }
        var r = rect
        r.origin.x = lo
        r.size.width = hi - lo
        return r
    }

    static func expand(_ rect: CGRect, toMinWidth minWidth: CGFloat) -> CGRect {
        guard rect.width < minWidth else { return rect }
        var r = rect
        r.size.width = minWidth
        return r
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
