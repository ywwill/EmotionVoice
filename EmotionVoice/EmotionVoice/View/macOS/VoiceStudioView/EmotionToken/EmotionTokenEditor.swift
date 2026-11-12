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
    let insertTokenCategory: EmotionCategory
    let clearTrigger: Int

    /// 可选：纯文本 binding，编辑器内容变化时会同步更新。
    /// 用于保持 VoiceStudioViewModel.text 与编辑器内容一致。
    var textBinding: Binding<String>?

    /// 是否可交互。
    ///
    /// 传 false 时（例如生成弹窗覆盖在工作台上）文本域会变成不可编辑、不可选中：
    /// 不会被抢走 first responder，也不会注册 I-beam 光标区，
    /// 鼠标在它上方移动时不会把光标改成文本光标。
    var isInteractive: Bool = true

    /// 暴露给 SwiftUI 的初始化
    init(items: Binding<[TTSContentItem]>,
         insertTrigger: Int = 0,
         insertLabel: String = "",
         insertEmoji: String = "",
         insertTokenEnglishTag: String = "",
         insertTokenCategory: EmotionCategory = .emotion,
         clearTrigger: Int = 0,
         textBinding: Binding<String>? = nil,
         isInteractive: Bool = true) {
        self._items = items
        self.insertTrigger = insertTrigger
        self.insertLabel = insertLabel
        self.insertEmoji = insertEmoji
        self.insertTokenEnglishTag = insertTokenEnglishTag
        self.insertTokenCategory = insertTokenCategory
        self.clearTrigger = clearTrigger
        self.textBinding = textBinding
        self.isInteractive = isInteractive
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

        // v13：语气胶囊要画在字形**下面**（先在 draw(_:) 里铺胶囊，再交 super 画文字）。
        // NSTextView 默认 drawsBackground = true，它刷的那层背景会把胶囊整片盖掉，
        // 所以这里必须关掉，让 SwiftUI 卡片自己的背景（AppColor.bgSecondary）透上来。
        // 徽章的底色默认也按这个背景色取值（见 resolvedBadgeBackgroundColor）。
        tokenView.drawsBackground = false
        tokenView.backgroundColor = .clear

        scrollView.documentView = tokenView

        // 强制 tile 一次，让 documentView 真正占据 scrollview 的可视区
        scrollView.layoutSubtreeIfNeeded()
        if scrollView.contentSize.height > 0 {
            tokenView.frame = NSRect(origin: .zero, size: scrollView.contentSize)
        }

        context.coordinator.bind(to: tokenView)
        context.coordinator.tokenView = tokenView

        // 初始化内容
        // ⚠️ 写入失败时不要把缓存记成新内容（否则 `updateNSView` 会认为已同步、永不重试）。
        if tokenView.setContent(items) {
            context.coordinator.lastExportedFromView = items
        }

        // SwiftUI 嵌入 NSTextView 时默认不会让它自动获得 first responder。
        // 在下一个主循环强制把 NSTextView 设为 first responder，确保用户点击编辑区后立即可输入。
        // 被覆盖层挡住时（isInteractive == false）不要抢焦点，否则会把弹窗的键盘操作吃掉。
        guard isInteractive else { return scrollView }
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

        // 0. 先同步可交互状态，再谈内容。
        //    ⚠️ 顺序不能反：草稿恢复是「关弹窗 + 写新正文」同一帧发生的，上一次 update 因为
        //    弹窗把 `isEditable` 设成了 false。若先做下面的 `setContent`，NSTextView 会以
        //    「不可编辑」为由拒绝写入，正文原地不动。先把状态改回 true，写入才成立。
        //
        //    这样它既不会被 makeFirstResponder 抢走焦点，也不会注册 I-beam 的 cursor rect，
        //    鼠标划过上方时不会把光标变成文本光标（SwiftUI 自绘内容不参与 AppKit 的
        //    cursor rect 判定，只靠窗口级 disableCursorRects 有时压不住）。
        if tokenView.isEditable != isInteractive || tokenView.isSelectable != isInteractive {
            tokenView.isEditable = isInteractive
            tokenView.isSelectable = isInteractive
            tokenView.window?.invalidateCursorRects(for: tokenView)

            if isInteractive {
                // 恢复可编辑后把焦点还回编辑区，保持弹窗出现前的输入状态
                DispatchQueue.main.async { [weak tokenView] in
                    guard let tokenView, let window = tokenView.window else { return }
                    if window.firstResponder !== tokenView {
                        window.makeFirstResponder(tokenView)
                    }
                }
            }
        }

        // 不可交互时，如果焦点还留在文本域里就交出去
        if !isInteractive, let window = nsView.window, window.firstResponder === tokenView {
            window.makeFirstResponder(nil)
        }

        // 1. 外部 items 变化 → setContent（仅当内容不一致时）
        //
        //    这里原本每次 SwiftUI 刷新都会先 `exportItems()` 全量扫一遍再比对；
        //    VoiceStudioView 每次按键都会重算 body（VM 是 ObservableObject），
        //    于是「每次按键 = 一次全文档 export」。改为用 Coordinator 缓存的上一次
        //    导出结果先做一次廉价比对，命中就直接跳过。
        if !coord.isUpdatingFromEditor {
            if let cached = coord.lastExportedFromView, cached == items {
                // 视图内容与 binding 已一致，无需导出也无需 setContent
            } else {
                let current = tokenView.exportItems()
                if current != items {
                    // ⚠️ 只有在真的写进去之后才更新缓存。写失败却把缓存记成新内容，
                    //    下一轮就会认定「已经同步」而永不重试 —— 内容会永远停在旧的那份。
                    coord.lastExportedFromView = tokenView.setContent(items) ? items : current
                } else {
                    coord.lastExportedFromView = items
                }
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
                                         englishTag: insertTokenEnglishTag.isEmpty ? insertLabel : insertTokenEnglishTag,
                                         category: insertTokenCategory)
                tokenView.insertToken(token)
            }
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

        /// 最近一次「视图 → 外部」导出的结果缓存。
        /// 有了它，updateNSView 不必每次都调 `exportItems()` 全量扫描。
        var lastExportedFromView: [TTSContentItem]?

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
            EmotionTokenTextView.active = view
            view.onContentChange = { [weak self] in
                Task { @MainActor [weak self] in
                    self?.handleContentChange()
                }
            }
            // 同步通道：保存 / 恢复草稿前，View 会调 `commitPendingChangesNow()`，
            // 走这里当场把编辑器内容写进 binding。不能复用上面的 Task 版本 ——
            // 那条会晚一拍，恢复流程里正好在 `apply` 之后才跑，会把旧内容写回去盖掉新正文。
            view.onCommitRequest = { [weak self] in
                self?.handleContentChange()
            }
            // 注册到 Shared 的结算钩子：⌘S / 文件菜单保存前会调它。
            // 那条路径没有 View 上下文、直接读共享 VM，少了这一步就会存到去抖里的上一版正文。
            PendingEditorCommit.handler = { [weak view] in
                view?.commitPendingChangesNow()
            }
        }

        func handleContentChange() {
            guard let tv = tokenView else { return }
            let exported = tv.exportItems()
            lastExportedFromView = exported
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
