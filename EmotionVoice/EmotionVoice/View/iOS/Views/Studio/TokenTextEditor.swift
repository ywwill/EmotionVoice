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
    /// 「键盘 + 本编辑器的 accessory」顶边的屏幕 Y（收起时回调 `nil`）。
    ///
    /// ⚠️ SwiftUI 自带的键盘避让**不一定把 `inputAccessoryView` 那一截算进去** ——
    /// 通知里的键盘框有时是纯键盘、有时才带上 accessory（同一条生命周期里还会变），
    /// 于是底部那条会压进标签条里。这里取「键盘框顶 / accessory 框顶」里更靠上的那个，
    /// 上层拿它跟自己的内容底边比一下，差多少就让开多少（见 `StudioView.keyboardSeam`）。
    var onKeyboardTopChanged: ((CGFloat?) -> Void)? = nil

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
            context.coordinator.accessoryContainer.frame = CGRect(x: 0, y: 0, width: tv.bounds.width, height: AccessoryMetrics.baseHeight)
            tv.inputAccessoryView = context.coordinator.accessoryContainer
            // accessory 高度变了（副行换行 / 动态类型）→ 底部条跟着重新让位
            context.coordinator.accessory.onHeightChanged = { [weak coordinator = context.coordinator] _ in
                coordinator?.remeasureKeyboardTop()
            }
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

    /// 文档串 → 带占位附件的富文本（拟声 = pill 宽，语气 / 中断 = 一段空白宽）
    static func attributed(doc: String, marks: [EmotionMark], textColor: UIColor) -> NSAttributedString {
        let result = NSMutableAttributedString()
        let chars = Array(doc)

        // ⚠️ 每个标记独占一个占位符，严格一一对应；同位置重复只可能出现在
        // 位置还没来得及修正的中间态，后来者优先（它才是最后插进去的那个）。
        var attachAt: [Int: EmotionMark] = [:]
        for mark in marks { attachAt[mark.location] = mark }

        var index = 0
        for ch in chars {
            if String(ch) == TokenDocument.placeholder, let mark = attachAt[index] {
                result.append(NSAttributedString(attachment: Self.placeholder(for: mark.token)))
            } else {
                result.append(NSAttributedString(string: String(ch)))
            }
            index += 1
        }

        let range = NSRange(location: 0, length: result.length)
        result.addAttributes(bodyAttributes(textColor: textColor), range: range)
        return result
    }

    /// 一个标记在文档里占的那个占位附件
    static func placeholder(for token: EmotionToken) -> NSTextAttachment {
        if token.category == .richLanguage {
            // 占位附件比可见的 pill 左右各多留 `pillSpacing`，否则 pill 会贴着相邻文字
            return InlineSpaceAttachment(width: pillWidth(for: token) + pillSpacing * 2,
                                         height: pillHeight,
                                         baselineOffset: -3)
        }
        // 语气 / 中断：只占一段空白宽度 —— 这段物理空隙就是胶囊左右内边距的来源。
        // ⚠️ 高度必须 ≤ 正文字高，否则 TextKit 会为它把整行撑高。
        return InlineSpaceAttachment(width: toneSpacing, height: 12, baselineOffset: -2)
    }

    // MARK: 占位尺寸

    /// 拟声占位附件的高度（与 `TokenCapsuleOverlay.Config.pillHeight` 保持一致）
    static let pillHeight: CGFloat = 20
    /// 拟声 pill 左右各留的间距（与 `TokenCapsuleOverlay.Config.pillSpacing` 保持一致）
    static let pillSpacing: CGFloat = 8
    /// 语气 / 中断标记占的宽度。
    ///
    /// ⚠️ 它同时决定了三件事，改动前先算一遍（`p` = 胶囊 `capsulePadX`）：
    ///  * 文字距离胶囊左右各 `p`；
    ///  * 中断两侧天然的断开量；
    ///  * **相邻两个标签之间只有一份 `toneSpacing` 可花**，却要同时付前一个的右 `p`
    ///    和后一个的左 `p` —— 剩下的自然缝只有 `toneSpacing − 2p`（现在 14 − 12 = 2pt），
    ///    不够看，还得由 `TokenCapsuleOverlay.cutToneSeam` 再让一次到 `capsuleSeamGap = 6`。
    /// 想要更大的左右内边距，得把它和 `capsulePadX` 一起抬，别只动一个。
    static let toneSpacing: CGFloat = 14
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

        /// 键盘通知订阅（量「键盘 + accessory」顶边用）
        private var keyboardTokens: [NSObjectProtocol] = []

        init(_ parent: TokenTextEditor) {
            self.parent = parent
            super.init()
            observeKeyboard()
        }

        deinit {
            let nc = NotificationCenter.default
            keyboardTokens.forEach { nc.removeObserver($0) }
        }

        // MARK: 键盘 / accessory 顶边

        private func observeKeyboard() {
            let nc = NotificationCenter.default
            let onFrame: (Notification) -> Void = { [weak self] note in
                // 通知回调是 @Sendable，过一层主队列再碰 @MainActor 状态（与 notifyEditingChanged 一致）
                DispatchQueue.main.async { self?.measureKeyboardTop(note) }
            }
            [UIResponder.keyboardWillChangeFrameNotification,
             UIResponder.keyboardDidChangeFrameNotification,
             UIResponder.keyboardDidShowNotification].forEach { name in
                keyboardTokens.append(nc.addObserver(forName: name, object: nil,
                                                     queue: .main, using: onFrame))
            }
            keyboardTokens.append(
                nc.addObserver(forName: UIResponder.keyboardWillHideNotification,
                               object: nil, queue: .main) { [weak self] _ in
                    DispatchQueue.main.async {
                        self?.lastKeyboardFrame = nil
                        self?.parent.onKeyboardTopChanged?(nil)
                    }
                })
        }

        /// 量「键盘 + accessory」最靠上的那条边（屏幕坐标 Y）
        private func measureKeyboardTop(_ note: Notification) {
            guard let frame = note.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect else { return }
            lastKeyboardFrame = frame
            applyKeyboardFrame(frame)
        }

        /// accessory 自己变高了也要重算一次（副行换行 / 动态类型），否则底部条还按旧高度让位
        func remeasureKeyboardTop() {
            guard let frame = lastKeyboardFrame else { return }
            DispatchQueue.main.async { [weak self] in self?.applyKeyboardFrame(frame) }
        }

        private func applyKeyboardFrame(_ frame: CGRect) {
            let screenH = UIScreen.main.bounds.height
            // ⚠️ 键盘框不在屏内就直接放弃：收起过程中 accessory 还会短暂挂在键盘窗口里，
            // 只认 accessory 会让它「没键盘也占一截高度」，底部条凭空飘起来。
            guard frame.minY > 0, frame.minY < screenH - 1 else { return }

            var top = frame.minY
            // accessory 自己那一截：它挂在键盘窗口里，转成窗口坐标就是屏幕坐标
            let container = accessoryContainer
            if container.window != nil {
                let rect = container.convert(container.bounds, to: nil)
                if rect.height > 1, rect.minY > 0, rect.minY < screenH - 1 {
                    top = min(top, rect.minY)
                }
            }
            parent.onKeyboardTopChanged?(top)
        }

        /// 最近一次有效的键盘框（accessory 高度变化后要拿它重算一次）
        private var lastKeyboardFrame: CGRect?

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

        /// 在光标处插入一个占位的标记所在的 U+FFFC + 附件，并把光标停到它**之后**。
        ///
        /// ⚠️ 光标必须跳过占位符：标记的作用域从 `loc + 1` 开始，停在占位符之前打字，
        /// 那行字会落在上一段（或者根本不属于这个标签）—— 也就是
        /// 「选完标签一输入，文本没进胶囊」。
        ///
        /// ⚠️ 直接改 `textStorage` 不走 `shouldChangeTextIn`，逗留在它之后的旧标记
        /// 必须手动补一次 +1 平移，否则「再插一个标签，上一个标签位置就偏了」。
        private func insertPlaceholder(token: EmotionToken) {
            guard let tv = textView else { return }
            let loc = tv.selectedRange.location
            guard loc <= (tv.text as NSString).length else { return }

            let attr = NSMutableAttributedString(attachment: TokenTextEditor.placeholder(for: token))
            attr.addAttributes(TokenTextEditor.bodyAttributes(textColor: UIColor(parent.palette.textPrimary)),
                               range: NSRange(location: 0, length: attr.length))
            tv.textStorage.insert(attr, at: loc)
            tv.selectedRange = NSRange(location: loc + 1, length: 0)
            // ⚠️ 光标刚从附件旁边移过来，typingAttributes 可能继承了附件那一格的属性；
            // 不清一次接着打的字会带上奇怪的字号 / 基线下坠。
            tv.typingAttributes = TokenTextEditor.bodyAttributes(textColor: UIColor(parent.palette.textPrimary))

            let shifted = TokenDocument.adjust(marks: store.marks,
                                               editedRange: NSRange(location: loc, length: 0),
                                               replacementLength: 1)
            store.commit(doc: tv.text, marks: shifted + [EmotionMark(location: loc, token: token)])
            tvDidChangeContent(tv)
        }

        /// 在光标处插入一个语气 / 拟声标签
        func insert(item: EmotionItem, category: EmotionCategory) {
            let token = EmotionToken(label: item.label.localized(),
                                     emoji: item.emoji,
                                     englishTag: item.tag,
                                     category: category)
            insertPlaceholder(token: token)
        }

        /// 插入「中断」：作用域边界，一样占一个空白宽度，但不画胶囊（只有灰徽章）
        func insertInterrupt() {
            let token = EmotionToken(label: Constants.interruptItem.label.localized(),
                                     emoji: Constants.interruptItem.emoji,
                                     englishTag: Constants.interruptItem.tag,
                                     category: .interrupt)
            insertPlaceholder(token: token)
        }

        /// 删除一个标记（点 ×）：连它占的那个占位符一起删
        func removeMark(id: UUID) {
            guard let tv = textView, let mark = store.marks.first(where: { $0.id == id }) else { return }
            var others = store.marks.filter { $0.id != id }
            let maxLen = (tv.text as NSString).length
            if mark.location < maxLen {
                tv.textStorage.deleteCharacters(in: NSRange(location: mark.location, length: 1))
                others = TokenDocument.adjust(marks: others,
                                              editedRange: NSRange(location: mark.location, length: 1),
                                              replacementLength: 0)
            }
            store.commit(doc: tv.text, marks: others)
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

    /// accessory 高度变化的回调（副行换行 / 动态类型会让内容变高）
    var onHeightChanged: ((CGFloat) -> Void)?

    private var heightTicket: AnyCancellable?

    /// 上次构建 SwiftUI 树时的深浅色。
    /// ⚠️ `hosting.rootView = ...` 会把整棵 accessory 视图树拆掉重建并重新布局，
    /// 而 accessory 挂在键盘上、处在输入的关键路径里 —— 每个键击来一次就是肉眼可见的卡顿。
    private var lastIsDark: Bool = false

    init() {
        container = AccessoryContainerView(frame: CGRect(x: 0, y: 0, width: 320, height: AccessoryMetrics.baseHeight))
        refresh(palette: AuroraPalette(scheme: .light))
        container.embed(hosting.view)
        // ⚠️ 高度由 SwiftUI 报回来：写死常量会把多出来的那几 pt 裁掉
        heightTicket = config.$contentHeight
            .removeDuplicates()
            .sink { [weak self] height in
                guard let self, height > 1 else { return }
                self.container.contentHeight = height
                self.onHeightChanged?(height)
            }
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

/// 高度由 SwiftUI 报回来的容器：inputAccessoryView 靠它决定高度
final class AccessoryContainerView: UIView {

    /// ⚠️ setter 里必须 invalidate：键盘系统只在 intrinsic 变化时重新给 accessory 排一次高
    ///
    /// ⚠️ 光 invalidate **不够**：容器是手写 frame 建出来的（`translatesAutoresizingMaskIntoConstraints`
    /// 把 frame 翻成了宽 / 高约束），而键盘只在弹出那一刻量一次高度 —— 于是容器会永远停在初始
    /// 高度，多出来的那截就是「标签条下面一条空白、离键盘老远」。必须自己改 frame。
    var contentHeight: CGFloat = AccessoryMetrics.baseHeight {
        didSet {
            guard abs(oldValue - contentHeight) > 0.5 else { return }
            invalidateIntrinsicContentSize()
            var f = frame
            guard abs(f.height - contentHeight) > 0.5 else { return }
            f.size.height = contentHeight
            frame = f
            superview?.setNeedsLayout()
        }
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: contentHeight)
    }

    /// ⚠️ 归零安全区：accessory 挂在键盘窗口里，那边的 bottom inset 会莫名其妙地渗进来，
    /// SwiftUI 侧一尊重安全区，内容就被顶上去、底下一截空白（看着像「没贴住键盘」）。
    override var safeAreaInsets: UIEdgeInsets { .zero }

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
