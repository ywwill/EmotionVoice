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

import SwiftUI
import UIKit

struct TokenTextEditor: UIViewRepresentable {

    /// 文档串（含拟声占位符 U+FFFC）
    @Binding var doc: String
    /// 情感标记
    @Binding var marks: [EmotionMark]

    var palette: AuroraPalette
    var isDark: Bool
    var minHeight: CGFloat = 170
    var isEditable: Bool = true
    /// 键盘 accessory 是否显示
    var showsAccessory: Bool = true

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
        overlay.textView = tv
        overlay.config.badgeBackground = UIColor(palette.surface2)
        overlay.config.primaryText = UIColor(palette.textPrimary)
        overlay.config.editable = isEditable
        overlay.config.isDark = isDark
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

        // 文本由外部改动时才重建 attributedText（用户输入时 textView 已是最新，
        // 重建会把光标顶回开头）
        if uiView.text != doc {
            let selected = uiView.selectedRange
            uiView.attributedText = Self.attributed(doc: doc,
                                                    marks: marks,
                                                    textColor: UIColor(palette.textPrimary))
            let maxLoc = (uiView.text as NSString).length
            uiView.selectedRange = NSRange(location: min(selected.location, maxLoc), length: 0)
        }

        if let overlay = context.coordinator.overlay {
            overlay.config.marks = marks
            overlay.config.editable = isEditable
            overlay.config.isDark = isDark
            overlay.config.badgeBackground = UIColor(palette.surface2)
            overlay.config.primaryText = UIColor(palette.textPrimary)
            overlay.setNeedsDisplay()
        }

        // accessory：更新主题与回调
        let host = context.coordinator.accessory
        host.update(palette: palette,
                    onPick: { [weak coordinator = context.coordinator] item, category in
                        coordinator?.insert(item: item, category: category)
                    },
                    onInterrupt: { [weak coordinator = context.coordinator] in
                        coordinator?.insertInterrupt()
                    },
                    onDone: { [weak coordinator = context.coordinator] in
                        coordinator?.endEditing()
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
                let attachment = SoundPlaceholderAttachment(width: Self.pillWidth(for: token),
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

    static let pillHeight: CGFloat = 19
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

        let accessory = AccessoryHost()
        var accessoryContainer: UIView { accessory.container }

        /// 由 `shouldChangeTextIn` 算好、`textViewDidChange` 时落地的标记
        private var pendingMarks: [EmotionMark]?

        init(_ parent: TokenTextEditor) {
            self.parent = parent
            super.init()
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

            if category == .richLanguage {
                let attachment = SoundPlaceholderAttachment(
                    width: TokenTextEditor.pillWidth(for: token),
                    height: TokenTextEditor.pillHeight,
                    baselineOffset: -3)
                let attr = NSMutableAttributedString(attachment: attachment)
                attr.addAttributes(TokenTextEditor.bodyAttributes(textColor: UIColor(parent.palette.textPrimary)),
                                   range: NSRange(location: 0, length: attr.length))
                tv.textStorage.insert(attr, at: loc)
                tv.selectedRange = NSRange(location: loc + 1, length: 0)
            }

            var next = parent.marks
            next.append(EmotionMark(location: loc, token: token))
            parent.marks = next
            parent.doc = tv.text
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
            var next = parent.marks
            next.append(EmotionMark(location: loc, token: token))
            parent.marks = next
            overlay?.setNeedsDisplay()
        }

        /// 删除一个标记（点 ×）
        func removeMark(id: UUID) {
            guard let tv = textView, let mark = parent.marks.first(where: { $0.id == id }) else { return }
            if mark.token.category == .richLanguage {
                let maxLen = (tv.text as NSString).length
                if mark.location < maxLen {
                    tv.textStorage.deleteCharacters(in: NSRange(location: mark.location, length: 1))
                }
            }
            parent.marks = parent.marks.filter { $0.id != id }
            parent.doc = tv.text
            tvDidChangeContent(tv)
        }

        func endEditing() {
            textView?.resignFirstResponder()
        }

        private func tvDidChangeContent(_ tv: UITextView) {
            overlay?.config.marks = parent.marks
            overlay?.setNeedsDisplay()
            tv.setNeedsLayout()
        }

        // MARK: UITextViewDelegate

        func textView(_ textView: UITextView,
                      shouldChangeTextIn range: NSRange,
                      replacementText text: String) -> Bool {
            pendingMarks = TokenDocument.adjust(marks: parent.marks,
                                                editedRange: range,
                                                replacementLength: (text as NSString).length)
            return true
        }

        func textViewDidChange(_ textView: UITextView) {
            parent.doc = textView.text
            if let pendingMarks {
                parent.marks = pendingMarks
                self.pendingMarks = nil
            }
            tvDidChangeContent(textView)
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            overlay?.setNeedsDisplay()
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            overlay?.setNeedsDisplay()
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

    init() {
        container = AccessoryContainerView(frame: CGRect(x: 0, y: 0, width: 320, height: 116))
        refresh(palette: AuroraPalette(scheme: .light))
        container.embed(hosting.view)
    }

    func update(palette: AuroraPalette,
                onPick: @escaping (EmotionItem, EmotionCategory) -> Void,
                onInterrupt: @escaping () -> Void,
                onDone: @escaping () -> Void) {
        config.onPick = onPick
        config.onInterrupt = onInterrupt
        config.onDone = onDone
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
