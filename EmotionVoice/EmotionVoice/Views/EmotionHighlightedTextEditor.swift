//
//  EmotionHighlightedTextEditor.swift
//  EmotionVoice
//
//  Created by young on 2026/8/8.
//

import SwiftUI
import AppKit

/// 高亮情感标签的 NSTextView 封装
///
/// 通过 NSTextViewDelegate 监听文本变化并应用样式；
/// 同时将选中区间（光标位置）通过 `selectedRange` 双向绑定回宿主，
/// 使情感面板按钮能"在光标处插入"而不是只能在末尾追加。
struct EmotionHighlightedTextEditor: NSViewRepresentable {

    @Binding var text: String
    @Binding var selectedRange: NSRange
    let emotions: [EmotionItem]

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        // 手动创建 scroll view + NSTextView，让 NSTextView 使用带 placeholder 的子类，
        // 避免 SwiftUI overlay 把点击事件挡掉导致 NSTextView 无法成为 first responder。
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear

        let textContainer = NSTextContainer(size: NSSize(
            width: 0,
            height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
        textContainer.lineFragmentPadding = 0

        let layoutManager = NSLayoutManager()
        layoutManager.addTextContainer(textContainer)

        // 关键：用 contentSize 初始化 frame，确保 NSTextView 在首次渲染时就有非零宽高。
        // 否则 documentView 为 0×0，点击区域为空，NSTextView 无法成为 first responder。
        let initialSize = scrollView.contentSize
        let textView = PlaceholderDrawingTextView(
            frame: NSRect(origin: .zero, size: NSSize(
                width: max(initialSize.width, 1),
                height: max(initialSize.height, 1))),
            textContainer: textContainer)
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                  height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.allowsUndo = true
        textView.isEditable = true
        textView.isSelectable = true

        scrollView.documentView = textView

        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 0, height: 0)
        textView.font = NSFont.systemFont(ofSize: 14)
        textView.textColor = NSColor(white: 0.96, alpha: 1.0)
        textView.placeholder = "插入文本或粘贴内容".localized()
        textView.placeholderColor = NSColor(white: 0.5, alpha: 1.0)

        context.coordinator.textView = textView
        // 首次进入时将外部传入的 selectedRange 应用到 NSTextView
        let safe = Self.clamp(range: selectedRange, in: textView.string)
        textView.setSelectedRange(safe)
        context.coordinator.applyHighlight()

        // SwiftUI 嵌入 NSTextView 时默认不会让它自动获得 first responder。
        // 在下一个主循环强制把 NSTextView 设为 first responder，确保用户点击编辑区后立即可输入。
        DispatchQueue.main.async { [weak textView] in
            guard let textView, let window = textView.window else { return }
            if window.firstResponder !== textView {
                window.makeFirstResponder(textView)
            }
        }

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }

        // 文本从外部变化：同步到 NSTextView
        if textView.string != text {
            textView.string = text
            context.coordinator.applyHighlight()
            // 文本长度变化，重置光标到末尾
            let end = (text as NSString).length
            if !context.coordinator.isInternalUpdate {
                textView.setSelectedRange(NSRange(location: end, length: 0))
            }
        }

        // 选中区间从外部变化：同步到 NSTextView（仅在两者不一致时）
        let current = textView.selectedRange()
        let external = Self.clamp(range: selectedRange, in: textView.string)
        if !NSEqualRanges(current, external) && !context.coordinator.isInternalUpdate {
            textView.setSelectedRange(external)
            // 滚动到可见
            if let layoutMgr = textView.layoutManager,
               let textContainer = textView.textContainer {
                let glyphIdx = layoutMgr.glyphIndexForCharacter(at: external.location)
                let rect = layoutMgr.boundingRect(forGlyphRange: NSRange(location: glyphIdx, length: 0),
                                                  in: textContainer)
                textView.scroll(NSPoint(x: 0, y: rect.origin.y))
            }
        }
    }

    private static func clamp(range: NSRange, in text: String) -> NSRange {
        let length = (text as NSString).length
        var r = range
        if r.location < 0 { r.location = 0 }
        if r.location > length { r.location = length }
        if r.length < 0 { r.length = 0 }
        if r.location + r.length > length { r.length = length - r.location }
        return r
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        let parent: EmotionHighlightedTextEditor
        weak var textView: NSTextView?

        /// 标记"由 NSTextView 自身触发的更新"，避免 updateNSView 反向覆盖刚发生的变化
        var isInternalUpdate: Bool = false

        init(_ parent: EmotionHighlightedTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            isInternalUpdate = true
            defer { isInternalUpdate = false }
            parent.text = textView.string
            // 用户输入后，把光标推到当前 NSTextView 选中处
            parent.selectedRange = textView.selectedRange()
            // IME 合成中（中文/日文/韩文等）不要修改 textStorage，否则会打断 marked text，
            // 导致只能输入字母、无法上屏汉字。合成结束后下一次 textDidChange
            // 会再次走到这里并应用高亮。
            if textView.hasMarkedText() { return }
            applyHighlight(to: textView)
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            isInternalUpdate = true
            defer { isInternalUpdate = false }
            parent.selectedRange = textView.selectedRange()
        }

        /// 应用 [xxx] 标签的高亮
        func applyHighlight(to tv: NSTextView? = nil) {
            guard let textView = tv ?? self.textView else { return }
            let storage = textView.textStorage
            guard let storage else { return }

            let fullRange = NSRange(location: 0, length: storage.length)
            storage.beginEditing()

            // 先还原默认样式
            storage.removeAttribute(.foregroundColor, range: fullRange)
            storage.removeAttribute(.font, range: fullRange)
            storage.addAttribute(.font,
                                 value: NSFont.systemFont(ofSize: 14),
                                 range: fullRange)
            storage.addAttribute(.foregroundColor,
                                 value: NSColor(white: 0.96, alpha: 1.0),
                                 range: fullRange)

            // 高亮所有 [xxx] 标签（中文 / 英文均能命中）
            let text = textView.string as NSString
            let pattern = "\\[[^\\]]+\\]"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
                storage.endEditing()
                return
            }

            let accent = NSColor(red: 0.95, green: 0.75, blue: 0.53, alpha: 1.0)
            let mono = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
            regex.enumerateMatches(in: text as String,
                                   options: [],
                                   range: fullRange) { match, _, _ in
                guard let range = match?.range else { return }
                storage.addAttribute(.foregroundColor, value: accent, range: range)
                storage.addAttribute(.font, value: mono, range: range)
            }

            storage.endEditing()
        }
    }
}

// MARK: - PlaceholderDrawingTextView

/// 带 placeholder 的 NSTextView 子类。
///
/// 只在文本为空时把 placeholder 字符串画在 textContainer 的原点附近。
/// 不参与 hit-test —— 所有点击都会正常传递给 NSTextView 的原生 first responder 逻辑，
/// 避免 SwiftUI overlay 拦截点击导致 NSTextView 无法获得 first responder → 无法输入。
final class PlaceholderDrawingTextView: NSTextView {
    var placeholder: String = "" {
        didSet { needsDisplay = true }
    }
    var placeholderColor: NSColor = NSColor.tertiaryLabelColor

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !placeholder.isEmpty else { return }
        let inset = textContainerInset
        let origin = NSPoint(x: inset.width, y: inset.height)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font ?? NSFont.systemFont(ofSize: 14),
            .foregroundColor: placeholderColor
        ]
        (placeholder as NSString).draw(at: origin, withAttributes: attrs)
    }

    override var string: String {
        didSet {
            // 文本变化时强制重绘，让 placeholder 隐藏/出现
            needsDisplay = true
        }
    }

    override func setNeedsDisplay(_ rect: NSRect) {
        super.setNeedsDisplay(rect)
    }
}
