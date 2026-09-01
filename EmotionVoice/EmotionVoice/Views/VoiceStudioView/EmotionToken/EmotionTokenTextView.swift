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

    /// 当前 Token 样式。改样式后需要重绘所有 token。
    var tokenStyle: EmotionTokenStyle = .default

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
        textContainerInset = NSSize(width: 0, height: 8)
        font = NSFont.systemFont(ofSize: 14)
        textColor = NSColor.white
        backgroundColor = .clear
        drawsBackground = false
        usesFindBar = true
    }

    // MARK: - Insert Token

    /// 在当前光标位置插入一个 emotion token。
    ///   * 如果光标前不是空白/换行/Token，自动补一个空格。
    ///   * 如果有选中文本，把选中片段替换为 token。
    @discardableResult
    func insertToken(_ token: EmotionToken) -> Bool {
        let attachment = EmotionTokenAttachment.makeAttachment(for: token, style: tokenStyle)
        // 标记位置（包括 attachment 自身）使用普通 body 风格属性，
        // 这样在 token 之后输入的字符仍是普通白色文字，而不是 pill 颜色。
        var bodyAttrs = typingAttributes
        if bodyAttrs[.font] == nil {
            bodyAttrs[.font] = NSFont.systemFont(ofSize: 14)
        }
        if bodyAttrs[.foregroundColor] == nil {
            bodyAttrs[.foregroundColor] = NSColor.white
        }
        // 注意：attachment 自身的字体颜色会被 cell 覆盖，这里只是做 typo。

        let attr = NSMutableAttributedString(attachment: attachment)
        attr.addAttributes(bodyAttrs, range: NSRange(location: 0, length: attr.length))

        let range = selectedRange()
        let storage = textStorage

        // 是否需要补前缀空格
        var prefix = ""
        let nsString = (storage?.string ?? "") as NSString
        if range.length == 0 && range.location > 0 && range.location <= nsString.length {
            let prevIndex = range.location - 1
            let prev = nsString.substring(with: NSRange(location: prevIndex, length: 1))
            // token 是 attachment，所以 storage[prevIndex] 一定是普通字符
            if !prev.isEmpty && ![" ", "\n", "\t"].contains(prev) {
                prefix = " "
            }
        }

        let prefixAttr: NSAttributedString
        if prefix.isEmpty {
            prefixAttr = NSAttributedString()
        } else {
            prefixAttr = NSAttributedString(string: prefix, attributes: bodyAttrs)
        }

        let combined = NSMutableAttributedString()
        combined.append(prefixAttr)
        combined.append(attr)

        guard shouldChangeText(in: range, replacementString: combined.string) else { return false }
        storage?.replaceCharacters(in: range, with: combined)
        let newLocation = range.location + combined.length
        setSelectedRange(NSRange(location: newLocation, length: 0))
        typingAttributes = bodyAttrs
        didChangeText()
        return true
    }

    /// 删除所有 token，同时保留普通文本
    func clearAllTokens() {
        guard let storage = textStorage else { return }
        storage.beginEditing()
        defer {
            storage.endEditing()
            didChangeText()
            onContentChange?()
        }

        var ranges: [NSRange] = []
        storage.enumerateAttribute(.attachment,
                                   in: NSRange(location: 0, length: storage.length),
                                   options: []) { value, range, _ in
            if let att = value as? NSTextAttachment, EmotionTokenAttachment.isEmotionToken(att) {
                ranges.append(range)
            }
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

        let bodyAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14),
            .foregroundColor: NSColor.white
        ]
        let result = NSMutableAttributedString()

        for item in items {
            switch item {
            case .text(let s):
                if !s.isEmpty {
                    result.append(NSAttributedString(string: s, attributes: bodyAttrs))
                }
            case .emotion(let token):
                let attachment = EmotionTokenAttachment.makeAttachment(for: token, style: tokenStyle)
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
            guard shouldChangeText(in: r, replacementString: "") else { return }
            storage.deleteCharacters(in: r)
            setSelectedRange(NSRange(location: r.location, length: 0))
            didChangeText()
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
            guard shouldChangeText(in: prevAttachmentRange, replacementString: "") else { return }
            textStorage?.deleteCharacters(in: prevAttachmentRange)
            setSelectedRange(NSRange(location: prevAttachmentRange.location, length: 0))
            didChangeText()
            return
        }

        // 情况 5（可选吸附模式）：cursor 之前最近的 token 距离很近 → 整体删除它
        if !strictAtomicDelete, let nearest = nearestTokenIndex(around: r.location, lookingBackward: true) {
            // 只在「最近 token 距离 ≤ 2」时吸附，避免误删（保险起见设为 1 即可：必须紧邻）
            if r.location - nearest == 1 {
                let attachRange = NSRange(location: nearest, length: 1)
                guard shouldChangeText(in: attachRange, replacementString: "") else { return }
                textStorage?.deleteCharacters(in: attachRange)
                setSelectedRange(NSRange(location: nearest, length: 0))
                didChangeText()
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
            guard shouldChangeText(in: r, replacementString: "") else { return }
            storage.deleteCharacters(in: r)
            setSelectedRange(NSRange(location: r.location, length: 0))
            didChangeText()
            return
        }

        // 情况 2：有非空选区
        if r.length > 0 {
            super.deleteForward(sender)
            return
        }

        // 情况 3：cursor 之后那个字符是 attachment → 整体删除
        if let nextAttachmentRange = attachmentRange(at: r.location) {
            guard shouldChangeText(in: nextAttachmentRange, replacementString: "") else { return }
            textStorage?.deleteCharacters(in: nextAttachmentRange)
            setSelectedRange(NSRange(location: r.location, length: 0))
            didChangeText()
            return
        }

        if !strictAtomicDelete, let nearest = nearestTokenIndex(around: r.location, lookingBackward: false) {
            if nearest - r.location == 1 {
                let attachRange = NSRange(location: nearest, length: 1)
                guard shouldChangeText(in: attachRange, replacementString: "") else { return }
                textStorage?.deleteCharacters(in: attachRange)
                setSelectedRange(NSRange(location: r.location, length: 0))
                didChangeText()
                return
            }
        }

        super.deleteForward(sender)
    }

    // MARK: - didChange / didChangeSelection

    override func didChangeText() {
        super.didChangeText()
        onContentChange?()
    }

    // 无法 override didChangeSelection — NSTextView 不是 NSResponder 子类暴露该方法。
    // 改为由 NSTextView 自身的 selection 改变机制处理；
    // SwiftUI 端用 NSViewRepresentable 的代表性 mode + didChange text 周期维持一致。

    /// 监听 selection 的另一种方式：继承自 NSResponder 没有标准 hook，
    /// 这里靠 didChangeText 触发的 onContentChange 来调度即可。

    private func refreshSelectionStates() {
        guard let storage = textStorage else { return }
        let allAtt = Array(kEmotionAttachmentStyles.keys)
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
        let attrs = typingAttributes.isEmpty ? [
            .font: NSFont.systemFont(ofSize: 14),
            .foregroundColor: NSColor.white
        ] : typingAttributes
        let attributedString = NSAttributedString(string: plainText, attributes: attrs)

        guard shouldChangeText(in: range, replacementString: plainText) else { return }
        textStorage?.replaceCharacters(in: range, with: attributedString)
        let newLocation = range.location + plainText.count
        setSelectedRange(NSRange(location: newLocation, length: 0))
        didChangeText()
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
                if let token = EmotionTokenAttachment.parse(from: att) {
                    cell.tokenLabel = token.label
                    cell.tokenEmoji = token.emoji
                }
                att.attachmentCell = cell
                kEmotionAttachmentStyles[ObjectIdentifier(att)] = tokenStyle
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
}
