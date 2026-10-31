//
//  PlayerDetailView.swift
//  iOSEmora
//
//  播放详情（push 进项目标签的导航栈）
//
//  与 macOS 右侧详情面板的差异：
//  - macOS 的四列 meta 条在 iPhone 上折成 **2×2**（宽屏回到 4 列）
//  - 底部状态栏**去掉三组键帽提示**（iOS 没有键盘快捷键），只留播放状态
//  - 倍速菜单 0.5–2x 六档保留（macOS 的 `playbackRateOptions`）
//  - 波形整卡可点击 / 拖动定位（44pt 触摸高度）
//  - 时间行改成音频播放器的常规排布：**左边已播放 / 右边总时长**；
//    拖动频谱时左边跟着手指实时走，并在频谱上方浮出当前落点的时间气泡，松手即恢复。
//

import SwiftUI

struct PlayerDetailView: View {
    @Environment(\.aurora) private var c
    @Environment(\.screenMetrics) private var metrics

    let item: AudioItem

    @StateObject private var player = AudioPreviewPlayer.shared
    @State private var isSharing = false
    @State private var voiceName: String = ""
    /// 按下频谱那一刻是否正在播放（松手后据此恢复，避免拖动中反复 seek 掉帧）
    @State private var resumeAfterScrub = false
    /// 拖动中的落点（0~1）。`nil` = 没在拖，时间行跟播放器走。
    ///
    /// ⚠️ 拖动期间**不 seek**（每帧 seek 会让解码器反复丢缓冲，实测掉到 20fps 以下），
    /// 所以 `player.currentTime` 在这段时间里是不动的 —— 左边那个「已播放」必须由
    /// `scrubFraction` 顶上，否则拖到哪儿数字都不变，用户会以为拖动没生效。
    @State private var scrubFraction: Double? = nil

    /// 快进 / 快退步长（秒）。详情页是精听场景，15 秒太粗，5 秒刚好够定位一句话。
    private static let skipStep: Double = 5

    private var url: URL { item.absoluteURL }

    /// ⚠️ 时长以播放器拿到的为准：流式文件的 `item.duration` 可能是入库时的估值，
    /// 取 `max` 才能保证右侧「总时长」在播放开始后不再跳变。
    private var totalDuration: Double { max(player.duration, item.duration) }

    /// 时间行左边显示什么：拖动中 = 手指落点，否则 = 播放进度
    private var displayTime: Double {
        guard let f = scrubFraction else { return player.currentTime }
        return f * totalDuration
    }

    /// ⚠️ 必须用 identifier（`item.fileName`）判定，不能用 `player.isPlaying(url:)`：
    /// 详情页是用 `play(url:identifier: item.fileName)` 起的播，`playingKey` 存的是文件名，
    /// 拿 `url.path` 去比永远不等 —— 正是「点了暂停图标不变、只会从头重播」的根因。
    private var isThisPlaying: Bool { player.playingKey == item.fileName && player.isPlaying }
    private var isThisPaused: Bool { player.playingKey == item.fileName && player.isPaused }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                waveformCard
                    .padding(.horizontal, metrics.pageMargin)
                    .padding(.top, 12)

                transportRow

                controlRow

                metaCard
                    .padding(.horizontal, metrics.pageMargin)

                textCard
                    .padding(.horizontal, metrics.pageMargin)
                    .padding(.top, 12)

                statusLine
                    .padding(.horizontal, metrics.pageMargin + 4)
                    .padding(.top, 14)

                Spacer(minLength: 24)
            }
        }
        .background(c.backgroundGrouped)
        .navigationTitle(item.shownName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { isSharing = true } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(c.accent)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .sheet(isPresented: $isSharing) {
            ShareSheet(items: [url])
        }
        .onAppear {
            voiceName = VoiceService.shared.fetchByKeys([item.voice]).first?.localizedName ?? item.voice
            guard item.isOnDisk else { return }
            if player.isPlaying(url: url) {
                // 从列表点进来时已经在播这条：接管标识即可，别从头重播
                player.reidentify(item.fileName)
            } else if !isThisPlaying {
                player.play(url: url, identifier: item.fileName)
            }
        }
        .onDisappear { player.stop() }
    }

    // MARK: 波形卡

    private var waveformCard: some View {
        VStack(spacing: 0) {
            scrubTimeLane

            WaveformScrubber(progress: player.progress,
                             seed: item.fileName,
                             tint: c.accent,
                             trackTint: c.slot,
                             onScrubStart: {
                                 // 播放中按下 → 先暂停，拖动期间只跟手不出声
                                 resumeAfterScrub = isThisPlaying
                                 if isThisPlaying { player.pause() }
                             },
                             onScrubChanged: { fraction in
                                 scrubFraction = fraction
                             },
                             onScrubEnd: { fraction in
                                 player.seek(to: fraction * max(player.duration, item.duration))
                                 if resumeAfterScrub { player.resume() }
                                 resumeAfterScrub = false
                                 // 松手 → 交还给播放进度（下一帧 player.currentTime 已经是新位置）
                                 scrubFraction = nil
                             })
            .frame(height: 52)

            HStack {
                Text(formatDuration(displayTime))
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(scrubFraction == nil ? c.textSecondary : c.accent)
                Spacer(minLength: 0)
                Text(formatDuration(totalDuration))
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(c.textTertiary)
            }
            .padding(.top, 8)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: AuroraRadius.lg, style: .continuous)
                .fill(c.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: AuroraRadius.lg, style: .continuous)
                        .strokeBorder(c.line, lineWidth: 0.5)
                )
        )
    }

    /// 拖动时跟随手指的时间气泡（落在频谱正上方）。
    ///
    /// ⚠️ 这条 24pt 的轨道**恒占位**（拖动与否都在）：只在按下时才把高度让出来，
    /// 整张卡会在手指落下的那一帧突然长高一截、波形跟着往下跳 —— 手感比没有气泡还差。
    ///
    /// ⚠️ 气泡横向位置按落点百分比算，并夹在轨道内（`0 … width - 气泡宽`），
    /// 否则拖到两端时气泡会探出卡片外面被裁掉。
    private var scrubTimeLane: some View {
        GeometryReader { geo in
            if let f = scrubFraction {
                let laneWidth = max(geo.size.width, 1)
                let bubbleWidth: CGFloat = 64
                let x = min(max(f * laneWidth - bubbleWidth / 2, 0), max(laneWidth - bubbleWidth, 0))
                Text(formatDuration(f * totalDuration))
                    .font(.system(size: 12.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(c.accent)
                    .padding(.horizontal, 9)
                    .frame(height: 24)
                    .background(
                        Capsule(style: .continuous)
                            .fill(c.accentSoft)
                            .overlay(
                                Capsule(style: .continuous)
                                    .strokeBorder(c.accent.opacity(0.32), lineWidth: 0.5)
                            )
                    )
                    // ⚠️ 顺序别反：先「撑满轨道 + 靠左」再 offset，
                    //    反过来写的话 offset 会被外层 frame 的 alignment 抵消掉。
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .offset(x: x)
                    .animation(.easeOut(duration: 0.08), value: x)
            }
        }
        .frame(height: 24)
    }

    // MARK: 走带

    private var transportRow: some View {
        HStack(spacing: 22) {
            transportButton("backward.end.fill", size: 30) { player.seek(to: 0) }
            transportButton("gobackward.5", size: 24) { player.skip(by: -Self.skipStep) }

            Button {
                player.togglePlayback(url: url, identifier: item.fileName)
            } label: {
                ZStack {
                    Circle().fill(c.ctaGradient)
                    Image(systemName: isThisPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 26, weight: .semibold))
                        // ⚠️ 图标随状态切换要带动画：不带的话按钮像是「点了没反应」，
                        // 而真正的问题（见 `isThisPlaying` 注释）已经修在判定上了。
                        .animation(.easeOut(duration: 0.14), value: isThisPlaying)
                        .foregroundStyle(c.ctaForeground)
                }
                .frame(width: 64, height: 64)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isThisPlaying ? "暂停".localized() : "播放".localized())

            transportButton("goforward.5", size: 24) { player.skip(by: Self.skipStep) }
            transportButton("forward.end.fill", size: 30) {
                player.seek(to: max(player.duration, item.duration))
            }
        }
        .padding(.top, 16)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity)
    }

    private func transportButton(_ systemName: String, size: CGFloat,
                                 action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(c.textSecondary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: 倍速 / 剩余 / 从头播放

    private var controlRow: some View {
        HStack(spacing: 10) {
            Menu {
                ForEach(AudioPreviewPlayer.playbackRateOptions, id: \.rate) { option in
                    Button {
                        player.setPlaybackRate(option.rate)
                    } label: {
                        HStack {
                            Text(option.label)
                            if abs(player.playbackRate - option.rate) < 0.001 {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "speedometer")
                        .font(.system(size: 13, weight: .semibold))
                    Text(rateLabel)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                }
                .foregroundStyle(c.accent)
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background(
                    Capsule(style: .continuous)
                        .fill(c.accentSoft)
                )
            }

            Spacer(minLength: 0)

            Text("剩余约 %@".localized(
                formatDuration(max(0, max(player.duration, item.duration) - player.currentTime))))
                .font(.system(size: 12))
                .foregroundStyle(c.textTertiary)

            Spacer(minLength: 0)

            Button { player.seek(to: 0) } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 12, weight: .semibold))
                    Text("从头播放".localized())
                        .font(.system(size: 12.5))
                }
                .foregroundStyle(c.textSecondary)
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background(
                    Capsule(style: .continuous)
                        .fill(c.surface3)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, metrics.pageMargin)
        .padding(.top, 10)
        .padding(.bottom, 14)
    }

    private var rateLabel: String {
        let r = player.playbackRate
        if r == r.rounded() { return String(format: "%.0fx", r) }
        return String(format: "%.2fx", r)
    }

    // MARK: meta 卡（手机 2×2 / 宽屏 4 列）

    private var metaCard: some View {
        let cols = metrics.metaColumns
        let items: [(String, String, String)] = [
            ("clock", "时长".localized(), formatDuration(max(item.duration, player.duration))),
            ("waveform", "格式".localized(), item.format.uppercased()),
            ("diamond.fill", "积分".localized(), formatCredits(item.pointsCost)),
            ("person.wave.2.fill", "音色".localized(), voiceName)
        ]
        let rows = Int(ceil(Double(items.count) / Double(cols)))

        return VStack(spacing: 0) {
            ForEach(0..<rows, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<cols, id: \.self) { col in
                        let idx = row * cols + col
                        if idx < items.count {
                            metaCell(icon: items[idx].0, key: items[idx].1, value: items[idx].2)
                            if col < cols - 1 { separator(vertical: true) }
                        } else {
                            Spacer(minLength: 0)
                        }
                    }
                }
                if row < rows - 1 { separator(vertical: false) }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: AuroraRadius.lg, style: .continuous)
                .fill(c.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: AuroraRadius.lg, style: .continuous)
                        .strokeBorder(c.line, lineWidth: 0.5)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: AuroraRadius.lg, style: .continuous))
    }

    private func separator(vertical: Bool) -> some View {
        Group {
            if vertical {
                Rectangle().fill(c.line).frame(width: 0.5)
            } else {
                Rectangle().fill(c.line).frame(height: 0.5)
            }
        }
    }

    private func metaCell(icon: String, key: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundStyle(c.textTertiary)
                Text(key)
                    .font(.system(size: 11))
                    .foregroundStyle(c.textTertiary)
            }
            Text(value)
                .font(.system(size: 16, weight: .semibold, design: .monospaced))
                .foregroundStyle(c.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: 文本卡

    private var textCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("%d 字 · %d 句".localized(item.text.count, sentenceCount))
                    .font(.system(size: 11.5))
                    .foregroundStyle(c.textTertiary)
                Spacer(minLength: 0)
                Button {
                    UIPasteboard.general.string = item.text
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 11))
                        Text("复制".localized())
                            .font(.system(size: 12))
                    }
                    .foregroundStyle(c.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule(style: .continuous).fill(c.surface3)
                    )
                }
                .buttonStyle(.plain)
            }
            Text(item.text)
                .font(.system(size: 14.5))
                .lineSpacing(1.62 * 14.5 - 14.5)
                .foregroundStyle(c.textPrimary)
                .textSelection(.enabled)
                .padding(.top, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: AuroraRadius.lg, style: .continuous)
                .fill(c.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: AuroraRadius.lg, style: .continuous)
                        .strokeBorder(c.line, lineWidth: 0.5)
                )
        )
    }

    // MARK: 状态行

    private var statusLine: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isThisPlaying ? c.success : c.textTertiary)
                .frame(width: 7, height: 7)
            Text(statusText)
                .font(.system(size: 12))
                .foregroundStyle(c.textSecondary)
            Spacer(minLength: 0)
        }
    }

    private var statusText: String {
        if isThisPlaying { return "正在播放 · %@".localized(rateLabel) }
        if isThisPaused { return "已暂停".localized() }
        return "待播放".localized()
    }

    private var sentenceCount: Int {
        item.text.components(separatedBy: CharacterSet(charactersIn: "。！？!?；;\n"))
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .count
    }
}

// MARK: - 可拖动波形

/// 波形定位条：整条可**点击**也可**拖动**，已播部分着色，播放头带抓手。
///
/// 两条关键取舍：
///  * **用 `Canvas` 一次画完所有柱子**，而不是 `HStack` 里塞 88 个 `RoundedRectangle` ——
///    后者在 0.1s 一次的进度刷新里要重排两遍整条栈，拖动时会明显掉帧。
///  * 拖动过程中既要**立刻跟手**（本地 `dragging` 覆盖 `progress`），又要**真的出声**
///    （`onChanged` 里同步 seek）：只在 `onEnded` 才 seek 的话，手指划过去了声音没动，
///    用户会以为拖动没生效。
private struct WaveformScrubber: View {
    let progress: Double
    let seed: String
    let tint: Color
    let trackTint: Color
    /// 开始拖动的那一刻回调：用来**先暂停播放**，避免边拖边 seek 掉帧
    var onScrubStart: (() -> Void)? = nil
    /// **拖动过程中**每一次跟手都回调（传当前落点 0~1，松手时传 `nil`）。
    /// ⚠️ 光有 `onScrubEnd` 不够：拖动期间不 seek，`player.currentTime` 是不动的，
    /// 上层拿不到「手指现在指到几秒」，时间显示就会僵在旧值上。
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
            let shown = min(max(dragging ?? progress, 0), 1)

            ZStack(alignment: .leading) {
                Canvas { ctx, size in
                    for i in 0..<count {
                        let x = CGFloat(i) * (barWidth + barGap)
                        let amp = envelope(index: i, count: count)
                        let barH = max(3, amp * size.height)
                        let rect = CGRect(x: x, y: (size.height - barH) / 2,
                                          width: barWidth, height: barH)
                        let center = (x + barWidth / 2) / size.width
                        let color = center <= shown ? tint : trackTint
                        ctx.fill(Path(roundedRect: rect, cornerRadius: barWidth / 2, style: .continuous),
                                 with: .color(color))
                    }
                }

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
                            onScrubStart?()      // 播放中 → 先暂停，否则每帧 seek 会卡
                        }
                        // ⚠️ 拖动中**只跟手，不 seek**：每帧 seek 会让解码器反复丢弃已缓冲
                        // 的数据重建，实测掉到 20fps 以下。落定到松手时那一次就够了。
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

    /// 由文件名派生的确定性包络（同一条音频每次进来波形一致）。
    ///
    /// 早年是「两个正弦叠加」，波形呈规则的波浪、一眼假。改成**值噪声**三层叠加：
    /// 低频给出「一句一句」的呼吸感，高频给出齿音细节，再叠一层极低频做整体起伏，
    /// 首尾各渐隐，视觉上接近真实语音波形。
    private func envelope(index: Int, count: Int) -> CGFloat {
        let t = Double(index) / Double(max(count - 1, 1))
        let coarse = valueNoise(t * 3.1 + phase(0.0))        // 段落起伏
        let mid = valueNoise(t * 9.7 + phase(1.7))           // 音节
        let fine = valueNoise(t * 23.3 + phase(4.3))         // 细节
        var v = 0.28 + 0.46 * mid + 0.20 * fine
        v *= 0.45 + 0.55 * coarse
        // 首尾渐隐，避免第一 / 最后一根柱子贴着卡片边缘顶到底
        v *= 0.35 + 0.65 * sin(min(max(t, 0), 1) * .pi)
        return CGFloat(min(max(v, 0.14), 1))
    }

    private func phase(_ offset: Double) -> Double {
        Double(abs(seedHash % 997)) / 997.0 * 31.0 + offset
    }

    private var seedHash: Int {
        var hash: UInt64 = 1469598103934665603
        for byte in seed.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1099511628211
        }
        return Int(hash % 100_003)
    }

    /// 一维值噪声：整数点取哈希，中间用 smoothstep 插值
    private func valueNoise(_ t: Double) -> Double {
        let i = Int(floor(t))
        let f = t - Double(i)
        let a = hashNoise(i)
        let b = hashNoise(i + 1)
        let s = f * f * (3 - 2 * f)
        return a + (b - a) * s
    }

    private func hashNoise(_ n: Int) -> Double {
        var x = n &* 374761393 &+ seedHash
        x = (x ^ (x >> 13)) &* 1274126177
        x ^= x >> 16
        return Double(abs(x) % 100_000) / 100_000.0
    }
}
