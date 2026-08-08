//
//  EmotionHighlightedTextEditor.swift
//  EmotionVoice
//
//  Created by young on 2026/8/8.
//

import SwiftUI
import AppKit

/// 高亮情感标签的 NSTextView 封装
/// 通过 NSTextViewDelegate 监听文本变化并应用样式
struct EmotionHighlightedTextEditor: NSViewRepresentable {

    @Binding var text: String
    let emotions: [EmotionItem]

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }

        textView.delegate = context.coordinator
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 0, height: 0)
        textView.textContainer?.lineFragmentPadding = 0
        textView.font = NSFont.systemFont(ofSize: 14)
        textView.textColor = NSColor(white: 0.96, alpha: 1.0)

        context.coordinator.textView = textView
        context.coordinator.applyHighlight()

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        if textView.string != text {
            textView.string = text
            context.coordinator.applyHighlight()
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        let parent: EmotionHighlightedTextEditor
        weak var textView: NSTextView?

        init(_ parent: EmotionHighlightedTextEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            applyHighlight(to: textView)
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

            // 高亮所有 [xxx] 标签
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