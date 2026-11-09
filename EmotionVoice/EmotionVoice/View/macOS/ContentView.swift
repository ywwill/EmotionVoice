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
    @State private var renderedSection: SidebarSection = .voiceStudio

    /// 已经访问过的分区。
    ///
    /// ⚠️ 两个「重页面」（语音合成 / 音色库）一旦访问过就常驻在 ZStack 中，
    /// 再次切入只切 opacity，**不再销毁重建**：
    /// - VoiceStudioView 的 NSTextView（字形缓存、语气胶囊、attachment 状态表、
    ///   Coordinator 与 first responder）保持同一个实例；
    /// - VoicesLibraryView 的 @StateObject VM（分页缓存、筛选状态）保持同一个实例。
    /// 旧实现用 `.id(renderedSection)` 强制换身份，每次切页都把这两棵树全量重建，
    /// 是切页时 CPU / 内存尖峰与掉帧的根因。
    @State private var visitedSections: Set<SidebarSection> = [.voiceStudio]

    /// 需要常驻（保留实例）的重页面。
    /// 其余分区仍按需创建 / 销毁：历史记录、积分中心依赖 onAppear 重新拉数据，
    /// 播放快捷键也依赖 onDisappear 注销，保留实例反而会改变语义。
    private static let retainedSections: Set<SidebarSection> = [.voiceStudio, .voices]

    /// 音色库空闲预热的等待时长。
    ///
    /// 音色库首次出现要一次性完成：VM 初始化 + 27 个分类 chip 的 FlowLayout
    /// 测量 + 20 张骨架卡 + 2 处 ultraThinMaterial 离屏层 + 首屏全表排序 /
    /// 约 29 次全量 COUNT / 当前页 Voice 对象构建。以前这些全压在「点击音色库」
    /// 那一帧上，用户感受到的就是「只有第一次卡」。
    /// 现在启动后等首屏 + 更新检查 + 评分弹窗都过去，再在空闲期把页面挂进
    /// ZStack（隐藏态），由它自己的 onAppear 把数据也一并备好；用户首次点击
    /// 只剩一次 alpha 变化。
    /// ⚠️ 别把这步塞进 `checkForUpdateAtLaunch()` 那条 `.task`：网络请求超时
    /// 会把预热无限期推迟，必须单独一条 `.task`。
    private static let voicesWarmUpDelay: Duration = .milliseconds(800)

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
        // 空闲期预热音色库（与网络检查并行，互不阻塞）
        .task { await warmUpVoicesLibrary() }
        // 每次打开 App（冷启动 / 重新激活）都申请一次 App Store 评分
        .requestReviewOnEveryOpen()
        .onChange(of: appState.selectedSection) { _, newSection in
            // `.home` 已无侧边栏入口，历史上与工作台共用同一页面，归一化避免空白页
            scheduleContentSwap(to: newSection == .home ? .voiceStudio : newSection)
        }
    }

    private func scheduleContentSwap(to section: SidebarSection) {
        guard section != renderedSection else { return }
        // 所有切换都即时响应。旧的「首次进音色库先 sleep 100ms 让位给侧边栏
        // spring」已删除：重页面现在在启动空闲期就预热好了，点击时没有视图构建，
        // 等 100ms 只会变成「点了没反应」。即便预热未完成用户就点进来，
        // 即时上屏（哪怕掉一帧）也比让人干等更跟手。
        applyContentSwap(to: section)
    }

    /// 启动空闲期把音色库挂进常驻层（隐藏态），提前完成首次构建 + 首屏取数。
    ///
    /// `VoicesLibraryView(isActive: false)` 的 `onAppear` 会照常触发：
    /// 先上静态骨架，再跨 32ms 跑 `vm.load()`。骨架扫光按 `isActive` 关闭，
    /// 隐藏层不绘制、不拦截点击，因此预热期间既无可见变化也无常驻动画开销。
    /// 预热完成后用户第一次点「音色库」只是把这一层的 opacity 从 0 切到 1。
    private func warmUpVoicesLibrary() async {
        try? await Task.sleep(for: Self.voicesWarmUpDelay)
        guard !Task.isCancelled else { return }
        // 用户抢在预热前自己点了进来 / 已经访问过，就不用重复插入
        guard !visitedSections.contains(.voices) else { return }

        // 第 1 帧：只算数据缓存（全表排序 + 全量 COUNT），不碰视图树。
        // 与下面挂视图树分到两帧，避免两个大头挤在同一帧造成启动后可感知的掉帧。
        VoiceService.shared.warmUpVoiceLibraryCache()
        try? await Task.sleep(for: .milliseconds(32))
        guard !Task.isCancelled else { return }
        guard !visitedSections.contains(.voices) else { return }

        // 第 2 帧：挂隐藏视图树；它自己的 onAppear 会在 32ms 后跑完 vm.load()，
        // 此时有序 key 与 chip 计数都已命中缓存，只剩取当前页这一窗 Voice 对象。
        visitedSections.insert(.voices)
    }

    private func applyContentSwap(to section: SidebarSection) {
        renderedSection = section
        // 只记录需要常驻的重页面；轻量页仍由条件渲染自行管理生命周期
        if Self.retainedSections.contains(section) {
            visitedSections.insert(section)
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        ZStack(alignment: .topLeading) {
            // —— 常驻层：访问过的重页面留在树里，靠 opacity 显隐 ——
            if visitedSections.contains(.voiceStudio) {
                retainedPage(
                    VoiceStudioView(isActive: renderedSection == .voiceStudio),
                    isCurrent: renderedSection == .voiceStudio
                )
            }
            if visitedSections.contains(.voices) {
                retainedPage(
                    VoicesLibraryView(isActive: renderedSection == .voices),
                    isCurrent: renderedSection == .voices
                )
            }

            // —— 按需层：轻量页沿用「每次切入重建」，保持 onAppear 刷新语义 ——
            switch renderedSection {
            case .projects:
                lightweightPage(HistoryView())
            case .credits:
                lightweightPage(CreditsView())
            case .settings:
                lightweightPage(SettingsView())
            default:
                EmptyView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColor.bgPrimary)
    }

    /// 常驻页：撑满内容区 + alpha 显隐。
    /// `allowsHitTesting(false)` 让隐藏页不拦截鼠标；文本域的键盘焦点由
    /// `VoiceStudioView.isActive` 交给 `EmotionTokenEditor.isInteractive` 处理。
    private func retainedPage<Content: View>(_ content: Content, isCurrent: Bool) -> some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            // 不透明底：ZStack 里当前页要能盖住下层 opacity 0 的常驻页。
            // 尤其工作台是 AppKit 的 NSTextView，SwiftUI 的 opacity(0) 对
            // NSViewRepresentable 不总是可靠，铺一层底可避免隐藏页内容透出。
            .background(AppColor.bgPrimary)
            .opacity(isCurrent ? 1 : 0)
            .allowsHitTesting(isCurrent)
            .animation(.easeInOut(duration: 0.12), value: isCurrent)
    }

    /// 轻量页：只补撑满布局、不透明底与淡入淡出，生命周期仍由条件渲染管理。
    private func lightweightPage<Content: View>(_ content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppColor.bgPrimary)
            .transition(.opacity.animation(.easeInOut(duration: 0.12)))
    }
}
