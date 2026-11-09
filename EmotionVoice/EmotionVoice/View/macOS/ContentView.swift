//
//  ContentView.swift
//  EmotionVoice
//
//  Created by young on 2026/8/8.
//

import SwiftUI

struct ContentView: View {

    @EnvironmentObject var appState: AppState

    /// 检查更新：启动静默拉一次 `app_updates`，命中就出顶部横幅 / 强制更新弹窗
    @StateObject private var updateManager = AppUpdateManager.shared

    /// 实际渲染到右侧的内容分区。
    ///
    /// 刻意滞后于 `appState.selectedSection`：点击菜单时 `selectedSection` 立即变化，
    /// 侧边栏的高亮块随之开始滑动；若重内容（VoiceStudioView 的 NSTextView、
    /// VoicesLibraryView 的骨架网格）在同一帧被构建，会长时间阻塞主线程，
    /// 让滑动动画直接掉帧。这里先把滑动动画让出去，等它基本走完再换内容。
    @State private var renderedSection: SidebarSection = .voiceStudio

    /// 内容切换的调度任务（支持连续点击时取消上一次）
    @State private var swapTask: Task<Void, Never>? = nil

    /// 让位给侧边栏滑动动画的时长。
    /// 取 spring(response: 0.36) 的约 2/3：此时位移已完成 ~90%，
    /// 剩下几像素的回弹与内容替换的掉帧重叠也看不出来。
    private static let contentSwapDelay: Duration = .milliseconds(100)

    var body: some View {
        HStack(spacing: 0) {
            Sidebar()
            Divider()
                .background(AppColor.borderSubtle)

            // 更新横幅浮在内容区顶部（Z 轴叠在内容之上，不占布局高度）：
            // 不能再用 VStack 顶条 —— 那样横幅一出现就把 VoiceStudioView 等页面
            // 整体往下挤，工作台的文本域、生成栏会跟着跳一下。
            // 只叠在内容列之内，不越过 Divider 盖住侧边栏。
            mainContent
                .overlay(alignment: .top) {
                    if updateManager.showsBanner, let info = updateManager.availableUpdate {
                        AppUpdateBannerMac(manager: updateManager, info: info)
                            .padding(.top, AppUpdateBannerMac.topInset)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .animation(.easeInOut(duration: 0.22), value: updateManager.showsBanner)
        }
        .background(AppColor.bgPrimary)
        .frame(minWidth: 1000, minHeight: 800)
        // 生成弹窗 / 后台接收卡片挂在这一层：
        // 弹窗关闭后接收仍在后台跑，提示必须能跨页面存在（见 GenerationOverlay）
        .overlay { GenerationOverlay() }
        // 更新详情 / 强制更新弹窗
        .sheet(item: $updateManager.presentedUpdate) { info in
            AppUpdateSheetMac(manager: updateManager, info: info)
        }
        .task { await updateManager.checkForUpdateAtLaunch() }
        // 每次打开 App（冷启动 / 重新激活）都申请一次 App Store 评分
        .requestReviewOnEveryOpen()
        .onChange(of: appState.selectedSection) { _, newSection in
            scheduleContentSwap(to: newSection)
        }
    }

    /// 延迟替换右侧内容，避开侧边栏滑动动画的关键帧
    private func scheduleContentSwap(to section: SidebarSection) {
        // 任何一次点击都先取消上一次的调度：
        // 连点（A→B→A）时不能让旧的调度把内容切回中间态
        swapTask?.cancel()
        swapTask = nil

        guard section != renderedSection else { return }

        swapTask = Task { @MainActor in
            try? await Task.sleep(for: Self.contentSwapDelay)
            guard !Task.isCancelled else { return }
            // 无动画事务地替换：只让 .transition 做轻量淡入，不与滑动争抢帧
            renderedSection = section
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        Group {
            switch renderedSection {
            case .home:
                // 已移除侧边栏入口；保留以保证 switch 穷尽。
                // 程序不会进入此分支（默认 section = .voiceStudio，且无 UI 可触发）。
                VoiceStudioView()
            case .voiceStudio: VoiceStudioView()
            case .voices:      VoicesLibraryView()
            case .projects:    HistoryView()
            case .credits:     CreditsView()
//            case .stats:       StatsView()
            case .settings:    SettingsView()
            }
        }
        .id(renderedSection)
        .transition(.opacity.animation(.easeInOut(duration: 0.12)))
    }
}
