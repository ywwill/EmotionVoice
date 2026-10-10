//
//  AudioGenerationModal.swift
//  EmotionVoice
//
//  Created by young on 2026/9/20.
//

import SwiftUI
import Combine
import UniformTypeIdentifiers
import AppKit

// MARK: - 音频数据累积动画

/// 累积进度的填充曲线
///
/// 流式返回时拿不到音频总大小，所以画不出真实百分比，需要一条经验曲线。
/// 这里刻意做成「前慢后快」并额外叠加一道保底闸门：
///
/// 1. **对数 + 幂**：先 `log10` 把字节数压到 0~1，再取 `>1` 次幂。
///    幂次会把曲线的前段整体压低 —— 刚开几句时进度几乎不动，
///    数据堆起来之后才明显变快，避免"一上来就冲到很满、后面还有大量数据在收却看不出变化"。
/// 2. **与时间轴进度取小值**：ViewModel 里 `generationProgress` 是按"已耗时 / 预期时长"估算的完成度，
///    它跟音频实际体量无关。两者谁保守听谁的，保证进度条永远不会跑在真实完成度前面
///    （wav/48kHz 下一段十几秒的音频就有近 1MB，只靠字节曲线会过早触顶）。
///
/// 想让曲线回到纯字节驱动，把 `fill(bytes:timeProgress:)` 里的 `min` 去掉即可。
enum AccumulationCurve {
    /// 参考上限（KB）：数据达到这个量级时，字节曲线饱和
    static let referenceKB: Double = 1024
    /// 幂次：1 为纯对数；越大前段越慢（后置越明显）
    static let exponent: Double = 1.35
    /// 最高占比，剩下的留给收尾落盘
    static let ceiling: Double = 0.94

    /// 仅由字节数决定的填充比例（0 ~ ceiling）
    static func byteFill(bytes: Double) -> Double {
        guard bytes > 0 else { return 0 }
        let kb = bytes / 1000.0
        let normalized = min(1, log10(1 + kb) / log10(1 + referenceKB))
        return ceiling * pow(normalized, exponent)
    }

    /// 最终填充比例：字节曲线与时间轴进度取小值
    /// - parameter timeProgress: ViewModel 中基于预期时长算出的进度（0~1）
    static func fill(bytes: Double, timeProgress: Double) -> Double {
        let timeCeiling = min(ceiling, max(0, timeProgress))
        return min(byteFill(bytes: bytes), timeCeiling)
    }
}

/// 字节数格式化（与 App 内其它位置口径一致，使用 1000 进制）
private func formatDataSize(_ bytes: Int) -> String {
    let value = max(0, bytes)
    if value < 1000 {
        return "\(value) B"
    } else if value < 1000 * 1000 {
        return String(format: "%.1f KB", Double(value) / 1000.0)
    } else {
        return String(format: "%.2f MB", Double(value) / (1000.0 * 1000.0))
    }
}

/// 速率格式化（字节/秒）
private func formatDataSpeed(_ bytesPerSecond: Double) -> String {
    guard bytesPerSecond > 0 else { return "等待数据" }
    if bytesPerSecond < 1000 {
        return String(format: "%.0f B/s", bytesPerSecond)
    } else if bytesPerSecond < 1000 * 1000 {
        return String(format: "%.1f KB/s", bytesPerSecond / 1000.0)
    } else {
        return String(format: "%.2f MB/s", bytesPerSecond / (1000.0 * 1000.0))
    }
}

/// 一滴水：由一批到达的数据触发
struct WaterDrop: Identifiable {
    let id = UUID()
    /// 归一化横向位置 0~1
    let x: CGFloat
    /// 生成时刻，后续所有运动都由这个时间戳推导，无需逐帧保存中间状态
    let birth: Date
}

enum WaterFieldMetrics {
    /// 水滴从生成到触及水面的时长
    static let fallDuration: Double = 0.5
    /// 入水水花从溅起到落回的时长（短促，不留尾）
    static let splashDuration: Double = 0.34
    /// 一滴水的完整生命周期（超过就回收）
    static var lifetime: Double { fallDuration + splashDuration }
    /// 同时存在的水滴上限
    static let maxActiveDrops = 14
}

/// 水滴累积池
///
/// 刻意放弃「从左到右填充」的横向形态 —— 那种形态天然有个 100% 的尽头，
/// 而流式返回的音频根本无从得知什么时候结束。
///
/// 改用「水池」的隐喻，一切都在表达"还在往里堆"而不是"还差多少"：
/// - 每收到一批数据就滴下一滴水，触面后只溅起一小朵水花、随即落回水面消失；
///   刻意不画向外扩散的同心波纹 —— 那种一圈圈荡开的形态会让人去数圈、找边界，
///   反而把注意力从"还在累积"拉回到"发生了几次"上；
/// - 水面持续做微波起落，即便数据暂时断流也始终是活的；
/// - 池底水位随累积总量缓慢抬高，并且永远留有余量，不会给出"快满了"的暗示；
/// - 没有终点线、没有刻度：看不到尽头。
struct WaterDropField: View {
    /// 水位，从池底算起 0~1
    var level: Double
    var drops: [WaterDrop]
    var isRaining: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: false)) { timeline in
            Canvas { context, size in
                render(context: &context, size: size, now: timeline.date)
            }
        }
    }

    private func render(context: inout GraphicsContext, size: CGSize, now: Date) {
        let clampedLevel = min(max(level, 0), 1)
        // 有数据在收时水面起伏更大，断流时收敛但依然是活的
        let amplitude: CGFloat = isRaining ? 2.6 : 1.4
        let baseY = size.height * CGFloat(1 - clampedLevel)
        let t = CGFloat(now.timeIntervalSinceReferenceDate)

        // 两道不同波长、反向流动的正弦叠加，看不出明显周期
        func surfaceY(atX x: CGFloat, phase: CGFloat) -> CGFloat {
            let w1 = sin(x / 150.0 + t * 1.1 + phase) * amplitude
            let w2 = sin(x / 82.0 - t * 0.8 + phase) * amplitude * 0.55
            return baseY + w1 + w2
        }

        // 1) 水体：水面以下一整块，竖向渐变
        let waterPath = Path { path in
            path.move(to: CGPoint(x: 0, y: size.height))
            let steps = 28
            for i in 0...steps {
                let x = size.width * CGFloat(i) / CGFloat(steps)
                path.addLine(to: CGPoint(x: x, y: surfaceY(atX: x, phase: 0)))
            }
            path.addLine(to: CGPoint(x: size.width, y: size.height))
            path.closeSubpath()
        }
        let waterGradient = Gradient(colors: [
            AppColor.accentPrimary.opacity(0.55),
            AppColor.accentSecondary.opacity(0.18)
        ])
        context.fill(
            waterPath,
            with: .linearGradient(
                waterGradient,
                startPoint: CGPoint(x: 0, y: baseY),
                endPoint: CGPoint(x: 0, y: size.height)
        )
        )

        // 2) 水面：主线 + 错开相位的淡影，做出厚度
        let mainLine = Path { path in
            let steps = 56
            for i in 0...steps {
                let x = size.width * CGFloat(i) / CGFloat(steps)
                let y = surfaceY(atX: x, phase: 0)
                if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                else { path.addLine(to: CGPoint(x: x, y: y)) }
            }
        }
        context.stroke(mainLine, with: .color(AppColor.accentGlow.opacity(0.9)), lineWidth: 1.4)

        let echoLine = Path { path in
            let steps = 56
            for i in 0...steps {
                let x = size.width * CGFloat(i) / CGFloat(steps)
                let y = surfaceY(atX: x, phase: 1.8)
                if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                else { path.addLine(to: CGPoint(x: x, y: y)) }
            }
        }
        context.stroke(echoLine, with: .color(AppColor.accentPrimary.opacity(0.22)), lineWidth: 1)

        // 3) 水滴：下落中 / 入水水花
        for drop in drops {
            let age = now.timeIntervalSince(drop.birth)
            guard age >= 0, age < WaterFieldMetrics.lifetime else { continue }

            let cx = drop.x * size.width
            let surfaceAtX = surfaceY(atX: cx, phase: 0)

            if age < WaterFieldMetrics.fallDuration {
                drawFallingDrop(context: &context,
                                x: cx,
                                surfaceY: surfaceAtX,
                                progress: age / WaterFieldMetrics.fallDuration)
            } else {
                let cycle = (age - WaterFieldMetrics.fallDuration) / WaterFieldMetrics.splashDuration
                guard cycle < 1 else { continue }
                drawSplash(context: &context, x: cx, surfaceY: surfaceAtX, cycle: cycle)
            }
        }
    }

    /// 下落中的水滴：越接近水面越快（二次方加速），拖尾随速度拉长
    private func drawFallingDrop(context: inout GraphicsContext,
                                 x: CGFloat,
                                 surfaceY: CGFloat,
                                 progress: Double) {
        let p = min(max(progress, 0), 1)
        let eased = p * p
        let y = surfaceY * CGFloat(eased)

        let length: CGFloat = 6 + 10 * CGFloat(p)
        let width: CGFloat = 2.2
        let rect = CGRect(x: x - width / 2, y: y - length, width: width, height: length)
        let gradient = Gradient(colors: [
            AppColor.accentGlow.opacity(0.15),
            AppColor.accentGlow.opacity(0.95)
        ])
        context.fill(
            Path(roundedRect: rect, cornerRadius: width / 2),
            with: .linearGradient(
                gradient,
                startPoint: CGPoint(x: x, y: y - length),
                endPoint: CGPoint(x: x, y: y)
            )
        )
    }

    /// 入水：只在入水点原地溅起一小朵水花随即落回，刻意不画向外扩散的圈
    private func drawSplash(context: inout GraphicsContext,
                            x: CGFloat,
                            surfaceY: CGFloat,
                            cycle: Double) {
        let c = min(max(cycle, 0), 1)
        let fade = pow(1 - c, 1.6)

        // 摊开的水花
        let radius: CGFloat = 2.0 + 3.6 * CGFloat(c)
        let height = radius * 0.62
        let splash = CGRect(x: x - radius, y: surfaceY - height / 2,
                            width: radius * 2, height: height)
        context.fill(
            Path(ellipseIn: splash),
            with: .color(AppColor.accentGlow.opacity(fade * 0.85))
        )

        // 向上溅起又落回的细水柱（只占前 60% 时长）
        guard c < 0.6 else { return }
        let jet = c / 0.6
        let jetHeight: CGFloat = 8.0 * CGFloat(sin(jet * .pi))
        let jetWidth: CGFloat = 1.4
        let jetRect = CGRect(x: x - jetWidth / 2, y: surfaceY - jetHeight,
                             width: jetWidth, height: jetHeight)
        context.fill(
            Path(roundedRect: jetRect, cornerRadius: jetWidth / 2),
            with: .color(AppColor.accentGlow.opacity((1 - jet) * 0.7))
        )
    }
}

/// 音频数据累积监视器
///
/// 用「水池」表达"还在持续累积"：每收到一批数据就滴下一滴水，
/// 触面后原地溅起一小朵水花随即落回；水位随累积量缓慢抬高且永远留有余量。
struct AudioAccumulationMonitor: View {
    let bytes: Int
    let progress: Double
    let isActive: Bool

    /// 水位上限：永远不满，不给"快好了"的暗示
    private static let poolCeiling: Double = 0.82
    /// 目标滴速（滴/秒）：据此把实时速率折算成「一滴代表多少字节」
    private static let targetDropsPerSecond: Double = 8
    /// 两滴之间的最小间隔
    private static let minDropInterval: Double = 0.07
    /// 欠账上限：避免长时间无数据后一次性补一大串
    private static let maxDropBudget: Double = 6

    /// 平滑显示的字节数（追赶真实值，形成滚动累加的观感）
    @State private var displayBytes: Double = 0
    /// 实时接收速率（字节/秒，EMA 平滑）
    @State private var speed: Double = 0
    @State private var sampleBytes: Int = 0
    @State private var sampleDate: Date = Date()
    /// 正在下落 / 溅起的水滴
    @State private var drops: [WaterDrop] = []
    /// 累积的"欠账"：本帧应收到的水滴数（可能是小数）
    @State private var dropBudget: Double = 0
    @State private var lastDropDate: Date = Date()

    private let ticker = Timer.publish(every: 1.0 / 24.0, on: .main, in: .common).autoconnect()

    private var level: Double {
        AccumulationCurve.fill(bytes: displayBytes, timeProgress: progress) * Self.poolCeiling
    }

    var body: some View {
        VStack(spacing: 12) {
            // 水滴累积池
            WaterDropField(level: level, drops: drops, isRaining: isActive)
                .frame(height: 120)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.small))

            // 数值 + 速率
            HStack(spacing: 6) {
                Image(systemName: "drop.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(AppColor.accentPrimary)

                Text("已接收: %@".localized(formatDataSize(Int(displayBytes))))
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    .foregroundStyle(AppColor.textPrimary)

                Spacer()

                HStack(spacing: 5) {
                    Circle()
                        .fill(speed > 0 ? AppColor.statusSuccess : AppColor.textTertiary)
                        .frame(width: 6, height: 6)
                    Text(formatDataSpeed(speed))
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(AppColor.textTertiary)
                }
                .opacity(isActive ? 1 : 0.6)
            }
        }
        .padding(16)
        .background(AppColor.bgTertiary)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.medium)
                .stroke(AppColor.borderSubtle, lineWidth: 1)
        )
        .onReceive(ticker) { now in
            tick(now)
        }
        .onChange(of: isActive) { _, active in
            if !active {
                // 停止接收：清掉在途水滴，让水面回归平静
                drops.removeAll()
                dropBudget = 0
                speed = 0
            } else {
                sampleBytes = bytes
                sampleDate = Date()
            }
        }
    }

    /// 每帧：平滑追赶字节数、按实时吞吐折算水滴；每 0.5 秒重算一次速率
    private func tick(_ now: Date) {
        let target = Double(bytes)
        let delta = target - displayBytes
        if delta > 0 {
            displayBytes = min(target, displayBytes + max(delta * 0.22, 8))
        } else {
            displayBytes = target
        }

        let elapsed = now.timeIntervalSince(sampleDate)
        if elapsed >= 0.5 {
            let instant = max(0, Double(bytes - sampleBytes)) / elapsed
            speed = speed * 0.4 + instant * 0.6
            sampleBytes = bytes
            sampleDate = now
        }

        guard isActive else { return }

        // 回收过期的水滴
        if let oldest = drops.first, now.timeIntervalSince(oldest.birth) > WaterFieldMetrics.lifetime {
            drops.removeFirst()
        }

        // 按当前速率往预算里加，攒够一滴就落一滴
        let bytesPerDrop = max(1, speed / Self.targetDropsPerSecond)
        dropBudget = min(dropBudget + delta / bytesPerDrop, Self.maxDropBudget)
        while dropBudget >= 1 && drops.count < WaterFieldMetrics.maxActiveDrops {
            guard now.timeIntervalSince(lastDropDate) >= Self.minDropInterval else { break }
            drops.append(WaterDrop(x: CGFloat.random(in: 0.06...0.94), birth: now))
            dropBudget -= 1
            lastDropDate = now
        }
    }
}

// MARK: - 通用图标按钮

/// 通用的图标按钮组件，可复用
/// - Parameters:
///   - icon: SF Symbol 图标名
///   - title: 按钮文字
///   - isLoading: 是否显示加载状态
///   - action: 点击回调
struct ActionIconButton: View {
    let icon: String
    let title: String
    var isLoading: Bool = false
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            ZStack {
                VStack(spacing: 4) {
                    Image(systemName: icon)
                        .font(.system(size: 14))
                    Text(title)
                        .font(.system(size: 10))
                }
                .foregroundStyle(AppColor.textSecondary)
                .opacity(isLoading ? 0 : 1)
                
                if isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(0.6)
                }
            }
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .disabled(isLoading)
    }
}

// MARK: - 预览

/// 模拟 wav/48kHz 下约 90KB/s 的持续到达，并配一条 11 秒的时间轴，
/// 用来反复观察"数据一直往里堆"的观感（可在 Xcode Canvas 里直接调参）
private struct AccumulationAnimationPreview: View {
    @State private var bytes: Int = 0
    @State private var startedAt: Date = Date()

    private static let expectedDuration: TimeInterval = 11
    private static let bytesPerSecond: Double = 90_000

    private let ticker = Timer.publish(every: 1.0 / 12.0, on: .main, in: .common).autoconnect()

    private var progress: Double {
        min(0.95, 0.05 + 0.90 * (Date().timeIntervalSince(startedAt) / Self.expectedDuration))
    }

    var body: some View {
        VStack(spacing: 18) {
            AudioAccumulationMonitor(bytes: bytes, progress: progress, isActive: true)

            HStack(spacing: 12) {
                Button("模拟一批数据") { bytes += Int.random(in: 4_000...16_000) }
                Button("重置") {
                    bytes = 0
                    startedAt = Date()
                }
            }
            .buttonStyle(.bordered)
        }
        .frame(width: 480)
        .padding(40)
        .background(AppColor.bgSecondary)
        .onReceive(ticker) { _ in
            let chunk = Int(Self.bytesPerSecond / 12.0)
            bytes += max(1, chunk + Int.random(in: -800...800))
        }
    }
}

#Preview("音频数据累积动画") { AccumulationAnimationPreview() }

// MARK: - 高度测量

/// 把标注过的子视图实际高度向上冒泡，弹窗据此把内容区收到贴合高度
private struct MeasuredHeight: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct MeasureHeight: ViewModifier {
    func body(content: Content) -> some View {
        content.background(
            GeometryReader { proxy in
                Color.clear.preference(key: MeasuredHeight.self, value: proxy.size.height)
            }
        )
    }
}

private extension View {
    func measureHeight() -> some View { modifier(MeasureHeight()) }
}

// MARK: - 音频生成弹窗

struct AudioGenerationModal: View {
    @ObservedObject var vm: VoiceStudioViewModel
    @Binding var isPresented: Bool

    /// 完成态内容区最大高度：再长就改为内部滚动，避免把弹窗顶出屏幕
    private static let completedContentMaxHeight: CGFloat = 460

    @State private var isCompleted: Bool = false
    @State private var audioName: String = ""
    @State private var isEditingName: Bool = false
    @State private var isPlaying: Bool = false
    @State private var playbackProgress: Double = 0.0
    @State private var playbackTimer: Timer? = nil
    @State private var showDownloadOverlay: Bool = false
    @State private var isExporting: Bool = false
    @State private var exportSuccess: Bool = false
    @State private var isSeeking: Bool = false  // 是否正在拖动滑块
    @State private var playerIsPlaying: Bool = false  // 播放器实际播放状态
    
    // 使用真实的音频时长（生成完成后从 ViewModel 获取）
    @State private var audioDuration: TimeInterval = 0
    // 记录播放开始时的系统时间，用于精确计算进度
    @State private var playbackStartTime: Date?

    /// 完成态内容区的实测高度（初值取经验值；只在拿到有效测量后才更新）
    @State private var completedContentHeight: CGFloat = 450

    var body: some View {
        ZStack {
            // 遮罩
            Color.black.opacity(0.75)
                .ignoresSafeArea()
                .onTapGesture {
                    if !isGenerating { isPresented = false }
                }
            
            // 弹窗主体
            VStack(spacing: 0) {
                // 头部
                header
                
                // 内容
                if isGenerating {
                    generatingContent
                } else {
                    completedContent
                }
                
                // 底部
                footer
            }
            .frame(width: 520)
            .background(AppColor.bgSecondary)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.large))
            .shadow(color: .black.opacity(0.6), radius: 40, x: 0, y: 12)
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.large)
                    .stroke(AppColor.borderSubtle, lineWidth: 1)
            )
        }
        .animation(.easeInOut(duration: 0.35), value: isGenerating)
        .animation(.easeInOut(duration: 0.35), value: isCompleted)
        // 弹窗与工作台的 NSTextView 共处同一窗口，鼠标从文本域移上来时光标可能还停留在 I-beam。
        // 这里在弹窗出现的当下先复位成箭头，之后由各控件的 hover 接管。
        .onAppear { NSCursor.arrow.set() }
        .onPreferenceChange(MeasuredHeight.self) { height in
            // 完成态分支不在层级里时会回落成 0，这里忽略无效值，避免卡片被压扁
            if height > 0 { completedContentHeight = height }
        }
        // 弹窗改由整窗 overlay 承载后不再有 sheet 自带的 Esc 关闭，这里补回来
        .onExitCommand {
            if !isGenerating { isPresented = false }
        }
        .onChange(of: vm.generationProgress) { _, newProgress in
            if newProgress >= 1.0 {
                withAnimation {
                    isCompleted = true
                }
            }
        }
        .onChange(of: vm.generatedAudioDuration) { _, newDuration in
            // 文件保存成功后立即更新时长
            if newDuration > 0 {
                audioDuration = newDuration
            }
        }
        .onAppear {
            audioName = generateDefaultAudioName()

            // 观察播放器实际播放状态
            observePlayerState()
        }
        .onDisappear {
            playbackTimer?.invalidate()
            AudioPreviewPlayer.shared.stop()
        }
        .onChange(of: AudioPreviewPlayer.shared.isPlaying) { _, newValue in
            playerIsPlaying = newValue
            // 外部停止（如系统控制中心）时同步状态
            if !newValue && isPlaying {
                isPlaying = false
                playbackTimer?.invalidate()
            }
        }
    }
    
    /// 观察播放器状态
    private func observePlayerState() {
        Task { @MainActor in
            playerIsPlaying = AudioPreviewPlayer.shared.isPlaying
        }
    }
    
    // MARK: - 计算属性
    
    private var isGenerating: Bool {
        vm.isGenerating && !isCompleted
    }

    /// 完成态内容区高度：贴合内容，超过上限则改为内部滚动
    private var completedScrollHeight: CGFloat {
        min(max(completedContentHeight, 0), Self.completedContentMaxHeight)
    }

    private var currentVoice: Voice? {
        vm.voice
    }
    
    private var estimatedRemainingTime: Int {
        let remaining = 1.0 - vm.generationProgress
        return max(1, Int(remaining * 10))
    }
    
    /// 格式化文件大小
    private var formattedFileSize: String {
        let bytes = vm.receivedBytes
        if bytes < 1000 {
            return "\(bytes) B"
        } else if bytes < 1000 * 1000 {
            return String(format: "%.1f KB", Double(bytes) / 1000.0)
        } else {
            return String(format: "%.2f MB", Double(bytes) / (1000.0 * 1000.0))
        }
    }
    
    private var formattedDuration: String {
        let duration = audioDuration > 0 ? audioDuration : 0
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    private var formattedCurrentTime: String {
        let duration = audioDuration > 0 ? audioDuration : 1
        let current = duration * playbackProgress
        let minutes = Int(current) / 60
        let seconds = Int(current) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    /// 时长格式化 HH:mm:ss
    private var formattedDurationHHMMSS: String {
        let duration = audioDuration > 0 ? audioDuration : 0
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
    }

    /// 格式化采样率
    private func formatSampleRate(_ rate: Int) -> String {
        if rate >= 1000 {
            return "\(rate / 1000) kHz"
        } else {
            return "\(rate) Hz"
        }
    }
    
    // MARK: - 头部
    
    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        LinearGradient(
                            colors: [AppColor.accentPrimary, AppColor.accentSecondary],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 28, height: 28)
                Text("🎵")
                    .font(.system(size: 14))
            }
            
            Text(isCompleted ? "生成完成" : "音频生成")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppColor.textPrimary)
            
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Color.clear)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AppColor.borderSubtle)
                .frame(height: 0.5)
        }
    }
    
    // MARK: - 生成中内容
    
    private var generatingContent: some View {
        // 生成中内容是定高的短块，不需要 ScrollView ——
        // ScrollView 会吃掉容器全部剩余高度，导致卡片被撑满、底部留出大片空白
        VStack(spacing: 20) {
            // 静态图标（无旋转动画）
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                AppColor.accentPrimary.opacity(0.15),
                                AppColor.accentPrimary.opacity(0.05)
                    ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 72, height: 72)
                    .overlay(
                        Circle()
                            .stroke(AppColor.accentPrimary.opacity(0.25), lineWidth: 1)
                    )

                Text("⚡")
                    .font(.system(size: 28))
            }
            .frame(width: 80, height: 80)

            // 标题
            Text("正在合成音频")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(AppColor.textPrimary)

            // 副标题
            Text(voiceInfoSubtitle)
                .font(.system(size: 13))
                .foregroundStyle(AppColor.textTertiary)

            // 已接收数据大小（持续累积动画）
            AudioAccumulationMonitor(
                bytes: vm.receivedBytes,
                progress: vm.generationProgress,
                isActive: isGenerating
            )
        }
        .padding(20)
    }
    
    // MARK: - 完成内容
    
    private var completedContent: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 16) {
                    // 音频信息
                    audioInfoCard

                    // 音频播放器
                    audioPlayerCard

                    // 音色信息
                    voiceInfoRow

                    // 标签
                    tagsSection

                    // 消耗积分
                    costInfo
                }
                .padding(20)
                // 上报实际内容高度，弹窗据此把内容区收到贴合高度
                .measureHeight()
            }
            // 内容短则收缩、超长则内部滚动，卡片不会被撑满
            .frame(height: completedScrollHeight)
        }
    }
    
    // MARK: - 音频信息卡片
    
    private var audioInfoCard: some View {
        HStack(spacing: 16) {
            // 头像
            ZStack(alignment: .topTrailing) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [AppColor.accentPrimary, AppColor.accentSecondary],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 52, height: 52)
                    
                    Text("🎵")
                        .font(.system(size: 18, weight: .bold))
                }
                
                // 成功徽章
                if isCompleted {
                    ZStack {
                        Circle()
                            .fill(AppColor.statusSuccess)
                            .frame(width: 20, height: 20)
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .shadow(color: AppColor.statusSuccess.opacity(0.4), radius: 4)
                    .offset(x: 4, y: -4)
                }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    if isEditingName {
                        TextField("音频名称", text: $audioName)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(AppColor.textPrimary)
                            .textFieldStyle(.plain)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(AppColor.bgElevated)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(AppColor.borderMedium, lineWidth: 1)
                            )
                            .onSubmit {
                                isEditingName = false
                            }
                    } else {
                        Text(audioName)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(AppColor.textPrimary)
                    }
                    
                    Button {
                        isEditingName.toggle()
                        if !isEditingName && audioName.isEmpty {
                            audioName = generateDefaultAudioName()
                        }
                    } label: {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 14))
                            .foregroundStyle(AppColor.textTertiary)
                            .frame(width: 22, height: 22)
                            .background(Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)
                    .pointingHandCursor()
                }
                
                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Image(systemName: "doc")
                            .font(.system(size: 10))
                        Text(formattedFileSize)
                    }

                    Text("·")

                    Text(formatSampleRate(vm.sampleRate))

                    Text("·")

                    Text(vm.selectedFormat.uppercased())

                    Text("·")

                    Text(formattedDurationHHMMSS)
                }
                .font(.system(size: 12))
                .foregroundStyle(AppColor.textTertiary)
            }
            
            Spacer()
        }
        .padding(16)
        .background(AppColor.bgTertiary)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium))
    }
    
    // MARK: - 音频播放器
    
    private var audioPlayerCard: some View {
        VStack(spacing: 12) {
            // 播放按钮 + 波形条撑满整行
            GeometryReader { geometry in
                HStack(spacing: 16) {
                    // 播放按钮
                    Button {
                        togglePlayback()
                    } label: {
                        ZStack {
                            Circle()
                                .fill(
                                    LinearGradient(
                                        colors: [AppColor.accentPrimary, AppColor.accentSecondary],
                                        startPoint: .topLeading,
                                        endPoint: .bottomTrailing
                                    )
                                )
                                .frame(width: 48, height: 48)
                                .shadow(color: AppColor.accentPrimary.opacity(0.3), radius: 8, y: 4)

                            if isPlaying {
                                // 暂停图标
                                HStack(spacing: 3) {
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(AppColor.bgPrimary)
                                        .frame(width: 4, height: 16)
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(AppColor.bgPrimary)
                                        .frame(width: 4, height: 16)
                                }
                            } else {
                                // 播放图标
                                Image(systemName: "play.fill")
                                    .font(.system(size: 16))
                                    .foregroundStyle(AppColor.bgPrimary)
                                    .offset(x: 2)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .pointingHandCursor()

                    // 波形条撑满剩余空间
                    let barCount = max(20, Int(geometry.size.width / 5))
                    HStack(spacing: 2) {
                        ForEach(0..<barCount, id: \.self) { i in
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(i < Int(Double(barCount) * playbackProgress) ? AppColor.accentPrimary : AppColor.bgElevated)
                                .frame(width: 3, height: CGFloat.random(in: 8...40))
                        }
                    }
                    .frame(height: 50)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(height: 50)

            // 进度条
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(AppColor.bgElevated)
                        .frame(height: 4)

                    RoundedRectangle(cornerRadius: 2)
                        .fill(
                            LinearGradient(
                                colors: [AppColor.accentPrimary, AppColor.accentGlow],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geometry.size.width * playbackProgress, height: 4)
                }
                .frame(height: 4)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            isSeeking = true
                            let progress = max(0, min(1, value.location.x / geometry.size.width))
                            playbackProgress = progress
                        }
                        .onEnded { value in
                            isSeeking = false
                            let progress = max(0, min(1, value.location.x / geometry.size.width))
                            playbackProgress = progress
                            // 同步到播放器实际时间
                            let seekTime = audioDuration * progress
                            AudioPreviewPlayer.shared.seek(to: seekTime)
                        }
                )
            }
            .frame(height: 4)
            .pointingHandCursor()

            // 底部时间：左 = 当前进度，右 = 总时长
            HStack {
                Text(formattedCurrentTime)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(AppColor.textSecondary)
                Spacer()
                Text(formattedDuration)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(AppColor.textTertiary)
            }
        }
        .padding(20)
        .background(AppColor.bgTertiary)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium))
    }
    
    // MARK: - 音色信息
    
    private var voiceInfoRow: some View {
        HStack(spacing: 12) {
            if let voice = currentVoice {
                AvatarView(text: String(voice.name.prefix(1)), size: 32)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(voice.isPremium ? "\(voice.name) · 旗舰音色" : voice.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AppColor.textPrimary)
                    
                    HStack(spacing: 4) {
                        if !voice.gender.isEmpty {
                            Text(voice.gender)
                        }
                        if let age = voice.age {
                            Text("\(age)岁")
                        }
                        if !voice.lang.isEmpty {
                            Text("· \(voice.lang)")
                        }
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(AppColor.textTertiary)
                }
                
                Spacer()
            }
        }
        .padding(12)
        .background(AppColor.bgTertiary)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium))
    }
    
    // MARK: - 标签
    
    private var tagsSection: some View {
        HStack(spacing: 6) {
            if let voice = currentVoice {
                if !voice.scene.isEmpty {
                    tagView(voice.scene, isAccent: true)
                }
                if !voice.desc.isEmpty {
                    tagView(voice.desc, isAccent: false)
                }
            }
        }
    }
    
    private func tagView(_ text: String, isAccent: Bool) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(isAccent ? AppColor.accentGlow : AppColor.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(isAccent ? AppColor.accentPrimary.opacity(0.12) : AppColor.bgTertiary)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(
                        isAccent ? AppColor.accentPrimary.opacity(0.25) : AppColor.borderSubtle,
                        lineWidth: 1
                    )
            )
    }
    
    // MARK: - 消耗积分
    
    private var costInfo: some View {
        HStack {
            HStack(spacing: 6) {
                Text("💎")
                    .font(.system(size: 14))
                Text("消耗积分")
                    .font(.system(size: 12))
                    .foregroundStyle(AppColor.textTertiary)
            }
            
            Spacer()
            
            Text(formatCredits(vm.estimatedPoints))
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundStyle(AppColor.accentPrimary)
        }
        .padding(12)
        .background(
            LinearGradient(
                colors: [
                    AppColor.accentPrimary.opacity(0.08),
                    AppColor.accentPrimary.opacity(0.02)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.medium)
                .stroke(AppColor.accentPrimary.opacity(0.15), lineWidth: 1)
        )
    }
    
    // MARK: - 底部
    
    private var footer: some View {
        HStack(spacing: 12) {
            if isCompleted {
                // 小尺寸的操作按钮 - 统一样式
                HStack(spacing: 16) {
                    // 导出按钮
                    exportButton
                }
            }
            
            Spacer()
            
            Button {
                if isCompleted {
                    saveAudioNameIfNeeded()
                    isPresented = false
                }
            } label: {
                HStack(spacing: 6) {
                    Text("完成")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(AppColor.bgPrimary)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(
                    LinearGradient(
                        colors: [AppColor.accentPrimary, AppColor.accentSecondary],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.small))
                .shadow(color: AppColor.accentPrimary.opacity(0.25), radius: 8, y: 4)
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
            .opacity(isCompleted ? 1 : 0)
            .disabled(!isCompleted)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(
            Color.clear
                .background(AppColor.bgSecondary.opacity(0.4))
        )
        .overlay(alignment: .top) {
            Rectangle()
                .fill(AppColor.borderSubtle)
                .frame(height: 0.5)
        }
        .opacity(isCompleted ? 1 : 0)
        .disabled(!isCompleted)
    }
    
    private var downloadOverlaySmall: some View {
        Text("导出中...")
            .font(.system(size: 10))
            .foregroundStyle(AppColor.textPrimary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(AppColor.bgPrimary)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
    
    // MARK: - 导出和分享按钮
    
    /// 导出按钮
    private var exportButton: some View {
        ActionIconButton(icon: "arrow.down.doc", title: "导出", isLoading: isExporting) {
            exportAudio()
        }
    }
    
    // MARK: - 导出功能
    
    /// 导出音频到用户选择的位置
    private func exportAudio() {
        guard let sourceURL = vm.generatedAudioURL else {
            Log(message: "AudioGenerationModal: 无音频文件可导出")
            return
        }
        
        isExporting = true
        
        // 确定默认文件名
        let defaultFileName = "\(audioName).\(sourceURL.pathExtension)"
        
        // 创建保存面板
        let savePanel = NSSavePanel()
        savePanel.title = "导出音频".localized()
        savePanel.message = "选择保存位置".localized()
        savePanel.nameFieldStringValue = defaultFileName
        savePanel.canCreateDirectories = true
        savePanel.allowedContentTypes = [.audio]
        
        // 显示面板
        savePanel.begin { [self] response in
            if response == .OK, let destinationURL = savePanel.url {
                // 复制文件到目标位置
                do {
                    // 如果目标文件已存在，先删除
                    if FileManager.default.fileExists(atPath: destinationURL.path) {
                        try FileManager.default.removeItem(at: destinationURL)
                    }
                    try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
                    
                    Log(message: "AudioGenerationModal: 导出成功 - \(destinationURL.path)")
                    
                    // 打开包含导出文件的文件夹
                    NSWorkspace.shared.selectFile(destinationURL.path, inFileViewerRootedAtPath: destinationURL.deletingLastPathComponent().path)
                    
                    // 显示成功提示
                    DispatchQueue.main.async {
                        isExporting = false
                        exportSuccess = true
                        // 2秒后自动隐藏成功提示
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
    
    // MARK: - 辅助方法
    
    private var voiceInfoSubtitle: String {
        guard let voice = currentVoice else { return "" }
        return "\(voice.name) · \(voice.desc) · 情感标签"
    }
    
    private func generateDefaultAudioName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        return "音频_\(formatter.string(from: Date()))"
    }
    
    /// 保存编辑后的音频名称
    private func saveAudioNameIfNeeded() {
        guard let audioId = vm.generatedAudioId else { return }
        
        let nameToSave = audioName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !nameToSave.isEmpty && nameToSave != generateDefaultAudioName() {
            ProjectService.shared.renameAudio(id: audioId, displayName: nameToSave)
        }
    }
    
    private func togglePlayback() {
        // 确保有生成的音频 URL
        guard let audioURL = vm.generatedAudioURL else {
            Log(message: "AudioGenerationModal: 无音频文件可播放")
            return
        }
        
        Task { @MainActor in
            let player = AudioPreviewPlayer.shared
            
            if player.isPlaying(url: audioURL) {
                // 正在播放同一文件 → 暂停
                player.stop()
                isPlaying = false
                playbackTimer?.invalidate()
            } else {
                // 停止之前的播放
                player.stop()
                playbackProgress = 0
                
                // 播放前验证文件有效性
                guard FileManager.default.fileExists(atPath: audioURL.path) else {
                    Log(message: "AudioGenerationModal: 音频文件不存在")
                    isPlaying = false
                    return
                }
                
                // 检查文件大小（过小的文件可能不完整）
                do {
                    let attributes = try FileManager.default.attributesOfItem(atPath: audioURL.path)
                    if let fileSize = attributes[.size] as? Int64, fileSize < 1000 {
                        Log(message: "AudioGenerationModal: 音频文件过小，可能不完整")
                        isPlaying = false
                        return
                    }
                } catch {
                    Log(message: "AudioGenerationModal: 无法读取文件属性: \(error)")
                }
                
                // 开始播放
                if player.play(url: audioURL, identifier: audioURL.path) {
                    isPlaying = true
                    // 从 ViewModel 获取真实时长
                    audioDuration = vm.generatedAudioDuration
                    startPlaybackTimer()
                } else {
                    Log(message: "AudioGenerationModal: 播放失败")
                    isPlaying = false
                }
            }
        }
    }
    
    private func startPlaybackTimer() {
        playbackTimer?.invalidate()
        let duration = audioDuration > 0 ? audioDuration : 1.0
        
        // 记录播放开始时间，用于精确计算进度
        playbackStartTime = Date()
        
        // 延迟启动定时器，等待播放器状态稳定
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                Task { @MainActor in
                    let player = AudioPreviewPlayer.shared
                    guard let url = self.vm.generatedAudioURL else { return }
                    
                    // 如果正在拖动滑块，跳过进度更新
                    if self.isSeeking {
                        return
                    }
                    
                    if player.isPlaying(url: url) {
                        // 使用播放器实际时间计算进度
                        let currentTime = player.currentTime
                        if duration > 0 {
                            self.playbackProgress = min(1.0, currentTime / duration)
                        }
                    } else {
                        // 播放结束或停止
                        if self.isPlaying {
                            self.isPlaying = false
                            self.playbackProgress = 0
                        }
                        self.playbackTimer?.invalidate()
                    }
                }
            }
        }
    }
}
