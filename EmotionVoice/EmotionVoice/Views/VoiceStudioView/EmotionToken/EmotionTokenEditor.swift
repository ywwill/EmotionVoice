//
//  EmotionTokenEditor.swift
//  EmotionVoice
//
//  Created by young on 2026/9/1.
//
//  SwiftUI ↔ NSTextView 桥接层。
//  把 EmotionTokenTextView 包装成 SwiftUI View，并以「结构化 [TTSContentItem]」为外部数据模型。
//
//  用法：
//    @State private var items: [TTSContentItem] = []
//    @State private var insertTrigger: Int = 0
//    @State private var insertLabel: String = ""
//    @State private var insertEmoji: String = ""
//
//    EmotionTokenEditor(
//        items: $items,
//        insertTrigger: insertTrigger,
//        insertLabel: insertLabel,
//        insertEmoji: insertEmoji
//    )
//

import SwiftUI
import AppKit

/// SwiftUI 视图：包装 NSTextView，提供 emotion token 混合编辑能力
struct EmotionTokenEditor: NSViewRepresentable {

    @Binding var items: [TTSContentItem]
    let insertTrigger: Int
    let insertLabel: String
    let insertEmoji: String
    let insertTokenEnglishTag: String
    let clearTrigger: Int

    /// 可选：纯文本 binding，编辑器内容变化时会同步更新。
    /// 用于保持 VoiceStudioViewModel.text 与编辑器内容一致。
    var textBinding: Binding<String>?

    /// 暴露给 SwiftUI 的初始化
    init(items: Binding<[TTSContentItem]>,
         insertTrigger: Int = 0,
         insertLabel: String = "",
         insertEmoji: String = "",
         insertTokenEnglishTag: String = "",
         clearTrigger: Int = 0,
         textBinding: Binding<String>? = nil) {
        self._items = items
        self.insertTrigger = insertTrigger
        self.insertLabel = insertLabel
        self.insertEmoji = insertEmoji
        self.insertTokenEnglishTag = insertTokenEnglishTag
        self.clearTrigger = clearTrigger
        self.textBinding = textBinding
    }

    func makeCoordinator() -> Coordinator {
        // 关键：把当前 VM 的 trigger 初始值传给 Coordinator，
        // 避免页面切换回来时 SwiftUI 重建 Coordinator 后，
        // 因为 lastInsertTrigger = 0 而误触发一次「insertToken」。
        Coordinator(
            items: $items,
            textBinding: textBinding,
            initialInsertTrigger: insertTrigger,
            initialClearTrigger: clearTrigger
        )
    }

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.hasVerticalRuler = false
        scrollView.hasHorizontalRuler = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.backgroundColor = .clear
        scrollView.autohidesScrollers = true

        // 自定义一个 EmotionTokenTextView，配置 size tracking。
        // 注意：NSTextView.scrollableTextView() 已经创建了一个默认的 NSTextView，
        // 但我们需要一个能管理 token 的子类。直接把子类化的 view 设为 documentView，
        // 并把原 NSTextView 的 textContainer 一起接管，避免 width = 0 导致 container 不渲染。
        let originalTextView = scrollView.documentView as? NSTextView
        let textContainer = originalTextView?.textContainer ?? NSTextContainer(size: NSSize(
            width: 0,
            height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true

        // 关键：用 NSScrollView 的 contentSize 给 text view 一个非零初始 frame，
        // 否则 documentView 会被替换为 0×0 的 view，点击区域为空，NSTextView 无法成为 first responder。
        let initialSize = scrollView.contentSize
        let tokenView = EmotionTokenTextView(frame: NSRect(origin: .zero, size: NSSize(
            width: max(initialSize.width, 1),
            height: max(initialSize.height, 1))),
                                             textContainer: textContainer)
        tokenView.minSize = NSSize(width: 0, height: 0)
        tokenView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                   height: CGFloat.greatestFiniteMagnitude)
        tokenView.isVerticallyResizable = true
        tokenView.isHorizontallyResizable = false
        tokenView.autoresizingMask = [.width]

        scrollView.documentView = tokenView

        // 强制 tile 一次，让 documentView 真正占据 scrollview 的可视区
        scrollView.layoutSubtreeIfNeeded()
        if scrollView.contentSize.height > 0 {
            tokenView.frame = NSRect(origin: .zero, size: scrollView.contentSize)
        }

        context.coordinator.bind(to: tokenView)
        context.coordinator.tokenView = tokenView

        // 初始化内容
        tokenView.setContent(items)

        // SwiftUI 嵌入 NSTextView 时默认不会让它自动获得 first responder。
        // 在下一个主循环强制把 NSTextView 设为 first responder，确保用户点击编辑区后立即可输入。
        DispatchQueue.main.async { [weak tokenView] in
            guard let tokenView, let window = tokenView.window else { return }
            if window.firstResponder !== tokenView {
                window.makeFirstResponder(tokenView)
            }
        }

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let tokenView = nsView.documentView as? EmotionTokenTextView else { return }
        let coord = context.coordinator

        // 1. 外部 items 变化 → setContent（仅当内容不一致时）
        if !coord.isUpdatingFromEditor {
            let current = tokenView.exportItems()
            if current != items {
                tokenView.setContent(items)
            }
        }

        // 2. 触发插入
        if insertTrigger > coord.lastInsertTrigger {
            coord.lastInsertTrigger = insertTrigger
            DispatchQueue.main.async { [weak tokenView, weak nsView] in
                guard let tokenView, let nsView else { return }
                nsView.window?.makeFirstResponder(tokenView)
                let token = EmotionToken(label: insertLabel,
                                         emoji: insertEmoji,
                                         englishTag: insertTokenEnglishTag.isEmpty ? insertLabel : insertTokenEnglishTag)
                tokenView.insertToken(token)
            }
        }

        // 3. 触发清空
        if clearTrigger > coord.lastClearTrigger {
            coord.lastClearTrigger = clearTrigger
            tokenView.clearAllTokens()
        }
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator {
        let itemsBinding: Binding<[TTSContentItem]>
        weak var tokenView: EmotionTokenTextView?
        var lastInsertTrigger: Int = 0
        var lastClearTrigger: Int = 0

        /// 当 SwiftUI binding 由内部 NSTextView 触发时为 true；外部 set 才 false。
        var isUpdatingFromEditor: Bool = false

        /// 可选：纯文本 binding，编辑器内容变化时同步更新。
        var textBinding: Binding<String>?

        /// 用 VM 当前 trigger 初始化，避免页面切换回 VoiceStudioView
        /// 时 Coordinator 被重建（lastXxxTrigger=0）误触发一次额外操作。
        init(items: Binding<[TTSContentItem]>,
             textBinding: Binding<String>? = nil,
             initialInsertTrigger: Int = 0,
             initialClearTrigger: Int = 0) {
            self.itemsBinding = items
            self.textBinding = textBinding
            self.lastInsertTrigger = initialInsertTrigger
            self.lastClearTrigger = initialClearTrigger
        }

        func bind(to view: EmotionTokenTextView) {
            self.tokenView = view
            view.onContentChange = { [weak self] in
                Task { @MainActor [weak self] in
                    self?.handleContentChange()
                }
            }
        }

        func handleContentChange() {
            guard let tv = tokenView else { return }
            let exported = tv.exportItems()
            if itemsBinding.wrappedValue != exported {
                isUpdatingFromEditor = true
                itemsBinding.wrappedValue = exported
                // 同步纯文本（用于 API 调用和字数统计）
                if let tb = textBinding {
                    let plain = exported.map { $0.content }.joined()
                    if tb.wrappedValue != plain {
                        tb.wrappedValue = plain
                    }
                }
                // 注意：SwiftUI 在下一个 runloop 同步 binding 后再解除标志位
                DispatchQueue.main.async { [weak self] in
                    self?.isUpdatingFromEditor = false
                }
            }
        }
    }
}
