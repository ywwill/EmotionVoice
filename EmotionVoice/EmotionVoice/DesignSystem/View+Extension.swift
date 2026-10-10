//
//  View+Extension.swift
//  EmotionVoice
//
//  Created by young on 2026/8/8.
//

import SwiftUI
import AppKit

extension View {

    /// 应用卡片样式
    func cardStyle(
        background: Color = AppColor.bgSecondary,
        cornerRadius: CGFloat = AppRadius.medium,
        borderColor: Color = AppColor.borderSubtle,
        borderWidth: CGFloat = 1
    ) -> some View {
        self
            .background(background)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: borderWidth)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    /// 玻璃质感背景（标题栏/工具栏）
    func glassBackground(opacity: Double = 0.75) -> some View {
        self.background(
            Color(hex: 0x15171B).opacity(opacity)
                .background(.ultraThinMaterial)
        )
    }

    /// 鼠标悬浮时切换为手型
    ///
    /// 这里刻意用 `set()` 而不是 `push()` / `pop()`：push/pop 要求 enter 与 exit 严格配对，
    /// 一旦在悬浮状态下视图被移除（弹窗关闭、列表刷新、条件分支切换），exit 就不会触发，
    /// 残留的手型会一直压在光标栈上，导致之后整屏都停在手型。`set()` 无需配对，语义直接。
    func pointingHandCursor() -> some View {
        self.onHover { hovering in
            if hovering {
                NSCursor.pointingHand.set()
            } else {
                NSCursor.arrow.set()
            }
        }
    }
}

// MARK: - 光标区域屏蔽

/// 覆盖层（overlay）显示期间，屏蔽下层 AppKit 视图注册的光标区域。
///
/// 成因：工作台里的 `EmotionTokenEditor` 内部是真实的 `NSTextView`，它会向所属窗口注册
/// I-beam 的 cursor rect。而 SwiftUI 自绘的遮罩与卡片并不是 `NSView`，不参与 AppKit 的光标
/// 判定 —— 于是鼠标移到弹窗上时，下层的 I-beam 会"穿透"上来，异常范围正好就是弹窗卡片
/// 盖住的那块区域（这也是为什么异常高度恰好等于 `generatingContent` 的高度）。
///
/// 做法：覆盖层出现时禁用整个窗口的 cursor rects，让 SwiftUI 的 hover 全权决定光标；
/// 覆盖层消失时立刻恢复，工作台里正常的文本光标不受影响。
private struct WindowCursorRectsGuard: NSViewRepresentable {
    let disabled: Bool

    func makeNSView(context: Context) -> NSView {
        let view = GuardView()
        view.disabled = disabled
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? GuardView else { return }
        view.disabled = disabled
    }

    /// 一个 1×1 的透明占位视图，唯一作用是拿到宿主窗口并切换 cursor rects 开关。
    /// 靠 `viewDidMoveToWindow` 拿到 window，比延时猜时机更准。
    private final class GuardView: NSView {
        /// 记录已生效的状态，保证 disable / enable 严格配对，不会被反复叠加
        private var applied: Bool?

        var disabled: Bool = false {
            didSet { apply() }
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            apply()
        }

        private func apply() {
            guard let window = window, applied != disabled else { return }
            applied = disabled
            if disabled {
                window.disableCursorRects()
                NSCursor.arrow.set()
            } else {
                window.enableCursorRects()
                // 重新收集一遍光标区域，让工作台里的文本光标立刻恢复正常
                window.resetCursorRects()
            }
        }
    }
}

extension View {
    /// 覆盖层显示期间禁用窗口的 cursor rects，
    /// 避免下层文本域（`NSTextView`）的 I-beam 穿透到 SwiftUI 自绘的弹窗上。
    func suppressesCursorRects(_ active: Bool) -> some View {
        background {
            WindowCursorRectsGuard(disabled: active)
                .frame(width: 1, height: 1)
                .opacity(0)
                .allowsHitTesting(false)
        }
    }
}
