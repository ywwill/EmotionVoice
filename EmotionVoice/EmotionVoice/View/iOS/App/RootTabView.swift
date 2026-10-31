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

struct RootTabView: View {
    @Environment(\.colorScheme) private var scheme

    @StateObject private var appState = AppState()
    @StateObject private var uiState = IOSUIState.shared
    @StateObject private var router = TabRouter()
    @StateObject private var studioVM = VoiceStudioViewModel.shared

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

                // 后台接收浮条（标签栏之上）
                backgroundBar
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

    // MARK: - 后台接收浮条

    /// 弹窗关掉但任务还在跑时，从任意标签都能一键回到弹窗
    @ViewBuilder
    private var backgroundBar: some View {
        if studioVM.isGenerating && !appState.showGenerationModal {
            BackgroundReceiveBar(vm: studioVM) {
                appState.showGenerationModal = true
            }
            .padding(.horizontal, 16)
            // 抬到标签栏之上；二级界面标签栏已隐藏，贴底即可
            .padding(.bottom, router.activePath.isEmpty ? 58 : 18)
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
    @ObservedObject var vm: VoiceStudioViewModel
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: 9) {
                PulseDot(color: c.accent)
                Text("正在后台接收".localized())
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(c.textPrimary)
                Text(autoByteUnit(Double(vm.stats.receivedBytes)).value +
                     autoByteUnit(Double(vm.stats.receivedBytes)).unit)
                    .font(.system(size: 12.5, design: .monospaced))
                    .foregroundStyle(c.textSecondary)
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
}
