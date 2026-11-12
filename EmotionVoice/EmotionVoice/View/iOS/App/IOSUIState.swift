//
//  IOSUIState.swift
//  iOSEmora
//

import Foundation
import SwiftUI
import Combine

struct ToastMessage: Identifiable, Equatable {
    enum Style {
        case success
        case failure
        case info
    }

    let id = UUID()
    let text: String
    let style: Style
    let duration: TimeInterval

    static func success(_ text: String, duration: TimeInterval = 1) -> ToastMessage {
        .init(text: text, style: .success, duration: duration)
    }
    static func failure(_ text: String) -> ToastMessage { .init(text: text, style: .failure, duration: 1) }
    static func info(_ text: String) -> ToastMessage { .init(text: text, style: .info, duration: 1) }
}

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

    /// 购买积分 Sheet（设置页账户卡 / 工作台积分不足，两个入口共用）
    @Published var purchaseSheetPresented: Bool = false

    /// 顶部 Toast
    @Published var toast: ToastMessage? = nil

    /// 底部撤销 Toast（软删后 5 秒内可恢复）
    @Published var undoToast: UndoToastMessage? = nil

    /// 多选工具条显示时让出 mini player 的位置（避免两层底栏叠放）
    @Published var hideMiniPlayer: Bool = false

    @Published var historyReloadSignal: Int = 0

    /// 音色选择 Sheet（工作台「更换音色」）
    @Published var voicePickerPresented: Bool = false

    private var toastTask: Task<Void, Never>?
    private var undoTask: Task<Void, Never>?

    private init() {}

    // MARK: - Toast
    func showToast(_ message: ToastMessage) {
        toastTask?.cancel()
        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) { toast = message }
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
        withAnimation(.easeOut(duration: 0.25)) { toast = nil }
    }

    // MARK: - 撤销
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

    func consumeUndoToast() {
        undoTask?.cancel()
        undoTask = nil
        let action = undoToast?.onUndo
        withAnimation(.easeOut(duration: 0.2)) { undoToast = nil }
        action?()
    }
}

// MARK: - 音色库筛选状态
@MainActor
final class VoiceLibraryFilterStore {

    static let shared = VoiceLibraryFilterStore()
    var selectedCategory: VoiceCategory?
    var searchText: String = ""
    var showFavoritesOnly: Bool = false

    private init() {
        let ud = UserDefaults.standard
        for key in ["voiceLibrarySelectedCategory",
                    "voiceLibrarySearchText",
                    "voiceLibraryShowFavoritesOnly",
                    "voiceLibraryCurrentPage"] {
            ud.removeObject(forKey: key)
        }
    }

    func update(selectedCategory: VoiceCategory?, searchText: String, showFavoritesOnly: Bool) {
        self.selectedCategory = selectedCategory
        self.searchText = searchText
        self.showFavoritesOnly = showFavoritesOnly
    }
}

// MARK: - Toast
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
