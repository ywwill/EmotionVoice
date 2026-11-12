//
//  ContentView.swift
//  EmotionVoice
//
//  Created by young on 2026/8/8.
//

import SwiftUI
import Foundation   // TimeInterval
import Combine   // @Published / ObservableObject

struct ContentView: View {

    @EnvironmentObject var appState: AppState
    /// macOS 端自己的 Toast 状态（不与 iOS 共用类型 / 状态）
    @StateObject private var uiState = MacUIState.shared

    /// 检查更新：启动静默拉一次 `app_updates`，命中就出顶部横幅 / 强制更新弹窗
    @StateObject private var updateManager = AppUpdateManager.shared

    /// 实际渲染到右侧的内容分区。
    @State private var renderedSection: SidebarSection = .voiceStudio
    @State private var visitedSections: Set<SidebarSection> = [.voiceStudio]

    private static let retainedSections: Set<SidebarSection> = [.voiceStudio, .voices]

    private static let voicesWarmUpDelay: Duration = .milliseconds(800)

    var body: some View {
        HStack(spacing: 0) {
            Sidebar()
            Divider()
                .background(AppColor.borderSubtle)

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
        // 顶部 Toast：macOS 独立实现，出现 / 消失都带动画，1s 自动收起。
        .overlay(alignment: .top) {
            if let toast = uiState.toast {
                MacToastHost(message: toast)
                    .id(toast.id)
                    .padding(.top, 14)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(3)
            }
        }
        // 更新详情 / 强制更新弹窗
        .sheet(item: $updateManager.presentedUpdate) { info in
            AppUpdateSheetMac(manager: updateManager, info: info)
        }
        .task { await updateManager.checkForUpdateAtLaunch() }
        .task { await warmUpVoicesLibrary() }
        .onChange(of: appState.selectedSection) { _, newSection in
            scheduleContentSwap(to: newSection == .home ? .voiceStudio : newSection)
        }
    }

    private func scheduleContentSwap(to section: SidebarSection) {
        guard section != renderedSection else { return }
        applyContentSwap(to: section)
    }

    private func warmUpVoicesLibrary() async {
        try? await Task.sleep(for: Self.voicesWarmUpDelay)
        guard !Task.isCancelled else { return }
        // 用户抢在预热前自己点了进来 / 已经访问过，就不用重复插入
        guard !visitedSections.contains(.voices) else { return }

        VoiceService.shared.warmUpVoiceLibraryCache()
        try? await Task.sleep(for: .milliseconds(32))
        guard !Task.isCancelled else { return }
        guard !visitedSections.contains(.voices) else { return }

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

// MARK: - macOS 顶部 Toast
struct MacToastMessage: Identifiable, Equatable {
    enum Style { case success, failure, info }

    let id = UUID()
    let text: String
    let style: Style
    let duration: TimeInterval

    static func success(_ text: String, duration: TimeInterval = 1) -> MacToastMessage {
        .init(text: text, style: .success, duration: duration)
    }
    static func failure(_ text: String) -> MacToastMessage { .init(text: text, style: .failure, duration: 1) }
    static func info(_ text: String) -> MacToastMessage { .init(text: text, style: .info, duration: 1) }
}

@MainActor
final class MacUIState: ObservableObject {
    static let shared = MacUIState()

    @Published var toast: MacToastMessage? = nil
    private var toastTask: Task<Void, Never>?
    private init() {}

    func showToast(_ message: MacToastMessage) {
        toastTask?.cancel()
        // ⚠️ 出现动画要显式带事务：`.transition` 只在带动画的事务里插入视图时才跑。
        //    `.id(message.id)` 让连续两条 Toast 各自重播入场。
        withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) { toast = message }
        let d = message.duration
        toastTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(d * 1_000_000_000))
            if !Task.isCancelled {
                withAnimation(.easeOut(duration: 0.25)) { self.toast = nil }
            }
        }
    }
}

/// macOS 自绘顶部 Toast。
///
/// ⚠️ 刻意**不沿用 iOS 的 Aurora 风格**（高饱和实色胶囊 + 纯白字 + 同色光晕）：
/// macOS 主项目是 Cold Luxury 冷调深色 + 琥珀金小面积强调，浮层统一走
/// `bgElevated` 底 + `borderMedium` 0.5pt 描边 + 中性黑投影
/// （同一套见 `AppUpdateBannerMac`、`AudioGenerationModal.header`）。
/// 状态色只落在左侧 24×24 图标方块上，正文用 `textPrimary`，避免整块高亮色喧宾夺主。
private struct MacToastHost: View {
    let message: MacToastMessage

    var body: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(tint.opacity(0.12))
                    .frame(width: 24, height: 24)
                    .overlay(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(tint.opacity(0.28), lineWidth: 1)
                    )
                Image(systemName: iconName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
            }

            Text(message.text)
                .font(.system(size: 12.5, weight: .semibold))
                .foregroundStyle(AppColor.textPrimary)
                .lineLimit(2)
        }
        .padding(.horizontal, 14)
        .frame(height: 42)   // 与 AppUpdateBannerMac 同高，两张浮层视觉一致
        .background(
            RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                .fill(AppColor.bgElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                        .strokeBorder(AppColor.borderMedium, lineWidth: 0.5)
                )
        )
        .shadow(color: .black.opacity(0.35), radius: 16, x: 0, y: 6)
        .padding(.horizontal, 16)
    }

    private var iconName: String {
        switch message.style {
        case .success: return "checkmark.circle.fill"
        case .failure: return "xmark.circle.fill"
        case .info: return "info.circle.fill"
        }
    }

    /// 只给图标上色：success / failure 沿用项目状态色，info 用琥珀金主强调色
    /// （iOS 的 info 是蓝色，macOS 这里不跟着走蓝色）。
    private var tint: Color {
        switch message.style {
        case .success: return AppColor.statusSuccess
        case .failure: return AppColor.statusError
        case .info: return AppColor.accentPrimary
        }
    }
}
