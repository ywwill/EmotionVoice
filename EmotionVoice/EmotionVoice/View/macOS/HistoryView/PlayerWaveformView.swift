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
private enum WaveMetrics {
    /// 波形区高度
    static let height: CGFloat = 84
    /// 柱间距
    static let gap: CGFloat = 2
    /// 柱宽 + 间距的目标步长，用来按宽度推算柱子数
    static let pitch: CGFloat = 6
    static let minBars: Int = 28
    static let maxBars: Int = 118
}

struct PlayerWaveformView: View {

    @ObservedObject var player: AudioPreviewPlayer

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
                        isHovered: isHovering || isScrubbing
                    )
                    .frame(width: width, height: WaveMetrics.height)

                    if isHovering || isScrubbing {
                        hoverBubble
                            .offset(x: min(max(width * hoverRatio - 26, 0), max(width - 52, 0)))
                            .offset(y: -12)
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
            // 顶部留白给悬停气泡
            .frame(height: WaveMetrics.height)
            .padding(.top, 14)

            timeRow
                .padding(.top, 6)
        }
    }

    // MARK: - 时间行

    private var timeRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 0) {
            Text(PlayerTextMetrics.formatTime(displayTime))
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(AppColor.textSecondary)

            Spacer()

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
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(AppColor.textPrimary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(AppColor.bgElevated)
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(AppColor.borderMedium, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .allowsHitTesting(false)
    }

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
}

// MARK: - 波形绘制

/// 单图层 Canvas：柱子数按宽度自适应，柱高用固定包络推导（不随播放变化，可稳定复现）
private struct WaveformCanvas: View {

    let progress: Double
    let isHovered: Bool

    var body: some View {
        Canvas { ctx, size in
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
                let h = Self.barHeight(at: t) * size.height
                let bar = Path(
                    roundedRect: CGRect(x: x, y: (size.height - h) / 2, width: barWidth, height: h),
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
                        startPoint: .zero,
                        endPoint: CGPoint(x: 0, y: size.height)
                    )
                )
            }

            // 播放头：外发光 + 竖线 + 顶部圆点
            let headX = min(max(cut, 0), size.width)
            ctx.fill(
                Path(roundedRect: CGRect(x: headX - 5, y: 12, width: 10, height: size.height - 18), cornerRadius: 5),
                with: .color(AppColor.accentPrimary.opacity(0.18))
            )
            ctx.fill(
                Path(roundedRect: CGRect(x: headX - 1, y: 16, width: 2, height: size.height - 22), cornerRadius: 1),
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
