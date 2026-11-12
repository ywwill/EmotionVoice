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
    /// 检查更新：启动静默拉一次 `app_updates`，命中就出顶部横幅 / 强制更新弹窗
    @StateObject private var updateManager = AppUpdateManager.shared
    // ⚠️ 根容器不订阅任何播放态：`AudioPreviewPlayer`（10Hz）会让整个 TabView +
    //    3 个 NavigationStack 一起重算；连低频代理 `PlaybackStatus` 也不再需要 ——
    //    mini player 的显隐只看 `NowPlayingStore.currentItem`（见 `bottomDock`），
    //    播放按钮 / 进度由 `MiniPlayerView` 自己订阅。

    /// 键盘弹起时底部浮层让位：搜索框聚焦时 mini player / 后台浮条不压到键盘。
    @State private var keyboardVisible = false

    private var palette: AuroraPalette { AuroraPalette(scheme: scheme) }

    var body: some View {
        ScreenMetricsReader { metrics in
            ZStack(alignment: .bottom) {
                TabView(selection: $router.selection) {
                    stack(for: .studio) { StudioView() }
                    stack(for: .library) { VoicesLibraryView() }
                    stack(for: .projects) { ProjectsView() }
                }
                .tint(palette.accent)

                // 底部浮层三选一（互斥，不叠放）：撤销 Toast > 后台接收浮条 > mini player
                bottomDock(tabBarClearance: metrics.tabBarClearance)
                    // ⚠️ 这段动画是浮层「进 / 出场」唯一的事务来源：三条分支各自的
                    //    `.transition` 只在状态变化落在带动画的事务里才生效，否则瞬切。
                    //    用 `dockKind` 这个粗粒度字符串做 value —— 只关心「换成了哪一种」，
                    //    不跟着 mini player 的 10Hz 播放进度重放动画。
                    // ⚠️ 二级页（播放详情 / 设置 / 最近删除）push 时给 nil：浮层要跟着
                    //    NavigationStack 的推入立刻让位，不能还在底下自播 0.36s 的下沉 ——
                    //    那会被看成「进详情页前底部弹了一下」。pop 回来时 path 已空，
                    //    自动恢复成带弹簧的上滑。
                    .animation(router.activePath.isEmpty ? Self.dockAnimation : nil,
                               value: dockKind)
                    // ⚠️ 浮层不参与键盘避让：它的位置是按标签栏算的固定值，
                    //    一旦被键盘的 safe area 压缩带着走，收起键盘时就会「一边下移
                    //    一边归位」。显隐由 `keyboardVisible` 单独控制（见 DidHide 注释）。
                    .ignoresSafeArea(.keyboard, edges: .bottom)
            }
            // 顶部更新横幅：**浮层**（Z 轴重叠），不占布局高度 —— 不再把 StudioView /
            // 音色库 / 项目页整体往下推。
            // ⚠️ 让开导航栏：根容器顶边就在状态栏下方，inline 导航栏（44pt）正好占前 44pt，
            //    直接贴顶会盖住「创作」标题和左右 toolbar 按钮，所以下移一个导航栏高度。
            //    iPadOS 18 把标签栏也并进这一行（胶囊分段控件），顶栏比 iPhone 高约 8pt。
            .overlay(alignment: .top) {
                updateBannerLayer
                    .padding(.top, metrics.isPadClass ? AppUpdateBanner.navBarClearance + 8
                                                     : AppUpdateBanner.navBarClearance)
                    .animation(.easeInOut(duration: 0.22), value: updateManager.showsBanner)
            }
            .overlay { generationOverlay }
            .overlay(alignment: .top) { toastLayer }
            .sheet(isPresented: $uiState.purchaseSheetPresented) {
                PurchaseSheet()
                    .presentationDetents([.large])
            }
            // 强制更新弹窗
            .sheet(item: $updateManager.presentedUpdate) { info in
                AppUpdateSheet(manager: updateManager, info: info)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.hidden)
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
        // 生成期间申请后台执行时间：按 Home / 锁屏后这条 WebSocket 还能继续收分片。
        // ⚠️ 挂在根容器而不是弹窗上（弹窗关掉生成仍在跑），且整次生成只 start/finish
        //    各一次 —— 多片段合成会多次建立 WebSocket，不能按单段去申请 / 结束。
        .onChange(of: studioVM.isGenerating) { _, generating in
            if generating {
                GenerationBackgroundKeeper.shared.start()
            } else {
                GenerationBackgroundKeeper.shared.finish(success: studioVM.generatedAudioURL != nil)
            }
        }
        .onAppear {
            // 根容器重建时若恰有生成在跑（如从后台恢复），补一次申请；start() 幂等
            if studioVM.isGenerating { GenerationBackgroundKeeper.shared.start() }
        }
        // 启动时清一次到期记录（磁盘删除不夹在任何动画事务里）
        .task {
            let expired = AudioFlagStore.shared.purgeExpired()
            for id in expired { ProjectService.shared.deleteAudio(id: id) }
        }
        // 启动静默检查更新：失败 / 无更新都不打扰用户
        .task { await updateManager.checkForUpdateAtLaunch() }
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillShowNotification)) { _ in
            keyboardVisible = true
        }
        // ⚠️ 收键盘必须等 **DidHide**，不能用 WillHide：
        //    WillHide 在键盘刚开始下落的那一帧就发出，此时底部安全区**仍被键盘占着**，
        //    ZStack 的可用高度还没恢复 —— mini player 会插在「键盘顶边之上」的高位，
        //    等键盘落完、安全区恢复后再被布局推到最终位置。观感就是：先冒出来一小条，
        //    然后一边下移一边盖住 Studio 的 generateBar。等键盘完全落干净再插入，
        //    浮层直接从最终位置弹簧上滑，没有任何位移过程。
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardDidHideNotification)) { _ in
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

    // MARK: - 更新横幅（浮层，不参与布局）

    @ViewBuilder
    private var updateBannerLayer: some View {
        if updateManager.showsBanner, let info = updateManager.availableUpdate {
            AppUpdateBanner(manager: updateManager, info: info)
                .transition(.move(edge: .top).combined(with: .opacity))
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

    /// 浮层进 / 出场的曲线：出现时从标签栏下沿弹上来（略带过冲），消失时反向沉下去。
    /// 时长压到 0.36s，和标签栏显隐的 0.28s 同一量级，切二级页时两段动作不打架。
    static let dockAnimation = Animation.spring(response: 0.36, dampingFraction: 0.84)

    /// 三条分支共用的过渡：位移 + 淡入淡出 + 轻微缩小。
    /// ⚠️ 加 `scale` 是为了让「沉下去」的卡片在 58pt 的标签栏区域内彻底被带走 ——
    ///    只靠 `.move` 的话位移量等于卡片高度（56pt），下沿会露出 2pt 一条边。
    static let dockTransition: AnyTransition = .move(edge: .bottom)
        .combined(with: .opacity)
        .combined(with: .scale(scale: 0.96, anchor: .bottom))

    /// 当前浮层是哪一种（只用于驱动过渡动画，不参与内容渲染）。
    /// ⚠️ 用粗粒度的枚举式字符串而不是把条件散在 `body` 里：`animation(_:value:)`
    ///    只在 value 变化时给子树注入事务，值稳定就不会重放动画。
    private var dockKind: String {
        if uiState.undoToast != nil { return "undo" }
        if !keyboardVisible && studioVM.isGenerating && !appState.showGenerationModal {
            return "receiving"
        }
        if !keyboardVisible && router.activePath.isEmpty && !uiState.hideMiniPlayer,
           nowPlaying.currentItem != nil {
            return "mini"
        }
        return "none"
    }

    /// 优先级：撤销 Toast > 后台接收浮条 > mini player。
    /// ⚠️ 三者都占「标签栏之上」同一位置，叠放会互相盖住；多选工具条自己在
    ///    `ProjectsView.safeAreaInset` 里，靠 `uiState.hideMiniPlayer` 让出位置。
    /// `tabBarClearance` 由 `ScreenMetrics` 按平台给出：iPhone 底部标签栏 58pt，
    /// iPad（标签栏在顶部）贴底 18pt —— 硬写 58 会让浮层悬在半空。
    @ViewBuilder
    private func bottomDock(tabBarClearance: CGFloat) -> some View {
        if let undo = uiState.undoToast {
            UndoToastView(message: undo) { uiState.consumeUndoToast() }
                .padding(.horizontal, 12)
                .padding(.bottom, router.activePath.isEmpty ? tabBarClearance : 18)
                .transition(Self.dockTransition)
                .zIndex(4)
        } else if !keyboardVisible && studioVM.isGenerating && !appState.showGenerationModal {
            // 弹窗关掉但任务还在跑时，从任意标签都能一键回到弹窗
            BackgroundReceiveBar(stats: studioVM.stats) {
                appState.showGenerationModal = true
            }
            .padding(.horizontal, 16)
            // 抬到标签栏之上；二级界面标签栏已隐藏，贴底即可
            .padding(.bottom, router.activePath.isEmpty ? tabBarClearance : 18)
            .transition(Self.dockTransition)
            .zIndex(2)
        } else if !keyboardVisible && router.activePath.isEmpty && !uiState.hideMiniPlayer,
                  let item = nowPlaying.currentItem {
            // ⚠️ 显隐**只由 `NowPlayingStore.currentItem` 决定** —— 也就是只有用户点 ✕
            //    才收起。早先还要求 `status.playingKey != nil`，于是这些「不是用户意图」
            //    的时刻都会把浮层弄没：切标签时离开的音色库页 `player.stop()`、播到结尾
            //    （`playingKey` 归 nil）、音色库试听把当前 key 顶掉。用户的心智模型是
            //    「只要我不关它就在」，停下来也该留着能接着播。
            MiniPlayerView(item: item,
                           voiceName: nowPlaying.currentVoiceName,
                           onExpand: {
                               router.selection = .projects
                               router.push(.player(item))
                           },
                           onToggle: { NowPlayingStore.shared.toggle(item) },
                           onClose: { NowPlayingStore.shared.close() })
                .padding(.horizontal, 12)
                .padding(.bottom, tabBarClearance)
                .transition(Self.dockTransition)
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
