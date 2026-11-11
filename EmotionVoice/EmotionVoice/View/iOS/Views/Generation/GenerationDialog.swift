//
//  GenerationDialog.swift
//  iOSEmora
//

import SwiftUI
import Combine
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
    // ⚠️ 弹窗主体不订阅播放器：10Hz progress 会把四宫格 / 音色卡 / 积分行 / 网格
    //    一起拖着重算（macOS `AudioGenerationModal` 开头注释写的就是这个坑）。
    //    完成态播放器的订阅隔离在 `ModalAudioPlayer` 里。

    @State private var litCells = 0
    @State private var bytesPerCell = 4096
    @State private var gridRemainder = 0
    @State private var remainingCredits: Double = 0
    /// 完成态「剩余」的动画值：生成中是扣费前余额，完成后滚到扣费后余额。
    /// 直接绑 remainingCredits 的话，完成态是新建视图，首帧就是终值，看不到变化。
    @State private var animatedRemaining: Double = 0

    // 完成态
    @State private var displayName: String = ""
    @State private var isExporting = false
    @State private var isSharing = false
    @State private var exportData: Data? = nil

    /// 完成态频谱的真实振幅包络（0...1，共 waveformBars 条）
    @State private var waveform: [CGFloat] = []
    /// 名称输入框焦点：`.done` 收键盘
    @FocusState private var nameFocused: Bool

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
        .task(id: hasResult) {
            guard hasResult else { return }
            // 等完成态首帧落地，再把「扣费前余额」滚到「扣费后余额」。
            // 80ms 是为了跨过一次渲染周期：同周期内合并两次 @State 写入会没有动画。
            try? await Task.sleep(nanoseconds: 80_000_000)
            animatedRemaining = remainingCredits
        }
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

            gridBox
                .padding(.horizontal, 16)
                .padding(.top, 12)

            HStack(spacing: 6) {
                PulseDot(color: c.accent)
                Text("请保持 App 在前台运行，以免影响数据接收。".localized())
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
            // 名称可编辑行：预填默认名（对齐 macOS AudioGenerationModal），右侧 × 一键清空。
            // 清空按钮只在有内容时出现，样式与项目页 RenameDialog 一致。
            HStack(spacing: 8) {
                TextField("音频名称".localized(), text: $displayName)
                    .font(.system(size: 15.5))
                    .foregroundStyle(c.textPrimary)
                    .focused($nameFocused)
                    .submitLabel(.done)
                    .onSubmit { nameFocused = false }

                if !displayName.isEmpty {
                    Button { displayName = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 15))
                            .foregroundStyle(c.textTertiary)
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity.combined(with: .scale(scale: 0.7)))
                    .accessibilityLabel("清空".localized())
                }

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
            // 只在「空 ↔ 非空」翻转时动一下，打字期间不触发
            .animation(reduceMotion ? nil : .easeOut(duration: 0.16), value: displayName.isEmpty)

            StatGrid(items: [
                ("大小".localized(), formatDataSize(fileSize)),
                ("采样率".localized(), String(format: "%.2fk", Double(vm.sampleRate) / 1000.0)),
                ("格式".localized(), (vm.generatedAudioURL?.pathExtension ?? vm.selectedFormat).uppercased()),
                ("时长".localized(), formatDuration(vm.generatedAudioDuration))
            ])
            // ⚠️ LazyVGrid 在 VStack(alignment:.center) 里只拿「理想宽度」→ 四列缩在中间。
            //    显式撑满，左右边界才和下面同样 16pt 边距的 miniPlayer 对齐。
            .frame(maxWidth: .infinity, alignment: .leading)
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
                Text("消耗".localized())
                    .font(.system(size: 12))
                    .foregroundStyle(c.textTertiary)
                Text(formatCredits(chargedPoints))
                    .font(AuroraFont.mono15)
                    .foregroundStyle(AuroraDecor.creditB)
                Spacer(minLength: 0)
                AnimatedCreditText(value: animatedRemaining,
                                   font: .system(size: 11.5, design: .monospaced),
                                   weight: .regular,
                                   color: c.textTertiary,
                                   stringFormat: NSLocalizedString("剩余 %@", comment: ""))
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
        }
    }

    // MARK: 播放器

    /// ⚠️ 播放器的 10Hz 订阅只关在 `ModalAudioPlayer` 里，弹窗主体零重算。
    private var miniPlayer: some View {
        ModalAudioPlayer(audioURL: vm.generatedAudioURL,
                         fallbackDuration: vm.generatedAudioDuration,
                         samples: waveform,
                         barCount: Self.waveformBars)
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
                SecondaryButton(title: "导出".localized(),) { isSharing = true }

                PrimaryButton(title: "完成".localized()) {
                    commitName()
                    onDismiss()
                }
            } else {
                SecondaryButton(title: "隐藏窗口".localized(), systemImage: "") {
                    onBackground()
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
        // 生成中：动画起点取扣费前余额；完成态才新建的弹窗直接落终值，不造假起点
        animatedRemaining = vm.isGenerating
            ? remainingCredits + chargedPoints
            : remainingCredits

        if let started = vm.generationStartedAt {
            ticker.start(at: started)
        }
        // 完成态名称不空着：与 macOS AudioGenerationModal 同规则预填一个可直接用的名字。
        // 预填值只是输入框里的「预设」，用户可点右侧 × 清空后自己写或留空。
        displayName = Self.defaultAudioName(from: vm.plainText)
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

    /// 完成态默认名（与 macOS `AudioGenerationModal.generateDefaultAudioName()` 同规则）。
    ///
    /// ① 换行折成空格 → 先截 40 字再 `sanitizeFileName`（洗掉 `/ : * ?` 等非法字符）→ 取前 10 字；
    ///    情感 / 拟声标签是编辑器装饰，只取 `plainText`，不混进名字。
    /// ② 文本为空 / 洗完什么都不剩 → 退回本地化的「音频_MM-dd HH:mm」时间戳。
    /// ⚠️ 时间戳兜底用带参数的 `.localized(...)`，不要写成 `String(format: "…%@…".localized(), …)`。
    private static func defaultAudioName(from plainText: String) -> String {
        let source = plainText
            .components(separatedBy: .newlines)
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        let cleaned = sanitizeFileName(String(source.prefix(40)))
        let prefix = String(cleaned.prefix(10))
            .trimmingCharacters(in: CharacterSet(charactersIn: "-").union(.whitespaces))
        if !prefix.isEmpty { return prefix }

        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        return sanitizeFileName("音频_%@".localized(formatter.string(from: Date())))
    }

    /// 完成：写入自定义名称；点过「清空」则按「无自定义名」落库，列表回退到时间戳文件名。
    private func commitName() {
        guard let id = vm.generatedAudioId else { return }
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        ProjectService.shared.renameAudio(id: id,
                                          displayName: trimmed.isEmpty ? nil : trimmed)
    }
}
