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
//  ⚠️ 空作用域（标签后面还没有文字 / 下一个边界紧挨着）**只画徽章、不铺胶囊**。
//  早年给空作用域补一条 34pt 宽的兜底胶囊，它会一直压在之后输入的正文上。
//
//  ⚠️ 每个标记都在文档里占一个占位：语气 / 中断占 `TokenTextEditor.toneSpacing = 14pt`
//  的空白，拟声占 pill 宽。胶囊的左右内边距就是从这段**物理空隙**里出的。
//  早年用来补偿零宽空缺的 `applyInterruptGaps` / `applyNeighborGaps` 都已删掉 ——
//  它们会把 pad 吃成负数，正是「文字紧贴标签边缘」的来源。
//
//  ⚠️ 但相邻两个标签之间**只有一份** 14pt 空隙，要同时付前一个的右内边距和后一个的
//  左内边距，剩下的自然缝只有 2pt（再被两条描边吃掉一半）→ 看着就是首尾重叠。
//  `resolveSeams` 因此还留了一支「语气 ↔ 语气」，带 `capsuleMinPad` 地板地再让一次。
//
//  ⚠️ 徽章锚点取 `location + 1`（占位符之后那个位置，也就是接下来要打字的地方），
//  并且用**插入符矩形**（零长字符区间）而不是「前一个字符的右边缘」：
//  后者在两个位置会拿到**上一行**的坐标（前一个字符是换行符 / 折行前的末字），
//  锚点一旦落到上一行，徽章就飘到上一行行尾 —— 表现就是「中断后面的标签底色没了」。
//

import UIKit
import SwiftUI

final class TokenCapsuleOverlay: UIView {

    struct Config {
        var marks: [EmotionMark] = []
        var editable: Bool = true
        /// 当前深浅色（决定情感色是否压暗）
        var isDark: Bool = false
        /// 语气胶囊：填充 14% / 1px 内描边 42% / 圆角 9。
        ///
        /// ⚠️ 左右内边距 `capsulePadX = 6` 是从**标记自带的占位宽度**里出的：
        /// 每个语气 / 中断标记在文档里占 `TokenTextEditor.toneSpacing = 14pt` 的空白，
        /// 相邻两个标签于是天然有 14pt 的物理空隙 —— 左右各分 6pt 给胶囊做内边距，
        /// 剩下 2pt 是两个胶囊之间能看到的缝。两者必须满足 `capsulePadX × 2 < toneSpacing`，
        /// 否则胶囊会重新重叠（曾经的「相邻标签叠出一条更深色带」）。
        var capsuleFillAlpha: CGFloat = 0.14
        var capsuleStrokeAlpha: CGFloat = 0.42
        var capsuleCorner: CGFloat = 9
        /// 相邻两个**语气胶囊**之间至少要有多少可见缝隙。
        ///
        /// ⚠️ 两个相邻标签之间只有**一个** 14pt 占位（`TokenTextEditor.toneSpacing`），
        /// 而它要同时支付前一个胶囊的右内边距（6pt）与后一个的左内边距（6pt）——
        /// 剩下 2pt，再被两条 1pt 描边各吃掉 0.5pt，肉眼只剩 1pt：
        /// 这就是「两个语气标签连在一起，前一个的末尾和后一个的开头重叠」。
        /// 所以还得再让一次：`resolveSeams` 从两侧各匀一点出来把缝撑到这里。
        var capsuleSeamGap: CGFloat = 6
        /// 为缝隙让位时，胶囊在文字两侧**最少**要保留多少内边距。
        ///
        /// ⚠️ 这是早年「为了挤出缝隙把 `capsulePadX` 吃到负数」不再重演的关键：
        /// 让位量到此为止，代价是牺牲缝而不是牺牲文字与边缘的距离。
        var capsuleMinPad: CGFloat = 3
        var capsulePadX: CGFloat = 6
        var capsulePadY: CGFloat = 6
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
        /// 剩下的才是胶囊相对文字的内边距）。
        ///
        /// ⚠️ 这是三道收敛里唯一还需要的一支：pill 是**实心**且位置由自己的占位符决定，
        /// 语气胶囊又必须画到它旁边（不像「语气 ↔ 语气」两种都由 `toneSpacing` 撑开），
        /// 所以只能由胶囊单方面让位 —— pill 不让，胶囊单方面退到 `pillInset − pillSeamGap`。
        var pillSeamGap: CGFloat = 3

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
            // ⚠️ 跳过标记自己占的那个占位符：它是一段空白宽度，不是它的正文。
            // 作用域末尾 `end` 是下一个边界的位置（也就是**下一个占位符的起点**），
            // 于是 `[start, end)` 之间只有纯文本，胶囊的外扩不会碰到任何邻居的占位。
            let owner = min(max(mark.location + 1, 0), docLength)
            let start = min(owner, docLength)
            let end = min(max(TokenDocument.scopeEnd(at: i, in: ordered, docLength: docLength), owner), docLength)

            var pieces: [CGRect] = []
            if end > start {
                for piece in TokenDocument.scopePieces(start: start, end: end, soundLocations: soundLocations) {
                    pieces.append(contentsOf: Self.lineRects(charRange: piece,
                                                             layoutManager: lm, container: tc,
                                                             lineSpacing: config.lineSpacing,
                                                             fallbackLineHeight: config.fallbackLineHeight))
                }
            }
            if pieces.isEmpty {
                // 空作用域（标签后还没文字 / 下一个边界紧挨着）：
                // ⚠️ 只登记一个徽章，**不画胶囊**。铺一条固定宽度的兜底胶囊会压在
                // 之后输入的正文上，而接缝收敛救不回来 —— 那里没有任何可让位的空隙。
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

            for r in pieces {
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

            // 徽章锚在**第一段**胶囊的左上角（跨行时只在第一行标一次）
            let first = pieces[0].offsetBy(dx: inset.left, dy: inset.top)
            badgeItems.append(BadgeItem(mark: mark,
                                        preferredX: first.minX - Self.badgeInsetX,
                                        capsuleTop: first.minY - config.capsulePadY))
        }

        // 2.5) 中断：作用域边界，**不画胶囊**，只留一个灰徽章（否则它既看不见也删不掉）。
        //      它占的那 14pt 空白自己就是「断开」：前一条胶囊的右内边距、后一条胶囊的
        //      左内边距都从这里出，中间剩下的就是看得见的停顿 —— 不需要再切一刀。
        for mark in ordered where mark.token.category == .interrupt {
            let anchor = Self.emptyScopeRect(characterIndex: min(max(mark.location + 1, 0), docLength),
                                             layoutManager: lm, container: tc,
                                             docLength: docLength,
                                             lineSpacing: config.lineSpacing,
                                             fallbackLineHeight: config.fallbackLineHeight)
                .offsetBy(dx: inset.left, dy: inset.top)
            badgeItems.append(BadgeItem(mark: mark,
                                        preferredX: anchor.minX - Self.badgeInsetX,
                                        capsuleTop: anchor.minY - config.capsulePadY))
        }

        // 3) 接缝收敛：
        //    ① 语气 ↔ 语气：挤一下把可见缝撑到 `capsuleSeamGap`（有一份 14pt 占位可花）；
        //    ② 语气 ↔ pill：pill 是实心不让，胶囊退到它边上。
        resolveSeams(&boxes,
                     pillGap: config.pillSeamGap,
                     toneGap: config.capsuleSeamGap,
                     minPad: config.capsuleMinPad)

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

    /// 接缝收敛用的盒子：一段胶囊（可让位）或一个拟声 pill（实心，不让位）
    private struct SeamBox {
        var rect: CGRect
        /// 盒子里文字（或 pill）的真实范围 —— 收敛时不能切到它
        var textRect: CGRect
        var lineMinY: CGFloat
        var isSolid: Bool
        var mark: EmotionMark?
    }

    /// 相邻两个语气胶囊之间只有一份 14pt 占位（`TokenTextEditor.toneSpacing`）可花，
    /// 而它要同时付「前一个的右内边距 + 后一个的左内边距」，余下的缝不够看。
    /// 这里从两侧各匀出一点，把可见缝撑到 `toneGap`。
    ///
    /// ⚠️ 每一侧的让位量有下限 `minPad`：最多让到文字与胶囊边缘只剩 `minPad` 为止。
    /// 早年那版没有这个地板，为了挤出缝隙一路把 `capsulePadX` 吃到 0（甚至负数）——
    /// 于是每修一次「两个标签要有缝」，就复发一次「标签里的文字紧贴边缘」。
    /// 现在的取舍是：**让位到此为止** —— 缝不够就宁可缝略窄，也不许把文字顶到边上。
    ///
    /// ⚠️ 只处理**不同标记**的胶囊：同一个语气标签被拟声 pill 切成多段时不参与，
    /// 它们是同一个胶囊的几截，中间本来就该断开由 pill 负责。
    private func cutToneSeam(_ boxes: inout [SeamBox], i: Int, j: Int, toneGap: CGFloat, minPad: CGFloat) {
        guard let a = boxes[i].mark, let b = boxes[j].mark, a.id != b.id else { return }
        let need = boxes[i].rect.maxX + toneGap - boxes[j].rect.minX
        guard need > 0.5 else { return }

        // 每一侧实际还压着多少只属于自己的空间（`rect` 可能已被 `clampX` 挤过）
        let slackI = boxes[i].rect.maxX - boxes[i].textRect.maxX
        let slackJ = boxes[j].textRect.minX - boxes[j].rect.minX
        let giveI = max(min(need / 2, slackI - minPad), 0)
        let giveJ = max(min(need - giveI, slackJ - minPad), 0)
        guard giveI > 0 || giveJ > 0 else { return }

        if giveI > 0, boxes[i].rect.width - giveI >= 4 {
            boxes[i].rect.size.width -= giveI
        }
        if giveJ > 0, boxes[j].rect.width - giveJ >= 4 {
            boxes[j].rect.origin.x += giveJ
            boxes[j].rect.size.width -= giveJ
        }
    }

    /// 拟声 pill 旁的让位。pill 是实心块且位置由自己的占位符决定，只能由胶囊单方面退。
    private func cutPillSeam(_ boxes: inout [SeamBox], i: Int, j: Int, pillGap: CGFloat) {
        guard boxes[i].isSolid != boxes[j].isSolid else { return }
        guard boxes[i].rect.maxX > boxes[j].rect.minX - pillGap else { return }

        if boxes[i].isSolid {
            let right = boxes[j].rect.maxX
            let target = boxes[i].rect.maxX + pillGap
            let left = min(max(boxes[j].rect.minX, target), right - 4)
            boxes[j].rect.origin.x = left
            boxes[j].rect.size.width = right - left
        } else {
            let target = boxes[j].rect.minX - pillGap
            let width = max(target - boxes[i].rect.minX, 4)
            boxes[i].rect.size.width = width
        }
    }

    /// 同一行相邻盒子之间的接缝收敛：先按「行 → x」排好，再逐对收。
    ///
    /// ⚠️ 早年这里管四支（语气↔语气 / 语气↔中断 / 语气↔裸文本 / 语气↔pill），
    /// 现在只剩**语气 ↔ 语气**与**语气 ↔ pill** 两支：其余三种的间距都由标记自带的
    /// 占位宽度在**排版阶段**就给了，绘制层再切一刀只会把刚配对好的内边距重新吃掉。
    private func resolveSeams(_ boxes: inout [SeamBox], pillGap: CGFloat, toneGap: CGFloat, minPad: CGFloat) {
        guard boxes.count > 1 else { return }
        boxes.sort { a, b in
            if abs(a.lineMinY - b.lineMinY) > 1 { return a.lineMinY < b.lineMinY }
            return a.rect.minX < b.rect.minX
        }
        for i in 0..<(boxes.count - 1) {
            let j = i + 1
            // 不同行之间不存在水平接缝
            guard abs(boxes[i].lineMinY - boxes[j].lineMinY) <= 1 else { continue }
            if boxes[i].isSolid || boxes[j].isSolid {
                cutPillSeam(&boxes, i: i, j: j, pillGap: pillGap)
            } else {
                cutToneSeam(&boxes, i: i, j: j, toneGap: toneGap, minPad: minPad)
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
    static func lineRects(charRange: NSRange,
                          layoutManager lm: NSLayoutManager,
                          container tc: NSTextContainer,
                          lineSpacing: CGFloat,
                          fallbackLineHeight: CGFloat) -> [CGRect] {
        let wanted = lm.glyphRange(forCharacterRange: charRange, actualCharacterRange: nil)
        let glyphRange = NSIntersectionRange(wanted, NSRange(location: 0, length: lm.numberOfGlyphs))
        guard glyphRange.length > 0 else { return [] }

        var result: [CGRect] = []
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
            result.append(r)
        }
        return result
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

/// 只为行内占出一块矩形，自己不画任何东西（pill 由 overlay 画，语气 / 中断只留空）。
final class InlineSpaceAttachment: NSTextAttachment {

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
