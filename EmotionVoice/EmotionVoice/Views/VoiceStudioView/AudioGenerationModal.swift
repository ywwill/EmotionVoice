//
//  AudioGenerationModal.swift
//  EmotionVoice
//
//  Created by young on 2026/9/20.
//
//  视觉与交互严格对齐 UI/audio-streaming-modal.html：
//  - 状态一「接收中」：波形呼吸 + 不确定进度条 + 持续累积的字节数 / 数据块 / 用时 / 码率 + 数据块日志
//  - 状态二「完成」：完成条幅 + 可重命名 + 四宫格元信息 + 音色卡 + 波形播放器 + 消耗积分 + 导出/完成
//  - 两种状态都可关闭，关闭只收起界面，不打断仍在进行的接收
//

import SwiftUI
import Combine
import UniformTypeIdentifiers
import AppKit

// MARK: - 格式化
// 字节 / 时长格式化（formatDataSize / autoByteUnit / receivedNumberFormatter /
// formatDuration）已统一迁移到 Helper/Func.swift，作为公共方法供各处复用。

/// 秒 → mm:ss
private func formatClock(_ seconds: TimeInterval) -> String {
    let total = max(0, Int(seconds.rounded(.down)))
    return String(format: "%02d:%02d", total / 60, total % 60)
}

/// 采样率：24000 → "24 kHz"
private func formatSampleRate(_ rate: Int) -> String {
    rate >= 1000 ? "\(rate / 1000) kHz" : "\(rate) Hz"
}

// MARK: - 接收中：波形动画

/// 数据块到达日志的一行
private struct ChunkLine: Identifiable {
    let id = UUID()
    let index: Int
    let size: Int
}

/// 持续流动的波形条
///
/// 流式返回拿不到总大小，所以这里不表达"还差多少"，只表达"还在往里堆"。
///
/// 两条实现要点：
/// 1. 条数按容器宽度自适应铺满整条（早期是写死 26 根、居中摆放，看起来像只占中间一小撮）。
/// 2. 不用 TimelineView 每秒 30 次重算 body，而是给每根条挂一条
///    `repeatForever` 的缩放动画（时长/延迟错开，等价于 CSS 的 delay+duration），
///    动画完全跑在渲染服务端，SwiftUI 一次都不用重绘。
private struct StreamingWaveView: View {

    @State private var animating = false

    private static let barWidth: CGFloat = 6
    private static let spacing: CGFloat = 6

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let count = max(12, min(56, Int((w + Self.spacing) / (Self.barWidth + Self.spacing))))
            let totalBarWidth = CGFloat(count) * Self.barWidth + CGFloat(count - 1) * Self.spacing
            let barStartX = (w - totalBarWidth) / 2
            let sweepWidth = max(60, w * 0.45)

            ZStack(alignment: .leading) {
                // 波形条：每根独立错相呼吸
                HStack(spacing: Self.spacing) {
                    ForEach(0..<count, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 3)
                            .fill(
                                LinearGradient(
                                    colors: [AppColor.accentGlow, AppColor.accentSecondary],
                                    startPoint: .top,
                                    endPoint: .bottom
                                )
                            )
                            .frame(width: Self.barWidth, height: Self.barHeight(index: i))
                            .scaleEffect(x: 1, y: animating ? 1 : 0.28, anchor: .center)
                            .animation(
                                Animation.easeInOut(duration: 0.9 + Double(i % 5) * 0.11)
                                    .repeatForever(autoreverses: true)
                                    .delay(Double(i) * 0.055),
                                value: animating
                            )
                    }
                }
                .frame(width: totalBarWidth)
                .offset(x: barStartX)

                // 扫光：一遍遍从左扫到右
                LinearGradient(
                    colors: [Color.clear, AppColor.accentPrimary.opacity(0.13), Color.clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: sweepWidth)
                .offset(x: animating ? w : -sweepWidth)
                .animation(
                    Animation.linear(duration: 1.9).repeatForever(autoreverses: false),
                    value: animating
                )
            }
        }
        .frame(height: 92)
        .background(
            LinearGradient(
                colors: [AppColor.accentPrimary.opacity(0.05), AppColor.accentPrimary.opacity(0.01)],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.medium)
                .stroke(AppColor.accentPrimary.opacity(0.14), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium))
        .onAppear { animating = true }
    }

    private static func barHeight(index i: Int) -> CGFloat {
        16 + abs(sin(Double(i) * 0.9)) * 44
    }
}

/// 不确定进度条：没有百分比，只有一段来回滑动的高光
private struct IndeterminateProgressBar: View {

    @State private var animating = false

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            ZStack(alignment: .leading) {
                Capsule().fill(AppColor.bgTertiary)
                LinearGradient(
                    colors: [
                        AppColor.accentPrimary.opacity(0),
                        AppColor.accentPrimary,
                        AppColor.accentPrimary.opacity(0)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: w * 0.38)
                .clipShape(Capsule())
                .offset(x: animating ? w * 1.02 : -w * 0.4)
            }
        }
        .frame(height: 6)
        .onAppear {
            animating = false
            withAnimation(.linear(duration: 1.35).repeatForever(autoreverses: false)) {
                animating = true
            }
        }
    }
}

/// 统计小格（数据块 / 已用时 / 当前码率，或 大小 / 采样率 / 格式 / 时长）
private struct StatCell: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.system(size: 10.5))
                .foregroundStyle(AppColor.textTertiary)
            Text(value)
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(AppColor.textPrimary)
                .fontDesign(.monospaced)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(AppColor.bgTertiary)
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.small)
                .stroke(AppColor.borderSubtle, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.small))
    }
}

// MARK: - 完成态：波形播放器

/// 接收中的统计心跳
///
/// 不能用 `let ticker = Timer.publish(...).autoconnect()`：接收过程中
/// `receivedBytes` 每来一块就变一次，弹窗被反复重建，Combine 的订阅会被
/// 取消再重连，计时器永远走不满一个周期，`onReceive` 一次都不触发
/// （表现就是字节数和速率一直停在 0）。这里改成由对象持有的真实 Timer。
private final class StatsTicker: ObservableObject {
    @Published var now: Date = Date()

    private var timer: Timer?

    func start() {
        guard timer == nil else { return }
        // 注意：这个 block 的参数是 Timer 本身，不是触发时刻
        let t = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
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

/// 波形绘制：单图层 Canvas，所有柱子合成 2 条 Path，各 fill 一次
///
/// 对齐 `PlayerWaveformView` 的画法。之前的版本是逐条 fill（60 条 × 渐变），
/// 播放时每 0.1s 就要建 60 次渐变并填充 60 次；现在整帧只有两次 fill。
private struct ModalWaveCanvas: View {

    var progress: Double
    var isHovered: Bool

    private static let gap: CGFloat = 2
    private static let barCount = 60
    fileprivate static let heights: [CGFloat] = (0..<60).map { i in
        let v = sin(Double(i) * 0.55) * 0.35
            + sin(Double(i) * 0.21 + 1.3) * 0.4
            + sin(Double(i) * 1.7) * 0.15
        return max(0.18, min(1, 0.55 + v * 0.42)) * 40
    }

    var body: some View {
        Canvas { ctx, size in
            let n = Self.barCount
            let gap = Self.gap
            let barW = max(1.5, (size.width - gap * CGFloat(n - 1)) / CGFloat(n))
            let cut = size.width * CGFloat(min(max(progress, 0), 1))

            var background = Path()
            var played = Path()
            var x: CGFloat = 0

            for i in 0..<n {
                let h = Self.heights[i]
                let bar = Path(
                    roundedRect: CGRect(x: x, y: (size.height - h) / 2, width: barW, height: h),
                    cornerRadius: 2
                )
                background.addPath(bar)
                // 只有中心线越过播放头的柱子才算"已播放"
                if x + barW * 0.5 <= cut {
                    played.addPath(bar)
                }
                x += barW + gap
            }

            ctx.fill(background, with: .color(Color.white.opacity(isHovered ? 0.20 : 0.13)))

            if !played.isEmpty {
                ctx.fill(
                    played,
                    with: .linearGradient(
                        Gradient(colors: [AppColor.accentGlow, AppColor.accentSecondary]),
                        startPoint: .zero,
                        endPoint: CGPoint(x: 0, y: size.height)
                    )
                )
            }
        }
    }
}

/// 生成弹窗里的播放器（播放按钮 + 时间 + 波形进度）
///
/// 性能约定，与 `AudioPlayerDetailView` 一致：
/// **只有这个子视图订阅 `AudioPreviewPlayer`**。播放进度以 10Hz 刷新，
/// 订阅范围一旦上移到弹窗，四宫格、音色卡、积分行这些都会跟着重算 ——
/// 这就是之前"播放时十分卡顿"的原因。弹窗外层用 `let` 传入 URL 和时长，
/// 播放期间一次都不参与重绘。
private struct ModalAudioPlayer: View {

    let audioURL: URL
    let duration: TimeInterval

    @ObservedObject private var player = AudioPreviewPlayer.shared

    @State private var isScrubbing = false
    @State private var scrubProgress: Double = 0
    @State private var isHovering = false
    @State private var hoverRatio: CGFloat = 0

    private var isPlaying: Bool { player.isPlaying(url: audioURL) }
    private var displayProgress: Double { isScrubbing ? scrubProgress : player.progress }
    private var displayTime: Double { isScrubbing ? scrubProgress * duration : player.currentTime }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Button { togglePlayback() } label: {
                    ZStack {
                        Circle()
                            .fill(AppColor.accentPrimary)
                            .frame(width: 40, height: 40)
                            .shadow(color: AppColor.accentPrimary.opacity(0.25), radius: 8, y: 3)
                        Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(AppColor.bgPrimary)
                            .offset(x: isPlaying ? 0 : 1.5)
                    }
                }
                .buttonStyle(.plain)
                .pointingHandCursor()

                VStack(alignment: .leading, spacing: 2) {
                    Text(formatClock(displayTime))
                        .font(.system(size: 14, weight: .semibold))
                        .fontDesign(.monospaced)
                        .foregroundStyle(AppColor.textPrimary)
                    Text("\(formatClock(duration))")
                        .font(.system(size: 14, weight: .semibold))
                        .fontDesign(.monospaced)
                        .foregroundStyle(AppColor.textPrimary)
                }

                Spacer()

                HStack(spacing: 6) {
                    Circle()
                        .fill(isPlaying ? AppColor.statusSuccess : AppColor.textTertiary)
                        .frame(width: 6, height: 6)
                    Text(isPlaying ? "正在播放".localized() : "已暂停".localized())
                        .font(.system(size: 11))
                        .foregroundStyle(isPlaying ? AppColor.statusSuccess : AppColor.textTertiary)
                }
            }

            waveRow
                .padding(.top, 22)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 13)
        .background(AppColor.bgTertiary)
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.medium)
                .stroke(AppColor.borderSubtle, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium))
    }

    // MARK: 波形进度条（点击定位 + 拖动擦洗 + 悬停气泡）

    private var waveRow: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)

            ZStack(alignment: .leading) {
                ModalWaveCanvas(
                    progress: displayProgress,
                    isHovered: isHovering || isScrubbing
                )
                .frame(width: width, height: 46)

                // 播放头
                Capsule()
                    .fill(AppColor.accentPrimary)
                    .frame(width: 2, height: 34)
                    .offset(x: width * CGFloat(displayProgress) - 1)

                if isHovering || isScrubbing {
                    Text(formatClock(hoverRatio * duration))
                        .font(.system(size: 10.5))
                        .fontDesign(.monospaced)
                        .foregroundStyle(AppColor.textPrimary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(AppColor.bgElevated)
                        .overlay(
                            RoundedRectangle(cornerRadius: 5)
                                .stroke(AppColor.borderMedium, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                        .offset(x: min(max(width * hoverRatio - 18, 0), max(width - 36, 0)))
                        .offset(y: -26)
                        .allowsHitTesting(false)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let p = min(max(value.location.x / width, 0), 1)
                        isScrubbing = true
                        hoverRatio = p
                        scrubProgress = p
                        player.seek(to: p * duration)
                    }
                    .onEnded { _ in
                        isScrubbing = false
                    }
            )
            .onContinuousHover { phase in
                switch phase {
                case .active(let point):
                    hoverRatio = min(max(point.x / width, 0), 1)
                    isHovering = true
                case .ended:
                    isHovering = false
                }
            }
        }
        .frame(height: 46)
    }

    // MARK: 播放控制

    private func togglePlayback() {
        if player.isPlaying(url: audioURL) {
            player.stop()
            return
        }
        // 暂停中且还是同一个文件 → 继续播
        if player.isPaused && player.playingKey == audioURL.path {
            player.resume()
            return
        }

        player.stop()
        guard FileManager.default.fileExists(atPath: audioURL.path) else {
            Log(message: "AudioGenerationModal: 音频文件不存在")
            return
        }
        if let attrs = try? FileManager.default.attributesOfItem(atPath: audioURL.path),
           let size = attrs[.size] as? Int64,
           size < 1000 {
            Log(message: "AudioGenerationModal: 音频文件过小，可能不完整")
            return
        }
        if !player.play(url: audioURL, identifier: audioURL.path) {
            Log(message: "AudioGenerationModal: 播放失败")
        }
    }
}

// MARK: - 音频生成弹窗

struct AudioGenerationModal: View {

    @ObservedObject var vm: VoiceStudioViewModel
    @Binding var isPresented: Bool

    /// 接收统计单独订阅：高频更新只影响弹窗，不牵连工作台
    @ObservedObject private var stats = VoiceStudioViewModel.shared.stats

    /// 弹窗宽度（对齐设计稿 max-width: 560）
    private static let modalWidth: CGFloat = 560

    /// 接收中的统计心跳（对象持有，避免弹窗重建时计时器被重置）
    @StateObject private var ticker = StatsTicker()

    // 状态
    @State private var isCompleted: Bool = false
    @State private var audioName: String = ""
    @State private var audioDuration: TimeInterval = 0
    @State private var isExporting: Bool = false
    @State private var exportSuccess: Bool = false

    /// 完成瞬间冻结下来的展示数据。
    /// 这些值如果留在 body 里现算（读文件属性 / 跑 TextSplitter），
    /// 播放期间每次重绘都会重来一遍，纯属浪费。
    @State private var fileSizeText: String = "—"
    @State private var consumedPoints: Double = 0

    // 接收中的实时统计
    @State private var startedAt: Date = Date()
    @State private var elapsed: TimeInterval = 0
    @State private var displayBytes: Double = 0
    @State private var speed: Double = 0
    @State private var sampleBytes: Int = 0
    @State private var sampleDate: Date = Date()
    @State private var chunkLog: [ChunkLine] = []
    /// 完成瞬间冻结下来的统计（供完成条幅使用）
    @State private var finishedElapsed: TimeInterval = 0
    @State private var finishedChunkCount: Int = 0

    /// 日志节流：距上一行不足 200ms 时，把新数据块的大小并入该行
    /// （数据仍是真实到达量，只是不让它把弹窗刷爆）
    @State private var lastLogDate: Date = .distantPast

    @State private var remainingCredits: Double = 0
    /// 提示圆点的闪烁开关
    @State private var blink: Bool = false

    var body: some View {
        ZStack {
            // 遮罩
            Color.black.opacity(0.75)
                .ignoresSafeArea()
                .onTapGesture {
                    // 接收中不允许点遮罩关闭，避免误触打断观感（关闭按钮仍可用）
                    if isCompleted { dismiss() }
                }

            // 弹窗主体
            VStack(spacing: 0) {
                header

                if isGenerating {
                    generatingContent
                } else {
                    completedContent
                }

                footer
            }
            .frame(width: Self.modalWidth)
            .background(AppColor.bgSecondary)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.large))
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.large)
                    .stroke(AppColor.borderSubtle, lineWidth: 1)
            )
            .overlay(alignment: .top) {
                // 顶部一道强调高光（对应设计稿 modal::before）
                LinearGradient(
                    colors: [Color.clear, AppColor.accentPrimary.opacity(0.55), Color.clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(height: 1)
            }
            .shadow(color: .black.opacity(0.6), radius: 40, x: 0, y: 12)
        }
        .animation(.easeInOut(duration: 0.35), value: isGenerating)
        .animation(.easeInOut(duration: 0.35), value: isCompleted)
        // 弹窗与工作台的 NSTextView 共处同一窗口，鼠标从文本域移上来时光标可能还停留在 I-beam。
        // 这里在弹窗出现的当下先复位成箭头，之后由各控件的 hover 接管。
        .onAppear {
            NSCursor.arrow.set()
            // 焦点若还停在工作台的 NSTextView 上，先交还给窗口：
            // 否则弹窗期间键盘事件会被下层文本域吃掉，鼠标光标也可能被它带成 I-beam
            if let window = NSApp.keyWindow ?? NSApp.mainWindow,
               window.firstResponder is NSTextView {
                window.makeFirstResponder(nil)
            }
        }
        .onExitCommand { dismiss() }
        .onAppear {
            audioName = generateDefaultAudioName()
            // 与后台接收卡片共用 VM 记下的开始时刻：中途关掉再回来，已用时不归零
            startedAt = vm.generationStartedAt ?? Date()
            sampleBytes = stats.receivedBytes
            sampleDate = Date()
            refreshCredits()
            refreshCompletedInfo()
            // 被「后台接收完成」的信号重新唤起时，stats.progress 已经是 1.0，
            // onChange(of: stats.progress) 不会再触发一次 —— 这里直接落到完成态，
            // 否则会停在"正在接收"的空壳界面上（此时 vm.isGenerating 已是 false）。
            if vm.generatedAudioURL != nil, !vm.isGenerating {
                // 时长同理：onChange(of: vm.generatedAudioDuration) 不会再触发一次
                audioDuration = vm.generatedAudioDuration
                isCompleted = true
                return
            }
            blink = true
            ticker.start()
        }
        .onDisappear {
            ticker.stop()
            AudioPreviewPlayer.shared.stop()
        }
        .onReceive(ticker.$now) { now in
            guard isGenerating else { return }
            tick(now)
        }
        .onChange(of: stats.receivedBytes) { oldValue, newValue in
            let delta = newValue - oldValue
            guard delta > 0 else { return }
            // 段号取真实段数（与 WebSocket 每次 onAudio 一一对应）
            appendChunkLog(chunkIndex: stats.receivedChunks, size: delta, at: Date())
        }
        .onChange(of: stats.progress) { _, newProgress in
            guard newProgress >= 1.0 else { return }
            finishedElapsed = elapsed
            finishedChunkCount = stats.receivedChunks
            ticker.stop()
            refreshCompletedInfo()
            withAnimation { isCompleted = true }
        }
        .onChange(of: vm.generatedAudioDuration) { _, newDuration in
            if newDuration > 0 { audioDuration = newDuration }
        }
    }

    // MARK: - 计算属性

    private var isGenerating: Bool { vm.isGenerating && !isCompleted }

    private var currentVoice: Voice? { vm.voice }

    /// 实时码率（kbps），还没有数据时显示占位
    private var bitrateText: String {
        guard speed > 0 else { return "— kbps" }
        return "%d kbps".localized(max(1, Int(speed * 8 / 1000)))
    }

    // MARK: - 头部

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        isCompleted
                        ? AppColor.statusSuccess.opacity(0.12)
                        : AppColor.accentPrimary.opacity(0.12)
                    )
                    .frame(width: 28, height: 28)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(
                                isCompleted
                                ? AppColor.statusSuccess.opacity(0.28)
                                : AppColor.accentPrimary.opacity(0.25),
                                lineWidth: 1
                            )
                    )
                Image(systemName: isCompleted ? "checkmark.circle.fill" : "music.quarternote.3")
                    .symbolEffect(.pulse)
                    .font(.system(size: isCompleted ? 15 : 14, weight: isCompleted ? .bold : .regular))
                    .foregroundStyle(isCompleted ? AppColor.statusSuccess : AppColor.textPrimary)
            }

            Text(isCompleted ? "音频生成完成".localized() : "正在接收".localized())
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppColor.textPrimary)
                
            Spacer()

            // 关闭：只收起弹窗，接收任务仍在 ViewModel 里跑
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AppColor.textTertiary)
                    .frame(width: 26, height: 26)
                    .background(Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
            .help("关闭（后台继续接收）".localized())
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 15)
        .background(AppColor.bgTertiary.opacity(0.45))
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AppColor.borderSubtle)
                .frame(height: 0.5)
        }
    }

    // MARK: - 状态一：接收中

    private var generatingContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            StreamingWaveView()

            IndeterminateProgressBar()
                .padding(.top, 16)

            // 累积字节数 + 速率（单位按 1000 进制自适应 B/KB/MB/GB）
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                let rx = autoByteUnit(displayBytes)
                Text(rx.value)
                    .font(.system(size: 26, weight: .semibold))
                    .fontDesign(.monospaced)
                    .foregroundStyle(AppColor.textPrimary)
                Text("%@ 已接收".localized(rx.unit))
                    .font(.system(size: 13))
                    .foregroundStyle(AppColor.textSecondary)
                Spacer()
                let sp = autoByteUnit(speed)
                Text("↑ \(sp.value) \(sp.unit)/s")
                    .font(.system(size: 11))
                    .fontDesign(.monospaced)
                    .foregroundStyle(AppColor.accentPrimary)
            }
            .padding(.top, 16)

            // 提示
            HStack(spacing: 6) {
                Circle()
                    .fill(AppColor.accentPrimary)
                    .frame(width: 5, height: 5)
                    .opacity(blink ? 1 : 0.25)
                    .animation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true), value: blink)
                Text("音频数据持续累积中，接收完成后可立即试听".localized())
                    .font(.system(size: 11.5))
                    .foregroundStyle(AppColor.textTertiary)
            }
            .padding(.top, 8)

            // 三项统计
            HStack(spacing: 10) {
                StatCell(title: "数据块".localized(), value: "%d 段".localized(stats.receivedChunks))
                StatCell(title: "已用时".localized(), value: formatClock(elapsed))
                StatCell(title: "当前码率".localized(), value: bitrateText)
            }
            .padding(.top, 16)

            // 数据块到达日志（只保留最近 4 条）
            VStack(alignment: .leading, spacing: 4) {
                Spacer(minLength: 0)
                ForEach(chunkLog) { line in
                    HStack(spacing: 5) {
                        Text("#\(String(format: "%03d", line.index))")
                            .foregroundStyle(AppColor.textSecondary)
                        Text("· +\(formatDataSize(line.size))")
                        Text("✓ 已写入缓冲区".localized())
                            .foregroundStyle(AppColor.statusSuccess)
                    }
                    .font(.system(size: 11))
                    .fontDesign(.monospaced)
                    .foregroundStyle(AppColor.textTertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 74)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.black.opacity(0.22))
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.small)
                    .stroke(AppColor.borderSubtle, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.small))
            .padding(.top, 14)
        }
        .padding(EdgeInsets(top: 22, leading: 20, bottom: 20, trailing: 20))
    }

    // MARK: - 状态二：完成

    private var completedContent: some View {
        VStack(spacing: 14) {
            nameRow
            metaGrid
            voiceCard
            // 播放器独立成订阅播放器的子视图：10Hz 的进度刷新只重绘它自己，
            // 不会带着四宫格 / 音色卡 / 积分行一起重算
            if let url = vm.generatedAudioURL {
                ModalAudioPlayer(audioURL: url, duration: audioDuration)
            }
            costRow
        }
        .padding(20)
    }

    private var nameRow: some View {
        HStack(spacing: 8) {
            TextField("", text: $audioName)
                .textFieldStyle(.plain)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppColor.textPrimary)
                .padding(.horizontal, 11)
                .padding(.vertical, 9)
                .background(AppColor.bgTertiary)
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.small)
                        .stroke(AppColor.borderSubtle, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.small))

            Text(vm.selectedFormat.uppercased())
                .font(.system(size: 11))
                .fontDesign(.monospaced)
                .foregroundStyle(AppColor.accentPrimary)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(AppColor.accentPrimary.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(AppColor.accentPrimary.opacity(0.22), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 5))
        }
    }

    private var metaGrid: some View {
        HStack(spacing: 10) {
            StatCell(title: "大小".localized(), value: fileSizeText)
            StatCell(title: "采样率".localized(), value: formatSampleRate(vm.sampleRate))
            StatCell(title: "格式".localized(), value: vm.selectedFormat.uppercased())
            StatCell(title: "时长".localized(), value: formatClock(audioDuration))
        }
    }

    private var voiceCard: some View {
        HStack(spacing: 11) {
            if let voice = currentVoice {
                ZStack {
                    RoundedRectangle(cornerRadius: 11)
                        .fill(AppColor.accentPrimary.opacity(0.16))
                        .frame(width: 40, height: 40)
                        .overlay(
                            RoundedRectangle(cornerRadius: 11)
                                .stroke(AppColor.accentPrimary.opacity(0.3), lineWidth: 1)
                        )
                    Text(voice.localizedAvatar)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AppColor.accentGlow)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(voice.localizedName)
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(AppColor.textPrimary)
                        if voice.isPremium {
                            Text("⭐ 旗舰".localized())
                                .font(.system(size: 10))
                                .foregroundStyle(AppColor.accentPrimary)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 1)
                                .background(AppColor.accentPrimary.opacity(0.14))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 4)
                                        .stroke(AppColor.accentPrimary.opacity(0.25), lineWidth: 1)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                    }

                    if !voice.localizedDesc.isEmpty {
                        Text(voice.localizedDesc)
                            .font(.system(size: 11.5))
                            .foregroundStyle(AppColor.textSecondary)
                            .lineLimit(1)
                    }

                    HStack(spacing: 4) {
                        Text("适用场景".localized())
                        Text(voice.localizedScene)
                            .foregroundStyle(AppColor.textSecondary)
                        Text("· \(voice.lang.displayName)")
                        if !voice.localizedGender.isEmpty {
                            Text("· \(voice.localizedGender)")
                        }
                        if let age = voice.age {
                            Text("· " + "%d 岁".localized(age))
                        }
                    }
                    .font(.system(size: 10.5))
                    .foregroundStyle(AppColor.textTertiary)
                }

                Spacer()
            }
        }
        .padding(12)
        .background(
            LinearGradient(
                colors: [AppColor.accentPrimary.opacity(0.09), AppColor.accentPrimary.opacity(0.02)],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.medium)
                .stroke(AppColor.accentPrimary.opacity(0.22), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium))
    }

    private var costRow: some View {
        HStack(spacing: 10) {
            Text("💎")
                .font(.system(size: 13))
            VStack(alignment: .leading, spacing: 1) {
                Text("本次消耗积分".localized())
                    .font(.system(size: 11.5))
                    .foregroundStyle(AppColor.textTertiary)
                Text("−\(formatCredits(consumedPoints))")
                    .font(.system(size: 15, weight: .semibold))
                    .fontDesign(.monospaced)
                    .foregroundStyle(AppColor.accentPrimary)
            }
            Spacer()
            Text("剩余 %@ 积分".localized(formatCredits(remainingCredits)))
                .font(.system(size: 11))
                .fontDesign(.monospaced)
                .foregroundStyle(AppColor.textTertiary)
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .background(Color.white.opacity(0.025))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.small)
                .stroke(AppColor.borderSubtle, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.small))
    }

    // MARK: - 底部

    private var footer: some View {
        HStack(spacing: 10) {
            if isGenerating {
                Spacer()
            } else {
                Spacer()
                Button { exportAudio() } label: {
                    Text(exportTitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AppColor.textPrimary)
                        .frame(height: 36)
                        .padding(.horizontal, 16)
                        .background(AppColor.bgElevated)
                        .overlay(
                            RoundedRectangle(cornerRadius: AppRadius.small)
                                .stroke(AppColor.borderMedium, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.small))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
                .disabled(isExporting)

                Button {
                    saveAudioNameIfNeeded()
                    dismiss()
                } label: {
                    Text("完成".localized())
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppColor.bgPrimary)
                        .frame(height: 36)
                        .padding(.horizontal, 16)
                        .background(AppColor.accentPrimary)
                        .clipShape(RoundedRectangle(cornerRadius: AppRadius.small))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(AppColor.bgTertiary.opacity(0.4))
        .overlay(alignment: .top) {
            Rectangle()
                .fill(AppColor.borderSubtle)
                .frame(height: 0.5)
        }
    }

    private var exportTitle: String {
        if isExporting { return "导出中…".localized() }
        if exportSuccess { return "✓ 已导出".localized() }
        return "⬇ 导出".localized()
    }

    // MARK: - 行为

    /// 关闭弹窗：只收起界面，ViewModel 里的生成任务继续跑
    private func dismiss() {
        isPresented = false
    }

    /// 每 0.25s：平滑追赶字节数；每 0.5s 重算一次速率
    private func tick(_ now: Date) {
        elapsed = now.timeIntervalSince(startedAt)

        let target = Double(stats.receivedBytes)
        let delta = target - displayBytes
        if delta > 0 {
            displayBytes = min(target, displayBytes + max(delta * 0.35, 8))
        } else {
            displayBytes = target
        }

        let interval = now.timeIntervalSince(sampleDate)
        guard interval >= 0.5 else { return }
        let instant = max(0, Double(stats.receivedBytes - sampleBytes)) / interval
        // 首次取样区间可能很短，直接采用瞬时值，之后做指数平滑
        speed = speed <= 0 ? instant : speed * 0.4 + instant * 0.6
        sampleBytes = stats.receivedBytes
        sampleDate = now
    }

    /// 追加一条数据块日志。
    ///
    /// 数据来源是 `stats.receivedBytes`，即 BailianTTSService 每次
    /// `onAudio(binaryData)` 回调里 `audioChunk.count` 的真实累加值，
    /// 不是模拟出来的。这里只做一件事：200ms 内到达的多块合并成一行
    /// （WebSocket 一秒可能来几十上百块，逐块刷会把界面刷爆）；
    /// 段号用 `stats.receivedChunks`，是真实段数，不受合并影响。
    private func appendChunkLog(chunkIndex: Int, size: Int, at date: Date) {
        guard size > 0 else { return }

        if date.timeIntervalSince(lastLogDate) >= 0.2 {
            chunkLog.append(ChunkLine(index: chunkIndex, size: size))
            if chunkLog.count > 4 { chunkLog.removeFirst() }
            lastLogDate = date
        } else if let last = chunkLog.indices.last {
            let merged = chunkLog[last].size + size
            chunkLog[last] = ChunkLine(index: chunkIndex, size: merged)
        }
    }

    private func refreshCredits() {
        Task { @MainActor in
            remainingCredits = CreditsService.shared.balance
        }
    }

    /// 生成完成后一次性算出展示用的静态数据。
    ///
    /// 文件大小要读磁盘属性、积分要跑一遍字数统计，放在 body 里现算的话
    /// 播放期间每 0.1s 就要重来一次，白烧 CPU。
    private func refreshCompletedInfo() {
        refreshCredits()
        consumedPoints = vm.estimatedPoints
        if let url = vm.generatedAudioURL,
           let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = attrs[.size] as? Int64 {
            fileSizeText = formatDataSize(Int(size))
        } else {
            fileSizeText = formatDataSize(stats.receivedBytes)
        }
    }

    /// 默认音频名：优先取输入文本的前 10 个字符，空则退回时间戳。
    ///
    /// 两条细节：
    /// 1. 取的是 `plainText` —— 情感 / 拟声标签是编辑器里的 UI 装饰
    ///    （"...笑声..."），不该混进文件名。
    /// 2. 文本是自由输入，必须先过一遍 `sanitizeFileName` 洗掉文件名不允许的字符
    ///    （`/`、`:` 等），这个名不只是显示，导出时还会直接变成保存面板的默认文件名。
    private func generateDefaultAudioName() -> String {
        // 换行折叠成空格：否则"前 10 个字符"里可能一个有效字符都没有
        let source = vm.plainText
            .components(separatedBy: .newlines)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        // 先截 40 再清洗：10 个名额可能被非法字符占掉，留点余量；
        // 顺带把正则的开销钉在常数级，长篇台词也不受影响
        let cleaned = sanitizeFileName(String(source.prefix(40)))
        let prefix = String(cleaned.prefix(10))
            .trimmingCharacters(in: CharacterSet(charactersIn: "-").union(.whitespaces))
        if !prefix.isEmpty { return prefix }

        // 兜底：文本为空，或洗完什么都不剩
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        return sanitizeFileName("音频_" + formatter.string(from: Date()))
    }

    /// 保存编辑后的音频名称
    private func saveAudioNameIfNeeded() {
        guard let audioId = vm.generatedAudioId else { return }
        let nameToSave = audioName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !nameToSave.isEmpty {
            ProjectService.shared.renameAudio(id: audioId, displayName: nameToSave)
        }
    }

    // MARK: - 导出

    /// 导出音频到用户选择的位置
    private func exportAudio() {
        guard let sourceURL = vm.generatedAudioURL else {
            Log(message: "AudioGenerationModal: 无音频文件可导出")
            return
        }

        isExporting = true

        let defaultFileName = "\(audioName).\(sourceURL.pathExtension)"

        let savePanel = NSSavePanel()
        savePanel.title = "导出音频".localized()
        savePanel.nameFieldStringValue = defaultFileName
        savePanel.canCreateDirectories = true
        savePanel.allowedContentTypes = [.audio]

        savePanel.begin { [self] response in
            if response == .OK, let destinationURL = savePanel.url {
                do {
                    if FileManager.default.fileExists(atPath: destinationURL.path) {
                        try FileManager.default.removeItem(at: destinationURL)
                    }
                    try FileManager.default.copyItem(at: sourceURL, to: destinationURL)

                    Log(message: "AudioGenerationModal: 导出成功 - \(destinationURL.path)")
                    NSWorkspace.shared.selectFile(
                        destinationURL.path,
                        inFileViewerRootedAtPath: destinationURL.deletingLastPathComponent().path
                    )

                    DispatchQueue.main.async {
                        isExporting = false
                        exportSuccess = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            exportSuccess = false
                        }
                    }
                } catch {
                    Log(message: "AudioGenerationModal: 导出失败 - \(error.localizedDescription)")
                    isExporting = false
                }
            } else {
                isExporting = false
            }
        }
    }
}
