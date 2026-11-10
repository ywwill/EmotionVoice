//
//  PlayerWaveformView.swift
//  EmotionVoice
//
//  播放详情里的波形进度条（点击定位 + 拖动擦洗 + 悬停时间气泡）
//
//  性能要点（这个视图是播放时唯一会 10Hz 重绘的地方）：
//  1. 所有柱子用 `Canvas` 一次性画完 —— 背景层一条 Path、已播放层一条 Path，各一次 fill。
//     旧实现是两层 `ForEach` 共 200+ 个 `RoundedRectangle`，再叠一个 `.mask()`
//     做进度裁切；mask 会强制离屏渲染，而 200+ 个 SwiftUI 视图每 0.1s 重新 diff + 布局
//     一次，是主线程被打满的主因。
//  2. 只有这里订阅 `AudioPreviewPlayer`。父级 `AudioPlayerDetailView` 用 `let` 持有播放器，
//     于是元信息卡、原文区这些重内容在播放期间完全不参与重绘。
//

import SwiftUI

/// 波形几何常量（对齐 UI/audio-player.html）
///
/// ⚠️ 高度是「文本区能拿多少」的直接变量：详情页竖向是
/// 波形 → 走带 → 倍速行 → 属性行 → 原文卡片 依次固定堆叠，
/// 上面每多 1pt 都是从原文区扣的。所以这里刻意压到 78（原 96），
/// 刻度带同步 12 → 10，波形本体仍有 68pt，柱形起伏照样看得清。
private enum WaveMetrics {
    /// 绘制区总高：上方 12px 给句边界刻度，下面 66px 是波形
    static let height: CGFloat = 78
    /// 句边界刻度区高度（保持 12：当前句的刻度要长到 11pt，再压就顶到波形上了）
    static let ticksHeight: CGFloat = 12
    /// 柱间距
    static let gap: CGFloat = 2
    /// 柱宽 + 间距的目标步长，用来按宽度推算柱子数
    static let pitch: CGFloat = 6
    static let minBars: Int = 28
    /// 上限只防超宽屏无限加柱子。详情页已取消 760 宽上限、改成撑满剩余空间，
    /// 原来 118 的封顶会让宽窗口下柱距被拉到 10pt 以上（明显变稀），
    /// 所以放宽到 240：到 1440pt 宽为止柱距都稳定在 pitch=6（柱宽 4 + 间距 2）。
    /// Canvas 是单 Path 一次 fill，柱子数量对性能没有影响。
    static let maxBars: Int = 240
}

struct PlayerWaveformView: View {

    @ObservedObject var player: AudioPreviewPlayer
    /// 字级时间轴；nil 时不画句边界刻度、不显示句定位信息（降级态）
    let timeline: AudioTimeline?

    @State private var isScrubbing: Bool = false
    @State private var scrubProgress: Double = 0
    @State private var isHovering: Bool = false
    @State private var hoverRatio: CGFloat = 0
    @State private var showsRemaining: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                let width = max(geo.size.width, 1)

                ZStack(alignment: .topLeading) {
                    WaveformCanvas(
                        progress: displayProgress,
                        isHovered: isHovering || isScrubbing,
                        ticks: sentenceTicks,
                        activeTick: activeTickIndex
                    )
                    .frame(width: width, height: WaveMetrics.height)

                    // 刻度热区：只有 12pt 高，落在波形上方，不抢拖动擦洗的手势
                    ForEach(Array(sentenceTicks.enumerated()), id: \.offset) { index, ratio in
                        Color.clear
                            .frame(width: 12, height: WaveMetrics.ticksHeight)
                            .contentShape(Rectangle())
                            .offset(x: min(max(width * ratio - 6, 0), max(width - 12, 0)))
                            .onTapGesture { seekToSentence(index) }
                            .help(tickHelp(index))
                    }

                    if isHovering || isScrubbing {
                        // ⚠️ 气泡必须整体待在刻度带（0…ticksHeight）**上方**：
                        // 之前 offset -10 时气泡底边落在 y≈+10，正好压住句边界刻线，
                        // 拖动时看不清当前落在哪一句。现在按「气泡高 18 + 2pt 间隙」上移 20，
                        // 底边固定在 y=-2，与刻线之间留出缝，同时不超出顶部 20pt 留白去盖住走带。
                        hoverBubble
                            .offset(x: min(max(width * hoverRatio - Self.bubbleWidth / 2, 0), max(width - Self.bubbleWidth, 0)))
                            .offset(y: -Self.bubbleLift)
                    }
                }
                .contentShape(Rectangle())
                .gesture(scrubGesture(width: width))
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
            // 顶部留白 = 悬停气泡的抬升量，气泡整块待在这里面，不与刻线 / 走带重叠
            .frame(height: WaveMetrics.height)
            .padding(.top, Self.bubbleLift)

            timeRow
                .padding(.top, 4)
        }
    }

    // MARK: - 时间行

    private var timeRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(PlayerTextMetrics.formatTime(displayTime))
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(AppColor.textSecondary)

            Spacer(minLength: 8)

            if let timeline, timeline.isAligned {
                Text(activeRangeText(at: displayTime, timeline: timeline))
                    .font(.system(size: 11))
                    .foregroundStyle(AppColor.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            Button {
                showsRemaining.toggle()
            } label: {
                Text(showsRemaining
                     ? "-" + PlayerTextMetrics.formatTime(remainingTime)
                     : PlayerTextMetrics.formatTime(player.duration))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(AppColor.textTertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private var hoverBubble: some View {
        Text(PlayerTextMetrics.formatTime(hoverRatio * player.duration))
            .font(.system(size: 10.5, design: .monospaced))
            .foregroundStyle(AppColor.textPrimary)
            .padding(.horizontal, 6)
            .frame(width: Self.bubbleWidth, height: Self.bubbleHeight)
            .background(AppColor.bgElevated)
            .overlay(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(AppColor.borderMedium, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            .allowsHitTesting(false)
    }

    /// 悬停/拖动时间气泡：固定尺寸 + 定宽，才能让「居中于指针」和「不压刻线」
    /// 都靠常量算准（宽度随文字变会导致气泡左右偏半个字）
    private static let bubbleHeight: CGFloat = 18
    private static let bubbleWidth: CGFloat = 46
    /// 气泡上移量 = 气泡高 + 2pt 间隙 → 气泡底边恒在 y=-2，不压句边界刻线
    private static let bubbleLift: CGFloat = 20

    // MARK: - 手势

    private func scrubGesture(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                let p = min(max(value.location.x / width, 0), 1)
                if !isScrubbing { isScrubbing = true }
                hoverRatio = p
                scrubProgress = p
                player.seek(to: p * player.duration)
            }
            .onEnded { _ in
                isScrubbing = false
            }
    }

    // MARK: - 计算属性

    private var displayProgress: Double {
        let raw = isScrubbing ? scrubProgress : player.progress
        guard raw.isFinite else { return 0 }
        return min(max(raw, 0), 1)
    }

    private var displayTime: Double {
        isScrubbing ? scrubProgress * player.duration : player.currentTime
    }

    private var remainingTime: Double {
        max(0, player.duration - displayTime)
    }

    // MARK: - 句边界刻度（对齐 UI/audio-player.html 的 .sentence-ticks）

    /// 每句起点在波形上的归一化位置。无时间轴时为空 → 刻度区整块不画。
    private var sentenceTicks: [CGFloat] {
        guard let timeline, timeline.isAligned else { return [] }
        // 用 timeline.duration 归一化而不是 player.duration：
        // sidecar 里的时长就是生成时的实际音频时长，两者不一致时以它为准才不会被拉偏。
        let total = max(0.001, timeline.duration)
        return timeline.sentences.map { cue in
            CGFloat(min(max(cue.begin / total, 0), 1))
        }
    }

    /// 当前句序号；-1 表示句间停顿 / 播放结束 / 没有时间轴（都不高亮任何刻度）
    private var activeTickIndex: Int {
        guard let timeline else { return -1 }
        return timeline.location(at: displayTime).index ?? -1
    }

    private func seekToSentence(_ index: Int) {
        guard let timeline, timeline.sentences.indices.contains(index) else { return }
        player.seek(to: timeline.sentences[index].begin)
    }

    private func tickHelp(_ index: Int) -> String {
        guard let timeline, timeline.sentences.indices.contains(index) else { return "" }
        return "第 %d 句 · %@".localized(index + 1, PlayerTextMetrics.formatPrecise(timeline.sentences[index].begin))
    }

    /// 时间行中间那句「现在读到哪」：第 N/M 句 · 起 – 止；句间停顿显示停顿长度与下一句
    private func activeRangeText(at t: Double, timeline: AudioTimeline) -> String {
        guard timeline.isAligned else {
            return "无时间戳 · 文本与时间轴未建立映射".localized()
        }
        let located = timeline.location(at: t)
        if let index = located.index, timeline.sentences.indices.contains(index) {
            let cue = timeline.sentences[index]
            return "第 %d / %d 句 · %@ – %@".localized(
                index + 1,
                timeline.sentences.count,
                PlayerTextMetrics.formatPrecise(cue.begin),
                PlayerTextMetrics.formatPrecise(cue.end)
            )
        }
        guard let next = located.next, timeline.sentences.indices.contains(next) else {
            return "播放结束".localized()
        }
        // 停顿长度 = 下一句起点 - 上一句终点（首句之前从 0 算起）
        let prevEnd = located.previous.flatMap { timeline.sentences.indices.contains($0) ? timeline.sentences[$0].end : nil } ?? 0
        let gap = max(0, timeline.sentences[next].begin - prevEnd)
        return "句间停顿 %@ · 下一句 %d".localized(
            String(format: "%.1fs", gap),
            next + 1
        )
    }
}

// MARK: - 波形绘制

/// 单图层 Canvas：柱子数按宽度自适应，柱高用固定包络推导（不随播放变化，可稳定复现）
private struct WaveformCanvas: View {

    let progress: Double
    let isHovered: Bool
    /// 句起点归一化位置（0...1）；空数组表示降级态，不画刻度
    let ticks: [CGFloat]
    /// 当前句序号；-1 表示停顿 / 降级态
    let activeTick: Int

    var body: some View {
        Canvas { ctx, size in
            // 顶部 12pt 单独留给句边界刻度，波形只在下方绘制
            let waveTop = WaveMetrics.ticksHeight
            let waveHeight = max(1, size.height - waveTop)
            let n = Self.barCount(for: size.width)
            let gap = WaveMetrics.gap
            let barWidth = max(2, (size.width - gap * CGFloat(n - 1)) / CGFloat(n))
            let corner = min(barWidth / 2, 2)
            let cut = size.width * CGFloat(min(max(progress, 0), 1))

            // 背景层：全部柱子合成一条 Path，只 fill 一次
            var background = Path()
            // 已播放层：只收进度线左侧的柱子，同样只 fill 一次
            var played = Path()
            var x: CGFloat = 0

            for i in 0..<n {
                let t = n > 1 ? Double(i) / Double(n - 1) : 0
                let h = Self.barHeight(at: t) * waveHeight
                let bar = Path(
                    roundedRect: CGRect(x: x, y: waveTop + (waveHeight - h) / 2, width: barWidth, height: h),
                    cornerRadius: corner
                )
                background.addPath(bar)
                if x + barWidth * 0.5 <= cut {
                    played.addPath(bar)
                }
                x += barWidth + gap
            }

            ctx.fill(background, with: .color(Color.white.opacity(isHovered ? 0.20 : 0.13)))

            if !played.isEmpty {
                let gradient = Gradient(colors: [AppColor.accentGlow, AppColor.accentSecondary])
                ctx.fill(
                    played,
                    with: .linearGradient(
                        gradient,
                        startPoint: CGPoint(x: 0, y: waveTop),
                        endPoint: CGPoint(x: 0, y: size.height)
                    )
                )
            }

            // 句边界刻度：2pt 宽 / 8pt 高 / 距顶 2pt；当前句加亮并长到 11pt
            // （与 HTML .tick / .tick.current 完全一致，逐个 fill 但每句只有一次，量级是 O(句数)）
            for (index, ratio) in ticks.enumerated() {
                let isCurrent = index == activeTick
                let tickX = min(max(size.width * ratio, 1), size.width - 1)
                let height: CGFloat = isCurrent ? 11 : 8
                let top: CGFloat = isCurrent ? 0 : 2
                ctx.fill(
                    Path(
                        roundedRect: CGRect(x: tickX - 1, y: top, width: 2, height: height),
                        cornerRadius: 1
                    ),
                    with: .color(isCurrent ? AppColor.accentGlow : AppColor.accentLine)
                )
            }

            // 播放头：外发光 + 竖线 + 顶部圆点
            let headX = min(max(cut, 0), size.width)
            ctx.fill(
                Path(roundedRect: CGRect(x: headX - 5, y: waveTop, width: 10, height: waveHeight - 6), cornerRadius: 5),
                with: .color(AppColor.accentPrimary.opacity(0.18))
            )
            ctx.fill(
                Path(roundedRect: CGRect(x: headX - 1, y: waveTop + 4, width: 2, height: waveHeight - 10), cornerRadius: 1),
                with: .color(AppColor.accentPrimary)
            )
            ctx.fill(
                Path(ellipseIn: CGRect(x: headX - 5, y: 4, width: 10, height: 10)),
                with: .color(AppColor.accentPrimary)
            )
        }
    }

    private static func barCount(for width: CGFloat) -> Int {
        min(WaveMetrics.maxBars, max(WaveMetrics.minBars, Int(width / WaveMetrics.pitch)))
    }

    /// 归一化柱高（0.12 - 1.0）：正弦包络叠一层确定性噪声，模拟语音起伏
    private static func barHeight(at t: Double) -> CGFloat {
        let envelope = 0.42 + 0.34 * sin(t * 11.3) + 0.16 * sin(t * 29.7 + 1.4)
        let v = envelope * 0.72 + hashNoise(Int(t * 1000)) * 0.34
        return CGFloat(min(max(v, 0.12), 1.0))
    }

    /// 与 index 绑定的伪随机数（0 - 1），避免用全局随机导致每次重绘波形都在跳
    private static func hashNoise(_ i: Int) -> Double {
        let x = sin(Double(i) * 12.9898) * 43758.5453
        return x - floor(x)
    }
}
