//
//  IOSUIState.swift
//  iOSEmora
//
//  跨标签页的浮层状态：购买 Sheet / Toast / 生成弹窗。
//
//  为什么放在全局而不是某个标签的 @State：
//  1. 后台接收条在三个标签上都可见，点「查看」要能把生成弹窗重新唤起；
//  2. 「积分不足」会从工作台直接唤起购买 Sheet，而购买入口本身在设置页；
//  3. Toast（购买结果）需要盖在标签栏之上。
//

import SwiftUI
import Combine   // @Published / ObservableObject 在 Combine，SwiftUI 不再隐式导出

/// Toast 提示
struct ToastMessage: Identifiable, Equatable {
    enum Style {
        case success
        case failure
        case info
    }

    let id = UUID()
    let text: String
    let style: Style
    /// 自动消失时长（成功 4s / 失败 8s）
    let duration: TimeInterval

    static func success(_ text: String) -> ToastMessage { .init(text: text, style: .success, duration: 4) }
    static func failure(_ text: String) -> ToastMessage { .init(text: text, style: .failure, duration: 8) }
    static func info(_ text: String) -> ToastMessage { .init(text: text, style: .info, duration: 3) }
}

@MainActor
final class IOSUIState: ObservableObject {

    static let shared = IOSUIState()

    // MARK: 浮层

    /// 购买积分 Sheet（设置页账户卡 / 工作台积分不足，两个入口共用）
    @Published var purchaseSheetPresented: Bool = false

    /// 顶部 Toast
    @Published var toast: ToastMessage? = nil

    /// 音色选择 Sheet（工作台「更换音色」）
    @Published var voicePickerPresented: Bool = false

    private var toastTask: Task<Void, Never>?

    private init() {}

    // MARK: - Toast

    func showToast(_ message: ToastMessage) {
        toastTask?.cancel()
        toast = message
        let d = message.duration
        toastTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(d * 1_000_000_000))
            if !Task.isCancelled {
                withAnimation(.easeOut(duration: 0.25)) { self.toast = nil }
            }
        }
    }

    func hideToast() {
        toastTask?.cancel()
        toastTask = nil
        toast = nil
    }
}

// MARK: - Toast 视图

/// 顶部落下的 Toast（购买结果）
struct ToastHost: View {
    @Environment(\.aurora) private var c
    let message: ToastMessage

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: iconName)
                .font(.system(size: 14, weight: .semibold))
            Text(message.text)
                .font(.system(size: 14, weight: .medium))
                .lineLimit(2)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(
            Capsule(style: .continuous)
                .fill(fillColor)
                .shadow(color: fillColor.opacity(0.35), radius: 14, x: 0, y: 8)
        )
        .padding(.horizontal, 24)
    }

    private var iconName: String {
        switch message.style {
        case .success: return "checkmark.circle.fill"
        case .failure: return "xmark.circle.fill"
        case .info: return "info.circle.fill"
        }
    }

    private var fillColor: Color {
        switch message.style {
        case .success: return c.success
        case .failure: return c.danger
        case .info: return c.info
        }
    }
}
