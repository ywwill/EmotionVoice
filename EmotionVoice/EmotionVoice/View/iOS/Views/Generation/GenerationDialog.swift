//
//  GenerationDialog.swift
//  iOSEmora
//
//  331pt 居中弹窗：接收中与完成态**共用同一个弹窗**，只切换顶部渐变条、图标与内容区。
//
//  内部按「7 层信息」填满，避免大面积留白：
//  ① 音色 × 参数 chips 行（含本次计费）② 实时波形 ③ 大字字节数 + 速率
//  ④ 不确定进度条 ⑤ 四宫格（已用时 / 数据块 / 目标大小 / 预计时长）
//  ⑥ 接收网格 ⑦ 后台接收 / 停止生成
//
//  完成态：顶部转紫→薄荷、图标换勾选、内容换成名称行 + 四宫格 + 播放器 + 网格 + 计费行
//  + 分享 / 导出 / 完成。
//

import SwiftUI
import Combine   // @Published / ObservableObject 在 Combine，SwiftUI 不再隐式导出
import UniformTypeIdentifiers
import AVFoundation

// MARK: - 计时器

/// 已用时计时（自持 Timer）
///
/// ⚠️ 不能用 `Timer.publish().autoconnect()`：弹窗被 10Hz 的 stats 刷新反复重建时
/// 订阅会断连，计时会停在 0。
@MainActor
final class ElapsedTicker: ObservableObject {
    @Published private(set) var elapsed: TimeInterval = 0

    private var timer: Timer?
    private var startedAt: Date?

    func start(at date: Date) {
        stop()
        startedAt = date
        elapsed = Date().timeIntervalSince(date)
        let t = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                guard let start = self.startedAt else { return }
                self.elapsed = Date().timeIntervalSince(start)
            }
        }
        timer = t
        RunLoop.main.add(t, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        startedAt = nil
    }

    deinit { timer?.invalidate() }
}

// MARK: - 弹窗

struct GenerationDialog: View {
    @Environment(\.aurora) private var c
    @Environment(\.screenMetrics) private var metrics
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @ObservedObject var vm: VoiceStudioViewModel
    @ObservedObject var stats: GenerationStats

    /// 关闭弹窗（不断连接）
    let onDismiss: () -> Void
    /// 后台接收
    let onBackground: () -> Void

    @StateObject private var gridModel = DataReceiveGridModel(rows: 5)
    @StateObject private var ticker = ElapsedTicker()
    @StateObject private var player = AudioPreviewPlayer.shared

    @State private var litCells = 0
    @State private var bytesPerCell = 4096
    @State private var gridRemainder = 0
    @State private var remainingCredits: Double = 0

    // 完成态
    @State private var displayName: String = ""
    @State private var isExporting = false
    @State private var isSharing = false
    @State private var exportData: Data? = nil

    /// 完成态频谱的真实振幅包络（0...1，共 waveformBars 条）
    @State private var waveform: [CGFloat] = []
    /// 拖动定位中的临时进度（nil = 跟随播放器）
    @State private var scrubProgress: CGFloat? = nil

    /// 网格目标格数（≈ 空槽数 × 0.82）
    private static let gridTargetCells = 82
    private static let gridMinBytesPerCell = 512
    /// 完成态频谱条数
    private static let waveformBars = 56

    private var hasResult: Bool { vm.generatedAudioURL != nil && !vm.isGenerating }

    var body: some View {
        ZStack {
            c.scrim
                .ignoresSafeArea()
                .background(.ultraThinMaterial)
                .onTapGesture { }   // 遮罩不关闭：避免误触中断生成

            dialogCard
                .frame(width: metrics.dialogWidth)
                .transition(.scale(scale: 0.92, anchor: .center).combined(with: .opacity))
        }
        .animation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.78),
                   value: vm.isGenerating)
        .onAppear(perform: prepare)
        .task(id: vm.generatedAudioURL) { await loadWaveform() }
        .onChange(of: stats.receivedBytes) { _, _ in feedGrid() }
        .onChange(of: vm.isGenerating) { _, generating in
            if generating {
                prepare()
            } else if vm.generatedAudioURL != nil {
                ticker.stop()
                stats.flush()
                feedGrid()
                // 扣费发生在写盘之后，这里读到的才是真正的剩余余额
                remainingCredits = CreditManager.shared.balance
            }
        }
        .fileExporter(isPresented: $isExporting,
                      document: exportDocument,
                      contentType: exportContentType,
                      defaultFilename: defaultFileName) { _ in }
        .sheet(isPresented: $isSharing) {
            if let url = vm.generatedAudioURL {
                ShareSheet(items: [url])
            }
        }
    }

    // MARK: 卡片

    private var dialogCard: some View {
        ZStack(alignment: .top) {
            topGlow

            VStack(spacing: 0) {
                header

                if hasResult {
                    completedContent
                } else {
                    generatingContent
                }

                footer
            }
        }
        .background(
            RoundedRectangle(cornerRadius: AuroraRadius.xxl, style: .continuous)
                .fill(c.surface)
                .shadow(color: c.shadow, radius: 40, x: 0, y: 18)
        )
        .clipShape(RoundedRectangle(cornerRadius: AuroraRadius.xxl, style: .continuous))
    }

    /// 顶部渐变：3pt 品牌条 + 向下 150pt 淡出的同色晕染（进行中紫→玫瑰，完成态紫→薄荷）
    ///
    /// ⚠️ 早期只放一条 5pt 实色条，边缘生硬且「只有顶部一点颜色」，现在改成
    /// 条 + 大面积淡出，让顶部是一整片渐变而不是一条线。
    private var topGlow: some View {
        ZStack(alignment: .top) {
            LinearGradient(stops: [
                .init(color: AuroraDecor.violet.opacity(0.42), location: 0),
                .init(color: hasResult ? AuroraDecor.mint.opacity(0.20) : AuroraDecor.rose.opacity(0.22), location: 0.30),
                .init(color: hasResult ? AuroraDecor.mint.opacity(0.07) : AuroraDecor.rose.opacity(0.08), location: 0.62),
                .init(color: .clear, location: 1)
            ], startPoint: .top, endPoint: .bottom)
            .frame(height: 150)

            Rectangle()
                .fill(hasResult ? AuroraDecor.popAltGradient : AuroraDecor.popGradient)
                .frame(height: 3)
        }
        .allowsHitTesting(false)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 11) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(hasResult ? c.success.opacity(0.16) : c.accentSoft)
                    .frame(width: 38, height: 38)
                Image(systemName: hasResult ? "checkmark.circle.fill" : "waveform")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(hasResult ? c.success : c.accent)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(hasResult ? "音频生成完成".localized() : "正在接收".localized())
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(c.textPrimary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(role: .cancel) { onDismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(c.textTertiary)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    // MARK: 进行中

    private var generatingContent: some View {
        VStack(spacing: 0) {
            chipsRow

            StreamingWaveBars(barCount: 24, tint: c.accent)
                .frame(height: 74)
                .padding(.horizontal, 16)
                .padding(.top, 2)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(autoByteUnit(Double(stats.receivedBytes)).value)
                    .font(.system(size: 30, weight: .bold, design: .monospaced))
                    .foregroundStyle(c.textPrimary)
                Text("%@ 已接收".localized(autoByteUnit(Double(stats.receivedBytes)).unit))
                    .font(.system(size: 12))
                    .foregroundStyle(c.textTertiary)
                Spacer(minLength: 0)
                Text("↑ \(autoByteUnit(bytesPerSecond).value) \(autoByteUnit(bytesPerSecond).unit)/s")
                    .font(AuroraFont.mono13)
                    .foregroundStyle(c.success)
            }
            .padding(.horizontal, 16)
            .padding(.top, 6)

            IndeterminateBar()
                .frame(height: 3)
                .padding(.horizontal, 16)
                .padding(.top, 10)

            StatGrid(items: [
                ("已用时".localized(), formatDuration(ticker.elapsed)),
                ("数据块".localized(), "%d 段".localized(stats.receivedChunks)),
                ("目标".localized(), "≈\(formatDataSize(estimatedBytes))"),
                ("时长".localized(), formatDuration(estimatedDuration))
            ])
            .padding(.horizontal, 16)
            .padding(.top, 12)

            gridBox
                .padding(.horizontal, 16)
                .padding(.top, 12)

            HStack(spacing: 6) {
                PulseDot(color: c.accent)
                Text("正在持续接收。关闭弹窗不会中断任务，可从顶部浮条随时返回。".localized())
                    .font(.system(size: 11.5))
                    .foregroundStyle(c.textTertiary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
        }
    }

    // MARK: 完成态

    private var completedContent: some View {
        VStack(spacing: 0) {
            // 名称可编辑行
            HStack(spacing: 8) {
                TextField("音频名称".localized(), text: $displayName)
                    .font(.system(size: 15.5))
                    .foregroundStyle(c.textPrimary)
                    .submitLabel(.done)
                Text((vm.generatedAudioURL?.pathExtension ?? vm.selectedFormat).uppercased())
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(c.accent)
                    .padding(.horizontal, 7)
                    .frame(height: 18)
                    .background(
                        Capsule(style: .continuous).fill(c.accentSoft)
                    )
            }
            .padding(.horizontal, 14)
            .frame(height: 40)
            .background(
                RoundedRectangle(cornerRadius: AuroraRadius.sm, style: .continuous)
                    .fill(c.surface3)
            )
            .padding(.horizontal, 16)

            StatGrid(items: [
                ("大小".localized(), formatDataSize(fileSize)),
                ("采样率".localized(), String(format: "%.2fk", Double(vm.sampleRate) / 1000.0)),
                ("格式".localized(), (vm.generatedAudioURL?.pathExtension ?? vm.selectedFormat).uppercased()),
                ("时长".localized(), formatDuration(vm.generatedAudioDuration))
            ])
            .padding(.horizontal, 16)
            .padding(.top, 10)

            miniPlayer
                .padding(.horizontal, 16)
                .padding(.top, 10)

            gridBox
                .padding(.horizontal, 16)
                .padding(.top, 10)

            HStack(spacing: 7) {
                Image(systemName: "diamond.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(AuroraDecor.creditB)
                Text("本次消耗积分".localized())
                    .font(.system(size: 12))
                    .foregroundStyle(c.textTertiary)
                Text("\(formatCredits(chargedPoints))")
                    .font(AuroraFont.mono15)
                    .foregroundStyle(AuroraDecor.creditB)
                Spacer(minLength: 0)
                Text("剩余 %@".localized(formatCredits(remainingCredits)))
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(c.textTertiary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
    }

    // MARK: 播放器

    private var miniPlayer: some View {
        VStack(spacing: 10) {
            HStack(spacing: 13) {
                Button {
                    if let url = vm.generatedAudioURL {
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
                    Text(formatDuration(max(vm.generatedAudioDuration, player.duration)))
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
        .onAppear {
            if let url = vm.generatedAudioURL { player.play(url: url) }
        }
        .onDisappear { player.stop() }
    }

    // MARK: 频谱

    /// 真实频谱条：振幅来自音频文件本身，可拖动定位
    private var waveformStrip: some View {
        GeometryReader { geo in
            WaveformBars(samples: waveform,
                         barCount: Self.waveformBars,
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
                            let total = max(player.duration, vm.generatedAudioDuration)
                            if total > 0 { player.seek(to: p * total) }
                        }
                )
        }
    }

    // MARK: 网格

    private var gridBox: some View {
        DataReceiveGridView(model: gridModel,
                            tint: AuroraDecor.rose,
                            cellSize: 11,
                            spacing: 4,
                            cornerRadius: 3.2)
        .frame(height: 5 * 11 + 4 * 4 + 4)
    }

    // MARK: chips

    private var chipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                dialogChip(vm.selectedFormat.uppercased())
                dialogChip(String(format: "%.2f kHz", Double(vm.sampleRate) / 1000.0))
                dialogChip(String(format: "%.1fx · %d%%", vm.rate, Int(vm.volume.rounded())))
                dialogChip("%d 字 · %d 句".localized(vm.plainText.count, sentenceCount))
                dialogChipCost("−%@ 积分".localized(formatCredits(chargedPoints)))
            }
            .padding(.horizontal, 16)
        }
    }

    private func dialogChip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11.5, design: .monospaced))
            .foregroundStyle(c.textSecondary)
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(Capsule(style: .continuous).fill(c.surface3))
    }

    private func dialogChipCost(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
            .foregroundStyle(AuroraDecor.creditB)
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(
                Capsule(style: .continuous)
                    .fill(AuroraDecor.creditB.opacity(0.14))
            )
    }

    // MARK: 底部按钮

    private var footer: some View {
        HStack(spacing: 8) {
            if hasResult {
                SecondaryButton(title: "", systemImage: "square.and.arrow.up",
                                height: 44, isFullWidth: false) { isSharing = true }
                    .frame(width: 50)
                    .accessibilityLabel("分享".localized())

                SecondaryButton(title: "导出".localized(), systemImage: "arrow.down.doc") {
                    prepareExport()
                }

                PrimaryButton(title: "完成".localized()) {
                    commitName()
                    onDismiss()
                }
            } else {
                SecondaryButton(title: "后台接收".localized(), systemImage: "person.crop.circle") {
                    onBackground()
                }
                DangerBorderButton(title: "停止生成".localized(), systemImage: "xmark") {
                    vm.cancelGeneration()
                    onDismiss()
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 14)
    }

    // MARK: - 数据

    private var voiceSubtitle: String {
        guard let v = vm.voice else { return "" }
        var parts = [v.localizedName]
        if !v.localizedDesc.isEmpty { parts.append(v.localizedDesc) }
        parts.append(v.localizedGender)
        if let age = v.age, age > 0 { parts.append("%d 岁".localized(age)) }
        return parts.joined(separator: " · ")
    }

    private var sentenceCount: Int {
        vm.plainText.components(separatedBy: CharacterSet(charactersIn: "。！？!?；;\n"))
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .count
    }

    private var estimatedDuration: TimeInterval {
        max(2.5, Double(vm.plainText.count) / 12.0)
    }

    private var bytesPerSecond: Double {
        switch vm.selectedFormat.lowercased() {
        case "mp3", "m4a", "aac", "mp4", "ogg": return 16_000
        default: return Double(vm.sampleRate) * 2
        }
    }

    private var estimatedBytes: Int {
        Int(estimatedDuration * bytesPerSecond)
    }

    private var fileSize: Int {
        guard let url = vm.generatedAudioURL,
              let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? NSNumber else { return estimatedBytes }
        return size.intValue
    }

    /// 本次计费（与 VM 同源：`字符数 / 100 × 2`，不做向上取整）
    private var chargedPoints: Double { vm.estimatedPoints }

    private var defaultFileName: String {
        let base = displayName.isEmpty ? "audio" : displayName
        let ext = vm.generatedAudioURL?.pathExtension ?? vm.selectedFormat
        return "\(base).\(ext)"
    }

    private var exportContentType: UTType {
        let ext = (vm.generatedAudioURL?.pathExtension ?? vm.selectedFormat).lowercased()
        switch ext {
        case "mp3": return .mp3
        case "m4a": return .mpeg4Audio
        case "wav": return .wav
        default: return .audio
        }
    }

    private var exportDocument: AudioFileDocument? {
        guard let data = exportData else { return nil }
        return AudioFileDocument(data: data)
    }

    // MARK: - 行为

    private func prepare() {
        // 每格字节数：本次文本 → 时长 → 字节 → ÷ 目标格数（与 macOS prepareGrid 同一公式）
        let unit = Int(ceil(estimatedDuration * bytesPerSecond / Double(Self.gridTargetCells)))
        bytesPerCell = max(Self.gridMinBytesPerCell, unit)
        gridRemainder = 0
        gridModel.reset()
        litCells = 0
        remainingCredits = CreditManager.shared.balance

        if let started = vm.generationStartedAt {
            ticker.start(at: started)
        }
        // ⚠️ 名称不再用正文前 20 字兜底：完成态不展示任何合成文本内容
        feedGrid()
    }

    private func feedGrid() {
        let total = stats.receivedBytes + gridRemainder
        let target = total / bytesPerCell
        let delta = target - litCells
        guard delta > 0 else { return }
        gridRemainder = total % bytesPerCell
        litCells = target
        gridModel.receive(delta)
    }

    private func prepareExport() {
        guard let url = vm.generatedAudioURL,
              let data = try? Data(contentsOf: url) else { return }
        exportData = data
        isExporting = true
    }

    /// 解析完成态频谱（解码在后台线程，只把包络写回主线程）
    private func loadWaveform() async {
        guard let url = vm.generatedAudioURL else {
            waveform = []
            return
        }
        let bars = Self.waveformBars
        let values = await Task.detached(priority: .utility) {
            AudioWaveformExtractor.envelope(url: url, barCount: bars)
        }.value
        waveform = values
    }

    private func commitName() {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let id = vm.generatedAudioId else { return }
        ProjectService.shared.renameAudio(id: id, displayName: trimmed)
    }
}

// MARK: - 子视图

/// 不确定进度条
private struct IndeterminateBar: View {
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
private struct StreamingWaveBars: View {
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

/// 完成态频谱：真实振幅 + 已播/未播双色 + 播放头
///
/// ⚠️ 振幅来自 `AudioWaveformExtractor` 扫 PCM 得到的包络，不是公式生成的假波形；
/// 尚未解析出数据时只画一条底线，不伪造起伏。
private struct WaveformBars: View {
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

/// 从音频文件抽取真实振幅包络（峰值 × RMS 混合），结果按「路径 + 大小 + 条数」缓存
enum AudioWaveformExtractor {
    private static let cache = NSCache<NSString, NSArray>()

    static func envelope(url: URL, barCount: Int) -> [CGFloat] {
        let key = cacheKey(url, barCount: barCount)
        if let hit = cache.object(forKey: key as NSString) as? [NSNumber] {
            return hit.map { CGFloat($0.doubleValue) }
        }
        let values = extract(url: url, barCount: barCount)
        if !values.isEmpty {
            cache.setObject(values.map { NSNumber(value: Double($0)) } as NSArray,
                            forKey: key as NSString)
        }
        return values
    }

    private static func cacheKey(_ url: URL, barCount: Int) -> String {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attrs?[.size] as? NSNumber)?.intValue ?? 0
        return "\(url.path)#\(size)#\(barCount)"
    }

    private static func extract(url: URL, barCount: Int) -> [CGFloat] {
        guard barCount > 0,
              let file = try? AVAudioFile(forReading: url) else { return [] }
        let totalFrames = Int(file.length)
        guard totalFrames > 0 else { return [] }

        let per = max(1, totalFrames / barCount)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                            frameCapacity: AVAudioFrameCount(per)) else { return [] }

        var raw: [CGFloat] = []
        raw.reserveCapacity(barCount)

        for _ in 0..<barCount {
            do { try file.read(into: buffer, frameCount: AVAudioFrameCount(per)) } catch { break }
            let n = Int(buffer.frameLength)
            guard n > 0 else { break }

            let step = max(1, n / 256)
            var peak: Float = 0
            var sumSq: Float = 0
            var count = 0
            if let f = buffer.floatChannelData {
                let ch = f[0]
                for i in stride(from: 0, to: n, by: step) {
                    let v = ch[i]
                    let a = abs(v)
                    if a > peak { peak = a }
                    sumSq += v * v
                    count += 1
                }
            } else if let s = buffer.int16ChannelData {
                let ch = s[0]
                for i in stride(from: 0, to: n, by: step) {
                    let v = Float(ch[i]) / 32768
                    let a = abs(v)
                    if a > peak { peak = a }
                    sumSq += v * v
                    count += 1
                }
            } else { break }

            guard count > 0 else { break }
            let rms = sqrt(sumSq / Float(count))
            // 峰值偏尖、RMS 偏平，混合后视觉更接近听感
            raw.append(CGFloat(min(max(peak * 0.55 + rms * 1.9, 0.015), 1)))
        }

        guard let maxV = raw.max(), maxV > 0.001 else { return [] }
        // 整体归一：真实录音常常整体偏小，抬到 0.9 峰值但保留相对形状
        return maxV < 0.9 ? raw.map { min($0 * (0.9 / maxV), 1) } : raw
    }
}

// MARK: - 导出 / 分享

struct AudioFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.audio] }

    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

/// `UIActivityViewController` 包装（替代 macOS 的分享面板）
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
