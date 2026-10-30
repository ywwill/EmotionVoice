//
//  EmotionTokenTextView.swift
//  EmotionVoice
//
//  Created by young on 2026/9/1.
//
//  NSTextView 子类，专为「文本 + Emotion Token」混合编辑设计：
//    * 普通文本输入：原生 NSTextView 处理。
//    * Token 插入：`insertToken(_:)` 接口。
//    * Token 删除：
//        - 整体 Delete（× 按钮）→ 由 `EmotionTokenAttachmentCell.trackMouse` 处理。
//        - Backspace / Forward Delete 在 token 边界外 → 整体删除 attachment。
//        - Backspace / Forward Delete 在 token 选中态 → 整体删除 attachment。
//    * 导出 / 导入：`exportItems()` / `setContent(_:)`。
//    * Undo / Redo：原生 NSTextView 通过 `shouldChangeText` + `didChangeText` 处理。
//
// 与 InlineTokenField 相比，这里支持多行（`isVerticallyResizable = true` / wrapping），
// 因为 TTS 文案经常跨行。
//

import AppKit

/// NSTextView 子类，同时管理 token 段
final class EmotionTokenTextView: NSTextView {

    // MARK: - 配置

    /// 删除 token 时是否要求 selectedRange 正好落在 token 边界（包括 token 之后 / 之前）
    ///   true  = 严格模式：仅当 selectedRange 与 token 相邻/重合时 Backspace 才是原子删除；
    ///           其他情况保持原生逐字符行为。
    ///   false = 宽松模式（默认）：自动把光标吸附到最近的 token 边界。
    var strictAtomicDelete: Bool = false

    /// 当前可插入的 token 集合（用于点击 event 时识别「这种 token 是否合法」）。
    /// 不影响 export，导出时所有解析成功的 token 都会进入 TTSContentItem。
    var recognizedTokens: [EmotionToken] = []

    // MARK: - 回调

    /// 内容变更时（增、删、改、undo、redo、setContent）。
    var onContentChange: (() -> Void)?
    /// 选中区间变化时
    var onSelectionChange: (() -> Void)?

    // MARK: - 私有

    private var isInternalUpdate: Bool = false

    // MARK: - 语气作用域（v4：只作为绘图数据，不再写入 NSTextStorage）

    /// 一个作用域：字符区间 + 解析后的情绪色（nil = 中断，不带语气）。
    ///
    /// 旧实现把 `.underlineStyle` / `.underlineColor` 写进 NSTextStorage，
    /// 导致每按一次键都要：beginEditing → 全文档 removeAttribute → addAttribute → endEditing，
    /// `endEditing` 会触发全文档 `processEditing`（属性修正 + 布局失效 + 重排），
    /// 这是「插入标签后继续输入变卡」的主因。现在只存数据，绘制阶段自己画胶囊，
    /// 输入过程零属性变更、零重排。
    private struct ToneScope: Equatable {
        /// 作用域的起点标记。用于 hover / 选中 / 删除，以及空作用域时定位徽章。
        let attachment: NSTextAttachment
        /// 需要包进胶囊的区间。通常只有一段；中间夹了拟声标记时拆成多段——
        /// 拟声标记是「插入的声音事件」，不代表文本，不该被胶囊圈进去。
        let segments: [NSRange]
        /// 情绪色；nil = 中断作用域（文本按普通正文渲染，胶囊 / 徽章都不画）
        let color: NSColor?

        static func == (lhs: ToneScope, rhs: ToneScope) -> Bool {
            lhs.attachment === rhs.attachment &&
            lhs.segments == rhs.segments &&
            lhs.color?.isEqual(rhs.color) == true
        }
    }

    /// 一个作用域的胶囊几何（container 坐标系）。绘制与命中测试共用，避免两边错位。
    private struct ToneCapsuleGeometry {
        let attachment: NSTextAttachment
        /// 情绪色；nil = 中断作用域，只保留几何用于命中，不画胶囊
        let color: NSColor?
        /// 每个行片段各一块胶囊（对应 CSS 的 `box-decoration-break: clone`）
        let capsuleRects: [NSRect]
        /// 左上角徽章（只在首块上，续段不再重复）
        let badge: ToneBadgeLayout?
        /// 徽章文字（emoji + 名称）
        let badgeText: String?
        let hovered: Bool
        let selected: Bool
    }

    private var toneScopes: [ToneScope] = []

    /// 徽章的底色。它压在胶囊描边上，必须不透明才读得清。
    /// 默认 nil → 按当前外观取编辑器背景色（暗 #15171B / 亮 白）。
    var badgeBackgroundColor: NSColor?

    private var resolvedBadgeBackgroundColor: NSColor {
        if let c = badgeBackgroundColor { return c }
        return EmotionTokenStyle.isDarkAppearance(effectiveAppearance)
            ? NSColor(red: 0.082, green: 0.090, blue: 0.106, alpha: 1.0)   // #15171B
            : NSColor.white
    }

    // MARK: - 内容变更去抖

    /// 输入停止多久后才把内容同步给 SwiftUI（VM 的 @Published 会触发整个
    /// VoiceStudioView 重算 body，逐键同步代价很高）。
    private static let contentChangeDelay: TimeInterval = 0.35
    private var contentChangeWorkItem: DispatchWorkItem?

    /// 正文行距。行距要同时喂饱三样东西：
    ///   · 胶囊实高 28.5pt（含 2×6 垂直内边距），比正文行高多 12pt；
    ///   · 徽章从胶囊上沿向上探出 `badgeTopOffset` = 14pt；
    ///   · 相邻两行的胶囊之间还要留得住呼吸位。
    /// 28 → 行距 44.5pt，胶囊之间净空 16pt，徽章顶端离上一行胶囊下沿还有 2pt。
    static let bodyLineSpacing: CGFloat = 28

    /// 正文段落样式。**必须**同时设成 `defaultParagraphStyle`：
    /// 段落样式取自段落**首字符**的属性，而语气 / 中断标签是 attachment，
    /// 自身不带段落样式 —— 一旦标签恰好落在段首，整段就会退回系统默认行距
    /// （实测 ≈ 0），排版直接塌掉、首行徽章也会被裁掉。这是离屏渲染时抓到的真 bug。
    static var bodyParagraphStyle: NSParagraphStyle {
        let ps = NSMutableParagraphStyle()
        ps.lineSpacing = bodyLineSpacing
        ps.paragraphSpacing = 0
        return ps
    }

    /// 普通文本的基础属性（含段落 lineSpacing，给语气胶囊与徽章留白）
    private var bodyAttributes: [NSAttributedString.Key: Any] {
        [
            .font: EmotionTokenStyle.bodyFont,
            .foregroundColor: NSColor.white,
            .paragraphStyle: Self.bodyParagraphStyle
        ]
    }

    // MARK: - Init

    override init(frame frameRect: NSRect, textContainer aTextContainer: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: aTextContainer)
        setupCommonProperties()
    }

    override init(frame frameRect: NSRect) {
        let textContainer = NSTextContainer(size: NSSize(width: frameRect.width,
                                                         height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
        super.init(frame: frameRect, textContainer: textContainer)
        setupCommonProperties()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupCommonProperties()
    }

    private func setupCommonProperties() {
        allowsUndo = true
        isRichText = true
        isEditable = true
        isSelectable = true
        isVerticallyResizable = true
        isHorizontallyResizable = false
        textContainer?.widthTracksTextView = true
        textContainer?.lineFragmentPadding = 0
        // 顶部留白：徽章压在首行胶囊的上沿之外（向上探出 badgeTopOffset = 14），
        // 再加胶囊自身 6pt 上内边距 + 字形到行顶的 ~0.5pt，首行徽章顶端在 container
        // y ≈ -20.5。给到 28 留出 7pt 余量，避免任何字体度量差异把徽章削掉半截。
        // （另有一层兜底：toneBadgeLayout 的 minY 会把徽章压回可见区域。）
        textContainerInset = NSSize(width: 0, height: 28)
        font = EmotionTokenStyle.bodyFont
        textColor = NSColor.white
        backgroundColor = .clear
        drawsBackground = false
        usesFindBar = true

        // 段落样式兜底：标签恰好是段首字符时，attachment 自身没有段落样式，
        // 不设 defaultParagraphStyle 的话该段行距会塌回系统默认（实测 ≈ 0）。
        defaultParagraphStyle = Self.bodyParagraphStyle
        // 光标处继续输入时也要带上同样的段落样式 + 正文字体
        typingAttributes = [
            .font: EmotionTokenStyle.bodyFont,
            .paragraphStyle: Self.bodyParagraphStyle
        ]

        // 悬停检测：仅在可编辑时开启，让 × 在鼠标移入 tag 时才高亮。
        // 只读（预览）场景不加追踪区，tag 保持完全静止、不出现 ×。
        //  * .mouseMoved   → 更新 hover（绘制 ×）
        //  * .cursorUpdate → 更新鼠标样式（必须走这个钩子，见 cursorUpdate(with:) 注释）
        //  * .inVisibleRect 让追踪区自动跟随滚动后的可见区域。
        if isEditable {
            let trackingArea = NSTrackingArea(rect: .zero,
                                              options: [.mouseMoved, .cursorUpdate, .activeInActiveApp, .inVisibleRect],
                                              owner: self,
                                              userInfo: nil)
            addTrackingArea(trackingArea)
        }
    }

    // MARK: - Insert Token

    /// 在当前光标位置插入一个 emotion token（不自动补前缀空格，
    /// 是否留间隔完全由用户在普通文本里自行决定）。
    /// 如果有选中文本，把选中片段替换为 token。
    @discardableResult
    func insertToken(_ token: EmotionToken) -> Bool {
        let attachment = EmotionTokenAttachment.makeAttachment(for: token)
        // 标记位置（包括 attachment 自身）使用普通 body 风格属性，
        // 这样在 token 之后输入的字符仍是普通白色文字，而不是 pill 颜色。
        let bodyAttrs = bodyAttributes
        // 注意：attachment 自身的字体颜色会被 cell 覆盖，这里只是做 typo。

        let attr = NSMutableAttributedString(attachment: attachment)
        attr.addAttributes(bodyAttrs, range: NSRange(location: 0, length: attr.length))

        let range = selectedRange()
        let storage = textStorage

        guard shouldChangeText(in: range, replacementString: attr.string) else { return false }
        storage?.replaceCharacters(in: range, with: attr)
        let newLocation = range.location + attr.length
        setSelectedRange(NSRange(location: newLocation, length: 0))
        typingAttributes = bodyAttrs
        didChangeText()
        // 插入是结构性改动，不等去抖，立刻同步给 VM
        flushPendingContentChange()
        return true
    }

    /// 删除所有 token，同时保留普通文本
    func clearAllTokens() {
        guard let storage = textStorage else { return }
        storage.beginEditing()
        defer {
            storage.endEditing()
            didChangeText()
            flushPendingContentChange()
        }

        var ranges: [NSRange] = []
        var keys: [ObjectIdentifier] = []
        storage.enumerateAttribute(.attachment,
                                   in: NSRange(location: 0, length: storage.length),
                                   options: []) { value, range, _ in
            if let att = value as? NSTextAttachment, EmotionTokenAttachment.isEmotionToken(att) {
                ranges.append(range)
                keys.append(ObjectIdentifier(att))
            }
        }
        clearHoverImmediately()
        for key in keys {
            kEmotionAttachmentIdentity.removeValue(forKey: key)
            kEmotionAttachmentSelectionStates.removeValue(forKey: key)
        }
        // 反向删除避免 range 失效
        for r in ranges.reversed() {
            storage.deleteCharacters(in: r)
        }
    }

    // MARK: - Export / Import

    /// 把当前编辑器内容导出为结构化的 [TTSContentItem]
    func exportItems() -> [TTSContentItem] {
        guard let storage = textStorage else { return [] }
        let attr = storage
        let nsString = attr.string as NSString

        var items: [TTSContentItem] = []
        var pendingText = ""

        attr.enumerateAttributes(in: NSRange(location: 0, length: attr.length)) { attrs, range, _ in
            if let attachment = attrs[.attachment] as? NSTextAttachment,
               EmotionTokenAttachment.isEmotionToken(attachment),
               let token = EmotionTokenAttachment.parse(from: attachment) {

                if !pendingText.isEmpty {
                    items.append(.text(pendingText))
                    pendingText = ""
                }
                items.append(.emotion(token))
            } else if attrs[.attachment] == nil {
                // 跳过非 token 的 attachment（理论上不会出现）
                pendingText.append(nsString.substring(with: range))
            }
        }
        if !pendingText.isEmpty {
            items.append(.text(pendingText))
        }
        return items
    }

    /// 用结构化数据替换整个编辑器内容。
    /// 当前选中区间会被推到末尾。
    func setContent(_ items: [TTSContentItem]) {
        guard let storage = textStorage else { return }

        isInternalUpdate = true
        defer { isInternalUpdate = false }

        let bodyAttrs = bodyAttributes
        let result = NSMutableAttributedString()

        for item in items {
            switch item {
            case .text(let s):
                if !s.isEmpty {
                    result.append(NSAttributedString(string: s, attributes: bodyAttrs))
                }
            case .emotion(let token):
                let attachment = EmotionTokenAttachment.makeAttachment(for: token)
                let attr = NSMutableAttributedString(attachment: attachment)
                attr.addAttributes(bodyAttrs, range: NSRange(location: 0, length: attr.length))
                result.append(attr)
            }
        }

        let fullRange = NSRange(location: 0, length: storage.length)
        if fullRange.length > 0 {
            guard shouldChangeText(in: fullRange, replacementString: result.string) else { return }
            storage.replaceCharacters(in: fullRange, with: result)
        } else {
            guard shouldChangeText(in: NSRange(location: 0, length: 0),
                                  replacementString: result.string) else { return }
            storage.setAttributedString(result)
        }
        setSelectedRange(NSRange(location: storage.length, length: 0))
        typingAttributes = bodyAttrs
        didChangeText()
        flushPendingContentChange()
    }

    // MARK: - 删除单个 token（统一入口）

    /// 删除一个 emotion token 本身（不再吞前缀空格：
    /// 因为 `insertToken` 已不再自动补空格，用户手动输入的空格应保留）。
    /// 返回是否真正执行了删除。
    @discardableResult
    func removeToken(at range: NSRange) -> Bool {
        guard let storage = textStorage else { return false }
        guard shouldChangeText(in: range, replacementString: "") else { return false }
        // 删除前把悬停 / 选中状态一并清掉，避免指针还停在原地时 hover 到一个已消失的附件
        if let att = storage.attribute(.attachment, at: range.location, effectiveRange: nil) as? NSTextAttachment {
            let key = ObjectIdentifier(att)
            if kEmotionAttachmentHovered === att { clearHoverImmediately() }
            kEmotionAttachmentSelectionStates.removeValue(forKey: key)
            // identity 字典会随编辑无限增长，这里顺手回收
            kEmotionAttachmentIdentity.removeValue(forKey: key)
        }
        storage.deleteCharacters(in: range)
        setSelectedRange(NSRange(location: range.location, length: 0))
        didChangeText()
        flushPendingContentChange()
        return true
    }

    // MARK: - 删除逻辑（最关键的代码）

    /// 找到 attachment 在 storage 中的精确 range（length == 1）
    private func attachmentRange(at index: Int) -> NSRange? {
        guard let storage = textStorage else { return nil }
        guard index >= 0 && index < storage.length else { return nil }
        var found: NSRange?
        storage.enumerateAttribute(.attachment,
                                   in: NSRange(location: index, length: 1),
                                   options: []) { value, range, stop in
            if value is NSTextAttachment {
                found = range
                stop.pointee = true
            }
        }
        return found
    }

    /// 选区是否完全覆盖一个 token（length == 1，且该位置是 attachment）
    func selectionIsToken() -> Bool {
        let r = selectedRange()
        guard r.length == 1, let storage = textStorage,
              r.location < storage.length,
              let attrs = storage.attributes(at: r.location, effectiveRange: nil)[.attachment] as? NSTextAttachment else {
            return false
        }
        return EmotionTokenAttachment.isEmotionToken(attrs)
    }

    /// 找到「在 location 之前 / 之后最近」的 token 字符位置。
    /// 用于把 Backspace / Forward Delete 的光标吸附到 token 边界。
    private func nearestTokenIndex(around index: Int, lookingBackward: Bool) -> Int? {
        guard let storage = textStorage else { return nil }
        let total = storage.length
        guard total > 0 else { return nil }

        if lookingBackward {
            // 从 index-1 开始向前找 attachment
            for i in stride(from: min(index, total) - 1, through: 0, by: -1) {
                if let attrs = storage.attributes(at: i, effectiveRange: nil)[.attachment] as? NSTextAttachment,
                   EmotionTokenAttachment.isEmotionToken(attrs) {
                    return i
                }
            }
            return nil
        } else {
            for i in index..<total {
                if let attrs = storage.attributes(at: i, effectiveRange: nil)[.attachment] as? NSTextAttachment,
                   EmotionTokenAttachment.isEmotionToken(attrs) {
                    return i
                }
            }
            return nil
        }
    }

    override func deleteBackward(_ sender: Any?) {
        let r = selectedRange()

        // 情况 1：选中了一个 token（length == 1, 落在 attachment 上）→ 整体删除
        if r.length == 1, let storage = textStorage,
           r.location < storage.length,
           let attrs = storage.attributes(at: r.location, effectiveRange: nil)[.attachment] as? NSTextAttachment,
           EmotionTokenAttachment.isEmotionToken(attrs) {
            _ = removeToken(at: r)
            return
        }

        // 情况 2：有非空选区（包括多个 token）→ 整体删除选区
        if r.length > 0 {
            super.deleteBackward(sender)
            return
        }

        // 情况 3：cursor 在 r.location == 0, 前面没有字符可删
        guard r.location > 0 else {
            super.deleteBackward(sender)
            return
        }

        // 情况 4：cursor 之前那个字符是 attachment → 整体删除
        if let prevAttachmentRange = attachmentRange(at: r.location - 1) {
            _ = removeToken(at: prevAttachmentRange)
            return
        }

        // 情况 5（可选吸附模式）：cursor 之前最近的 token 距离很近 → 整体删除它
        if !strictAtomicDelete, let nearest = nearestTokenIndex(around: r.location, lookingBackward: true) {
            // 只在「最近 token 距离 ≤ 2」时吸附，避免误删（保险起见设为 1 即可：必须紧邻）
            if r.location - nearest == 1 {
                _ = removeToken(at: NSRange(location: nearest, length: 1))
                return
            }
        }

        // 默认：逐字符删除
        super.deleteBackward(sender)
    }

    override func deleteForward(_ sender: Any?) {
        let r = selectedRange()

        // 情况 1：选中了一个 token
        if r.length == 1, let storage = textStorage,
           r.location < storage.length,
           let attrs = storage.attributes(at: r.location, effectiveRange: nil)[.attachment] as? NSTextAttachment,
           EmotionTokenAttachment.isEmotionToken(attrs) {
            _ = removeToken(at: r)
            return
        }

        // 情况 2：有非空选区
        if r.length > 0 {
            super.deleteForward(sender)
            return
        }

        // 情况 3：cursor 之后那个字符是 attachment → 整体删除
        if let nextAttachmentRange = attachmentRange(at: r.location) {
            _ = removeToken(at: nextAttachmentRange)
            return
        }

        if !strictAtomicDelete, let nearest = nearestTokenIndex(around: r.location, lookingBackward: false) {
            if nearest - r.location == 1 {
                _ = removeToken(at: NSRange(location: nearest, length: 1))
                return
            }
        }

        super.deleteForward(sender)
    }

    // MARK: - didChange / didChangeSelection

    /// 重新计算「语气标签作用域」：每个语气类标记之后的文本（直到下一个标记）。
    /// v4：只更新 `toneScopes` 这条绘图数据，不碰 textStorage（因此不会重排）。
    /// 单次只是 O(n) 的附件枚举，逐键调用无压力。
    private func recomputeToneScopes() {
        guard let storage = textStorage else {
            if !toneScopes.isEmpty {
                toneScopes = []
                needsDisplay = true
            }
            return
        }
        let full = NSRange(location: 0, length: storage.length)
        let dark = EmotionTokenStyle.isDarkAppearance(effectiveAppearance)

        var entries: [(location: Int, attachment: NSTextAttachment, color: NSColor,
                       category: EmotionCategory)] = []
        storage.enumerateAttribute(.attachment, in: full, options: []) { value, range, _ in
            guard let att = value as? NSTextAttachment,
                  EmotionTokenAttachment.isEmotionToken(att),
                  let id = kEmotionAttachmentIdentity[ObjectIdentifier(att)] else { return }
            entries.append((range.location, att, id.baseColor, id.category))
        }

        let sorted = entries.sorted { $0.location < $1.location }
        // 作用域边界：语气标记与中断标记都是（拟声标记不构成边界）
        let scopeIndices = sorted.indices.filter { sorted[$0].category != .richLanguage }

        var result: [ToneScope] = []
        result.reserveCapacity(scopeIndices.count)
        for (k, i) in scopeIndices.enumerated() {
            let e = sorted[i]
            let start = e.location + 1
            // v5：作用域延伸到「下一个边界标记」，拟声标记不再打断它
            // （插入拟声后继续输入的文本，仍属于前面的语气标签）
            var end = storage.length
            if k + 1 < scopeIndices.count {
                end = sorted[scopeIndices[k + 1]].location
            }
            // v13：作用域允许为空（标签刚插入、后面还没输文字），
            // 空作用域也要留一条记录，否则徽章无处安放 → 标签变成看不见也删不掉的幽灵。
            guard end >= start else { continue }

            // 拟声标记占的那 1 个字符不画线，把区间拆成若干段跳过它
            var segments: [NSRange] = []
            var cursor = start
            for j in (i + 1)..<sorted.count {
                let m = sorted[j]
                guard m.location < end else { break }
                guard m.category == .richLanguage else { continue }
                if m.location > cursor {
                    segments.append(NSRange(location: cursor, length: m.location - cursor))
                }
                cursor = m.location + 1
            }
            if end > cursor {
                segments.append(NSRange(location: cursor, length: end - cursor))
            }

            // 中断标签的作用域没有情绪色（nil）→ 编辑器里不画胶囊也不画徽章，
            // 它唯一的作用就是「切断」前一个语气标签的作用域。
            let col: NSColor? = (e.category == .emotion)
                ? (dark ? e.color : e.color.darkened(by: 0.40))
                : nil
            result.append(ToneScope(attachment: e.attachment, segments: segments, color: col))
        }

        let changed = (result != toneScopes)
        toneScopes = result
        if changed { needsDisplay = true }
    }

    // MARK: - 语气胶囊几何

    /// 由作用域数据算出每个胶囊矩形 + 首块的左上角徽章（container 坐标系）。
    ///
    /// 每次调用都现算：布局随时可能因换行 / 宽度变化而失效，缓存反而容易拿到过期几何。
    /// 一次调用只是 O(作用域数 × 行片段数) 的 layoutManager 查询，绘制与鼠标移动都用得起。
    /// 参与接缝收敛的一个盒子：语气胶囊的一块（可让位）或拟声标记本体（实心，不让位）。
    private struct CapsuleSeamBox {
        var rect: NSRect
        /// 该盒子真正包裹的文本矩形，用于「至少保留多少内边距」的兜底
        let textRect: NSRect
        let isSolid: Bool
        /// 所在 line fragment 的 minY，用作「同一行」的判据。
        /// 不能用 rect.minY：胶囊高 28.5、拟声 pill 高 17，两者 minY 差 7pt，
        /// 拿它判定会把同一行里的胶囊与拟声当成两行，接缝就永远收敛不到。
        let lineMinY: CGFloat
        /// 回写用：属于第几个作用域的第几块（拟声标记为 nil）
        let scopeIndex: Int?
        let fragmentIndex: Int?
    }

    private func toneCapsuleGeometries() -> [ToneCapsuleGeometry] {
        guard !toneScopes.isEmpty, let lm = layoutManager, let tc = textContainer else { return [] }
        let style = EmotionTokenStyle.default
        let font = EmotionTokenStyle.bodyFont
        let maxX = tc.size.width
        let capsuleH = (font.ascender - font.descender) + style.capsuleVerticalPadding * 2
        let textH = font.ascender - font.descender
        let hPad = style.capsuleHorizontalPadding
        // 行首 / 行尾的片段没有额外的内外空间，内边距必须夹进容器边界里，
        // 否则胶囊会伸出容器被裁掉（实测右侧会溢出 3pt、左侧会溢出 8pt）。
        let clampX = { (x0: CGFloat, x1: CGFloat) -> NSRect in
            let lo = max(0, x0)
            let hi = min(maxX, x1)
            return NSRect(x: lo, y: 0, width: max(hi - lo, 1), height: 0)
        }

        // 1) 每个作用域按「行片段」各出一块胶囊（对应 CSS 的 box-decoration-break: clone）
        var perScopeRects: [[NSRect]] = Array(repeating: [], count: toneScopes.count)
        var boxes: [CapsuleSeamBox] = []

        for (si, scope) in toneScopes.enumerated() {
            var rects: [NSRect] = []
            var textRects: [NSRect] = []
            var lineKeys: [CGFloat] = []
            for seg in scope.segments {
                let glyphRange = lm.glyphRange(forCharacterRange: seg, actualCharacterRange: nil)
                guard glyphRange.length > 0 else { continue }
                lm.enumerateLineFragments(forGlyphRange: glyphRange) { lineRect, _, container, lineGlyphRange, _ in
                    let sub = NSIntersectionRange(glyphRange, lineGlyphRange)
                    guard sub.length > 0 else { return }
                    let br = lm.boundingRect(forGlyphRange: sub, in: container)
                    guard br.width >= 0.5 else { return }
                    // 纵向不能用 br：`boundingRect(forGlyphRange:in:)` 的高度是**整行**高，
                    // 会带着 lineSpacing 一起算进来，胶囊会胖到把行距吃掉。
                    // 只有 x / width 可信，上下沿必须由基线 ± 字体度量推出来。
                    let baseline = lineRect.minY + lm.location(forGlyphAt: sub.location).y
                    let top = baseline - font.ascender - style.capsuleVerticalPadding
                    let band = clampX(br.minX - hPad, br.maxX + hPad)
                    textRects.append(NSRect(x: br.minX, y: top + style.capsuleVerticalPadding,
                                            width: br.width, height: textH))
                    rects.append(NSRect(x: band.minX, y: top,
                                        width: band.width, height: capsuleH))
                    lineKeys.append(lineRect.minY)
                }
            }
            // 作用域为空（标签后还没输入文字）→ 在标记处补一个最小宽度的空胶囊，
            // 徽章挂上去，标签才不会变成看不见也点不到的幽灵。
            if rects.isEmpty, let anchor = markerAnchor(for: scope.attachment) {
                let top = anchor.point.y - font.ascender - style.capsuleVerticalPadding
                let band = clampX(anchor.point.x - hPad, anchor.point.x + style.capsuleEmptyWidth - hPad)
                textRects.append(NSRect(x: anchor.point.x, y: top + style.capsuleVerticalPadding,
                                        width: 0, height: textH))
                rects.append(NSRect(x: band.minX, y: top, width: band.width, height: capsuleH))
                lineKeys.append(anchor.lineMinY)
            }
            perScopeRects[si] = rects
            for (fi, r) in rects.enumerated() {
                boxes.append(CapsuleSeamBox(rect: r, textRect: textRects[fi], isSolid: false,
                                            lineMinY: lineKeys[fi],
                                            scopeIndex: si, fragmentIndex: fi))
            }
        }

        // 2) 拟声标记也占位置：胶囊不能压到它下面（它是实心 pill，画在胶囊之上）
        for s in soundMarkerFrames() {
            boxes.append(CapsuleSeamBox(rect: s.frame, textRect: s.frame, isSolid: true,
                                        lineMinY: s.lineMinY,
                                        scopeIndex: nil, fragmentIndex: nil))
        }

        // 3) 接缝收敛
        resolveCapsuleSeams(&boxes)

        for b in boxes {
            guard let si = b.scopeIndex, let fi = b.fragmentIndex,
                  si < perScopeRects.count, fi < perScopeRects[si].count else { continue }
            perScopeRects[si][fi] = b.rect
        }

        // 4) 组装结果：徽章挂在首块的左上角
        var result: [ToneCapsuleGeometry] = []
        result.reserveCapacity(toneScopes.count)
        for (si, scope) in toneScopes.enumerated() {
            let rects = perScopeRects[si]
            guard let first = rects.first else { continue }
            let (label, emoji) = labelAndEmoji(for: scope.attachment)
            let text = (emoji.isEmpty ? "" : emoji + " ") + label
            let badge = toneBadgeLayout(forCapsule: first,
                                        label: label,
                                        emoji: emoji,
                                        style: style,
                                        maxX: maxX,
                                        // 兜底：顶部留白不够时把徽章压回可见区，宁可多盖一点胶囊
                                        minY: -textContainerOrigin.y + 2)
            result.append(ToneCapsuleGeometry(
                attachment: scope.attachment,
                color: scope.color,
                capsuleRects: rects,
                badge: badge,
                badgeText: text.isEmpty ? nil : text,
                hovered: scope.attachment === kEmotionAttachmentHovered,
                selected: kEmotionAttachmentSelectionStates[ObjectIdentifier(scope.attachment)] ?? false
            ))
        }
        return result
    }

    /// 相邻两段在文档里只隔 1 个字符位（语气标记宽 1px），两侧的 8px 内边距必然互相压进去。
    /// 这里按「行 → x」排序后两两收敛：在重叠区中点切开，但每侧至少保留
    /// `capsuleSeamMinPadding` 的内边距——宁可留 ~3px 重叠，也绝不让胶囊边缘切到文字。
    ///
    /// （设计稿靠 CSS 的 `margin: 0 4px` 在两段文本之间留出 8px 空隙才做到「3px 间隙」；
    ///  AppKit 里文本是连续排布的，没法凭空插空隙，只能这样收敛。）
    private func resolveCapsuleSeams(_ boxes: inout [CapsuleSeamBox]) {
        guard boxes.count > 1 else { return }
        let style = EmotionTokenStyle.default
        let gap = style.capsuleSeamGap
        let minPad = style.capsuleSeamMinPadding
        boxes.sort { a, b in
            if abs(a.lineMinY - b.lineMinY) > 1 { return a.lineMinY < b.lineMinY }
            return a.rect.minX < b.rect.minX
        }
        for i in 0..<(boxes.count - 1) {
            let j = i + 1
            // 不同行不存在水平接缝
            guard abs(boxes[i].lineMinY - boxes[j].lineMinY) <= 1 else { continue }
            guard boxes[i].rect.maxX > boxes[j].rect.minX - gap else { continue }
            let mid = (boxes[i].rect.maxX + boxes[j].rect.minX) / 2

            // 实心（拟声 pill）不让位：那一侧的间隙由胶囊单方面让出来。
            // 两边都是胶囊才在重叠区中点各让一半。
            var aMax = mid - gap / 2
            var bMin = mid + gap / 2
            if boxes[j].isSolid {
                aMax = boxes[j].rect.minX - gap
            } else if boxes[i].isSolid {
                bMin = boxes[i].rect.maxX + gap
            }

            if !boxes[i].isSolid {
                // 下限：不能切掉文字（minPad 允许贴到 advance 边界，字形自带 ~0.6pt 边距）
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

    /// 所有拟声标记的真实 frame（container 坐标系）。
    /// 不能用 `boundingRect(forGlyphRange:)`：它的高度会被抬到整行高，只有 x / width 可信。
    private func soundMarkerFrames() -> [(frame: NSRect, lineMinY: CGFloat)] {
        guard let storage = textStorage, let lm = layoutManager else { return [] }
        var out: [(frame: NSRect, lineMinY: CGFloat)] = []
        storage.enumerateAttribute(.attachment,
                                   in: NSRange(location: 0, length: storage.length),
                                   options: []) { value, range, _ in
            guard let att = value as? NSTextAttachment,
                  EmotionTokenAttachment.isEmotionToken(att),
                  let cell = att.attachmentCell as? EmotionTokenAttachmentCell,
                  cell.tokenCategory == .richLanguage else { return }
            let glyph = lm.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            guard glyph.length > 0 else { return }
            var lineOrigin = NSPoint.zero
            lm.enumerateLineFragments(forGlyphRange: glyph) { lineRect, _, _, _, _ in
                lineOrigin = lineRect.origin
            }
            let loc = lm.location(forGlyphAt: glyph.location)
            let size = cell.cellSize()
            // 返回的是 pill **绘制**用的矩形（左右各内缩 soundEdgeInset），
            // 不是 cell 的完整 frame——接缝要按看得见的边界算，否则间隙会落在 pill 底下。
            let inset = EmotionTokenStyle.default.soundEdgeInset
            out.append((NSRect(x: lineOrigin.x + loc.x,
                               y: lineOrigin.y + loc.y - size.height,
                               width: size.width, height: size.height)
                            .insetBy(dx: inset, dy: 0),
                        lineOrigin.y))
        }
        return out
    }

    /// 离屏几何测试用：导出当前语气胶囊 / 徽章 / × 的几何（container 坐标系）。
    /// - Note: internal 而非 private：供离屏几何测试直接调用（与 `hitTestTokenDelete` 同款）。
    func debugToneCapsuleGeometry() -> [(capsules: [NSRect], badge: NSRect?, close: NSRect?)] {
        toneCapsuleGeometries().map {
            (capsules: $0.capsuleRects, badge: $0.badge?.rect, close: $0.badge?.closeRect)
        }
    }

    /// 某个标记附件所在位置的基线点（container 坐标系），用于空作用域定位徽章。
    private func markerAnchor(for attachment: NSTextAttachment) -> (point: NSPoint, lineMinY: CGFloat)? {
        guard let storage = textStorage, let lm = layoutManager else { return nil }
        var found: NSRange?
        storage.enumerateAttribute(.attachment,
                                   in: NSRange(location: 0, length: storage.length),
                                   options: []) { value, range, stop in
            guard let att = value as? NSTextAttachment, att === attachment else { return }
            found = range
            stop.pointee = true
        }
        guard let r = found else { return nil }
        let glyph = lm.glyphRange(forCharacterRange: r, actualCharacterRange: nil)
        guard glyph.length > 0 else { return nil }
        var lineOrigin: NSPoint?
        lm.enumerateLineFragments(forGlyphRange: glyph) { lineRect, _, _, _, _ in
            lineOrigin = lineRect.origin
        }
        // 一个 line fragment 都没枚举到 → 布局还没做完，此时返回坐标只会得到 (0,0)，
        // 会把空作用域的胶囊错误地挂到第 1 行去。宁可返回 nil 让这次跳过。
        guard let origin = lineOrigin else { return nil }
        let loc = lm.location(forGlyphAt: glyph.location)
        // 取标记的**右边缘**：空作用域后面接着输入的文字是从这里开始的，
        // 拿左边缘会和上一段文本的末尾重合，接缝处就切不出间隙。
        let width = (attachment.attachmentCell as? EmotionTokenAttachmentCell)?.cellSize().width ?? 0
        return (NSPoint(x: origin.x + loc.x + width, y: origin.y + loc.y), origin.y)
    }

    /// 从 cell（缺失时退回 FileWrapper）里取出标签的名称与 emoji。
    private func labelAndEmoji(for attachment: NSTextAttachment) -> (label: String, emoji: String) {
        let cell = attachment.attachmentCell as? EmotionTokenAttachmentCell
        let token = (cell == nil) ? EmotionTokenAttachment.parse(from: attachment) : nil
        return (cell?.tokenLabel ?? token?.label ?? "",
                cell?.tokenEmoji ?? token?.emoji ?? "")
    }

    // MARK: - 自绘语气胶囊

    /// 三段式绘制（顺序**不能换**）：
    ///   1. 先画胶囊（填充 + 内描边）——必须在字形**下面**，否则会把正文盖住；
    ///   2. 再画徽章——它压在自己胶囊的上沿、且不与任何字形相交（徽章底边比首行字形顶端
    ///      还高 1.5pt），所以放在 super.draw 之前画不会被打断；
    ///   3. 最后交给 super 画文本 / 附件（拟声标记落在胶囊内部，视觉上不打断语气）。
    ///
    /// ⚠️ 徽章**必须**在 `super.draw(rect)` 之前画：实测 `super.draw` 返回后图形状态里的
    /// 裁剪被收窄到文本容器区域（从 container origin 开始），而徽章恰恰画在容器上沿之外
    /// （container y 为负），整块会被裁掉——胶囊在容器内、v12 的下划线也在容器内，
    /// 所以只有徽章消失。离屏渲染验证过：提前画就能完整显示（含 emoji + 文字）。
    override func draw(_ rect: NSRect) {
        let geometries = toneCapsuleGeometries()
        drawToneCapsules(geometries, in: rect)
        drawToneBadges(geometries, in: rect)
        super.draw(rect)
    }

    private func drawToneCapsules(_ geometries: [ToneCapsuleGeometry], in dirtyRect: NSRect) {
        guard !geometries.isEmpty else { return }
        let style = EmotionTokenStyle.default
        let origin = textContainerOrigin

        for g in geometries {
            // 中断作用域没有情绪色 → 不画胶囊（文本按普通正文渲染）
            guard let base = g.color else { continue }
            let fill = base.withAlphaComponent(g.hovered ? style.capsuleFillAlphaHovered
                                                         : style.capsuleFillAlpha)
            let stroke = base.withAlphaComponent(style.capsuleStrokeAlpha)
            for r in g.capsuleRects {
                let rr = r.offsetBy(dx: origin.x, dy: origin.y)
                guard rr.intersects(dirtyRect) else { continue }
                let path = NSBezierPath(roundedRect: rr,
                                        xRadius: style.capsuleCornerRadius,
                                        yRadius: style.capsuleCornerRadius)
                fill.setFill()
                path.fill()
                // 1px 内描边：路径内缩 0.5，描边才不会溢出到圆角外面
                let insetPath = NSBezierPath(roundedRect: rr.insetBy(dx: 0.5, dy: 0.5),
                                             xRadius: max(style.capsuleCornerRadius - 0.5, 0),
                                             yRadius: max(style.capsuleCornerRadius - 0.5, 0))
                stroke.setStroke()
                insetPath.lineWidth = 1
                insetPath.stroke()

                // 选中态：胶囊外再套一圈 2px 情绪色光环
                if g.selected {
                    let ring = NSBezierPath(roundedRect: rr.insetBy(dx: -1.5, dy: -1.5),
                                            xRadius: style.capsuleCornerRadius + 1.5,
                                            yRadius: style.capsuleCornerRadius + 1.5)
                    base.withAlphaComponent(style.capsuleSelectionRingAlpha).setStroke()
                    ring.lineWidth = 2
                    ring.stroke()
                }
            }
        }
    }

    private func drawToneBadges(_ geometries: [ToneCapsuleGeometry], in dirtyRect: NSRect) {
        guard !geometries.isEmpty else { return }
        let style = EmotionTokenStyle.default
        let origin = textContainerOrigin
        let bg = resolvedBadgeBackgroundColor

        for g in geometries {
            guard let badge = g.badge else { continue }
            let rr = badge.rect.offsetBy(dx: origin.x, dy: origin.y)
            guard rr.intersects(dirtyRect) else { continue }

            // 语气 = 情绪色；中断 = 次级文字色（刻意做成安静的弱提示）
            let accent = g.color ?? EmotionTokenStyle.badgeNeutralColor
            let path = NSBezierPath(roundedRect: rr,
                                    xRadius: style.badgeCornerRadius,
                                    yRadius: style.badgeCornerRadius)
            bg.setFill()
            path.fill()
            accent.withAlphaComponent(style.badgeStrokeAlpha).setStroke()
            path.lineWidth = 1
            path.stroke()

            if let text = g.badgeText {
                var attrs: [NSAttributedString.Key: Any] = [
                    .font: style.badgeFont,
                    .foregroundColor: accent
                ]
                // 选中态：徽章文字加下划线（对应设计稿 .seg.sel .badge）
                if g.selected {
                    attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
                }
                let textOrigin = NSPoint(x: badge.textOrigin.x + origin.x,
                                         y: badge.textOrigin.y + origin.y)
                (text as NSString).draw(at: textOrigin, withAttributes: attrs)
            }

            // × 只在悬停时绘制；位置常态已占位，所以徽章宽度不会跳。
            guard g.hovered else { continue }
            let cr = badge.closeRect.offsetBy(dx: origin.x, dy: origin.y)
            let xStr = "×" as NSString
            let xAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 11, weight: .bold),
                .foregroundColor: g.color ?? EmotionTokenStyle.badgeNeutralColor
            ]
            let xSize = xStr.size(withAttributes: xAttrs)
            xStr.draw(at: NSPoint(x: cr.midX - xSize.width / 2,
                                  y: rr.minY + style.badgeVerticalPadding),
                      withAttributes: xAttrs)
        }
    }

    // MARK: - 插入光标（caret 高度修正）

    /// `bodyLineSpacing = 28` 会把行片段矩形撑到 ≈ 44.5pt，系统默认按**整个行片段**
    /// 画插入光标，蓝色 caret 比字形高一大截、下探到两行之间的空隙里。
    /// 这里自绘：caret 上下沿由**基线 ± 字体度量**推出（与语气胶囊用的是同一套算法，
    /// 见 `toneCapsuleGeometries()`），于是 caret 正好等于胶囊夹住的那块文本区，天然居中。
    ///
    /// ⚠️ 不能改用 `lineFragmentUsedRect` 居中：usedRect 与字形度量不是同一套口径，
    /// 实测会把 caret 压得偏低、下沿超出胶囊。
    override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn: Bool) {
        // 熄灭（闪烁的灭相）交给 super 擦除——它会擦整个行片段矩形，必然覆盖我们画的小 caret
        guard turnedOn, shouldDrawInsertionPoint, isEditable,
              let lm = layoutManager, let tc = textContainer else {
            super.drawInsertionPoint(in: rect, color: color, turnedOn: turnedOn)
            return
        }

        let f = font ?? EmotionTokenStyle.bodyFont
        let fontHeight = f.ascender - f.descender

        var caretRect = NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: fontHeight)
        if let top = insertionPointTextTop(container: tc, layoutManager: lm) {
            caretRect.origin.y = top + textContainerOrigin.y
        }
        // 兜底：无论度量怎么偏，绝不溢出系统给的插入点矩形（行片段范围）
        caretRect.origin.y = min(max(caretRect.origin.y, rect.minY),
                                 max(rect.maxY - caretRect.height, rect.minY))

        color.setFill()
        NSBezierPath(rect: caretRect).fill()
    }

    /// 光标所在行「文本区顶端」的 y（container 坐标系），nil = 拿不到布局信息（空文本等）。
    ///
    /// 与胶囊几何同源：`baseline = lineRect.minY + location(forGlyphAt:).y`
    /// （`location` 返回的是相对**所在 line fragment 原点**的偏移，不是绝对 container 坐标）。
    private func insertionPointTextTop(container tc: NSTextContainer,
                                       layoutManager lm: NSLayoutManager) -> CGFloat? {
        guard let storage = textStorage, storage.length > 0 else { return nil }
        let length = storage.length
        let charIndex = min(max(selectedRange().location, 0), length)

        // 光标停在末尾空行（文本以换行结尾）：只有 extra line fragment 描述这一行
        if charIndex >= length, lm.extraLineFragmentTextContainer === tc {
            let frag = lm.extraLineFragmentRect
            let used = lm.extraLineFragmentUsedRect
            let f = font ?? EmotionTokenStyle.bodyFont
            return used.height > 0
                ? used.minY + (used.height - (f.ascender - f.descender)) / 2
                : frag.minY
        }

        let char = min(charIndex, length - 1)
        let glyph = min(lm.glyphIndexForCharacter(at: char), max(lm.numberOfGlyphs - 1, 0))
        guard lm.isValidGlyphIndex(glyph) else { return nil }
        let lineRect = lm.lineFragmentRect(forGlyphAt: glyph, effectiveRange: nil)
        let baseline = lineRect.minY + lm.location(forGlyphAt: glyph).y
        let f = font ?? EmotionTokenStyle.bodyFont
        return baseline - f.ascender
    }

    // MARK: - didChange

    override func didChangeText() {
        super.didChangeText()
        // 1) 作用域只算数据、不写属性，逐键调用也是 O(n) 的轻量扫描
        recomputeToneScopes()
        // 2) 换行重排会让 token 位置变化，光标区域（小手 Rect）要跟着重算
        syncContainerWidthToCells()
        invalidateTokenCursorRects()
        // 3) 内容同步给 SwiftUI 则去抖：等输入停下来再归纳
        scheduleContentChangeNotify()
    }

    /// 输入停止 `contentChangeDelay` 后通知外部（连续输入时每次按键都会重置定时器）。
    private func scheduleContentChangeNotify() {
        contentChangeWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.contentChangeWorkItem = nil
            self.onContentChange?()
        }
        contentChangeWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.contentChangeDelay, execute: item)
    }

    /// 把待同步的内容立刻推给外部。结构性改动（插入/删除标签、setContent、失焦）走这条路，
    /// 保证这些操作之后 VM 的 items 是同步的，不留 0.35s 的空窗。
    func flushPendingContentChange() {
        guard let item = contentChangeWorkItem else { return }
        item.cancel()
        contentChangeWorkItem = nil
        onContentChange?()
    }

    /// 失焦时立刻结算（用户可能在输入后马上点「生成」）。
    override func resignFirstResponder() -> Bool {
        flushPendingContentChange()
        return super.resignFirstResponder()
    }

    /// 明 / 暗外观切换：作用域颜色是提前解析好缓存的，外观变了要重算一次。
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        recomputeToneScopes()
    }

    // 无法 override didChangeSelection — NSTextView 不是 NSResponder 子类暴露该方法。
    // 改为由 NSTextView 自身的 selection 改变机制处理；
    // SwiftUI 端用 NSViewRepresentable 的代表性 mode + didChange text 周期维持一致。

    /// 监听 selection 的另一种方式：继承自 NSResponder 没有标准 hook，
    /// 这里靠 didChangeText 触发的 onContentChange 来调度即可。

    private func refreshSelectionStates() {
        guard let storage = textStorage else { return }
        let allAtt = Array(kEmotionAttachmentIdentity.keys)
        // 重置所有 token 的选中态
        for id in allAtt {
            kEmotionAttachmentSelectionStates[id] = false
        }

        // 当前选中范围覆盖到的 attachment → 标记为选中
        let r = selectedRange()
        guard r.length > 0 else { return }

        var searchRange = r
        storage.enumerateAttribute(.attachment,
                                   in: searchRange,
                                   options: []) { value, range, _ in
            guard let att = value as? NSTextAttachment,
                  EmotionTokenAttachment.isEmotionToken(att) else { return }
            kEmotionAttachmentSelectionStates[ObjectIdentifier(att)] = true
            searchRange = NSRange(location: range.location + range.length,
                                  length: storage.length - (range.location + range.length))
            _ = searchRange
        }
        needsDisplay = true
    }

    // MARK: - 粘贴修复

    override func paste(_ sender: Any?) {
        // 从剪贴板读取纯文本，避免粘贴进带颜色等格式的富文本
        guard let plainText = NSPasteboard.general.string(forType: .string) else {
            super.paste(sender)
            return
        }
        let range = selectedRange()
        // 使用当前 typingAttributes（白色字体）作为粘贴文本的属性
        let attrs = bodyAttributes
        let attributedString = NSAttributedString(string: plainText, attributes: attrs)

        guard shouldChangeText(in: range, replacementString: plainText) else { return }
        textStorage?.replaceCharacters(in: range, with: attributedString)
        let newLocation = range.location + plainText.count
        setSelectedRange(NSRange(location: newLocation, length: 0))
        didChangeText()
        flushPendingContentChange()
        fixUpPastedTokenAttachments()
    }

    /// 粘贴进来的 attachment 会被 NSTextView 用 generic NSTextAttachmentCell 替换，
    /// 失去 EmotionTokenAttachmentCell。这里在 didChangeText 后重新包一层。
    private func fixUpPastedTokenAttachments() {
        guard let storage = textStorage else { return }
        var didFix = false
        storage.enumerateAttributes(in: NSRange(location: 0, length: storage.length)) { attrs, range, _ in
            guard let att = attrs[.attachment] as? NSTextAttachment,
                  EmotionTokenAttachment.isEmotionToken(att) else { return }

            if !(att.attachmentCell is EmotionTokenAttachmentCell) {
                let cell = EmotionTokenAttachmentCell()
                var identity: EmotionTokenIdentity?
                if let token = EmotionTokenAttachment.parse(from: att) {
                    cell.tokenLabel = token.label
                    cell.tokenEmoji = token.emoji
                    let base = EmotionTokenStyle.baseColor(for: token.englishTag.isEmpty ? token.label : token.englishTag)
                    identity = EmotionTokenIdentity(baseColor: base, category: token.category)
                }
                att.attachmentCell = cell
                if let identity {
                    kEmotionAttachmentIdentity[ObjectIdentifier(att)] = identity
                }
                didFix = true
            }
        }
        if didFix, let lm = layoutManager, let tc = textContainer {
            let full = NSRange(location: 0, length: storage.length)
            lm.invalidateLayout(forCharacterRange: full, actualCharacterRange: nil)
            lm.invalidateDisplay(forCharacterRange: full)
            _ = tc
        }
    }

    // MARK: - 命中区域（container 坐标）

    /// 一个 token 的可交互几何。所有坐标均为 text container 坐标系。
    private struct TokenHitRegion {
        let attachment: NSTextAttachment
        let identity: EmotionTokenIdentity
        let range: NSRange
        /// cell 的真实 frame（container 坐标系）。
        /// 不能直接用 `layoutManager.boundingRect(forGlyphRange:)`：它的高度会被抬高到行高
        /// （实测拟声 cell 高 22，矩形给 39），只有 x / width / minY 可信。
        /// 这里用 glyph location + cellSize 精确还原：
        ///   **location(forGlyphAt:) 返回的坐标是相对「所在 line fragment 原点」的，不是绝对 container 坐标**
        ///   （实测第二行 lineFragment.minY = 29，location.y 仍是相对它），必须先加上 lineRect 原点，
        ///   否则第 2 行及以后所有标签的命中区都会整体上移一个行距 → hover 完全失效。
        let frame: NSRect
        let style: EmotionTokenStyle
        /// 删除按钮命中区（× 画在 frame 之外）
        let deleteRect: NSRect?
        /// 语气类的左上角徽章（画在 frame 之外，压在胶囊上沿）
        let badgeRect: NSRect?
        /// 语气类的胶囊矩形（跨行时每个行片段一块）。
        /// 只参与 hover，不参与小手光标——正文还是要能正常选中，光标应保持 I 型。
        let capsuleRects: [NSRect]
    }

    /// 扫描当前所有 emotion token，算出各自的真实 frame 与附属命中区。
    private func tokenHitRegions() -> [TokenHitRegion] {
        guard let storage = textStorage, let lm = layoutManager, let tc = textContainer else { return [] }
        let dark = EmotionTokenStyle.isDarkAppearance(effectiveAppearance)
        var regions: [TokenHitRegion] = []
        // 语气类的徽章 / 胶囊由作用域几何给出（绘制与命中必须同一份，否则会错位）。
        let toneGeometry = Dictionary(uniqueKeysWithValues: toneCapsuleGeometries().map { g in
            (ObjectIdentifier(g.attachment), g)
        })

        storage.enumerateAttribute(.attachment,
                                   in: NSRange(location: 0, length: storage.length),
                                   options: []) { value, range, _ in
            guard let att = value as? NSTextAttachment,
                  EmotionTokenAttachment.isEmotionToken(att) else { return }
            let glyph = lm.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            guard glyph.length > 0 else { return }

            // identity / cell 缺失时（例如还没被 fixUp 的粘贴附件）退回旧的 boundingRect 算法：
            // 宁可用「被抬高到行高的胖矩形」，也不能完全没有命中区——hover 彻底失效比矩形略大难查得多。
            let id = kEmotionAttachmentIdentity[ObjectIdentifier(att)]
                ?? EmotionTokenIdentity(baseColor: EmotionTokenStyle.fallbackBaseColor, category: .emotion)
            let cell = att.attachmentCell as? EmotionTokenAttachmentCell
            let style = EmotionTokenStyle.resolved(for: id, dark: dark)

            var lineOrigin = NSPoint.zero
            lm.enumerateLineFragments(forGlyphRange: glyph) { lineRect, _, _, _, _ in
                lineOrigin = lineRect.origin
            }
            // glyph location 的 y = cell 底边、x = cell 左边（均相对所在 line fragment 原点）
            let loc = lm.location(forGlyphAt: glyph.location)
            let frame: NSRect
            if let size = cell?.cellSize() {
                frame = NSRect(x: lineOrigin.x + loc.x,
                               y: lineOrigin.y + loc.y - size.height,
                               width: size.width, height: size.height)
            } else {
                frame = lm.boundingRect(forGlyphRange: glyph, in: tc)
            }

            let deleteRect: NSRect?
            let badgeRect: NSRect?
            let capsuleRects: [NSRect]
            if id.category == .richLanguage {
                deleteRect = soundDeleteHitRect(for: frame, style: style)
                badgeRect = nil
                capsuleRects = []
            } else {
                let g = toneGeometry[ObjectIdentifier(att)]
                // × 挂在徽章右侧；空作用域没有胶囊时 deleteRect 也不能为空，
                // 否则刚插入的标签删不掉（此时徽章一定存在，因为它是唯一可见物）。
                deleteRect = g?.badge?.closeRect
                badgeRect = g?.badge?.rect
                capsuleRects = g?.capsuleRects ?? []
            }
            regions.append(TokenHitRegion(attachment: att, identity: id, range: range,
                                          frame: frame, style: style,
                                          deleteRect: deleteRect, badgeRect: badgeRect,
                                          capsuleRects: capsuleRects))
        }
        return regions
    }

    /// 把视图坐标转成 container 坐标（各类命中统一在这个坐标系里做）。
    private func containerPoint(from pointInView: NSPoint) -> NSPoint {
        NSPoint(x: pointInView.x - textContainerOrigin.x,
                y: pointInView.y - textContainerOrigin.y)
    }

    // MARK: - 悬停 / 光标

    /// 鼠标离开某个 tag 到真正清空 hover 之间的宽限时间。
    /// 没有它的话，鼠标从胶囊移向 × 的过程中只要有一帧落在两者之外，
    /// × 就会在点到之前先消失（用户反馈的核心问题）。
    private static let hoverGrace: TimeInterval = 0.35
    private var hoverClearWorkItem: DispatchWorkItem?

    // MARK: - 鼠标样式

    /// point 处应该显示的鼠标样式：落在标签（含它的 × / 下方标注）上 → 小手，否则 I 型。
    ///
    /// v7 之前的做法只在 `mouseMoved` / `cursorUpdate` 里 `NSCursor.set()`，
    /// 但那是**临时**设置：NSTextView 本身注册了覆盖整片文本区的 I-beam cursor rect，
    /// 窗口一旦自己按 rect 复原游标（滚动、尺寸变化、上层 SwiftUI 触发 `resetCursorRects()`
    /// 等场景不会先发 cursorUpdate 问我们），小手就被压回去，直到下一次鼠标移动才被抢回来 ——
    /// 这才是「小手 ↔ 箭头/I 型」来回抖的根因。
    /// 根治办法：不靠事后 set()，而是把正确的游标**注册进 AppKit 的 cursor rect 机制**。
    private func desiredCursor(at point: NSPoint) -> NSCursor {
        attachment(at: point) != nil ? NSCursor.pointingHand : NSCursor.iBeam
    }

    /// 上一次真正设置过的鼠标样式。样式不变就不重复 set —— 每次 set 都可能触发
    /// 一轮 cursor 更新，重复调用本身就是抖动的放大器。
    private var appliedCursor: NSCursor?

    private func applyCursor(_ cursor: NSCursor) {
        if let applied = appliedCursor, applied === cursor { return }
        appliedCursor = cursor
        cursor.set()
    }

    /// 注册光标区域：整片文本区 I 型，标签及其 × / 标注区域小手。
    ///
    /// 刻意**不调用 super**：`NSTextView.resetCursorRects()` 会给整片文本区注册 I-beam，
    /// 那个 rect 会在窗口按 rect 复原游标时压掉小手。这里由我们自己注册，保证标签区域
    /// 在 AppKit 的游标机制里就是小手，不再需要与它抢。
    override func resetCursorRects() {
        guard isEditable else {
            // 只读（预览）场景没有 hover / ×，沿用 NSTextView 自己的行为即可
            super.resetCursorRects()
            return
        }
        // 关键：`tokenHitRegions()` 依赖 glyph 布局。而 `resetCursorRects()` 可能在首次绘制
        // （AppKit 惰性布局）之前就被调用，那时 `glyphRange(forCharacterRange:)` 返回空 →
        // 一个 token rect 都注册不上，整片只剩 I 型，之后又没有任何时机去刷新。这是
        // 「鼠标移到标签上却不是小手」的根因。这里先强制补一次布局。
        if let lm = layoutManager, let tc = textContainer {
            lm.ensureLayout(for: tc)
        }
        discardCursorRects()
        // 没被 clip view 包裹时（离屏测试、直接嵌视图的场景）visibleRect 可能是无穷大，
        // 那种尺寸喂给 addCursorRect 或矩形切分都会出问题，这里兜回 bounds。
        let visible = visibleRect.isUsable ? visibleRect : bounds
        guard visible.isUsable, !visible.isEmpty else { return }

        let origin = textContainerOrigin
        var tokenRects: [NSRect] = []
        for region in tokenHitRegions() {
            // 刻意**不含 capsuleRects**：胶囊里裹的是正文，光标必须保持 I 型才能正常选中 /
            // 定位插入点。胶囊只参与 hover（见 attachment(at:)），不参与小手光标。
            // 语气标记本体也排除：它是不可见占位（现在还有 5pt 宽），没有可点的视觉对象。
            let ownFrame = region.identity.category == .richLanguage ? region.frame : nil
            for rect in [ownFrame, region.deleteRect, region.badgeRect].compactMap({ $0 }) {
                let clipped = rect.offsetBy(dx: origin.x, dy: origin.y).intersection(visible)
                guard !clipped.isNull, !clipped.isEmpty else { continue }
                tokenRects.append(clipped)
            }
        }

        // 让两类区域**完全不相交**，这样谁都不依赖 AppKit 对重叠 rect 的优先级：
        // I 型只注册「扣掉标签区域后剩下的部分」，标签区域单独注册小手。
        for piece in subtracting(tokenRects, from: visible) {
            addCursorRect(piece, cursor: .iBeam)
        }
        for rect in tokenRects {
            addCursorRect(rect, cursor: .pointingHand)
        }
    }

    /// 把 `cuts` 从 `rect` 中挖掉，返回剩余部分的矩形列表（每个 cut 最多把一块切成 4 条）。
    /// - Note: internal 而非 private：供离屏几何测试直接调用。
    func subtracting(_ cuts: [NSRect], from rect: NSRect) -> [NSRect] {
        var pieces: [NSRect] = [rect]
        for cut in cuts {
            guard !cut.isNull, !cut.isEmpty else { continue }
            var next: [NSRect] = []
            for p in pieces {
                guard p.intersects(cut) else { next.append(p); continue }
                let inter = p.intersection(cut)
                // 上
                if inter.minY > p.minY {
                    next.append(NSRect(x: p.minX, y: p.minY, width: p.width, height: inter.minY - p.minY))
                }
                // 下
                if inter.maxY < p.maxY {
                    next.append(NSRect(x: p.minX, y: inter.maxY, width: p.width, height: p.maxY - inter.maxY))
                }
                // 左（只在相交的高度区间内）
                if inter.minX > p.minX {
                    next.append(NSRect(x: p.minX, y: inter.minY, width: inter.minX - p.minX, height: inter.height))
                }
                // 右
                if inter.maxX < p.maxX {
                    next.append(NSRect(x: inter.maxX, y: inter.minY, width: p.maxX - inter.maxX, height: inter.height))
                }
            }
            pieces = next
        }
        return pieces.filter { $0.isUsable }
    }

    /// token 位置会随输入 / 换行变化，光标区域要跟着重算（window 会回调 `resetCursorRects`）。
    private func invalidateTokenCursorRects() {
        guard let window else { return }
        window.invalidateCursorRects(for: self)
    }

    /// 宽度变化会整篇重排（token 换行位置变了），这种变化不走 didChangeText，必须自己刷一次。
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        syncContainerWidthToCells()
        invalidateTokenCursorRects()
    }

    /// 把当前容器宽度写进每个 cell。cell 绘制时 controlView 是 nil（实测），
    /// 拿不到容器宽度，只能靠这里预先同步。
    private func syncContainerWidthToCells() {
        guard let storage = textStorage, let tc = textContainer else { return }
        let maxX = tc.size.width
        storage.enumerateAttribute(.attachment,
                                   in: NSRange(location: 0, length: storage.length),
                                   options: []) { value, _, _ in
            guard let att = value as? NSTextAttachment,
                  EmotionTokenAttachment.isEmotionToken(att),
                  let cell = att.attachmentCell as? EmotionTokenAttachmentCell else { return }
            cell.containerMaxX = maxX
        }
    }

    /// 刚挂到窗口时 AppKit 会调 `resetCursorRects()`，之后不再主动调；
    /// 这里补一次，保证进入 window 后 token 区域一定被注册。
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        invalidateTokenCursorRects()
    }

    override func mouseMoved(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let target = attachment(at: point)
        // 命中标签时**不走 super**：NSTextView 的 mouseMoved 会把游标设回 I 型，
        // 之前「先 super 再自己设」的顺序下它会在后续事件里反复抢回去（游标抖动）。
        if target == nil { super.mouseMoved(with: event) }
        updateHover(to: target)
        applyCursor(desiredCursor(at: point))
    }

    /// AppKit 的正规游标钩子：窗口需要重新确认游标时会发 cursorUpdate 事件，
    /// 在这里回答才不会「设了又被系统改回默认箭头」。
    /// 与 mouseMoved 共用同一个 `desiredCursor(at:)`，保证两处口径一致。
    /// 落在标签上时同样不进 super，避免 NSTextView 的 I 型覆盖我们的小手。
    override func cursorUpdate(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let cursor = desiredCursor(at: point)
        if cursor === NSCursor.iBeam { super.cursorUpdate(with: event) }
        applyCursor(cursor)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        clearHoverImmediately()
        appliedCursor = NSCursor.iBeam
        NSCursor.iBeam.set()
    }

    // MARK: - 标签删除命中（× 绘制在 glyph 矩形之外，需在此层拦截）

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        if let range = hitTestTokenDelete(at: containerPoint(from: point)) {
            _ = removeToken(at: range)
            return
        }
        super.mouseDown(with: event)
    }

    /// 命中测试：当前 hover 那个 tag 的 × 是否被点中。
    /// v6：× 只在悬停时绘制，所以命中也要求该 tag 正处于悬停态——
    /// 否则点到一个看不见的按钮上会莫名其妙删掉标签。
    /// - Note: internal 而非 private：供离屏几何测试直接调用。
    func hitTestTokenDelete(at containerPoint: NSPoint) -> NSRange? {
        for r in tokenHitRegions() where r.attachment === kEmotionAttachmentHovered {
            if let d = r.deleteRect, d.contains(containerPoint) { return r.range }
        }
        return nil
    }

    /// 更新 hover。离开时不清空得太急，给一段宽限再收，避免 × 在点击前闪没。
    /// - Note: internal 而非 private：供离屏几何测试直接调用。
    func updateHover(to target: NSTextAttachment?) {
        hoverClearWorkItem?.cancel()
        hoverClearWorkItem = nil
        guard let t = target else {
            scheduleHoverClear()
            return
        }
        guard t !== kEmotionAttachmentHovered else { return }
        kEmotionAttachmentHovered = t
        needsDisplay = true
    }

    private func scheduleHoverClear() {
        guard kEmotionAttachmentHovered != nil else { return }
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.hoverClearWorkItem = nil
            kEmotionAttachmentHovered = nil
            self.needsDisplay = true
        }
        hoverClearWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.hoverGrace, execute: item)
    }

    /// 立刻清空 hover（删除了标签、鼠标离开视图时用）。
    private func clearHoverImmediately() {
        hoverClearWorkItem?.cancel()
        hoverClearWorkItem = nil
        if kEmotionAttachmentHovered != nil {
            kEmotionAttachmentHovered = nil
            needsDisplay = true
        }
    }

    /// 命中测试：返回 point 之下属本编辑器的 emotion token attachment（没有则 nil）。
    ///
    /// v6 关键修正：判定区域 = **字形矩形 ∪ 删除按钮区 ∪ 下方标注区**。
    /// × 与标注都画在字形矩形之外，只判字形矩形的话，鼠标一旦从胶囊移向 ×，
    /// hover 立刻丢失 → × 消失 → 永远点不到（用户反馈：删除按钮一碰就没）。
    /// - Note: internal 而非 private：供离屏几何测试直接调用。
    func attachment(at point: NSPoint) -> NSTextAttachment? {
        let p = containerPoint(from: point)
        var best: (attachment: NSTextAttachment, area: CGFloat)?
        for r in tokenHitRegions() {
            // 悬停区 = 字形 ∪ × ∪ 徽章 ∪ 整段胶囊。
            // 只判本体的话，鼠标从胶囊移向徽章 × 的过程中 hover 会丢，× 也就永远点不到。
            let candidates = [r.frame, r.deleteRect, r.badgeRect].compactMap { $0 } + r.capsuleRects
            // 取命中的最小区域：相邻 tag 的区域可能有重叠，小的那个更贴近指针所指之物
            for c in candidates where c.contains(p) {
                let area = c.width * c.height
                if best == nil || area < best!.area {
                    best = (r.attachment, area)
                }
            }
        }
        return best?.attachment
    }
}

private extension NSRect {
    /// 是否是一个可用于光标区域的有限矩形（Null / 空 / 无穷大都排除）。
    var isUsable: Bool {
        !isNull && !isEmpty && width.isFinite && height.isFinite &&
        width < CGFloat.greatestFiniteMagnitude && height < CGFloat.greatestFiniteMagnitude
    }
}
