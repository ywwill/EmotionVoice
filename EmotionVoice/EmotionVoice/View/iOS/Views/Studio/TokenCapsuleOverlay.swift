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
//  ⚠️ 徽章（emoji + 名称 + ×）**统一在最后一遍「横向排队」里落位**。
//  早年每个标签各画各的：徽章比它对应的胶囊宽得多（约 70pt），
//  两个标签挨在一起时前一个的徽章会横穿到后一个的胶囊 / 徽章上 ——
//  这就是「两个语气标签连在一起会重叠」。现在同一行的徽章从左到右依次让位。
//
//  ⚠️ 空作用域（标签后面还没有文字 / 下一个边界就在同一个位置）**只画徽章、不铺胶囊**。
//  早年给空作用域补一条 34pt 宽的兜底胶囊，而锚点是「前一个字符的右边缘」——
//  在文末插一个语气再插中断时，那条胶囊会一直压在之后输入的正文上，
//  接缝收敛也救不回来（两段之间没有物理空隙，谁都没有可让位的空间）。
//
//  ⚠️ 中断的锚点取**插入符矩形**（零长字符区间），不是「前一个字符的右边缘」。
//  后者在两个位置会拿到上一行的坐标：① 前一个字符是换行符（它的字形矩形是整行宽，
//  maxX 直接顶到容器右边缘）；② 前一个字符是折行前的末字。锚点一旦落到上一行，
//  徽章飘到上一行行尾、`applyInterruptGaps` 还会拿这个 x 去切下一行的胶囊 ——
//  表现就是「中断后面的语气标签底色只剩一条细丝 / 整行没底色」。
//
//  ⚠️ `applyInterruptGaps` 的左右两支都**只切与中断锚点同一行**的那一段。
//  中断标记不占字符位，锚点 x 是「这一行上的某个横坐标」，把它无差别地套到
//  下一行的胶囊上，就会把那一行整段推成一个贴着右边缘的细条 ——
//  这正是「语气标签换行后背景色没了」的根因。
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
        /// 相邻两段胶囊的接缝灵敏度（重叠超过这个值才去收敛）。
        /// ⚠️ 它**不是**切出来的缝隙宽度：iOS 的语气标记不占字符位，两段文本之间没有
        /// 物理空隙可切（见 `resolveSeams` 里语气–语气那一支的说明）。
        var capsuleSeamGap: CGFloat = 2
        /// **中断处**的接缝宽度：语气 – 中断 – 语气 之间要真正断开（读起来才有停顿感）。
        /// macOS 的中断标记是 5×1 可见占位，天然有 5pt 空隙；iOS 的中断标记不占字符位，
        /// 只能从两侧的内边距里各匀一半出来（`gap / 2` 的字形会露在胶囊外，这是代价）。
        var interruptSeamGap: CGFloat = 6
        /// 徽章（emoji + 名称）压在胶囊左上角
        var badgeHeight: CGFloat = 15
        var badgeFont = UIFont.systemFont(ofSize: 10.5, weight: .bold)
        /// 同一行相邻徽章之间留出的缝隙（徽章比胶囊宽得多，不让位就会叠在一起）
        var badgeSeamGap: CGFloat = 4
        /// 中断标记的徽章色（灰，与 macOS 的「中断 = 灰徽章」一致）
        var interruptColor: UIColor = .secondaryLabel
        /// 拟声 pill：只留虚线描边，**不铺底色**（铺底会在标签文字后面形成一块背景），圆角 6
        var pillCorner: CGFloat = 6
        /// 拟声 pill 的固定高度。⚠️ 不能拿行高当高度：正文 lineSpacing = 26，
        /// 行片段矩形会被撑到 45pt 上下，画出来就是一条和整行一样高的色块。
        var pillHeight: CGFloat = 20
        var pillFont = UIFont.systemFont(ofSize: 12, weight: .medium)
        /// 拟声 pill 左右各留出的间距：占位附件实际占 `pill 宽 + 2×spacing`，
        /// 虚线框只画在中间那一段 —— 没有它 pill 会直接贴在相邻文字 / 语气胶囊上。
        var pillSpacing: CGFloat = 8
        /// 语气胶囊与 pill 之间要留出的**可见**间隙（`pillSpacing` 里分给它这么多，
        /// 剩下的才是胶囊相对文字的内边距）。比 `capsuleSeamGap` 大，pill 才不会看着贴着胶囊。
        var pillSeamGap: CGFloat = 4
        /// 与「**没有底色**的邻居」之间要补出的可见间隙。
        ///
        /// ⚠️ iOS 的语气标记不占字符位（macOS 是 5×1 的可见占位，天然就有物理空隙），
        /// 所以胶囊为了实现自己的 `capsulePadX` 内边距，会一路盖到**不属于任何胶囊**的
        /// 前一段文字上。「插中断 → 输入一段字 → 再插一个语气标签」必现：中断的作用域
        /// 不画胶囊，那一段字裸着，于是看起来就是
        /// **「新标签的开始位置压在前一段文字的末尾上、两者之间没有一点空隙」**。
        /// 见 `applyNeighborGaps`。
        var uncoveredSeamGap: CGFloat = 3
        /// 给邻居让位时，最多允许把胶囊边缘推进自己第一段文字里多少 pt。
        /// 胶囊是**半透明覆盖层**，字形不受影响；这个上限只是防极端排版把整段吃掉。
        var uncoveredMaxCut: CGFloat = 3

        /// 空作用域（标签后面还没有文字 / 标签在文末）时徽章的落位锚点高度兜底。
        /// ⚠️ 没有这个兜底，在文末点一个语气标签就没有任何可画的东西 ——
        /// 标签会变成「看不见又删不掉」的幽灵（macOS 侧同样有这条规则）。
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
        /// 待画的徽章（语气胶囊徽章 / 空作用域兜底徽章 / 中断徽章），最后统一排位
        var badgeItems: [BadgeItem] = []

        // 1) 拟声 pill 先量好：它们是实心块，语气胶囊要给它们让位
        let soundLocations = Set(ordered
            .filter { $0.token.category == .richLanguage }
            .map { min(max($0.location, 0), max(docLength - 1, 0)) })

        for mark in ordered where mark.token.category == .richLanguage {
            let loc = min(max(mark.location, 0), max(docLength - 1, 0))
            guard let m = Self.pillRect(charRange: NSRange(location: loc, length: 1),
                                        layoutManager: lm, container: tc,
                                        pillHeight: config.pillHeight,
                                        pillSpacing: config.pillSpacing,
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

            var pieces: [TextPiece] = []
            if end > start {
                for piece in TokenDocument.scopePieces(start: start, end: end, soundLocations: soundLocations) {
                    pieces.append(contentsOf: Self.linePieces(charRange: piece,
                                                              layoutManager: lm, container: tc,
                                                              lineSpacing: config.lineSpacing,
                                                              fallbackLineHeight: config.fallbackLineHeight))
                }
            }
            if pieces.isEmpty {
                // 空作用域（标签后还没文字 / 下一个边界就在同一位置）：
                // ⚠️ 只登记一个徽章，**不画胶囊**。铺一条固定宽度的兜底胶囊会压在
                // 之后输入的正文上（中断插在语气后面时必现），而接缝收敛救不回来 ——
                // 两段文本严丝合缝，没有任何可让位的空隙。
                let anchor = Self.emptyScopeRect(characterIndex: start,
                                                 layoutManager: lm, container: tc,
                                                 docLength: docLength,
                                                 lineSpacing: config.lineSpacing,
                                                 fallbackLineHeight: config.fallbackLineHeight)
                    .offsetBy(dx: inset.left, dy: inset.top)
                badgeItems.append(BadgeItem(mark: mark,
                                            preferredX: anchor.minX - Self.badgeInsetX,
                                            capsuleTop: anchor.minY - config.capsulePadY))
                continue
            }

            for p in pieces {
                let capsule = p.rect.insetBy(dx: -config.capsulePadX, dy: -config.capsulePadY)
                    .offsetBy(dx: inset.left, dy: inset.top)
                let clamped = Self.clampX(capsule,
                                          minX: inset.left,
                                          maxX: inset.left + tc.size.width)
                boxes.append(SeamBox(rect: clamped,
                                     textRect: p.rect.offsetBy(dx: inset.left, dy: inset.top),
                                     lineMinY: p.rect.minY + inset.top,
                                     isSolid: false, mark: mark, charRange: p.charRange))
            }

            // 徽章锚在**第一段**胶囊的左上角（跨行时只在第一行标一次）
            let first = pieces[0].rect.offsetBy(dx: inset.left, dy: inset.top)
            badgeItems.append(BadgeItem(mark: mark,
                                        preferredX: first.minX - Self.badgeInsetX,
                                        capsuleTop: first.minY - config.capsulePadY))
        }

        // 2.5) 中断：作用域边界，不画胶囊，只留一个灰徽章（否则它既看不见也删不掉）。
        //      同一个锚点同时登记成「切口」，交给 `applyInterruptGaps` 把两侧胶囊断开。
        //      ⚠️ 记的是**矩形**而不是一个 x：切的时候要拿 y 判「是不是同一行」。
        var interruptAnchors: [UUID: CGRect] = [:]
        for mark in ordered where mark.token.category == .interrupt {
            let anchor = Self.emptyScopeRect(characterIndex: min(max(mark.location, 0), docLength),
                                             layoutManager: lm, container: tc,
                                             docLength: docLength,
                                             lineSpacing: config.lineSpacing,
                                             fallbackLineHeight: config.fallbackLineHeight)
                .offsetBy(dx: inset.left, dy: inset.top)
            interruptAnchors[mark.id] = anchor
            badgeItems.append(BadgeItem(mark: mark,
                                        preferredX: anchor.minX - Self.badgeInsetX,
                                            capsuleTop: anchor.minY - config.capsulePadY))
        }

        // 3) 三道缝隙收敛，都只收不放，按「先粗后细」的顺序落：
        //    ① 先给没有底色的邻居让位，② 再在中断处断开，③ 最后做相邻两段的接缝收敛。
        applyNeighborGaps(&boxes, gap: config.uncoveredSeamGap, maxCut: config.uncoveredMaxCut)
        applyInterruptGaps(&boxes, ordered: ordered, anchors: interruptAnchors,
                         gap: config.interruptSeamGap)
        resolveSeams(&boxes, gap: config.capsuleSeamGap, pillGap: config.pillSeamGap)

        // 4) 先画胶囊，再画 pill（pill 压在最上层），最后画徽章 ——
        //    徽章在最上层才能保证「×」不被任何底色切掉。
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
                                     pillSpacing: config.pillSpacing,
                                     lineSpacing: config.lineSpacing,
                                     fallbackLineHeight: config.fallbackLineHeight) {
                drawPill(for: mark, rect: m.rect.offsetBy(dx: inset.left, dy: inset.top))
            }
        }

        // 5) 徽章最后画，并在同一行里横向排队
        drawBadges(badgeItems, minX: inset.left, maxX: inset.left + tc.size.width)
    }

    // MARK: 徽章

    /// 一个待画的徽章（语气胶囊徽章 / 空作用域兜底徽章 / 中断徽章）
    private struct BadgeItem {
        let mark: EmotionMark
        /// 期望的落位（胶囊左上角往里 `badgeInsetX`）
        var preferredX: CGFloat
        /// 徽章所依附的「胶囊上沿」（text view 坐标系）
        var capsuleTop: CGFloat
    }

    /// 徽章左边相对胶囊左沿的内缩量（沿用旧 `drawBadge` 里的 `+ capsulePadX - 4`）
    private static let badgeInsetX: CGFloat = 4

    /// 同一行的徽章从左到右依次让位。
    ///
    /// 徽章宽度是「emoji + 名称 + ×」，普遍 60~90pt，远宽于它对应的胶囊：
    /// 两个标签挨在一起（甚至在同一个字符位置）时，前一个是必然横穿到后一个头上的。
    /// 这里按「行 → x」排序后逐个推进游标，保证任意两个徽章之间恒有 `badgeSeamGap`。
    private func drawBadges(_ items: [BadgeItem], minX: CGFloat, maxX: CGFloat) {
        guard !items.isEmpty else { return }
        let sorted = items.sorted { a, b in
            if abs(a.capsuleTop - b.capsuleTop) > 1 { return a.capsuleTop < b.capsuleTop }
            return a.preferredX < b.preferredX
        }

        var lineTop: CGFloat = .nan
        var cursor: CGFloat = -.infinity
        for item in sorted {
            if !(abs(lineTop - item.capsuleTop) <= 1) {   // 换行：游标重新起排
                lineTop = item.capsuleTop
                cursor = -.infinity
            }
            let width = Self.badgeWidth(for: item.mark,
                                        font: config.badgeFont,
                                        editable: config.editable)
            var x = max(item.preferredX, cursor + config.badgeSeamGap)
            // 行尾放不下就往左贴回容器内：宁可和前一个挤一点，也不能让 × 被裁掉
            if x + width > maxX { x = max(minX, maxX - width) }
            let color = item.mark.token.category == .interrupt
                ? config.interruptColor
                : UIColor(Self.emotionColor(for: item.mark.token, dark: config.isDark))
            drawBadge(for: item.mark, x: x, capsuleTop: item.capsuleTop, color: color)
            cursor = x + width
        }
    }

    /// 徽章宽度（与 `drawBadge` 里的排版常量保持一致）
    static func badgeWidth(for mark: EmotionMark, font: UIFont, editable: Bool) -> CGFloat {
        let emoji = mark.token.emoji
        let label = mark.token.label
        let text = emoji.isEmpty ? label : "\(emoji) \(label)"
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        let textW = ceil((text as NSString).size(withAttributes: attrs).width)
        let xSize: CGFloat = editable ? 15 : 0
        return textW + 7 + 3 + xSize + 5
    }

    // MARK: 接缝收敛

    /// 中断边界处把两侧胶囊各推开 `gap / 2`，让「停顿」在视觉上真的断开。
    ///
    /// ⚠️ 判定完全走**几何**（锚点 x 是否落在某条胶囊的文字左 / 右端点上），
    /// 不再比对「作用域的 `scopeEnd` == 下一个作用域的 `scopeStart`」—— 那个写法
    /// 要求中断两侧**都有**语气胶囊才成立，而实际最常见的用法是：
    /// 「语气 → 输入一段 → 插一个中断 → 继续输入」，中断后面压根没有第二条胶囊，
    /// `resolveSeams` 因为 `boxes.count <= 1` 直接返回，这条胶囊的 `capsulePadX = 8`
    /// 就一路盖过中断之后输入的正文 —— 表现就是「中断后面的字压在语气底色上」。
    /// 逐条盒子单独判定则无论对面有没有胶囊都成立。
    ///
    /// ⚠️ iOS 的中断标记**不占字符位**，两段文本之间没有物理空隙。所以分两种情况：
    ///  * **两侧都有胶囊**：各让 `gap / 2` 造出可见缝隙（接缝两侧的字形各露 `gap / 2`
    ///    在胶囊外 —— 这是要「看得见的断开」必须付的代价，macOS 靠 5×1 的可见占位
    ///    天然就有这段空隙）。
    ///  * **只有一侧有胶囊**（中断后面直接就是正文）：只把那侧的内边距收到 0，
    ///    停在文字边界上。既不会盖到对面的正文，也不会把字形切在胶囊外面 ——
    ///    后者看起来就是渲染 bug，不是「停顿」。
    ///
    /// ⚠️⚠️ **两条支都必须限定在「中断锚点所在的那一行」**。
    /// 中断标记不占字符位，锚点只是「某一行上的一个横坐标」。早年不判行，于是：
    ///  * 中断插在**折行点**（前一个字符是上一行的末字，锚点 x 很大）→
    ///    右邻语气的第一段其实在**下一行**，却被 `limit = a + gap/2` 从中间劈开，
    ///    只剩贴着右边缘的一条细丝 —— 这就是「语气标签换行后背景色没了」；
    ///  * 中断插在**换行符之后**（锚点 x 顶到容器右边缘）→ 同一段误伤更严重，
    ///    甚至算出负宽度，整段胶囊直接消失。
    /// 加上「同一行」这个条件后，跨行的情况自然落到「本来就有整行的换行空隙」，
    /// 不需要再造一条缝。
    private func applyInterruptGaps(_ boxes: inout [SeamBox],
                                    ordered: [EmotionMark],
                                    anchors: [UUID: CGRect],
                                    gap: CGFloat) {
        guard !anchors.isEmpty else { return }
        let half = gap / 2

        // 语气标记 → 它的所有盒段（跨行会切成多段），按盒子出现顺序
        var segsByMark: [UUID: [Int]] = [:]
        for (i, b) in boxes.enumerated() where !b.isSolid {
            if let id = b.mark?.id { segsByMark[id, default: []].append(i) }
        }

        for (idx, mark) in ordered.enumerated() where mark.token.category == .interrupt {
            guard let anchor = anchors[mark.id] else { continue }
            let a = anchor.minX
            let lineY = anchor.minY
            /// 只挑出落在中断那一行的盒段（跨行的段之间本来就有整行的空隙，不用再切）
            func onSameLine(_ i: Int) -> Bool { abs(boxes[i].lineMinY - lineY) <= 1 }

            // 左邻：中断之前最近的语气标记 → 它在**中断所在行**上的最后一段
            if let lastTone = ordered[..<idx].last(where: { $0.token.category == .emotion }),
               let last = segsByMark[lastTone.id]?.last(where: onSameLine) {
                let limit = a - half
                if limit > boxes[last].rect.minX + 4 {
                    let right = min(boxes[last].rect.maxX, limit)
                    boxes[last].rect.size.width = max(right - boxes[last].rect.minX, 4)
                }
            }

            // 右邻：中断之后最近的作用域边界；只有它也是语气标记时才有胶囊可让。
            // ⚠️ `a > minX + 1` 这条别省：中断落在**行首**（折行后 / 换行后 / 文档开头）时
            //    锚点 x 就等于这一行的左边缘，此时左右之间本来隔着整行的换行空隙，
            //    再切一次只会把胶囊左端啃掉 `gap / 2`，看着像渲染缺口。
            if let next = ordered[(idx + 1)...].firstIndex(where: {
                $0.token.category == .emotion || $0.token.category == .interrupt
            }), ordered[next].token.category == .emotion,
               let first = segsByMark[ordered[next].id]?.first(where: onSameLine),
               a > boxes[first].rect.minX + 1 {
                let limit = a + half
                if limit < boxes[first].rect.maxX - 4 {
                    let right = boxes[first].rect.maxX
                    let left = max(boxes[first].rect.minX, limit)
                    boxes[first].rect.origin.x = left
                    boxes[first].rect.size.width = right - left
                }
            }
        }
    }

    /// 接缝收敛用的盒子：一段胶囊（可让位）或一个拟声 pill（实心，不让位）
    private struct SeamBox {
        var rect: CGRect
        /// 盒子里文字（或 pill）的真实范围 —— 收敛时不能切到它
        var textRect: CGRect
        var lineMinY: CGFloat
        var isSolid: Bool
        var mark: EmotionMark?
        /// 盒子对应的字符区间（`textView` 坐标系）。给「没有底色的邻居」让位时，
        /// 要靠它找到紧邻的前一个字符在哪一行结束。
        var charRange: NSRange = NSRange(location: 0, length: 0)
    }

    /// 给**没有底色的邻居**让位。
    ///
    /// 语气标记在 iOS 上不占字符位，两段文本在排版上严丝合缝：胶囊为了自己的
    /// `capsulePadX` 内边距，会一路盖到前一段（恰好不属于任何胶囊）的字上。
    /// 最典型的复现路径是「语气 → 插中断 → 输入一段字 → 再插一个语气标签」：
    /// 中断的作用域不画胶囊，中间那段字是裸的，于是新标签的底色就压在它末尾几个字上，
    /// 两段之间一点空隙都没有 —— macOS 上同一个位置的中断标记是 5×1 的可见占位，
    /// 天然有物理空隙，所以那边从来没这个问题。
    ///
    /// ⚠️ 只处理**紧邻位置是被没有底色的文本占着**这一支：
    ///  * 前一段自己也带胶囊（语气 ↔ 语气）或者旁边就是拟声 pill —— 两边都在比 `rect`，
    ///    交给 `resolveSeams` 统一收敛。这里抢先收一次只会把两边的容量都啃小；
    ///  * 行首 —— 前一个字符在上一行，本来隔着一整行的空隙。
    ///
    /// ⚠️ 让位方式是「把胶囊左边缘往右顶」，而理想落点（邻居右边缘 + `gap`）恰好就是
    /// 自己第一段文字的起点（两者之间没有物理空隙），所以代价是胶囊会探进首字的字身框
    /// 一点点（`maxCut` 封顶）。胶囊是半透明覆盖层，字形照常显示。
    private func applyNeighborGaps(_ boxes: inout [SeamBox], gap: CGFloat, maxCut: CGFloat) {
        guard gap > 0, boxes.count > 0, let tv = textView else { return }
        let lm = tv.layoutManager
        let tc = tv.textContainer
        let inset = tv.textContainerInset

        for i in boxes.indices where !boxes[i].isSolid {
            let start = boxes[i].charRange.location
            guard start > 0 else { continue }
            guard let prev = Self.glyphRunRect(charRange: NSRange(location: start - 1, length: 1),
                                               layoutManager: lm, container: tc,
                                               lineSpacing: config.lineSpacing,
                                               fallbackLineHeight: config.fallbackLineHeight) else { continue }
            // 不同行：前者在上一行 / 下一个片段上，本来就有整行的空隙
            guard abs(prev.lineMinY + inset.top - boxes[i].lineMinY) <= 1 else { continue }
            let prevMaxX = prev.rect.maxX + inset.left
            // 本来就没压上去
            guard prevMaxX > boxes[i].rect.minX + 0.5 else { continue }
            // 那个位置已经有底色了 → 交给 `resolveSeams`
            if Self.isCovered(x: prevMaxX - 0.75, lineMinY: boxes[i].lineMinY,
                              excluding: i, in: boxes) { continue }

            let right = boxes[i].rect.maxX
            let limit = min(prevMaxX + gap, boxes[i].textRect.minX + maxCut)
            let left = min(max(boxes[i].rect.minX, limit), right - 4)
            guard left > boxes[i].rect.minX else { continue }
            boxes[i].rect.origin.x = left
            boxes[i].rect.size.width = right - left
        }
    }

    /// 同一行的 `lineMinY` 上，某个横坐标是否已经被**别的**盒子占着
    private static func isCovered(x: CGFloat, lineMinY: CGFloat,
                                  excluding: Int, in boxes: [SeamBox]) -> Bool {
        for (j, b) in boxes.enumerated() where j != excluding {
            guard abs(b.lineMinY - lineMinY) <= 1 else { continue }
            if x >= b.rect.minX, x <= b.rect.maxX { return true }
        }
        return false
    }

    /// 相邻两段在文档里只隔一个标记位，两侧的 `capsulePadX` 内边距必然互相压进去
    /// （实测重叠 16pt）。这里按「行 → x」排序后两两收敛，分两种情况：
    ///
    ///  * **拟声 pill 参与**：pill 是实心块不让位，间隙由胶囊单方面让出来，
    ///    于是胶囊背景在 pill 处自然断开，pill 不会压在同色底上。
    ///  * **语气 ↔ 语气**：两侧一起收到文字边界，谁也不让谁。
    ///
    /// 中断处的断开不在这里做 —— 见 `applyInterruptGaps`（它连「中断后面根本
    /// 没有下一条胶囊」的情况也要处理，而那时这里的 `boxes.count` 只有 1）。
    ///
    /// ⚠️ 语气–语气那一支**不能照搬 macOS**：macOS 的语气标记是 5×1 的可见占位，
    /// 两个作用域之间天然有 5pt 物理空隙，可以切出真正的 `capsuleSeamGap` 缝隙；
    /// iOS 的语气标记**不占字符位**，两段文本在排版上严丝合缝，重叠区中点就是文字边界本身。
    /// 早年照抄「各让 gap/2，且每侧至少留 `minPad` 内边距」，结果 `minPad` 这块地板
    /// 把两边都顶过了中线 —— 稳定重叠 `2 × minPad = 6pt`，
    /// 表现就是「相邻两个语气标签叠出一条更深的色带」。现在直接切在中线，零重叠也零切字。
    private func resolveSeams(_ boxes: inout [SeamBox],
                              gap: CGFloat,
                              pillGap: CGFloat) {
        guard boxes.count > 1 else { return }
        boxes.sort { a, b in
            if abs(a.lineMinY - b.lineMinY) > 1 { return a.lineMinY < b.lineMinY }
            return a.rect.minX < b.rect.minX
        }
        let trigger = max(gap, pillGap)
        for i in 0..<(boxes.count - 1) {
            let j = i + 1
            // 不同行之间不存在水平接缝
            guard abs(boxes[i].lineMinY - boxes[j].lineMinY) <= 1 else { continue }
            guard boxes[i].rect.maxX > boxes[j].rect.minX - trigger else { continue }

            if boxes[i].isSolid || boxes[j].isSolid {
                // ⚠️ 这里**不给胶囊留 minPad 兜底**：那会把胶囊边缘推进 pill 里 3pt，
                // 虚线框底下就透出一块胶囊底色。pill 不需要「给文字留内边距」。
                if !boxes[i].isSolid {
                    let target = min(boxes[i].rect.maxX, boxes[j].rect.minX - pillGap)
                    boxes[i].rect.size.width = max(target - boxes[i].rect.minX, 4)
                }
                if !boxes[j].isSolid {
                    let target = max(boxes[j].rect.minX, boxes[i].rect.maxX + pillGap)
                    let right = boxes[j].rect.maxX
                    let clampedMin = min(target, right - 4)
                    boxes[j].rect.origin.x = clampedMin
                    boxes[j].rect.size.width = right - clampedMin
                }
                continue
            }

            let mid = (boxes[i].rect.maxX + boxes[j].rect.minX) / 2

            // 语气 ↔ 语气：中线 = 文字边界，两侧各自收到它
            // 保险：夹在两段文字之间，极端排版（容器边缘裁剪导致两侧 padding 不等）下也不切字形
            let cut = min(max(mid, boxes[i].textRect.maxX), boxes[j].textRect.minX)

            let aRight = min(boxes[i].rect.maxX, cut)
            boxes[i].rect.size.width = max(aRight - boxes[i].rect.minX, 4)

            let bRight = boxes[j].rect.maxX
            let bLeft = max(boxes[j].rect.minX, min(cut, bRight - 4))
            boxes[j].rect.origin.x = bLeft
            boxes[j].rect.size.width = bRight - bLeft
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
    }

    /// 画一个徽章（emoji + 名称 + ×）。
    ///
    /// - Parameters:
    ///   - x: 徽章左边缘（text view 坐标系，由 `drawBadges` 排队后给出）
    ///   - capsuleTop: 所依附的胶囊上沿；徽章压在它上面，底边略微压进胶囊
    private func drawBadge(for mark: EmotionMark, x: CGFloat, capsuleTop: CGFloat, color: UIColor) {
        let label = mark.token.label
        let emoji = mark.token.emoji
        let text = emoji.isEmpty ? label : "\(emoji) \(label)"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: config.badgeFont,
            .foregroundColor: color
        ]
        let textW = ceil((text as NSString).size(withAttributes: attrs).width)

        // × 热区：常显（iOS 没有 hover），命中区外扩到 44pt 见方的手感
        let xSize: CGFloat = config.editable ? 15 : 0
        let w = Self.badgeWidth(for: mark, font: config.badgeFont, editable: config.editable)
        let h = config.badgeHeight
        let rect = CGRect(x: x, y: capsuleTop - h + 2, width: w, height: h)

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
        let leftPad: CGFloat = 7
        // 右边那块是 × 的热区（不可编辑时留一处对称的尾兜）
        let rightPad: CGFloat = config.editable ? xSize + 2 : 4
        let available = max(rect.width - leftPad - rightPad, 0)
        // ⚠️ 先量再画：`draw(with:options:)` 会把行片段对齐到传入 rect 的**左上角**，
        //    早年直接把整个 pill 的高当 rect 高塞进去（pill 20pt / 12pt 文本行盒约 15pt），
        //    文本就顶在虚线框上沿、下面空出一大截 —— 这是「拟声标签的文字没居中」的根因。
        //    现在按量出来的行盒在两个方向都居中：横向在「左内边距 ~ ×」之间，
        //    纵向对齐 pill 的中线。
        let measure = (label as NSString).boundingRect(
            with: CGSize(width: available, height: rect.height),
            options: [.usesLineFragmentOrigin, .truncatesLastVisibleLine],
            attributes: attrs, context: nil)
        let textW = min(ceil(measure.width), available)
        let textH = min(ceil(measure.height), rect.height)
        let textRect = CGRect(x: rect.minX + leftPad + max((available - textW) / 2, 0),
                              y: rect.midY - textH / 2,
                              width: textW,
                              height: textH)
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

    /// 一段文字在某几行上的矩形
    struct TextPiece {
        var rect: CGRect
        /// 这一段对应的**字符**区间（`lineFragmentusedRect` 给的是 glyph 区）
        var charRange: NSRange
    }

    /// 一个字符区间落在各行上的矩形（处理换行：同一作用域跨行会切成多个胶囊）
    ///
    /// ⚠️ 三处都必须兜住，少一处就会出现「某一行的胶囊底色没了」：
    ///  ① `glyphRange` 要先夹进 `numberOfGlyphs`：范围越界时 `boundingRect` 返回 `CGRect.null`，
    ///     那一行就被静默跳过（标签起点正好在换行处时必现）；
    ///  ② `boundingRect` 的宽度要夹进这一行的 `usedRect`：换行符 / 行尾空白参与计算时
    ///     它会一路撑到**整行宽**（实测：一行只有 6 个字，矩形却是容器宽 340）——
    ///     反向的情况（拿到 0 宽）同样要兜，否则画出来是一条看不见的细丝；
    ///  ③ 每一段都保证至少 1pt 宽：胶囊 = 文字矩形外扩 `capsulePadX`，
    ///     所以哪怕这一行零宽，也仍然有一个完整的圆角胶囊。
    static func linePieces(charRange: NSRange,
                           layoutManager lm: NSLayoutManager,
                           container tc: NSTextContainer,
                           lineSpacing: CGFloat,
                           fallbackLineHeight: CGFloat) -> [TextPiece] {
        let wanted = lm.glyphRange(forCharacterRange: charRange, actualCharacterRange: nil)
        let glyphRange = NSIntersectionRange(wanted, NSRange(location: 0, length: lm.numberOfGlyphs))
        guard glyphRange.length > 0 else { return [] }

        var result: [TextPiece] = []
        lm.enumerateLineFragments(forGlyphRange: glyphRange) { _, usedRect, textContainer, fragRange, _ in
            let inter = NSIntersectionRange(fragRange, glyphRange)
            guard inter.length > 0 else { return }
            var r = lm.boundingRect(forGlyphRange: inter, in: textContainer)
            let box = Self.textLineBox(glyphIndex: inter.location,
                                       layoutManager: lm, container: tc,
                                       lineSpacing: lineSpacing,
                                       fallbackHeight: fallbackLineHeight)

            if r.isNull || r.width.isNaN || r.height.isNaN {
                // 拿不到字形矩形：整行兜底，宁可宽一点也不让这一行没有胶囊
                r = CGRect(x: usedRect.minX, y: usedRect.minY,
                           width: usedRect.width, height: usedRect.height)
            }
            // 同一行的胶囊不许越过该行的实际排版宽度（换行符参与计算时会超宽）
            let hi = min(r.maxX, usedRect.maxX)
            r.size.width = max(hi - r.minX, 1)

            // 同一行用统一行高，保证胶囊上下沿齐平
            r.origin.y = box.minY
            r.size.height = box.height
            let chars = lm.characterRange(forGlyphRange: inter, actualGlyphRange: nil)
            result.append(TextPiece(rect: r, charRange: chars))
        }
        return result
    }

    /// 一个字符区间在同一行里的字形矩形 + 行顶（container 坐标系）。
    ///
    /// 用于找「紧邻的前一个字符」在哪一行结束 —— 给没有底色的邻居让位时要按这个位置切。
    /// ⚠️ 必须连带返回**行顶**而不是 `rect.minY`：`boundingRect` 的高度含 `lineSpacing`，
    /// 拿它的 y 去比行会全部判成同一行。
    static func glyphRunRect(charRange: NSRange,
                             layoutManager lm: NSLayoutManager,
                             container tc: NSTextContainer,
                             lineSpacing: CGFloat,
                             fallbackLineHeight: CGFloat) -> (rect: CGRect, lineMinY: CGFloat)? {
        let wanted = lm.glyphRange(forCharacterRange: charRange, actualCharacterRange: nil)
        let clipped = NSIntersectionRange(wanted, NSRange(location: 0, length: lm.numberOfGlyphs))
        guard clipped.length > 0 else { return nil }
        let raw = lm.boundingRect(forGlyphRange: clipped, in: tc)
        guard !raw.isNull, !raw.minX.isNaN, raw.width > 0 else { return nil }
        let box = Self.textLineBox(glyphIndex: clipped.location,
                                   layoutManager: lm, container: tc,
                                   lineSpacing: lineSpacing,
                                   fallbackHeight: fallbackLineHeight)
        return (raw, box.minY)
    }

    /// 空作用域 / 中断的锚点矩形（container 坐标系）。
    ///
    /// 标签后面还没有文字（或标签就在文末 / 正好落在换行处）时，作用域长度是 0，
    /// `lineRects` 拿不到任何矩形。这里退回到「标记所在位置那个点」。
    ///
    /// ⚠️ 用**零长字符区间**向 TextKit 要插入符矩形，而不是早年那样取「前一个字符的右边缘」。
    /// 后者在两处会拿到**上一行**的坐标，而标记本身属于下一行：
    ///  * 前一个字符是**换行符**：换行符的字形矩形是整行宽，`maxX` 直接顶到容器右边缘
    ///    （实测：x = 340，y = 上一行），中断徽章于是飘到上一行的最右边；
    ///  * 前一个字符是**折行前的末字**：锚点落在上一行行尾。
    /// 两种情况下 `applyInterruptGaps` 再拿这个 x 去切「下一行的胶囊」，就会把那一段切成
    /// 贴着右边缘的细丝 —— 「语气标签换行后背景色没了」就是这么来的。
    ///
    /// ⚠️ 插入符自己也有一个坑：**折行点**上 TextKit 把「下一行第一个字形之前」的插入符
    /// 报在**上一行的行尾**（实测 caret = (301.63, y = 上一行)，而该字形其实在下一行）。
    /// x 是上一行的右边缘、y 却该归下一行，直接拿去切下一行的胶囊同样会切出一条细丝。
    /// 一旦检测到「插入符的 y 与字形所在行不一致」，就把 x 归到**下一行的行首**。
    static func emptyScopeRect(characterIndex: Int,
                               layoutManager lm: NSLayoutManager,
                               container tc: NSTextContainer,
                               docLength: Int,
                               lineSpacing: CGFloat,
                               fallbackLineHeight: CGFloat) -> CGRect {
        let zero = CGRect(x: 0, y: 0, width: 0, height: fallbackLineHeight)
        guard lm.numberOfGlyphs > 0 else { return zero }

        let idx = min(max(characterIndex, 0), docLength)
        let caretRange = lm.glyphRange(forCharacterRange: NSRange(location: idx, length: 0),
                                       actualCharacterRange: nil)
        let caret = lm.boundingRect(forGlyphRange: caretRange, in: tc)
        let glyphIndex = min(max(caretRange.location, 0), max(lm.numberOfGlyphs - 1, 0))
        let box = Self.textLineBox(glyphIndex: glyphIndex,
                                   layoutManager: lm, container: tc,
                                   lineSpacing: lineSpacing,
                                   fallbackHeight: fallbackLineHeight)

        // 兜底：极少数排版（未布局完成 / 插入符拿不到）退回「前一个字符的右边缘」
        let x: CGFloat
        let y: CGFloat
        if caret.isNull || caret.minX.isNaN {
            if idx > 0 {
                let gRange = lm.glyphRange(forCharacterRange: NSRange(location: idx - 1, length: 1),
                                           actualCharacterRange: nil)
                guard gRange.length > 0 else { return zero }
                let glyphRect = lm.boundingRect(forGlyphRange: gRange, in: tc)
                let prevBox = Self.textLineBox(glyphIndex: gRange.location,
                                               layoutManager: lm, container: tc,
                                               lineSpacing: lineSpacing,
                                               fallbackHeight: fallbackLineHeight)
                x = glyphRect.maxX
                y = prevBox.minY
            } else {
                let glyphRect = lm.boundingRect(forGlyphRange: NSRange(location: 0, length: 1), in: tc)
                x = glyphRect.minX
                y = box.minY
            }
        } else {
            // 折行点：插入符被报在上一行行尾，但标记其实属于下一行 → 归到下一行行首
            x = (box.minY > caret.minY + 1) ? box.minX : caret.minX
            // ⚠️ 文末以换行结尾时，插入符落在**多出来的那个空行**上，而 `glyphIndex`
            //    被夹到了上一行 —— 取两者中更靠下的那个才是插入符真正的行。
            y = max(caret.minY, box.minY)
        }
        return CGRect(x: x, y: y, width: 0, height: box.height)
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
                         pillSpacing: CGFloat,
                         lineSpacing: CGFloat,
                         fallbackLineHeight: CGFloat) -> (rect: CGRect, lineMinY: CGFloat)? {
        let gRange = lm.glyphRange(forCharacterRange: charRange, actualCharacterRange: nil)
        guard gRange.length > 0 else { return nil }
        let raw = lm.boundingRect(forGlyphRange: gRange, in: tc)
        let box = Self.textLineBox(glyphIndex: gRange.location,
                                   layoutManager: lm, container: tc,
                                   lineSpacing: lineSpacing,
                                   fallbackHeight: fallbackLineHeight)
        // 占位附件比 pill 宽 `2 × pillSpacing`，虚线框只画在中间那一段
        let width = max(raw.width - pillSpacing * 2, 4)
        let rect = CGRect(x: raw.minX + pillSpacing,
                          y: box.midY - pillHeight / 2,
                          width: width,
                          height: pillHeight)
        return (rect, box.minY)
    }

    /// 把胶囊夹进容器宽度内：行首 / 行尾没有额外空间，不夹会被容器裁掉一角
    ///
    /// ⚠️ 夹完还要兜一个 `minWidth`：行首 / 行尾那一段经常被夹到只剩 1~2pt，
    /// 画出来是一条细丝，用户看到的就是「这一行的胶囊底色没了」。
    /// 兜完再整体推回容器内，保证不越界。
    static func clampX(_ rect: CGRect, minX: CGFloat, maxX: CGFloat, minWidth: CGFloat = 4) -> CGRect {
        let width = max(minWidth, min(rect.width, maxX - minX))
        var lo = min(max(minX, rect.minX), max(minX, maxX - width))
        var hi = lo + width
        if hi > maxX {
            hi = maxX
            lo = max(minX, hi - width)
        }
        guard hi > lo else { return rect }
        var r = rect
        r.origin.x = lo
        r.size.width = hi - lo
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
        // ⚠️ 附件不挂图时，iOS 会自己补一个「文稿」占位图标，正好落在拟声 pill 的虚线框里。
        // 挂一张透明图把它顶掉：尺寸仍由 `attachmentBounds` 决定，画出来什么都没有。
        self.image = Self.blankImage
    }

    /// 1×1 全透明图（只用来顶掉系统占位图标，实际尺寸不看它）
    private static let blankImage: UIImage? = {
        let format = UIGraphicsImageRendererFormat()
        format.opaque = false
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1), format: format).image { _ in }
    }()

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func attachmentBounds(for textContainer: NSTextContainer?,
                                   proposedLineFragment lineFrag: CGRect,
                                   glyphPosition position: CGPoint,
                                   characterIndex charIndex: Int) -> CGRect {
        CGRect(x: 0, y: baselineOffset, width: wantedWidth, height: wantedHeight)
    }
}
