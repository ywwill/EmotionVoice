//
//  GenerationOverlay.swift
//  EmotionVoice
//
//  生成弹窗的全局浮层：生成弹窗 + 失败提示 + 「接收完成」召回。
//
//  为什么要提到 ContentView 这一层：
//  弹窗关闭后接收并没有中断（关闭按钮、遮罩、Esc 都只是收起界面），
//  而工作台 VoiceStudioView 在切换分区时会被销毁重建，弹窗与提示若留在
//  它内部，用户切到音色库 / 我的项目后就再也唤不回来、失败也弹不出提示。
//
//  ⚠️ 「后台接收中」那张卡片**不在这里**，它是工作台内部的局部 UI，
//  锚在情感面板「拟声效果」区块的右下角（见 VoiceStudioView.richLanguageSection）。
//  全局只保留那些「无论用户在哪个页面都必须出现」的东西：弹窗与失败提示。
//

import SwiftUI
import AppKit
import Combine

/// 生成相关的全局浮层
///
/// 订阅 `VoiceStudioViewModel` 的范围刻意只到这一层：ContentView 本体不订阅 VM，
/// 工作台里 NSTextView 的每次输入不会牵动整窗重建，只有这张薄薄的浮层跟着刷新。
struct GenerationOverlay: View {

    @EnvironmentObject private var appState: AppState

    @ObservedObject private var vm = VoiceStudioViewModel.shared

    private var modalBinding: Binding<Bool> {
        Binding(
            get: { appState.showGenerationModal },
            set: { appState.showGenerationModal = $0 }
        )
    }

    var body: some View {
        ZStack {
            if appState.showGenerationModal {
                AudioGenerationModal(vm: vm, isPresented: modalBinding)
                    .transition(.opacity)
            }
        }
        // ⚠️ 显式撑满：ZStack 的尺寸只等于子视图的并集，不会自动吃满 overlay 给的空间。
        // 弹窗在场时它靠弹窗里的 `Color(...).ignoresSafeArea()` 撑开，看着正常；
        // 但浮层里一旦只剩一个小视图，ZStack 就缩成那么大，
        // 而 `.overlay` 默认 alignment 是 .center —— 视图于是被摆到屏幕正中。
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.25), value: appState.showGenerationModal)
        // 后台接收完成（弹窗可能早已被关掉）→ 把弹窗重新唤起到完成态
        .onChange(of: vm.generationCompletedSignal) { _, _ in
            appState.showGenerationModal = true
        }
        // 失败提示挂在这里而不是工作台：关掉弹窗后用户可能已经切到别的页面，
        // 挂在 VoiceStudioView 上就永远弹不出来。
        .alert(item: $vm.alertItem) { item in
            Alert(
                title: Text(item.title),
                message: Text(item.message),
                dismissButton: .default(Text("好".localized()))
            )
        }
    }
}

// MARK: - 后台接收卡片

/// 关闭弹窗之后的「还在接收」提示卡片
///
/// 由工作台持有（锚在情感面板「拟声效果」区块右下角），不是全局浮层：
/// 它只在语音合成页有意义，切走页面就不该再出现。
///
/// 数字全部取自 `GenerationStats` —— 和弹窗里那套统计是同一个数据源，
/// 是 WebSocket 每次 `onAudio` 的真实累加量，不是估算也不是模拟。
/// 点一下回到生成弹窗，接收过程不会被打断。

/// 卡片的尺寸常量
///
/// 刻意写死宽度而**不用 GeometryReader 量**：GeometryReader 会贪婪吃掉父视图给的全部空间，
/// 会把这张小卡片撑成满屏的一条（表现就是"居中漂浮"）。卡片宽度固定，扫光条按比例算即可。
private enum CardLayout {
    static let width: CGFloat = 236
    /// 扫光条宽度
    static let sweepWidth: CGFloat = width * 0.34
}

struct BackgroundReceivingCard: View {

    let onShowProgress: () -> Void

    /// 只订阅统计对象：它 10Hz 更新，卡片小，重绘代价可忽略
    @ObservedObject private var stats = VoiceStudioViewModel.shared.stats
    /// 已用时靠自己的低频心跳推进（0.5s），不跟着 10Hz 的数据块刷
    @StateObject private var clock = ReceivingClock()

    @State private var isHovering = false
    /// 扩散圈：false → true 触发一次 repeatForever
    @State private var ring = false
    /// 底部扫光：false → true 触发一次 repeatForever
    @State private var sweep = false

    var body: some View {
        Button(action: onShowProgress) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 10) {
                    pulseDot
                    texts
                    Spacer(minLength: 6)
                    chevron
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 11)

                sweepStrip
            }
            .frame(width: CardLayout.width)
            .background(AppColor.bgElevated)
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                    .stroke(
                        AppColor.accentPrimary.opacity(isHovering ? 0.45 : 0.22),
                        lineWidth: 1
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous))
            .shadow(color: .black.opacity(0.5), radius: 18, x: 0, y: 8)
            .scaleEffect(isHovering ? 1.015 : 1)
            .animation(.easeInOut(duration: 0.18), value: isHovering)
        }
        .buttonStyle(.plain)
        .contentShape(Rectangle())
        .pointingHandCursor()
        .onHover { hovering in isHovering = hovering }
        .onAppear {
            clock.start()
            ring = true
            sweep = true
        }
        .onDisappear { clock.stop() }
    }

    // MARK: 子组件

    /// 中心实心点 + 一圈不断向外扩散消失的光环
    private var pulseDot: some View {
        ZStack {
            Circle()
                .fill(AppColor.accentPrimary.opacity(0.55))
                .frame(width: 22, height: 22)
                .scaleEffect(ring ? 1.3 : 0.55)
                .opacity(ring ? 0 : 0.9)
                .animation(
                    .easeOut(duration: 1.5).repeatForever(autoreverses: false),
                    value: ring
                )
            Circle()
                .fill(AppColor.accentPrimary)
                .frame(width: 8, height: 8)
        }
        .frame(width: 22, height: 22)
    }

    private var texts: some View {
        VStack(alignment: .leading, spacing: 3) {
            
            let rx = autoByteUnit(Double(stats.receivedBytes))
            
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(rx.value)
                    .font(.system(size: 15, weight: .semibold))
                    .fontDesign(.monospaced)
                    .foregroundStyle(AppColor.textPrimary)
                Text(rx.unit)
                    .font(.system(size: 10))
                    .foregroundStyle(AppColor.textSecondary)
                Spacer()
            }
            
            Text("正在接收")
                .font(.system(size: 11))
        }
    }

    private var chevron: some View {
        HStack(spacing: 2) {
            Text("查看".localized())
                .font(.system(size: 11, weight: .medium))
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .semibold))
        }
        .foregroundStyle(isHovering ? AppColor.accentGlow : AppColor.accentPrimary)
    }

    /// 底部一道来回扫的高光：流式接收拿不到总量，只表达"还在往里堆"
    private var sweepStrip: some View {
        ZStack(alignment: .leading) {
            Rectangle()
                .fill(AppColor.accentPrimary.opacity(0.12))
            LinearGradient(
                colors: [
                    AppColor.accentPrimary.opacity(0),
                    AppColor.accentPrimary.opacity(0.85),
                    AppColor.accentPrimary.opacity(0)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: CardLayout.sweepWidth)
            // 从左侧界外扫到右侧界外，靠外层 .clipped() 裁掉溢出部分
            .offset(x: sweep ? CardLayout.width : -CardLayout.sweepWidth)
            .animation(
                .linear(duration: 1.5).repeatForever(autoreverses: false),
                value: sweep
            )
        }
        .frame(width: CardLayout.width, height: 2)
        .clipped()
    }

    // MARK: 数据

    /// 已用时：与弹窗共用 VM 记下的开始时刻，中途重开卡片也不会归零
    private var elapsed: TimeInterval {
        guard let start = VoiceStudioViewModel.shared.generationStartedAt else { return 0 }
        return max(0, clock.now.timeIntervalSince(start))
    }
}

/// 秒 → mm:ss（本文件自用；`AudioGenerationModal` 里有一份同名实现，各自文件内私有）
private func receivingClockText(_ seconds: TimeInterval) -> String {
    let total = max(0, Int(seconds.rounded(.down)))
    return String(format: "%02d:%02d", total / 60, total % 60)
}

/// 卡片的心跳
///
/// 与 `AudioGenerationModal.StatsTicker` 同理：不能用
/// `Timer.publish(...).autoconnect()`，卡片会被 stats 的高频更新反复重建，
/// Combine 订阅跟着断连重连，计时器永远走不满一个周期。这里用对象持有的真实 Timer。
private final class ReceivingClock: ObservableObject {

    @Published var now: Date = Date()

    private var timer: Timer?

    func start() {
        guard timer == nil else { return }
        let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.now = Date()
        }
        timer = t
        RunLoop.main.add(t, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }
}
