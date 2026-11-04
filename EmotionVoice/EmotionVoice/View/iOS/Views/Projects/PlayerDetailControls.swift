//
//  PlayerDetailControls.swift
//  iOSEmora
//
//  播放详情页高频控件：已播 / 剩余时间标签与可拖动波形（订阅隔离，勿上提）。
//  从 PlayerDetailView.swift 拆出：代码逐字搬移，未改动任何逻辑（原 private 类型按需放开为 internal）。
//

import SwiftUI
import Combine

// MARK: - 高频时间显示（订阅只关在这两个小 View 里）

/// 「已播放」时间：10Hz 只重算这一个 Text，不牵动整页。
/// 拖动中用手指落点顶上（拖动期间不 seek，`currentTime` 本来就不动）。
struct ElapsedTimeLabel: View {
    @Environment(\.aurora) private var c
    @ObservedObject private var player = AudioPreviewPlayer.shared
    let scrubFraction: Double?
    let duration: Double

    private var displayed: Double {
        scrubFraction.map { $0 * duration } ?? player.currentTime
    }

    var body: some View {
        Text(formatDuration(displayed))
            .font(.system(size: 13, design: .monospaced))
            .foregroundStyle(scrubFraction == nil ? c.textSecondary : c.accent)
    }
}

/// 「剩余约」同理：只重算自己。
struct RemainingTimeLabel: View {
    @Environment(\.aurora) private var c
    @ObservedObject private var player = AudioPreviewPlayer.shared
    let fallbackDuration: Double

    var body: some View {
        Text("剩余约 %@".localized(
            formatDuration(max(0, max(player.duration, fallbackDuration) - player.currentTime))))
            .font(.system(size: 12))
            .foregroundStyle(c.textTertiary)
    }
}

// MARK: - 可拖动波形

/// 波形定位条：整条可**点击**也可**拖动**，播放头带抓手。
///
/// ⚠️ 频谱是**静态假数据**：柱高来自写死的常量数组，不做任何噪声 / 哈希 / 三角函数计算；
/// 而且 `StaticWaveformBars` 的参数里**不含 progress**，配合 `.equatable()`，
/// 0.1s 一次的进度刷新不会重绘 Canvas。进度只用「已播色层的裁剪宽度」+ 播放头 offset
/// 表达，两者都是布局操作而非绘制操作 —— 这是「切倍速时 CPU 暴涨」的真正解法。
///
/// 拖动过程仍是「只跟手、不 seek」（每帧 seek 会让解码器反复丢缓冲），松手才落定。
struct WaveformScrubber: View {
    /// ⚠️ 详情页唯一订阅 10Hz 进度的小 View（macOS `PlayerWaveformView` 同款隔离）：
    ///    几何重算只发生在这里，长文本 / metaCard / 倍速 Menu 完全不参与。
    @ObservedObject private var player = AudioPreviewPlayer.shared
    let tint: Color
    let trackTint: Color
    /// 开始拖动的那一刻回调：用来**先暂停播放**，避免边拖边 seek 掉帧
    var onScrubStart: (() -> Void)? = nil
    /// **拖动过程中**每一次跟手都回调（传当前落点 0~1，松手时传 `nil`）。
    var onScrubChanged: ((Double?) -> Void)? = nil
    /// 松手回调：落定到最终位置并恢复播放
    var onScrubEnd: ((Double) -> Void)? = nil

    /// 柱宽 / 间距固定，根数由宽度反推 —— 宽屏（iPad / 折叠屏展开）自动变密
    private let barWidth: CGFloat = 3
    private let barGap: CGFloat = 2

    /// 拖动中的即时进度（nil = 没在拖，跟播放器走）
    @State private var dragging: Double? = nil
    /// 本次拖动是否已经通知过外部（一次拖动只暂停一次）
    @State private var didNotifyStart = false

    var body: some View {
        GeometryReader { geo in
            let width = max(geo.size.width, 1)
            let height = max(geo.size.height, 1)
            let count = max(8, Int(floor((width + barGap) / (barWidth + barGap))))
            let shown = min(max(dragging ?? player.progress, 0), 1)

            ZStack(alignment: .leading) {
                // 底层：全部柱子（未播色），静态
                StaticWaveformBars(count: count, width: width, height: height,
                                   barWidth: barWidth, barGap: barGap, color: trackTint)
                    .equatable()
                    .frame(width: width, height: height, alignment: .leading)

                // 上层：同一份静态柱子（已播色），只裁掉右侧未播部分。
                // ⚠️ 内层 frame 固定 width/height → Canvas 尺寸恒定，变的只有外层裁剪宽度，
                //    所以不会触发 Canvas 重绘。
                StaticWaveformBars(count: count, width: width, height: height,
                                   barWidth: barWidth, barGap: barGap, color: tint)
                    .equatable()
                    .frame(width: width, height: height, alignment: .leading)
                    .frame(width: max(shown * width, 0), alignment: .leading)
                    .clipped()

                // 播放头 + 抓手：让用户一眼看出「这里可以拖」
                Capsule(style: .continuous)
                    .fill(AuroraDecor.rose)
                    .frame(width: 2.5, height: height)
                    .overlay(alignment: .center) {
                        Circle()
                            .fill(AuroraDecor.rose)
                            .frame(width: 12, height: 12)
                            .shadow(color: AuroraDecor.rose.opacity(0.45), radius: 4, x: 0, y: 1)
                    }
                    .offset(x: min(max(shown * width - 1.25, 0), width - 2.5))
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !didNotifyStart {
                            didNotifyStart = true
                            onScrubStart?()
                        }
                        let f = Double(min(max(value.location.x / width, 0), 1))
                        dragging = f
                        onScrubChanged?(f)
                    }
                    .onEnded { value in
                        let f = min(max(value.location.x / width, 0), 1)
                        dragging = nil
                        didNotifyStart = false
                        onScrubChanged?(nil)
                        onScrubEnd?(Double(f))
                    }
            )
        }
    }
}

/// 静态频谱柱：参数全是尺寸 / 颜色常量，不含进度、不含 seed，且遵循 Equatable。
/// 父视图 10Hz 重算时 SwiftUI 直接跳过它的 body → Canvas 只画一次。
struct StaticWaveformBars: View, Equatable {
    let count: Int
    let width: CGFloat
    let height: CGFloat
    let barWidth: CGFloat
    let barGap: CGFloat
    let color: Color

    /// 写死的「语音包络」，循环铺满。零计算。
    private static let amplitudes: [CGFloat] = [
        0.18, 0.32, 0.54, 0.80, 0.46, 0.68, 0.90, 0.36,
        0.22, 0.58, 0.84, 0.60, 0.34, 0.72, 0.50, 0.26,
        0.42, 0.92, 0.64, 0.38, 0.20, 0.56, 0.74, 0.46,
        0.86, 0.32, 0.16, 0.48, 0.68, 0.96, 0.52, 0.28,
        0.62, 0.40, 0.22, 0.76, 0.88, 0.34, 0.18, 0.54,
        0.70, 0.44, 0.94, 0.30, 0.58, 0.24, 0.82, 0.38
    ]

    static func == (lhs: StaticWaveformBars, rhs: StaticWaveformBars) -> Bool {
        lhs.count == rhs.count && lhs.width == rhs.width && lhs.height == rhs.height
        && lhs.barWidth == rhs.barWidth && lhs.barGap == rhs.barGap && lhs.color == rhs.color
    }

    var body: some View {
        Canvas { ctx, size in
            let bars = Self.amplitudes
            let n = bars.count
            for i in 0..<count {
                let x = CGFloat(i) * (barWidth + barGap)
                let barH = max(3, bars[i % n] * size.height)
                let rect = CGRect(x: x, y: (size.height - barH) / 2,
                                  width: barWidth, height: barH)
                ctx.fill(Path(roundedRect: rect, cornerRadius: barWidth / 2, style: .continuous),
                         with: .color(color))
            }
        }
    }
}
