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

/// 底部「撤销」Toast：5 秒倒计时 + 尾随动作按钮。
/// ⚠️ 与顶部购买结果 Toast 分开两条通道：一个在顶、一个占标签栏之上，
///    撤销条显示时 mini player / 后台浮条让位，不叠放。
struct UndoToastMessage: Identifiable, Equatable {
    let id = UUID()
    let text: String
    let createdAt = Date()
    let duration: TimeInterval = 5
    let onUndo: () -> Void

    static func == (lhs: UndoToastMessage, rhs: UndoToastMessage) -> Bool { lhs.id == rhs.id }
}

@MainActor
final class IOSUIState: ObservableObject {

    static let shared = IOSUIState()

    // MARK: 浮层

    /// 购买积分 Sheet（设置页账户卡 / 工作台积分不足，两个入口共用）
    @Published var purchaseSheetPresented: Bool = false

    /// 顶部 Toast
    @Published var toast: ToastMessage? = nil

    /// 底部撤销 Toast（软删后 5 秒内可恢复）
    @Published var undoToast: UndoToastMessage? = nil

    /// 多选工具条显示时让出 mini player 的位置（避免两层底栏叠放）
    @Published var hideMiniPlayer: Bool = false

    /// 历史列表需要刷新的自增信号。
    /// ⚠️ 播放详情页 / 最近删除页里撤销软删时，列表页早已 onAppear 过，
    ///    光改 AudioFlagStore 不会让它重算；靠这个信号让 ProjectsView 重新 load()。
    @Published var historyReloadSignal: Int = 0

    /// 音色选择 Sheet（工作台「更换音色」）
    @Published var voicePickerPresented: Bool = false

    private var toastTask: Task<Void, Never>?
    private var undoTask: Task<Void, Never>?

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

    // MARK: - 撤销 Toast

    func showUndoToast(text: String, onUndo: @escaping () -> Void) {
        undoTask?.cancel()
        let message = UndoToastMessage(text: text, onUndo: onUndo)
        withAnimation(.easeOut(duration: 0.22)) { undoToast = message }
        undoTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(message.duration * 1_000_000_000))
            if !Task.isCancelled {
                withAnimation(.easeOut(duration: 0.25)) { undoToast = nil }
            }
        }
    }

    func requestHistoryReload() {
        historyReloadSignal += 1
    }

    /// 点「撤销」：先消费掉 Toast，再执行恢复闭包（避免倒计时任务把新 Toast 顶掉）。
    func consumeUndoToast() {
        undoTask?.cancel()
        undoTask = nil
        let action = undoToast?.onUndo
        withAnimation(.easeOut(duration: 0.2)) { undoToast = nil }
        action?()
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
