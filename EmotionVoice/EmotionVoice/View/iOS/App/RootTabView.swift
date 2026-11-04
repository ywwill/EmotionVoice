//
//  RootTabView.swift
//  iOSEmora
//
//  根容器：3 个标签 + 各自独立的导航栈 + 全局浮层。
//
//  全局浮层全部挂在这里而不是某个标签内：
//  ① 生成弹窗（关掉后接收仍在后台跑，后台浮条要能从任意标签把它唤回来）
//  ② 后台接收浮条
//  ③ Toast（购买结果）
//  ④ 购买 Sheet（设置页账户卡 / 工作台积分不足两个入口共用）
//
//  ⚠️ `ScreenMetricsReader` 只在最外层用一次 `GeometryReader`，
//  向下注入 `\.screenMetrics`，子视图不再各自测量。
//

import SwiftUI
import UIKit
import Combine

struct RootTabView: View {
    @Environment(\.colorScheme) private var scheme

    @StateObject private var appState = AppState()
    @StateObject private var uiState = IOSUIState.shared
    @StateObject private var router = TabRouter()
    @StateObject private var studioVM = VoiceStudioViewModel.shared
    @StateObject private var nowPlaying = NowPlayingStore.shared
    // ⚠️ 根容器绝不能订阅播放器：progress 10Hz 会让整个 TabView + 3 个 NavigationStack
    //    一起重算。这里只订阅低频播放态（macOS 宿主同款做法）。
    @StateObject private var status = PlaybackStatus.shared

    /// 键盘弹起时底部浮层让位：搜索框聚焦时 mini player / 后台浮条不压到键盘。
    @State private var keyboardVisible = false

    private var palette: AuroraPalette { AuroraPalette(scheme: scheme) }

    var body: some View {
        ScreenMetricsReader { _ in
            ZStack(alignment: .bottom) {
                TabView(selection: $router.selection) {
                    stack(for: .studio) { StudioView() }
                    stack(for: .library) { VoicesLibraryView() }
                    stack(for: .projects) { ProjectsView() }
                }
                .tint(palette.accent)

                // 底部浮层三选一（互斥，不叠放）：撤销 Toast > 后台接收浮条 > mini player
                bottomDock
            }
            .overlay { generationOverlay }
            .overlay(alignment: .top) { toastLayer }
            .sheet(isPresented: $uiState.purchaseSheetPresented) {
                PurchaseSheet()
                    .presentationDetents([.large])
                    .presentationDragIndicator(.visible)
            }
        }
        .environment(\.aurora, palette)
        .environmentObject(appState)
        .environmentObject(uiState)
        .environmentObject(router)
        // 后台接收完成（弹窗可能早已被关掉）→ 把弹窗重新唤起到完成态。
        // ⚠️ 用自增信号而不是 isGenerating：连续两次生成时它能各触发一次，
        // 而 Bool 只在翻转时触发。
        .onChange(of: studioVM.generationCompletedSignal) { _, _ in
            appState.showGenerationModal = true
        }
        // 启动时清一次到期记录（磁盘删除不夹在任何动画事务里）
        .task {
            let expired = AudioFlagStore.shared.purgeExpired()
            for id in expired { ProjectService.shared.deleteAudio(id: id) }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            keyboardVisible = true
        }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillHideNotification)) { _ in
            keyboardVisible = false
        }
    }

    // MARK: - 标签

    @ViewBuilder
    private func stack<Content: View>(for tab: TabRouter.Tab,
                                      @ViewBuilder root: () -> Content) -> some View {
        NavigationStack(path: router.binding(for: tab)) {
            root()
                .navigationDestination(for: Route.self) { route in
                    destination(for: route)
                }
                // 二级界面隐藏底部 3 个 tab；pop 回一级时恢复。
                // ⚠️ 用 `router.isTabBarHidden` 这个 Bool 驱动才有动画 ——
                // 把它写成挂在 destination 上的死植 `.hidden` 会瞬切。
                .toolbar(router.isTabBarHidden ? .hidden : .visible, for: .tabBar)
                .animation(TabRouter.tabBarAnimation, value: router.isTabBarHidden)
        }
        .tabItem {
            Label(tab.title, systemImage: tab.icon)
        }
        .tag(tab)
    }

    @ViewBuilder
    private func destination(for route: Route) -> some View {
        switch route {
        case .settings:
            SettingsView()
        case .creditRecords:
            CreditRecordsView()
        case .player(let item):
            PlayerDetailView(item: item)
        case .recentlyDeleted:
            RecentlyDeletedView()
        }
    }

    // MARK: - 生成弹窗

    @ViewBuilder
    private var generationOverlay: some View {
        if appState.showGenerationModal {
            GenerationDialog(vm: studioVM,
                             stats: studioVM.stats,
                             onDismiss: { appState.showGenerationModal = false },
                             onBackground: { appState.showGenerationModal = false })
                .transition(.opacity)
        }
    }

    // MARK: - 底部浮层（三选一，互斥）

    /// 优先级：撤销 Toast > 后台接收浮条 > mini player。
    /// ⚠️ 三者都占「标签栏之上」同一位置，叠放会互相盖住；多选工具条自己在
    ///    `ProjectsView.safeAreaInset` 里，靠 `uiState.hideMiniPlayer` 让出位置。
    @ViewBuilder
    private var bottomDock: some View {
        if let undo = uiState.undoToast {
            UndoToastView(message: undo) { uiState.consumeUndoToast() }
                .padding(.horizontal, 12)
                .padding(.bottom, router.activePath.isEmpty ? 58 : 18)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(4)
        } else if !keyboardVisible && studioVM.isGenerating && !appState.showGenerationModal {
            // 弹窗关掉但任务还在跑时，从任意标签都能一键回到弹窗
            BackgroundReceiveBar(stats: studioVM.stats) {
                appState.showGenerationModal = true
            }
            .padding(.horizontal, 16)
            // 抬到标签栏之上；二级界面标签栏已隐藏，贴底即可
            .padding(.bottom, router.activePath.isEmpty ? 58 : 18)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .zIndex(2)
        } else if !keyboardVisible && router.activePath.isEmpty && !uiState.hideMiniPlayer,
                  let item = nowPlaying.currentItem, status.playingKey != nil {
            MiniPlayerView(item: item,
                           voiceName: nowPlaying.currentVoiceName,
                           onExpand: {
                               router.selection = .projects
                               router.push(.player(item))
                           },
                           onToggle: { NowPlayingStore.shared.toggle(item) },
                           onClose: { NowPlayingStore.shared.close() })
                .padding(.horizontal, 12)
                .padding(.bottom, 58)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(2)
        }
    }

    // MARK: - Toast

    @ViewBuilder
    private var toastLayer: some View {
        if let toast = uiState.toast {
            ToastHost(message: toast)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(3)
        }
    }
}

// MARK: - 后台接收浮条

private struct BackgroundReceiveBar: View {
    @Environment(\.aurora) private var c
    /// ⚠️ 必须**单独订阅** stats：`GenerationStats` 是独立的 ObservableObject，
    /// 只订阅 vm 的话 vm 不会因为 stats 的 @Published 变化而发 objectWillChange，
    /// 浮条上的字节数就会一直停在弹窗关闭那一刻。
    @ObservedObject var stats: GenerationStats
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 9) {
                PulseDot(color: c.accent)
                Text("已接收: %@".localized(byteText))
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(c.textPrimary)
                Spacer(minLength: 0)
                Text("查看".localized())
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(c.accent)
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(
                Capsule(style: .continuous)
                    .fill(c.surface)
                    .shadow(color: c.shadow, radius: 18, x: 0, y: 8)
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(c.line, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    private var byteText: String {
        let u = autoByteUnit(Double(stats.receivedBytes))
        return "\(u.value) \(u.unit)"
    }
}
