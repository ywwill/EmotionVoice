//
//  GenerationDialogControls.swift
//  iOSEmora
//
//  生成弹窗内的子视图：不确定进度条 / 实时波形 / 完成态播放器 / 频谱条。
//  从 GenerationDialog.swift 拆出：代码逐字搬移，未改动任何逻辑（原 private 类型按需放开为 internal）。
//

import SwiftUI
import Combine

// MARK: - 子视图

/// 不确定进度条
struct IndeterminateBar: View {
    @Environment(\.aurora) private var c
    @State private var phase: CGFloat = -0.35

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(c.slot)
                Capsule()
                    .fill(AuroraDecor.popGradient)
                    .frame(width: geo.size.width * 0.35)
                    .offset(x: geo.size.width * phase * 1.9)
            }
        }
        .frame(height: 3)
        .clipShape(Capsule())
        .onAppear {
            withAnimation(.linear(duration: 1.15).repeatForever(autoreverses: false)) {
                phase = 1.0
            }
        }
    }
}

/// 实时波形
struct StreamingWaveBars: View {
    var barCount: Int = 24
    var tint: Color

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.09)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 5) {
                ForEach(0..<barCount, id: \.self) { i in
                    let h = Self.height(index: i, time: t)
                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                        .fill(tint.opacity(0.35 + 0.55 * h))
                        .frame(width: 5, height: max(6, CGFloat(h) * 66))
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    /// 确定性包络（与 macOS 波形同一公式）
    private static func height(index: Int, time: TimeInterval) -> Double {
        let p = Double(index) * 0.42 + time * 2.6
        let v = 0.42 + 0.34 * sin(p) + 0.16 * sin(p * 2.6 + 1.4)
        return min(max(v, 0.12), 1)
    }
}

// MARK: - 完成态播放器（订阅隔离）
struct ModalAudioPlayer: View {
    @Environment(\.aurora) private var c
    @ObservedObject private var player = AudioPreviewPlayer.shared

    let audioURL: URL?
    let fallbackDuration: Double
    let samples: [CGFloat]
    let barCount: Int

    @State private var scrubProgress: CGFloat? = nil

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 13) {
                Button {
                    if let url = audioURL {
                        if player.isPlaying(url: url) { player.pause() } else { player.play(url: url) }
                    }
                } label: {
                    ZStack {
                        Circle()
                            .fill(c.ctaGradient)
                            .frame(width: 48, height: 48)
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 19, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 1) {
                    Text(formatDuration(player.currentTime))
                        .font(.system(size: 15, weight: .semibold, design: .monospaced))
                        .foregroundStyle(c.textPrimary)
                    Text(formatDuration(max(fallbackDuration, player.duration)))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(c.textTertiary)
                }

                Spacer(minLength: 0)

                HStack(spacing: 6) {
                    Circle()
                        .fill(player.isPlaying ? c.success : c.textTertiary)
                        .frame(width: 7, height: 7)
                    Text(player.isPlaying ? "正在播放".localized() : "已暂停".localized())
                        .font(.system(size: 11.5))
                        .foregroundStyle(c.textSecondary)
                }
            }

            waveformStrip
                .frame(height: 36)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: AuroraRadius.md, style: .continuous)
                .fill(c.surface2)
                .overlay(
                    RoundedRectangle(cornerRadius: AuroraRadius.md, style: .continuous)
                        .strokeBorder(c.line, lineWidth: 0.5)
                )
        )
        // ⚠️ 生成完成**不自动起播**：后台接收完成时 `RootTabView` 会按
        //    `generationCompletedSignal` 自动把弹窗唤回完成态，用户可能根本没看屏幕，
        //    这时突然出声很突兀。与 macOS `AudioGenerationModal` 一致，
        //    播放只由下面的播放按钮触发。
        //    关闭弹窗仍停播：这个播放器走 `AudioPreviewPlayer` 私有路径，不挂
        //    `NowPlayingStore`，没有 mini player 接管，继续播会变成「无 UI 控制的声音」。
        .onDisappear { player.stop() }
    }

    /// 真实频谱条：振幅来自音频文件本身，可拖动定位
    private var waveformStrip: some View {
        GeometryReader { geo in
            WaveformBars(samples: samples,
                         barCount: barCount,
                         progress: scrubProgress ?? CGFloat(min(max(player.progress, 0), 1)))
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            scrubProgress = min(max(value.location.x / max(geo.size.width, 1), 0), 1)
                        }
                        .onEnded { _ in
                            let p = Double(scrubProgress ?? 0)
                            scrubProgress = nil
                            let total = max(player.duration, fallbackDuration)
                            if total > 0 { player.seek(to: p * total) }
                        }
                )
        }
    }
}

/// 完成态频谱：真实振幅 + 已播/未播双色 + 播放头
///
/// ⚠️ 振幅来自 `AudioWaveformExtractor` 扫 PCM 得到的包络，不是公式生成的假波形；
/// 尚未解析出数据时只画一条底线，不伪造起伏。
struct WaveformBars: View {
    @Environment(\.aurora) private var c
    let samples: [CGFloat]
    let barCount: Int
    let progress: CGFloat

    var body: some View {
        Canvas { ctx, size in
            let n = max(samples.isEmpty ? barCount : samples.count, 1)
            let gap: CGFloat = 2
            let barW = max(1.5, (size.width - gap * CGFloat(n - 1)) / CGFloat(n))
            let cut = size.width * min(max(progress, 0), 1)
            let played = GraphicsContext.Shading.linearGradient(
                Gradient(colors: [AuroraDecor.violet, AuroraDecor.rose]),
                startPoint: .zero,
                endPoint: CGPoint(x: size.width, y: 0)
            )
            let idle = GraphicsContext.Shading.color(c.slot)

            var x: CGFloat = 0
            for i in 0..<n {
                let amp = samples.isEmpty ? 0.06 : min(max(samples[i], 0.04), 1)
                let h = max(3, amp * size.height)
                let rect = CGRect(x: x, y: (size.height - h) / 2, width: barW, height: h)
                let path = Path(roundedRect: rect, cornerRadius: min(barW / 2, 1.6))
                ctx.fill(path, with: x + barW * 0.5 <= cut ? played : idle)
                x += barW + gap
            }

            if !samples.isEmpty {
                let headX = min(max(cut - 1, 0), max(size.width - 2, 0))
                ctx.fill(Path(CGRect(x: headX, y: 0, width: 2, height: size.height)),
                         with: .color(AuroraDecor.rose))
            }
        }
    }
}
