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
    /// 已播柱子的渐变终点（`nil` = 用 `tint` 纯色）。
    /// 传紫 → 玫瑰即与播放键的 `ctaGradient` 同一套色，波形和走带看起来是一个东西。
    var tintEnd: Color? = nil
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
                                   barWidth: barWidth, barGap: barGap,
                                   color: tint, endColor: tintEnd)
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
    /// 非 nil 时柱子铺一条「color → endColor」的横向渐变。
    ///
    /// ⚠️ 渐变按**整幅 Canvas 宽度**定义（不是按已播宽度），所以拖动进度时变的只有
    ///    外层的 `frame(width:)` 裁剪，Canvas 本身尺寸恒定、不会重绘 ——
    ///    这是这条波形能挂在 10Hz 进度上还不掉帧的前提，别改成「渐变终点跟着播放头走」。
    var endColor: Color? = nil

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
        && lhs.barWidth == rhs.barWidth && lhs.barGap == rhs.barGap
        && lhs.color == rhs.color && lhs.endColor == rhs.endColor
    }

    var body: some View {
        Canvas { ctx, size in
            let bars = Self.amplitudes
            let n = bars.count
            let shading: GraphicsContext.Shading
            if let endColor {
                shading = .linearGradient(
                    Gradient(colors: [color, endColor]),
                    startPoint: .zero,
                    endPoint: CGPoint(x: size.width, y: 0)
                )
            } else {
                shading = .color(color)
            }
            for i in 0..<count {
                let x = CGFloat(i) * (barWidth + barGap)
                let barH = max(3, bars[i % n] * size.height)
                let rect = CGRect(x: x, y: (size.height - barH) / 2,
                                  width: barWidth, height: barH)
                ctx.fill(Path(roundedRect: rect, cornerRadius: barWidth / 2, style: .continuous),
                         with: shading)
            }
        }
    }
}

// MARK: - 字级对齐阅读区（iOS 版，对应 macOS `PlayerTranscriptView`）
//
// 共享层已有全部数据：`AudioTimeline` / `AudioTimelineStore`（sidecar）+ 生成时
// `VoiceStudioViewModel` 落盘的段偏移。iOS 这里只补 UI。
//
// 性能约定与 macOS 完全一致（这是本项目最容易踩回去的坑）：
//  1. 只有 `AlignedTranscriptReader` 订阅 `AudioPreviewPlayer`；文本卡外壳和整页不订阅。
//  2. 高频状态在 body 里一次性收敛成离散值（当前句 / 当前字 / 句内进度 / 末字褪色），
//     句卡实现 `Equatable` + `.equatable()`，非当前句直接跳过 body，每帧只重绘一句。
//  3. 降级态（无 sidecar）绝不估算时间伪造对齐。

/// 逐字三态色
///
/// ⚠️ 用 hex 而不是 `Color`：颜色要在 10Hz 的逐帧路径上做三次乘加插值，
///    每帧把 `Color` 转 `UIColor` 取分量太贵（与 macOS `AppColor.WordTone` 同一取舍）。
///
/// ## 当前字用「播放键那颗玫红」
/// 三档仍是**聚光灯**模型（未读正常 → 读过退下去 → 当前最抢眼），但当前字换成**玫红**，
/// 与播放键 `ctaGradient` 的玫瑰端同源（暗色 `#E23C86` / 亮色 `#CE2B72`）。
///
/// 为什么换色相而不是继续加亮：暗底上「亮」和「饱和」不可兼得 —— 上一版当前字是
/// `#C29BFF`，亮度已经顶到 7.77:1，再提就成淡紫白；而它和未播 / 已读**同属紫色相**
/// （263° vs 250°），整行看上去仍是「一片灰紫在渐变」。玫红落在 335°，与另外两档
/// 差 85°，且是整段里**唯一的暖色**，扫一眼就能定位。
///
/// 对比度（相对卡片 surface）+ 饱和度：
/// - 暗色 #1B1731：未播 5.98:1 / 已读 4.31:1 / 当前 **5.94:1（S 65%）**
/// - 亮色 #FFFFFF：未播 5.47:1 / 已读 3.34:1 / 当前 **4.98:1（S 79%）**
///
/// ⚠️ 暗底**不能**直接用按钮那颗 `#E23C86`：它在这块底上只有 4.31:1，与「已读」等亮，
///    又回到「两者分不出」的老问题。`#FF5A9E` 是同一色相（335°）提亮一档，5.94:1。
/// ⚠️ 当前字带暖色，**当前句卡就绝不能用暖底**：`TranscriptSentenceRow` 的激活底色
///    保持中性的 `c.fill`（紫 5.5%，近似无彩），身份交给左侧 2pt 竖条 + 时间码。
/// ⚠️ 想再换色：只改下面 `resolve(_:)` 里 `active:` 的两个值即可（`unplayed` / `read`
///    是中性灰紫，最好别动，它们是「已读退下去」的基准）。
struct TranscriptTone: Equatable {
    let unplayed: UInt32
    let read: UInt32
    let active: UInt32

    static func resolve(_ scheme: ColorScheme) -> TranscriptTone {
        scheme == .dark
            ? TranscriptTone(unplayed: 0x9A93BA, read: 0x807AA3, active: 0xFF5A9E)
            : TranscriptTone(unplayed: 0x6B6588, read: 0x8F88AC, active: 0xCE2B72)
    }
}

/// 句卡时间码 "00:12.3"（与 macOS `PlayerTextMetrics.formatPrecise` 同口径）
func transcriptTimecode(_ seconds: Double) -> String {
    guard seconds.isFinite else { return "00:00.0" }
    let total = max(0, seconds)
    let whole = Int(total)
    let tenths = min(9, Int((total - Double(whole)) * 10))
    return String(format: "%02d:%02d.%d", whole / 60, whole % 60, tenths)
}

/// 单句：左侧句首时间码 + 逐字三态文本
struct TranscriptSentenceRow: View, Equatable {
    @Environment(\.aurora) private var c

    let cue: AudioSentenceCue
    let isActive: Bool
    let isDone: Bool
    /// -1 表示该句没有当前字
    let activeWordIndex: Int
    /// 当前字在自身时间窗内的进度 0...1
    let wordProgress: Double
    /// 句末末字在句间停顿里的褪色进度 0...1（1 = 已完全褪成已读色）
    let tailFade: Double
    let tone: TranscriptTone
    /// 主题标识：浅/深色切换时强制重算（tone 变了也要重绘文字）
    let scheme: ColorScheme

    static func == (lhs: TranscriptSentenceRow, rhs: TranscriptSentenceRow) -> Bool {
        lhs.cue == rhs.cue
            && lhs.isActive == rhs.isActive
            && lhs.isDone == rhs.isDone
            && lhs.activeWordIndex == rhs.activeWordIndex
            && lhs.wordProgress == rhs.wordProgress
            && lhs.tailFade == rhs.tailFade
            && lhs.tone == rhs.tone
            && lhs.scheme == rhs.scheme
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // 只显示句首时间码：句末与下一句句首之间还有停顿，两列并排会被读成
            // 「这句一直持续到第二个时间」。句内进度交给逐字高亮表达。
            Text(transcriptTimecode(cue.begin))
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(isActive ? c.accent : c.textTertiary)
                .frame(width: 46, alignment: .trailing)
                .padding(.top, 3)

            wordLine
                .font(.system(size: 14.5))
                .lineSpacing(6)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                // ⚠️ 不能用 `accentSoft`（紫 24%）：当前字现在就是紫色，
                //    紫字压紫底会立刻糊掉。改中性底，当前句的身份交给左侧竖条 + 时间码。
                .fill(isActive ? c.fill : Color.clear)
        )
        .overlay(alignment: .leading) {
            if isActive {
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(c.accent)
                    .frame(width: 2)
                    .padding(.vertical, 6)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            // 点句卡 = 从这句开头播；不做 @ObservedObject，直接走单例（不引入订阅）
            AudioPreviewPlayer.shared.seek(to: cue.begin)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(cue.text)
        .accessibilityHint("双击从这一句开始播放".localized())
    }

    /// 三态：已读 / 当前字 / 未播
    ///
    /// ⚠️ 必须拼 `word.text`，**禁止**用 begin_index / end_index 切 `cue.text`：
    ///    上游的 index 是「非标点字符的连续序号」，不是原文里的字符位置。
    /// ⚠️ 也不要给当前字加 `.bold()`：字重变化会改变单字宽度，整段会重新折行、左右抖动。
    ///    区分度全部交给颜色。
    private var wordLine: Text {
        var result = Text("")
        for (i, word) in cue.words.enumerated() {
            result = result + Text(word.text).foregroundColor(wordColor(at: i))
        }
        return result
    }

    // MARK: 播放文本颜色
    private func wordColor(at i: Int) -> Color {
        guard activeWordIndex >= 0 else {
            guard isDone else {
                return AppColor.blend(tone.unplayed, tone.unplayed, 0)
            }
            // 句末最后一字在句间停顿里从高亮褪到已读，接上下一句首字的渐亮
            if i == cue.words.count - 1, tailFade < 1 {
                return AppColor.blend(tone.active, tone.read, tailFade)
            }
            return AppColor.blend(tone.read, tone.read, 0)
        }
        if i == activeWordIndex {
            // ⚠️ 起点 0.72，不是 0：中文单字只有 200–350ms，10Hz 下这段插值只跑得到
            //    2–4 帧，起点太低等于这个字刚出口时还是一片灰，等看清已经念完了。
            //    垫到 0.72 后当前字**一亮相就已经是接近全亮的玫红**，剩下 0.28 只做轻微呼吸；
            //    同时它仍严格高于 read 色，所以任何一帧都不会和「已读」混淆。
            return AppColor.blend(tone.unplayed, tone.active, 0.72 + 0.28 * wordProgress)
        }
        if i == activeWordIndex - 1 {
            // 上一字从全暖褪到已读，和当前字的暖色起点在时间上重叠 → 高亮是「移交」不是「熄灭」
            return AppColor.blend(tone.active, tone.read, wordProgress)
        }
        return i < activeWordIndex
            ? AppColor.blend(tone.read, tone.read, 0)
            : AppColor.blend(tone.unplayed, tone.unplayed, 0)
    }
}

/// 唯一订阅 10Hz 进度的阅读区（含跟随滚动）。
///
/// 高度由外壳固定：iOS 整页本身是 ScrollView，这里再做「卡内独立滚动」是为了
/// 长文案跟随时不把波形 / 走带一起滚出屏幕（与 macOS 同一交互）。
struct AlignedTranscriptReader: View {
    @Environment(\.aurora) private var c
    @Environment(\.colorScheme) private var scheme
    @ObservedObject private var player = AudioPreviewPlayer.shared

    let timeline: AudioTimeline
    @Binding var follow: Bool

    @State private var recenterTick: Int = 0

    private var tone: TranscriptTone { TranscriptTone.resolve(scheme) }

    var body: some View {
        let t = player.currentTime
        let location = timeline.location(at: t)
        let activeIndex = location.index
        let activeWord = activeIndex.flatMap { timeline.wordIndex(in: $0, at: t) }
        let progress = wordProgress(at: t, sentence: activeIndex, word: activeWord)
        // 刚结束那一句的末字还在褪色时才有值；其余句一律拿 1（常量，不破坏 Equatable 复用）
        let tail = tailFade(at: t, previous: location.previous)
        let tailIndex = tail?.index
        let tailProgress = tail?.progress ?? 1
        let toneValue = tone

        return ScrollViewReader { proxy in
            ZStack(alignment: .bottomTrailing) {
                ScrollView {
                    // 用 VStack 而不是 LazyVStack：句数只有十几条，全量布局更便宜，
                    // 而且 ScrollViewReader.scrollTo 对尚未实体化的 lazy 行不保证定位成功
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(timeline.sentences, id: \.index) { cue in
                            TranscriptSentenceRow(
                                cue: cue,
                                isActive: cue.index == activeIndex,
                                isDone: cue.endMs <= Int((t * 1000).rounded()),
                                activeWordIndex: cue.index == activeIndex ? (activeWord ?? -1) : -1,
                                wordProgress: progress,
                                tailFade: cue.index == tailIndex ? tailProgress : 1,
                                tone: toneValue,
                                scheme: scheme
                            )
                            .equatable()
                            .id(cue.index)
                        }
                    }
                    .padding(.vertical, 2)
                }
                // 用户手指一按就打断跟随（不用 onScrollPhaseChange：它分不清程序化滚动动画）
                .simultaneousGesture(
                    DragGesture(minimumDistance: 8)
                        .onChanged { _ in if follow { follow = false } }
                )

                if !follow {
                    recenterButton {
                        follow = true
                        scrollCurrent(proxy, at: activeIndex, next: location.next)
                        recenterTick &+= 1
                    }
                    .padding(.trailing, 6)
                    .padding(.bottom, 6)
                }
            }
            .onChange(of: activeIndex ?? -1) { _, _ in
                if follow { scrollCurrent(proxy, at: activeIndex, next: location.next) }
            }
            .onChange(of: recenterTick) { _, _ in
                if follow { scrollCurrent(proxy, at: activeIndex, next: location.next) }
            }
        }
    }

    private func wordProgress(at t: Double, sentence: Int?, word: Int?) -> Double {
        guard let s = sentence, let w = word,
              timeline.sentences.indices.contains(s),
              timeline.sentences[s].words.indices.contains(w) else { return 0 }
        let cue = timeline.sentences[s].words[w]
        let span = max(1, cue.endMs - cue.beginMs)
        return min(max((t * 1000 - Double(cue.beginMs)) / Double(span), 0), 1)
    }

    /// 句间停顿里的末字褪色进度：句末之后 400ms 内从高亮色 smoothstep 褪到已读色。
    /// 没有这一路插值，换行换句时末字是「上一帧全亮、下一帧灭掉」的硬跳。
    private func tailFade(at t: Double, previous: Int?) -> (index: Int, progress: Double)? {
        guard let i = previous, timeline.sentences.indices.contains(i) else { return nil }
        let elapsed = t * 1000 - Double(timeline.sentences[i].endMs)
        guard elapsed >= 0, elapsed < 400 else { return nil }
        let k = elapsed / 400
        return (i, k * k * (3 - 2 * k))
    }

    private func scrollCurrent(_ proxy: ScrollViewProxy, at index: Int?, next: Int?) {
        // t 落在句间停顿时不高亮任何句，但跟随仍指向下一句，避免停在两句之间
        guard let target = index ?? next, timeline.sentences.indices.contains(target) else { return }
        withAnimation(.easeOut(duration: 0.22)) {
            proxy.scrollTo(target, anchor: .center)
        }
    }

    private func recenterButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 10, weight: .semibold))
                Text("回到当前句".localized())
                    .font(.system(size: 11.5, weight: .medium))
            }
            .foregroundStyle(c.accent)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(Capsule(style: .continuous).fill(c.surface3))
            .overlay(
                Capsule(style: .continuous).strokeBorder(c.accent.opacity(0.32), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }
}

/// 阅读区高度策略：给值就固定，`nil` 就吃满父级给的剩余高度。
///
/// ⚠️ 拆成 Modifier 而不是在调用处写 if/else：`AlignedTranscriptReader` 内部同时挂着
///    `ScrollViewReader` 与 `@State`（跟随开关、回中计数），换一个包装层就等于换一次
///    视图身份，滚动位置和跟随状态会被重置。这里两种分支都只加一个 `frame`，
///    阅读区本体始终是同一条视图链。
private struct ReaderHeight: ViewModifier {
    let height: CGFloat?

    func body(content: Content) -> some View {
        if let height {
            content.frame(height: height)
        } else {
            content.frame(maxHeight: .infinity)
        }
    }
}

/// 文本卡外壳：header（字数 / 句数 / 对齐徽章 / 跟随 / 复制）+ 对齐阅读区或静态降级态
struct TranscriptCard: View {
    @Environment(\.aurora) private var c

    let item: AudioItem
    let timeline: AudioTimeline?
    let sentenceCount: Int
    /// 阅读区高度策略：
    /// - `.some(h)`：固定高度（详情页要按剩余空间精确算时才用）
    /// - `nil`：**吃掉卡片剩余高度**。详情页的对齐态走这条 —— 卡片拿到的是确定高度，
    ///   阅读区填满它，卡片底边就正好贴着页面底部，不会在下方留一截空白。
    let readerHeight: CGFloat?

    @State private var follow: Bool = true
    @State private var didCopy: Bool = false

    private var isAligned: Bool { timeline?.isAligned == true }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if let timeline, timeline.isAligned {
                AlignedTranscriptReader(timeline: timeline, follow: $follow)
                    .modifier(ReaderHeight(height: readerHeight))
                    .padding(.top, 6)
            } else {
                staticText
                    .padding(.top, 10)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: AuroraRadius.lg, style: .continuous)
                .fill(c.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: AuroraRadius.lg, style: .continuous)
                        .strokeBorder(c.line, lineWidth: 0.5)
                )
        )
        .task(id: item.id) { follow = true }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("%d 字 · %d 句".localized(item.text.count, sentenceCount))
                .font(.system(size: 11.5))
                .foregroundStyle(c.textTertiary)

            Spacer(minLength: 0)

            if isAligned { followButton }
            copyButton
        }
    }

    private var followButton: some View {
        Button {
            follow.toggle()
        } label: {
            HStack(spacing: 4) {
                Circle()
                    .fill(follow ? c.accent : c.textTertiary)
                    .frame(width: 5, height: 5)
                Text("跟随".localized())
                    .font(.system(size: 11.5, weight: .medium))
            }
            .foregroundStyle(follow ? c.accent : c.textSecondary)
            .padding(.horizontal, 9)
            .frame(height: 26)
            .background(Capsule(style: .continuous).fill(follow ? c.accentSoft : c.surface3))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(follow ? "关闭跟随播放".localized() : "开启跟随播放".localized())
    }

    private var copyButton: some View {
        Button {
            UIPasteboard.general.string = item.text
            didCopy = true
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_400_000_000)
                didCopy = false
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: didCopy ? "checkmark" : "square.on.square")
                    .font(.system(size: 10.5, weight: .semibold))
                Text(didCopy ? "已复制".localized() : "复制".localized())
                    .font(.system(size: 11.5))
            }
            .foregroundStyle(didCopy ? c.success : c.textSecondary)
            .padding(.horizontal, 9)
            .frame(height: 26)
            .background(Capsule(style: .continuous).fill(c.surface3))
        }
        .buttonStyle(.plain)
    }

    /// 降级态：没有 sidecar 的历史音频，按原文静态展示（绝不估算时间伪造对齐）
    private var staticText: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "info.circle")
                    .font(.system(size: 12))
                    .foregroundStyle(c.accent)
                Text("该音频没有字级时间戳，文本按原文静态展示，不使用估算时间伪造对齐。".localized())
                    .font(.system(size: 11.5))
                    .foregroundStyle(c.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(c.surface3)
            )

            Text(item.text)
                .font(.system(size: 14.5))
                .lineSpacing(1.62 * 14.5 - 14.5)
                .foregroundStyle(c.textPrimary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// 时间行中间的「第 N / M 句」：拖动中跟手指落点，其余时间跟播放进度。
///
/// ⚠️ 与 `ElapsedTimeLabel` 同理，10Hz 只重算这一个 Text —— 放进 `PlayerDetailView`
///    body 会把整页（波形 / 走带 / 文本卡）拖着一起重算。
struct SentenceProgressLabel: View {
    @Environment(\.aurora) private var c
    @ObservedObject private var player = AudioPreviewPlayer.shared

    let timeline: AudioTimeline?
    /// 拖动中的落点 0~1；nil = 跟播放器
    let scrubFraction: Double?
    let duration: Double

    var body: some View {
        if let timeline, timeline.isAligned {
            Text(text(for: timeline))
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(scrubFraction == nil ? c.textTertiary : c.accent)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .accessibilityLabel(text(for: timeline))
        }
    }

    private func text(for timeline: AudioTimeline) -> String {
        let t = scrubFraction.map { $0 * duration } ?? player.currentTime
        let located = timeline.location(at: t)
        // 句间停顿时不高亮任何句，但进度按「下一句」报，避免停在两句之间来回跳
        guard let index = located.index ?? located.next,
              timeline.sentences.indices.contains(index) else {
            return "播放结束".localized()
        }
        return "第 %d / %d 句".localized(index + 1, timeline.sentences.count)
    }
}
