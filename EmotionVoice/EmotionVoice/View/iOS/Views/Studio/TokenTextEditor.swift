//
//  TokenTextEditor.swift
//  iOSEmora
//
//  iOS 的 TTS 文本编辑器：`UITextView` + 自绘胶囊层 + 键盘 accessory。
//
//  三条关键约束（都是 iOS 与 macOS 的差异点）：
//  1. `NSTextAttachmentCell` 是 AppKit 专属 → 胶囊改由 `TokenCapsuleOverlay` 自绘；
//  2. 键盘会遮住输入区 → 标签条挂 `inputAccessoryView`，随键盘一起升降；
//  3. 没有 hover → 标签的 × 改为常显，靠 `hitTest` 只吞 × 那一小块热区。
//
//  ⚠️ 性能铁律：**打字不经过 SwiftUI**。
//  早期版本每敲一个字就往两个 `@Binding` 里写，于是「一个字 → 整个 StudioView body 重算
//  → `updateUIView` → 键盘 accessory 的 SwiftUI 树整棵重建 + 胶囊层全量重绘」。
//  现在内容放在 `TokenEditorStore` 里（非 @Published），打字只在 UIKit 内部闭环，
//  只有「字数」这种低频派生值以 0.25s 合并的方式回推给 SwiftUI。
//

import SwiftUI
import UIKit
import Combine   // @Published / ObservableObject 在 Combine，SwiftUI 不再隐式导出

// MARK: - 内容仓库

/// 编辑器内容的权威存储。
///
/// ⚠️ `doc` / `marks` **故意不做 @Published**：它们是每个键击都会变的高频值，
/// 一旦发布，持有本对象的页面（连带 `UIViewRepresentable` 的 `updateUIView`、
/// 键盘 accessory 的 UIHostingController）就会被整体重算一次 —— 这就是「输入卡顿」的根因。
///
/// SwiftUI 侧只需要两样低频东西：
///  * `charCount` —— 字数角标 / 积分预估，合并到 0.25s 一次；
///  * `contentRevision` —— 外部整体改写内容（恢复草稿 / 清空）时自增，
///    让 `updateUIView` 知道该重建 `attributedText` 了。
@MainActor
final class TokenEditorStore: ObservableObject {

    private(set) var doc: String = ""
    private(set) var marks: [EmotionMark] = []

    /// 去掉拟声占位符后的字数（UI 显示用），合并刷新
    @Published private(set) var charCount: Int = 0
    /// 编辑器里是否还有东西（正文 **或** 标记）。「清空」按钮的可用态靠它 ——
    /// 只看字数是判不出来的：只插了一个语气标签、还没打字时 `charCount` 是 0。
    @Published private(set) var hasContent: Bool = false
    /// 外部整体改写内容的版本号
    @Published private(set) var contentRevision: Int = 0

    private var flushWork: DispatchWorkItem?

    /// 打字 / 插入 / 删除标记：只更新内容，延迟 0.25s 再回推字数
    func commit(doc: String, marks: [EmotionMark]) {
        self.doc = doc
        self.marks = marks
        scheduleFlush()
    }

    /// 外部整体改写内容（恢复草稿、清空）：立即回推并 bump 版本号
    func replace(doc: String, marks: [EmotionMark]) {
        self.doc = doc
        self.marks = marks
        flush()
        contentRevision += 1
    }

    /// 清空编辑器（「清空」按钮）
    func clear() {
        replace(doc: "", marks: [])
    }

    /// 立刻把字数推给 UI（结束编辑 / 生成前调用，避免读到 0.25s 前的旧值）
    func flush() {
        flushWork?.cancel()
        flushWork = nil
        let n = TokenDocument.plainText(doc: doc).count
        if charCount != n { charCount = n }
        let has = !doc.isEmpty || !marks.isEmpty
        if hasContent != has { hasContent = has }
    }

    private func scheduleFlush() {
        flushWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.flush() }
        flushWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
    }
}

// MARK: - 编辑器

struct TokenTextEditor: UIViewRepresentable {

    /// 内容仓库（引用类型，不参与 diff —— 打字不触发 SwiftUI 更新）
    let store: TokenEditorStore

    var palette: AuroraPalette
    var isDark: Bool
    var isEditable: Bool = true
    /// 键盘 accessory 是否显示
    var showsAccessory: Bool = true
    /// 开始 / 结束编辑的回调。
    ///
    /// UIKit 侧的通知需要回推给 SwiftUI 是为了「键盘弹出时收起顶部横条」（见 `StudioView`），
    /// ⚠️ 但它是**一次 = 一回、不是每键击一次**的低频事件，上层可以直接收。
    /// 回调走 `DispatchQueue.main.async`：`textViewDidBegin/EndEditing` 可能发生在
    /// 别的控件的事件处理过程中，同步写 @State 有「渲染过程中改状态」的风险。
    var onEditingChanged: ((Bool) -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UITextView {
        let tv = UITextView(usingTextLayoutManager: false)
        tv.backgroundColor = .clear
        tv.isEditable = isEditable
        tv.isSelectable = true
        tv.isScrollEnabled = true
        tv.alwaysBounceVertical = false
        tv.textContainerInset = UIEdgeInsets(top: 22, left: 14, bottom: 14, right: 14)
        tv.textContainer.lineFragmentPadding = 0
        tv.typingAttributes = Self.bodyAttributes(textColor: UIColor(palette.textPrimary))
        tv.font = Self.bodyFont
        tv.autocorrectionType = .no
        tv.smartQuotesType = .no
        tv.delegate = context.coordinator

        let overlay = TokenCapsuleOverlay(frame: tv.bounds)
        // ⚠️ 没有这行，overlay 会永远停在 makeUIView 时的 `.zero`：
        // 它是 UIScrollView 的子视图，自身 bounds 不变 → `layoutSubviews` 不会被调用 →
        // 自己给自己算 frame 的那段逻辑永远不被触发。交给 autoresizing 先撑到 bounds 大小，
        // 再由 `layoutSubviews` 把高度扩到 contentSize。
        overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        overlay.textView = tv
        overlay.config.badgeBackground = UIColor(palette.surface2)
        overlay.config.primaryText = UIColor(palette.textPrimary)
        // 中断徽章走中性灰，与「语气徽章 = 情感色」区分开
        overlay.config.interruptColor = UIColor(palette.textSecondary)
        overlay.config.editable = isEditable
        overlay.config.isDark = isDark
        // 行距必须同步给绘制层：TextKit 把它算进了行片段矩形，绘制前要减掉还原成字高
        overlay.config.lineSpacing = Self.lineSpacing
        overlay.config.pillSpacing = Self.pillSpacing
        overlay.config.onRemove = { [weak coordinator = context.coordinator] id in
            coordinator?.removeMark(id: id)
        }
        tv.addSubview(overlay)
        context.coordinator.overlay = overlay
        context.coordinator.textView = tv

        if showsAccessory {
            context.coordinator.accessoryContainer.frame = CGRect(x: 0, y: 0, width: tv.bounds.width, height: 116)
            tv.inputAccessoryView = context.coordinator.accessoryContainer
        }
        return tv
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.textView = uiView

        uiView.isEditable = isEditable
        uiView.tintColor = UIColor(palette.accent)

        // 只有外部改写了文档（恢复草稿 / 清空 / 版本号变化）才重建 attributedText。
        // 打字时 textView 本身就是最新值，重建会把光标顶回开头。
        let revisionChanged = context.coordinator.lastRevision != store.contentRevision
        if revisionChanged || uiView.text != store.doc {
            context.coordinator.lastRevision = store.contentRevision
            let selected = uiView.selectedRange
            uiView.attributedText = Self.attributed(doc: store.doc,
                                                    marks: store.marks,
                                                    textColor: UIColor(palette.textPrimary))
            let maxLoc = (uiView.text as NSString).length
            uiView.selectedRange = NSRange(location: min(selected.location, maxLoc), length: 0)
            context.coordinator.syncOverlayFrame(forceLayout: true)
        } else {
            context.coordinator.syncOverlayFrame()
        }

        if let overlay = context.coordinator.overlay {
            // ⚠️ 逐帧无脑 setNeedsDisplay 会让打字时每帧都全量重绘整个内容区。
            // 打字导致的重排由 Coordinator 在 `textViewDidChange` 里单独触发，
            // 这里只处理「SwiftUI 侧真的有东西变了」的情况。
            var dirty = false
            if overlay.config.marks != store.marks {
                overlay.config.marks = store.marks
                dirty = true
            }
            if overlay.config.editable != isEditable {
                overlay.config.editable = isEditable
                dirty = true
            }
            if overlay.config.isDark != isDark {
                overlay.config.isDark = isDark
                dirty = true
            }
            let badge = UIColor(palette.surface2)
            if overlay.config.badgeBackground != badge {
                overlay.config.badgeBackground = badge
                dirty = true
            }
            let primary = UIColor(palette.textPrimary)
            if overlay.config.primaryText != primary {
                overlay.config.primaryText = primary
                dirty = true
            }
            if dirty { overlay.setNeedsDisplay() }
        }

        // accessory：只有深浅色真的翻转时才重建 SwiftUI 树。
        // 早期版本每次 updateUIView 都 `hosting.rootView = AnyView(bar)`，
        // 等于每敲一个字就把键盘上方那 23+7 个胶囊按钮整棵重建并重新布局一遍。
        context.coordinator.accessory.update(palette: palette,
                                             isDark: isDark,
                                             onPick: { [weak coordinator = context.coordinator] item, category in
                                                 coordinator?.insert(item: item, category: category)
                                             },
                                             onInterrupt: { [weak coordinator = context.coordinator] in
                                                 coordinator?.insertInterrupt()
                                             },
                                             onClear: { [weak coordinator = context.coordinator] in
                                                 coordinator?.clearAll()
                                             })
    }

    static func dismantleUIView(_ uiView: UITextView, coordinator: Coordinator) {
        uiView.inputAccessoryView = nil
        uiView.delegate = nil
    }

    // MARK: - 文本样式

    static let bodyFont = UIFont.systemFont(ofSize: 16, weight: .regular)
    /// 行距 26：给语气徽章留出「压在胶囊左上角」的空间
    static let lineSpacing: CGFloat = 26

    static func bodyAttributes(textColor: UIColor) -> [NSAttributedString.Key: Any] {
        let style = NSMutableParagraphStyle()
        style.lineSpacing = lineSpacing
        style.paragraphSpacing = 2
        return [
            .font: bodyFont,
            .foregroundColor: textColor,
            .paragraphStyle: style
        ]
    }

    /// 文档串 → 带拟声附件的富文本
    static func attributed(doc: String, marks: [EmotionMark], textColor: UIColor) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let chars = Array(doc)
        let soundAt = Dictionary(uniqueKeysWithValues: marks
            .filter { $0.token.category == .richLanguage }
            .map { ($0.location, $0.token) })

        var index = 0
        for ch in chars {
            if String(ch) == TokenDocument.placeholder, let token = soundAt[index] {
                // 占位附件比可见的 pill 左右各多留 `pillSpacing`，否则 pill 会贴着相邻文字
                let attachment = SoundPlaceholderAttachment(width: Self.pillWidth(for: token) + pillSpacing * 2,
                                                            height: pillHeight,
                                                            baselineOffset: -3)
                result.append(NSAttributedString(attachment: attachment))
            } else {
                result.append(NSAttributedString(string: String(ch)))
            }
            index += 1
        }

        let range = NSRange(location: 0, length: result.length)
        result.addAttributes(bodyAttributes(textColor: textColor), range: range)
        return result
    }

    // MARK: 拟声 pill 尺寸

    /// 拟声占位附件的高度（与 `TokenCapsuleOverlay.Config.pillHeight` 保持一致）
    static let pillHeight: CGFloat = 20
    /// 拟声 pill 左右各留的间距（与 `TokenCapsuleOverlay.Config.pillSpacing` 保持一致）
    static let pillSpacing: CGFloat = 8
    private static let pillFont = UIFont.systemFont(ofSize: 12, weight: .medium)

    static func pillWidth(for token: EmotionToken) -> CGFloat {
        let w = (token.label as NSString).size(withAttributes: [.font: pillFont]).width
        // 左内边距 7 + 文字 + 间隙 3 + × 14 + 右内边距 6
        return ceil(w) + 7 + 3 + 14 + 6
    }

    // MARK: - Coordinator

    @MainActor
    final class Coordinator: NSObject, UITextViewDelegate {

        var parent: TokenTextEditor
        weak var textView: UITextView?
        var overlay: TokenCapsuleOverlay?

        /// 上次渲染时的内容版本号（-1 = 还没渲染过，首次 updateUIView 必须建一次）
        var lastRevision: Int = -1

        let accessory = AccessoryHost()
        var accessoryContainer: UIView { accessory.container }

        /// 由 `shouldChangeTextIn` 算好、`textViewDidChange` 时落地的标记
        private var pendingMarks: [EmotionMark]?

        /// 每个边界标记「最近一次结算时，它的作用域里有没有文本」。
        ///
        /// ⚠️ **自动回收的唯一判据是「非空 → 空」这一次翻转**。三种候选判据里只有它站得住：
        ///  * 「当前作用域为空就回收」→ 刚插入的标签作用域天然为空，等于标签一插就没；
        ///  * 「这次编辑删过字就回收」→ ① 第二个标签还没输入内容时，回头去删第一个标签里的
        ///    一个错字，第二个标签被连带回收；② 中文改候选词是「先删上屏的字、再插新候选」
        ///    两步，中间那一帧同样会误伤 —— 这正是
        ///    **「插第二个语气标签 → 打字 → 标签没了、文本并进第一个标签」**；
        ///  * `true → false` → 一个**从未有过内容**的标签永远不会被自动回收（上面两种场景
        ///    都不会触发），而「把标签里的字删光」必然翻转一次，
        ///    所以「删完了标签还赖着不走」也不会再现。
        private var scopeHadText: [UUID: Bool] = [:]
        /// 已经翻转过、等着结算的标记（输入停下来之后统一回收）
        private var pendingRemoval: Set<UUID> = []

        private var pruneTask: Task<Void, Never>? = nil

        /// 停手多久之后结算（这段时间足够「删一句话 → 又打回来」跑完）
        private static let pruneDelayNs: UInt64 = 350_000_000

        private var store: TokenEditorStore { parent.store }

        init(_ parent: TokenTextEditor) {
            self.parent = parent
            super.init()
        }

        /// 把胶囊层撑到整个可滚动内容区。
        ///
        /// overlay 自己算了同一件事，但它的 `layoutSubviews` 依赖自身 bounds 变化才触发；
        /// 文本变长时 tv 的 bounds 不变（高度是外部给的），overlay 就会停在旧高度里，
        /// 超出部分的胶囊被自己的画布裁掉 —— 所以每次内容变化都要显式同步一次。
        func syncOverlayFrame(forceLayout: Bool = false) {
            guard let tv = textView, let overlay else { return }
            if forceLayout {
                tv.setNeedsLayout()
                tv.layoutIfNeeded()   // 让 contentSize 立刻反映新文本
            }
            let target = CGRect(x: 0, y: 0,
                                width: tv.bounds.width,
                                height: max(tv.contentSize.height, tv.bounds.height))
            if overlay.frame != target {
                overlay.frame = target
                overlay.setNeedsDisplay()
            }
        }

        // MARK: 标记增删

        /// 在光标处插入一个语气 / 拟声标签
        func insert(item: EmotionItem, category: EmotionCategory) {
            guard let tv = textView else { return }
            let loc = tv.selectedRange.location
            let token = EmotionToken(label: item.label.localized(),
                                     emoji: item.emoji,
                                     englishTag: item.tag,
                                     category: category)

            var next = store.marks

            if category == .richLanguage {
                let attachment = SoundPlaceholderAttachment(
                    width: TokenTextEditor.pillWidth(for: token) + TokenTextEditor.pillSpacing * 2,
                    height: TokenTextEditor.pillHeight,
                    baselineOffset: -3)
                let attr = NSMutableAttributedString(attachment: attachment)
                attr.addAttributes(TokenTextEditor.bodyAttributes(textColor: UIColor(parent.palette.textPrimary)),
                                   range: NSRange(location: 0, length: attr.length))
                tv.textStorage.insert(attr, at: loc)
                tv.selectedRange = NSRange(location: loc + 1, length: 0)
                // ⚠️ 占位符占 1 个字符，光标之后的标记要整体 +1。
                // 直接改 textStorage 不会走 `shouldChangeTextIn`，必须手动补这一步，
                // 否则前一个标签会往左偏一格 —— 表现就是「再点一个标签，上一个标签位置就错了」。
                next = TokenDocument.adjust(marks: next,
                                            editedRange: NSRange(location: loc, length: 0),
                                            replacementLength: 1)
            }

            next.append(EmotionMark(location: loc, token: token))
            store.commit(doc: tv.text, marks: next)
            tvDidChangeContent(tv)
        }

        /// 插入「中断」：作用域边界，不占字符，也不画胶囊
        func insertInterrupt() {
            guard let tv = textView else { return }
            let loc = tv.selectedRange.location
            let token = EmotionToken(label: Constants.interruptItem.label.localized(),
                                     emoji: Constants.interruptItem.emoji,
                                     englishTag: Constants.interruptItem.tag,
                                     category: .interrupt)
            var next = store.marks
            next.append(EmotionMark(location: loc, token: token))
            store.commit(doc: tv.text, marks: next)
            tvDidChangeContent(tv)
        }

        /// 删除一个标记（点 ×）
        func removeMark(id: UUID) {
            guard let tv = textView, let mark = store.marks.first(where: { $0.id == id }) else { return }
            var next = store.marks
            if mark.token.category == .richLanguage {
                let maxLen = (tv.text as NSString).length
                if mark.location < maxLen {
                    tv.textStorage.deleteCharacters(in: NSRange(location: mark.location, length: 1))
                    // 同上：删掉占位符后，后面的标记要整体 −1
                    next = TokenDocument.adjust(marks: next,
                                                editedRange: NSRange(location: mark.location, length: 1),
                                                replacementLength: 0)
                }
            }
            next = next.filter { $0.id != id }
            store.commit(doc: tv.text, marks: next)
            tvDidChangeContent(tv)
        }

        /// 清空全部内容（正文 + 标记）
        func clearAll() {
            guard let tv = textView else { return }
            // 标记都要丢弃了，待结算的空作用域一起作废
            pruneTask?.cancel()
            pruneTask = nil
            pendingRemoval = []
            scopeHadText = [:]
            // 走 textStorage 直接替换：`tv.text = ""` 不会触发 `shouldChangeTextIn`，
            // 而这里标记本来就要全部丢弃，不需要走 adjust
            tv.textStorage.replaceCharacters(in: NSRange(location: 0, length: (tv.text as NSString).length),
                                             with: "")
            tv.selectedRange = NSRange(location: 0, length: 0)
            // replace() 会 bump contentRevision → updateUIView 重建 attributedText 并重绘胶囊层
            store.clear()
            tvDidChangeContent(tv)
        }

        /// 把开始 / 结束编辑回推给 SwiftUI（异步：这两个回调可能发生在别的控件的事件处理中）
        private func notifyEditingChanged(_ editing: Bool) {
            guard let cb = parent.onEditingChanged else { return }
            DispatchQueue.main.async { cb(editing) }
        }

        private func tvDidChangeContent(_ tv: UITextView) {
            // ⚠️ 作用域状态先结算：`store` 是唯一权威，标记留不留与绘制层无关。
            // 放在最前面，保证任何一条改内容的路径（打字 / 插标签 / 删标签 / 结算兜底）
            // 都会走同一遍判定 —— 早年只挂在 `textViewDidChange` 上，于是「插完标签
            // 立刻结算」这类时序错位会让同一段操作跑出两种结果。
            refreshScopeStates()
            guard let overlay else { return }
            let previous = overlay.config.marks
            overlay.config.marks = store.marks
            // ⚠️ 没有标记时胶囊层本来就是空的，别再为它跑一次全量 layout + 重绘。
            // 纯打字（绝大多数场景）因此完全不碰绘制层；
            // 但「从有标记变成没标记」必须重绘一次，否则旧胶囊会留在屏幕上。
            guard !store.marks.isEmpty || !previous.isEmpty else { return }
            syncOverlayFrame(forceLayout: true)
            overlay.setNeedsDisplay()
        }

        // MARK: UITextViewDelegate

        func textView(_ textView: UITextView,
                      shouldChangeTextIn range: NSRange,
                      replacementText text: String) -> Bool {
            guard !store.marks.isEmpty else { return true }
            pendingMarks = TokenDocument.adjust(marks: store.marks,
                                                editedRange: range,
                                                replacementLength: (text as NSString).length)
            return true
        }

        func textViewDidChange(_ textView: UITextView) {
            let marks = pendingMarks ?? store.marks
            pendingMarks = nil
            // ⚠️ 这里刻意不碰 SwiftUI：内容只进 store，字数等 0.25s 后再回推
            store.commit(doc: textView.text, marks: marks)
            tvDidChangeContent(textView)
        }

        // MARK: 空作用域结算

        /// 重算每个边界标记作用域里的文本，并处理「非空 → 空」的翻转。
        ///
        /// ⚠️ **每次内容变化都要跑一遍**（打字 / 插标签 / 删标签 / 清空），
        /// 且只比对「上一次结算的状态」与「现在的状态」—— 既不带「这次删没删东西」的时序信息，
        /// 也不需要延后采快照。掺进来的那些时序条件会让同一段操作在不同节奏下
        /// 得到不同结果（打得快就没事、慢一点标签就被吃掉）。
        private func refreshScopeStates() {
            let marks = store.marks
            guard !marks.isEmpty else {
                scopeHadText = [:]
                pendingRemoval = []
                pruneTask?.cancel()
                pruneTask = nil
                return
            }
            let nonEmpty = TokenDocument.boundaryEmptiness(marks: marks, doc: store.doc).nonEmpty

            var next: [UUID: Bool] = [:]
            next.reserveCapacity(marks.count)
            var flipped: Set<UUID> = []
            for mark in marks where TokenDocument.isBoundary(mark) {
                let hasText = nonEmpty.contains(mark.id)
                next[mark.id] = hasText
                if hasText {
                    // 又有内容了（改候选词重新上屏 / 删完又重打）→ 撤销待回收
                    pendingRemoval.remove(mark.id)
                } else if scopeHadText[mark.id] == true {
                    // 有 → 无：这次真的被删空了
                    flipped.insert(mark.id)
                }
            }
            scopeHadText = next
            guard !flipped.isEmpty else {
                if !pendingRemoval.isEmpty { schedulePrune() }
                return
            }
            pendingRemoval.formUnion(flipped)
            schedulePrune()
        }

        /// 排一次结算。每次新的编辑都会把它顶掉，所以实际只在**输入停下来**之后跑一次。
        ///
        /// ⚠️ 用 `Task` 而不是 `DispatchWorkItem`：GCD 的逃逸闭包是 `@Sendable`，
        /// Swift 6 下没法在里面直接调 `@MainActor` 方法（工程里已有若干同类报错）。
        /// `Task` 会继承调用点的 actor 隔离，这里正好是主线程。
        private func schedulePrune() {
            pruneTask?.cancel()
            pruneTask = Task { @MainActor [weak self] in
                try? await Task.sleep(nanoseconds: Self.pruneDelayNs)
                guard !Task.isCancelled else { return }
                self?.settlePrune()
            }
        }

        private func settlePrune() {
            pruneTask = nil
            guard let tv = textView, !pendingRemoval.isEmpty else { return }
            // 拼音候选还在选：此刻的文本不是最终形态，等 composition 落地后再判
            if tv.markedTextRange != nil {
                schedulePrune()
                return
            }
            let current = store.marks
            guard !current.isEmpty else { pendingRemoval = []; return }
            let stillEmpty = TokenDocument.boundaryEmptiness(marks: current, doc: tv.text).empty
            let doomed = pendingRemoval.intersection(stillEmpty)
            pendingRemoval = []
            guard !doomed.isEmpty else { return }
            for id in doomed { scopeHadText.removeValue(forKey: id) }
            store.commit(doc: tv.text, marks: current.filter { !doomed.contains($0.id) })
            tvDidChangeContent(tv)
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            syncOverlayFrame()
            overlay?.setNeedsDisplay()
            notifyEditingChanged(true)
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            store.flush()
            overlay?.setNeedsDisplay()
            notifyEditingChanged(false)
        }
    }
}

// MARK: - Accessory 宿主

/// 把 SwiftUI 的标签条包成 `inputAccessoryView`
@MainActor
final class AccessoryHost {

    let config = EditorAccessoryConfig()
    private(set) var hosting: UIHostingController<AnyView>!
    let container: AccessoryContainerView

    /// 上次构建 SwiftUI 树时的深浅色。
    /// ⚠️ `hosting.rootView = ...` 会把整棵 accessory 视图树拆掉重建并重新布局，
    /// 而 accessory 挂在键盘上、处在输入的关键路径里 —— 每个键击来一次就是肉眼可见的卡顿。
    private var lastIsDark: Bool = false

    init() {
        container = AccessoryContainerView(frame: CGRect(x: 0, y: 0, width: 320, height: 116))
        refresh(palette: AuroraPalette(scheme: .light))
        container.embed(hosting.view)
    }

    func update(palette: AuroraPalette,
                isDark: Bool,
                onPick: @escaping (EmotionItem, EmotionCategory) -> Void,
                onInterrupt: @escaping () -> Void,
                onClear: @escaping () -> Void) {
        config.onPick = onPick
        config.onInterrupt = onInterrupt
        config.onClear = onClear
        guard isDark != lastIsDark else { return }
        lastIsDark = isDark
        refresh(palette: palette)
    }

    private func refresh(palette: AuroraPalette) {
        let bar = EmotionAccessoryBar(config: config)
            .environment(\.aurora, palette)
        if hosting == nil {
            hosting = UIHostingController(rootView: AnyView(bar))
            hosting.view.backgroundColor = .clear
        } else {
            hosting.rootView = AnyView(bar)
        }
    }
}

/// 固定 intrinsicContentSize 的容器：inputAccessoryView 靠它决定高度
final class AccessoryContainerView: UIView {

    private var contentHeight: CGFloat = 116

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: contentHeight)
    }

    func embed(_ view: UIView) {
        view.translatesAutoresizingMaskIntoConstraints = false
        addSubview(view)
        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: leadingAnchor),
            view.trailingAnchor.constraint(equalTo: trailingAnchor),
            view.topAnchor.constraint(equalTo: topAnchor),
            view.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        view.backgroundColor = .clear
    }
}
