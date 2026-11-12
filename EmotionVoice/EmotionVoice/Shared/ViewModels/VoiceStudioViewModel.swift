//
//  VoiceStudioViewModel.swift
//  EmotionVoice
//
//  Created by young on 2026/8/8.
//

import Foundation
import SwiftUI
import Combine
#if canImport(AppKit)
import AppKit
#endif

// MARK: - 生成过程的实时接收统计

/// 一次生成过程里不断变化的接收数据：字节数、段数、进度
///
/// 存在的意义只有一个：**把它和 VoiceStudioViewModel 分开**。
/// `ObservableObject` 的失效是粗粒度的 —— 对象里任何一个 @Published 被写，
/// 所有订阅它的视图都会重算 body。工作台（VoiceStudioView）订阅的是 VM，
/// 里面还挂着一个 NSTextView 编辑器，重算代价不小；而 WebSocket 的 onAudio
/// 回调一秒能来几十上百次。把这些高频字段挪进来、只让生成弹窗订阅它，
/// 接收期间工作台一次都不会被惊动。
///
/// 发布节流见 `receive(bytes:estimatedProgress:)`：约 10Hz 落一次；
/// 段数是真实累加的（与每次 onAudio 一一对应），只是批量发布。
@MainActor
final class GenerationStats: ObservableObject {

    /// 已接收的音频数据字节数
    @Published private(set) var receivedBytes: Int = 0
    /// 已收到的数据块数量（真实段数）
    @Published private(set) var receivedChunks: Int = 0
    /// 生成进度（0~1）
    @Published private(set) var progress: Double = 0

    // MARK: 节流缓冲

    private var pendingBytes: Int = 0
    private var pendingChunks: Int = 0
    private var pendingProgress: Double = 0
    private var lastFlushDate: Date = .distantPast

    /// 发布节流间隔：每个数据块都发会把订阅视图刷爆
    private static let flushInterval: TimeInterval = 0.1

    /// 归零，准备下一次生成
    func reset() {
        receivedBytes = 0
        receivedChunks = 0
        progress = 0
        pendingBytes = 0
        pendingChunks = 0
        pendingProgress = 0
        lastFlushDate = .distantPast
    }

    /// 记下一块到达的真实数据（字节数 + 段数 + 基于时间的估算进度）
    func receive(bytes: Int, estimatedProgress: Double) {
        pendingBytes += bytes
        pendingChunks += 1
        pendingProgress = max(pendingProgress, estimatedProgress)

        let now = Date()
        if now.timeIntervalSince(lastFlushDate) >= Self.flushInterval {
            flush(now: now)
        }
    }

    /// 把缓冲里的数据一次性发布出去
    func flush(now: Date = Date()) {
        if pendingBytes > 0 {
            receivedBytes += pendingBytes
            pendingBytes = 0
        }
        if pendingChunks > 0 {
            receivedChunks += pendingChunks
            pendingChunks = 0
        }
        if pendingProgress > progress {
            progress = pendingProgress
        }
        pendingProgress = 0
        lastFlushDate = now
    }

    /// 直接推进进度（落盘、入库等阶段用，只增不减）
    func markProgress(_ value: Double) {
        pendingProgress = 0
        if value > progress { progress = value }
        lastFlushDate = Date()
    }
}

/// 语音合成工作台视图模型
///
/// 使用 shared 单例保证 VoiceStudioView 在多次进出（切换侧边栏）
/// 时仍保留文本输入、情感选择、语速音量等编辑状态。
@MainActor
final class VoiceStudioViewModel: ObservableObject {

    // MARK: - 单例

    /// 全局共享实例：保证页面切换时数据不丢失
    static let shared = VoiceStudioViewModel()

    /// 冷启动恢复上次使用的音色。
    ///
    /// ⚠️ 这里**只读不校验**：单例可能早于音色表同步完成就被创建，此刻
    /// `VoiceService.voice(forKey:)` 查不到并不代表 key 已失效。真正的回落
    /// 交给 `StudioView.onAppear`（那时音色必可查），避免「表还没就绪 → 记忆被默认音色覆盖」。
    init() {
        if let saved = UserDefaults.standard.string(forKey: Self.selectedVoiceKeyDefaultsKey),
           !saved.isEmpty {
            selectedVoiceKey = saved
        }
    }

    // MARK: - 状态

    // 文本（两套表示形式同步维护）
    //   - text: 纯字符串，用于 API 调用和字数统计
    //   - ttsItems: 结构化 items，用于 EmotionTokenEditor 渲染 token
    @Published var text: String = ""
    @Published var selectedRange: NSRange = NSRange(location: 0, length: 0)

    /// EmotionTokenEditor 的结构化数据：文本 + inline token
    @Published var ttsItems: [TTSContentItem] = []

    /// 触发 EmotionTokenEditor 在光标位置插入 token（insertTrigger 递增时触发）
    @Published var insertTokenTrigger: Int = 0
    @Published var insertTokenLabel: String = ""
    @Published var insertTokenEmoji: String = ""
    @Published var insertTokenEnglishTag: String = ""
    /// 本次插入 token 的家族（语气 / 拟声），供编辑器区分视觉风格
    @Published var insertTokenCategory: EmotionCategory = .emotion

    /// 触发 EmotionTokenEditor 清空所有 token
    @Published var clearTokensTrigger: Int = 0

    /// UserDefaults 键：上次使用的音色 key
    ///
    /// ⚠️ 与 `AppState.selectedVoiceKeyUDKey` 是**同一个字符串**（这里反过来引用本常量）：
    /// 工作台、音色库往这里写，冷启动时两边读到的都是这个值，不存在两套记忆。
    static let selectedVoiceKeyDefaultsKey = "selectedVoiceKey"

    // 音色
    ///
    /// ⚠️ 变更即落盘：单例在进程内本来就记得本次会话的选择，落盘是为了**冷启动**也能接上。
    /// 写入点是这里（而不是只在 `onAppear` 里同步），所以音色库「使用此音色」等
    /// 直接改 `selectedVoiceKey` 的路径同样会被记住。
    @Published var selectedVoiceKey: String = Constants.defaultVoice {
        didSet {
            guard selectedVoiceKey != oldValue else { return }
            UserDefaults.standard.set(selectedVoiceKey, forKey: Self.selectedVoiceKeyDefaultsKey)
        }
    }

    // 情感/语速/音量
    @Published var rate: Double = 1.0    // 0.5 - 2.0
    @Published var volume: Double = 100  // 0 - 100

    // 采样率/格式
    @Published var sampleRate: Int = Constants.defaultSampleRate
    @Published var selectedFormat: String = Constants.defaultFormat

    // 自然语言指令
    @Published var nlInstruction: String = ""

    // 选中的预设
    @Published var selectedPreset: String? = nil

    // 选中的语言
    @Published var selectedLanguage: String? = nil

    // 预设芯片（从 Constants 读取）
    var nlPresets: [String] {
        Constants.nlPresets.map { $0.name }
    }

    /// 应用预设
    func applyPreset(_ preset: String) {
        // 切换选中状态
        if selectedPreset == preset {
            selectedPreset = nil
        } else {
            selectedPreset = preset
        }
        updateNLInstruction()
    }

    /// 切换语言选择
    ///
    /// ⚠️ 语言 chip 只决定 TTS 请求的 `language_hints`（生成时走
    /// `Constants.languageHint(forName: selectedLanguage)`），**不写入指令输入框**：
    /// 输入框只放「想让声音怎么说话」的描述，语言名混进去会覆盖用户手打的指令。
    /// iOS / macOS 共用本方法，一处改两端生效。
    func toggleLanguage(_ language: String) {
        if selectedLanguage == language {
            selectedLanguage = nil
        } else {
            selectedLanguage = language
        }
    }

    /// 更新指令文本：只写入描述预设，语言不参与拼接
    ///
    /// ⚠️ 别把 `selectedLanguage` 加回来 —— 否则「先选语言、再点预设」时语言名
    /// 会跟着拼进输入框。指令必须是**当前界面语言**的文案：
    /// `nlPresets.instruction` 是中文原文兼本地化 key，三份 Localizable.strings
    /// 里已有译文；直接写原文会让英文 / 繁中界面下指令框冒出简体中文。
    /// iOS 与 macOS 共用本方法，一处改两端生效。
    private func updateNLInstruction() {
        nlInstruction = composedNLInstruction
    }

    /// 语言 + 预设拼出的指令文案。
    /// ⚠️ 拼接必须走 `.localized()`：两个值都是中文 key，直接拼原文会让英文 / 繁中界面冒出简体中文。
    private var composedNLInstruction: String {
        let parts: [String] = [
            selectedLanguage?.localized(),
            selectedPreset.flatMap { Constants.instructionForPreset($0)?.localized() }
        ].compactMap { $0 }
        // 中文沿用原来的半角逗号（零回归），英文补一个空格
        return parts.joined(separator: AppLanguage.isChinese ? "," : ", ")
    }

    /// 草稿导出：只存语义值。指令框被用户手改过时原文照存，避免丢内容。
    func exportNLInstruction() -> (language: String?, preset: String?, custom: String?) {
        let auto = composedNLInstruction
        return (selectedLanguage, selectedPreset, nlInstruction == auto ? nil : nlInstruction)
    }

    /// 草稿恢复：语义值按当前界面语言重新本地化拼接；自定义原文优先。
    func restoreNLInstruction(language: String?, preset: String?, custom: String?) {
        selectedLanguage = language
        selectedPreset = preset
        nlInstruction = custom ?? composedNLInstruction
    }

    // 生成状态
    @Published var isGenerating: Bool = false
    @Published var alertItem: AlertItem? = nil
    @Published var generatedAudioURL: URL? = nil

    /// 一次生成刚刚完成的信号（自增计数）
    ///
    /// 关掉弹窗后接收仍在后台继续，完成时靠它把弹窗重新唤起到完成态。
    /// 用自增计数而不是 Bool：连续两次生成时 onChange 能各触发一次。
    @Published private(set) var generationCompletedSignal: Int = 0

    /// 本次生成的开始时刻（后台卡片与弹窗共用，重开弹窗时已用时不归零）
    private(set) var generationStartedAt: Date? = nil
    @Published var generatedAudioId: Int64? = nil  // 用于保存编辑的名称
    @Published var generatedAudioDuration: TimeInterval = 0  // 生成的音频时长
    /// 生成过程的实时接收统计（字节数 / 段数 / 进度）
    ///
    /// 刻意单独成一个 ObservableObject，只有生成弹窗观察它 ——
    /// `ObservableObject` 的失效是粗粒度的：对象里任何一个 @Published 被写，
    /// 所有订阅它的视图都会重算 body。如果这些高频字段留在 VM 上，
    /// 每 100ms 一次更新就会把整个 VoiceStudioView（内含 NSTextView 编辑器）
    /// 一起拖下水。放到独立对象里之后，接收期间工作台一次都不重绘。
    let stats = GenerationStats()

    // TTS 服务
    private let ttsService = BailianTTSService.shared

    // MARK: - 计算属性

    /// 文本字符数（不含空白）
    var charCount: Int {
        ttsItems
            .filter { $0.isText }
            .map { $0.content }
            .joined()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .count
    }

    /// 不含任何情感 / 拟声标签的纯文本（入库、展示原文用）
    ///
    /// `text` 是把每个 token 的中文 label 直接拼进去的结果（"...笑声..."），
    /// 那些字是编辑器里的 UI 装饰，不是用户输入的台词，
    /// 落进 `audio_items.text` 会把历史「原文」污染掉（展示 / 复制 / 再编辑都会看到）。
    var plainText: String {
        ttsItems.toPlainText()
    }

    /// 预估积分消耗（使用 CreditManager 计算真实的积分消耗，最多保留 2 位小数）
    var estimatedPoints: Double {
        let charCount = TextSplitter.calculateCharCount(text)
        return CreditManager.shared.calculateCreditsDouble(for: .normalTTS(characterCount: charCount))
    }

    /// 当前音色
    var voice: Voice? {
        // ⚠️ 这是 SwiftUI body 里的计算属性：任何一次 body 求值都会跑一次。
        // 早先是 `fetchAll().first(where:)` —— 全表扫描 + 全量排序，叠在每一帧上就是卡顿。
        VoiceService.shared.voice(forKey: selectedVoiceKey)
    }

    // MARK: - 操作

    /// 在 EmotionTokenEditor 的光标位置插入「中断」标签。
    ///
    /// 中断标签不是一种情绪，而是一个**作用域边界**：从这里开始回到音色本身的
    /// 默认状态朗读，直到遇到下一个语气标签。它在发给 API 时会被剥掉
    /// （见 `Array.toTTSSegments()`），只用于把前后语气分段隔离。
    func insertInterrupt() {
        insertTokenLabel = Constants.interruptItem.label.localized()
        insertTokenEmoji = Constants.interruptItem.emoji
        insertTokenEnglishTag = Constants.interruptItem.tag
        insertTokenCategory = .interrupt
        insertTokenTrigger &+= 1
    }

    /// 在 EmotionTokenEditor 的光标位置插入情感标签。
    /// 触发 EmotionTokenEditor.updateNSView → insertToken(token)
    func insertEmotion(tag: String) {
        let emotions = Constants.emotions
        let rich = Constants.richLanguageTags
        guard let item = (emotions + rich).first(where: { $0.tag == tag }) else { return }
        insertTokenLabel = item.label.localized()
        insertTokenEmoji = item.emoji
        insertTokenEnglishTag = item.tag
        insertTokenCategory = rich.contains(where: { $0.tag == tag }) ? .richLanguage : .emotion
        insertTokenTrigger &+= 1
    }

    /// 清空文本
    func clearText() {
        text = ""
        ttsItems = []
        selectedRange = NSRange(location: 0, length: 0)
        clearTokensTrigger &+= 1
        alertItem = nil
        generatedAudioURL = nil
        stats.reset()
    }

    /// 从纯文本中解析 `[标签]` 并转换为 [TTSContentItem]。
    /// 用于：1) 初始化编辑器内容；2) 外部设置 text 时同步到 ttsItems。
    func textToItems(_ s: String) -> [TTSContentItem] {
        let pattern = "\\[([^\\]]+)\\]"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return s.isEmpty ? [] : [.text(s)]
        }
        let nsString = s as NSString
        let matches = regex.matches(in: s, range: NSRange(location: 0, length: nsString.length))

        var items: [TTSContentItem] = []
        var cursor = 0

        for match in matches {
            let openBracket = match.range.location
            let closeBracket = match.range.upperBound
            let labelRange = match.range(at: 1)
            guard let swiftRange = Range(labelRange, in: s) else { continue }
            let label = String(s[swiftRange])

            if openBracket > cursor {
                let textPart = nsString.substring(with: NSRange(location: cursor, length: openBracket - cursor))
                if !textPart.isEmpty { items.append(.text(textPart)) }
            }

            if label == Constants.interruptItem.label || label == Constants.interruptItem.tag {
                // 中断标签：作用域边界，不是一种语气
                items.append(.emotion(EmotionToken(label: Constants.interruptItem.label,
                                                   emoji: Constants.interruptItem.emoji,
                                                   englishTag: Constants.interruptItem.tag,
                                                   category: .interrupt)))
            } else if let emotionItem = (Constants.emotions + Constants.richLanguageTags)
                .first(where: { $0.label == label || $0.tag == label }) {
                let isRich = Constants.richLanguageTags.contains(where: { $0.label == label || $0.tag == label })
                let token = EmotionToken(label: emotionItem.label,
                                        emoji: emotionItem.emoji,
                                        englishTag: emotionItem.tag,
                                        category: isRich ? .richLanguage : .emotion)
                items.append(.emotion(token))
            } else {
                // 未识别的标签，保留为普通文本
                items.append(.text("[\(label)]"))
            }
            cursor = closeBracket
        }

        if cursor < nsString.length {
            let tail = nsString.substring(from: cursor)
            if !tail.isEmpty { items.append(.text(tail)) }
        }
        return items
    }
    
    /// 生成音频（集成阿里云 TTS 服务，无字符数限制）
    /// 验证已在 VoiceStudioView 中完成，此处直接开始生成并显示弹窗进度
    func generate(completion: @escaping (Bool) -> Void) {
        // 验证已在 VoiceStudioView.validateInputs() 中完成，此处直接开始生成
        
        // 直接使用结构化的 ttsItems 生成待合成的片段。
        //
        // ⚠️ 注意这里用的是 `toTTSSegments()` 而不是 `toTTSAPIString()`：
        // 中断标签（`[break]`）不是 API 支持的 tag，必须把它两侧的文本切成
        // **互相独立的请求**分别合成，否则前一个语气标签的作用域会越过中断标记
        // 继续影响后面的文本。合成完再按文档顺序拼接音频，即是完整朗读结果。
        let ttsSegments = ttsItems.toTTSSegments()
        let totalChars = ttsSegments.reduce(0) { $0 + $1.text.count }
        Log(message: "待合成 \(ttsSegments.count) 个片段，共 \(totalChars) 字符")

        // 预估积分消耗（在验证后立即计算）
        let points = estimatedPoints

        // 获取当前选中的音色
        guard let voice = self.voice else {
            alertItem = AlertItem(title: "无法生成".localized(),
                                   message: "请先选择一个音色".localized())
            completion(false)
            return
        }

        isGenerating = true
        generationStartedAt = Date()
        alertItem = nil
        stats.reset()
        generatedAudioURL = nil
        generatedAudioId = nil  // 重置音频 ID

        // 先用 wav 作为临时扩展名，生成后根据实际格式重命名
        let now = Date()
        let tempFileName = "\(now.filenameTimestamp).wav"

        // 落盘目录：Documents/GeneratedAudio/
        ensureGeneratedAudioDirectoryExists()
        let tempAudioURL = generatedAudioDirectoryURL().appendingPathComponent(tempFileName)

        // 显式声明强捕获：生成结束要写回 isGenerating / generatedAudioURL 等状态，
        // 弹窗关闭后还要靠 generationCompletedSignal 唤起，Task 期间 self 必须存活。
        // onAudio 内的 weak 是有意的：取消后残留的 WebSocket 回调应安全失效。
        Task { [self] in
            do {
                // 每个片段的进度窗口：片段 i 占 [i/n, (i+1)/n]，映射到 0.05 -> 0.95，
                // 保证整体进度单调递增（不会因为切段而回退）。
                let segmentCount = max(1, ttsSegments.count)
                var audioChunks: [Data] = []
                /// 每段的字级句子（段内相对时间），生成结束后统一叠加段偏移
                var segmentTimelines: [[AudioSentenceCue]] = []
                /// 每段音频的实际时长，作为下一段的时间轴起点
                var segmentDurations: [Double] = []

                for (idx, segment) in ttsSegments.enumerated() {
                    try Task.checkCancellation()

                    let windowStart = 0.05 + 0.90 * Double(idx) / Double(segmentCount)
                    let windowEnd = 0.05 + 0.90 * Double(idx + 1) / Double(segmentCount)
                    let startedAt = Date()
                    let approxDuration: TimeInterval = max(2.5, Double(segment.text.count) / 12.0)

                    let onAudio: (Data) -> Void = { [weak self] audioChunk in
                        guard let self else { return }
                        let elapsed = Date().timeIntervalSince(startedAt)
                        let frac = min(1.0, elapsed / approxDuration)
                        Task { @MainActor in
                            // 只写 stats（独立 ObservableObject），不会惊动订阅 VM 的工作台
                            self.stats.receive(bytes: audioChunk.count,
                                               estimatedProgress: windowStart +
                                                (windowEnd - windowStart) * frac)
                        }
                    }

                    let generation = try await ttsService.synthesizeWithTimeline(
                        text: segment.apiText,
                        voice: voice.key,
                        emotion: nil,
                        rate: rate,
                        volume: volume,
                        sampleRate: sampleRate,
                        format: self.selectedFormat.lowercased(),
                        nlInstruction: nlInstruction.isEmpty ? nil : nlInstruction,
                        // 语言 chip 选中项 → 百炼 language_hints；中文方言 / 未选 = nil
                        languageHint: Constants.languageHint(forName: selectedLanguage),
                        onAudio: onAudio,
                        // 字级字幕的显示文本以这段「纯台词」为准：apiText 里的
                        // `[emotion]` 前缀不是台词，上游 original_text 也不保证逐字一致
                        displaySource: segment.text
                    )
                    try Task.checkCancellation()
                    // 单个片段为空说明这一段没合成出音频，合并后会造成「缺了一段」的静默错误
                    guard !generation.audioData.isEmpty else { throw TTSError.noAudioData }
                    audioChunks.append(generation.audioData)
                    segmentTimelines.append(generation.sentences)

                    // 段偏移取「本段音频真实时长」：WAV 解析 header、MP3 按 32kbps 估算，
                    // 都拿不到时才退回该段最后一句的 end_time（宁可近似，也不能伪造字级锚点）。
                    let segmentSeconds = AudioConcatenator.durationSeconds(
                        of: generation.audioData,
                        format: self.selectedFormat,
                        sampleRate: sampleRate
                    ) ?? Double(generation.sentences.last?.endMs ?? 0) / 1000.0
                    segmentDurations.append(segmentSeconds)
                }

                let audioData = AudioConcatenator.merge(audioChunks)
                guard !audioData.isEmpty else { throw TTSError.noAudioData }

                // 收尾：把最后一段不足 100ms 的到达量补发，保证总数准确
                await MainActor.run { self.stats.flush() }

                stats.markProgress(0.95)

                // 写入磁盘（先用临时 wav 文件名）
                try audioData.write(to: tempAudioURL)
                Log(message: "音频已保存到: \(tempAudioURL.path)")

                stats.markProgress(0.98)
                
                // 检测 TTS 返回的实际音频格式
                let actualFormat = detectAudioFormat(from: audioData)
                Log(message: "检测到实际音频格式: \(actualFormat)")
                
                // 根据实际格式重命名文件
                let finalFileName = "\(now.filenameTimestamp).\(actualFormat)"
                let finalAudioURL = generatedAudioDirectoryURL().appendingPathComponent(finalFileName)
                try? FileManager.default.moveItem(at: tempAudioURL, to: finalAudioURL)
                Log(message: "文件重命名为: \(finalFileName)")

                // 计算真实时长（AVAsset 回退分支走异步 load，整条链改为 async）
                let duration = await AudioDuration.read(
                    url: finalAudioURL,
                    sampleRate: self.sampleRate,
                    bytes: audioData.count,
                    format: actualFormat
                )
                Log(message: "音频时长: \(duration)s")

                await MainActor.run {
                    // 直接创建音频条目
                    // 入库只存纯台词：情感 / 拟声 token 是编辑器里的装饰，
                    // 它们的 label（如「笑声」）不落库（历史原文、复制、再编辑都用它）
                    let createdAudio = ProjectService.shared.createAudio(
                        fileName: finalFileName,
                        text: self.plainText,
                        voice: voice.key,
                        format: actualFormat,
                        sampleRate: self.sampleRate,
                        pointsCost: points,
                        status: .completed,
                        duration: duration
                    )
                    guard let audio = createdAudio else {
                        self.alertItem = AlertItem(title: "保存失败".localized(),
                                                    message: "无法写入音频条目，请稍后重试".localized())
                    self.isGenerating = false
                    self.generationStartedAt = nil
                    self.stats.reset()
                    completion(false)
                    return
                }

                    // 字级时间轴落盘（sidecar，不入库）。
                    // 只有「每一段都拿到了 words[]」才认为对齐可信；任一段缺失
                    // （音色不支持时自动降级、上游未返回）就整条不写，播放器走静态原文，
                    // 避免半段时间轴错位还假装已对齐。
                    let allSegmentsAligned = !segmentTimelines.isEmpty
                        && segmentTimelines.allSatisfy { !$0.isEmpty }
                    if allSegmentsAligned {
                        let durationMs = Int((duration * 1000).rounded())

                        // 段偏移只在「上游时间戳是段内相对时间」时才该加。
                        // 判断不靠猜：加完偏移后末字必须落在音频时长之内。落不进去就说明
                        // 上游给的已经是绝对时间（再平移一次等于重复累加），后面几句会被推到
                        // 音频结束之后 —— 逐字高亮再也追不上声音，正是用户反馈的那个 bug。
                        func assemble(applyOffsets: Bool) -> [AudioSentenceCue] {
                            var cues: [AudioSentenceCue] = []
                            var offsetMs = 0
                            for (i, sentences) in segmentTimelines.enumerated() {
                                for sentence in sentences {
                                    var shifted = sentence
                                    shifted.index = cues.count
                                    if applyOffsets {
                                        shifted.words = sentence.words.map { word in
                                            var w = word
                                            w.beginMs += offsetMs
                                            w.endMs += offsetMs
                                            return w
                                        }
                                    }
                                    cues.append(shifted)
                                }
                                if applyOffsets {
                                    offsetMs += Int((segmentDurations[i] * 1000).rounded())
                                }
                            }
                            return cues
                        }

                        var cues = assemble(applyOffsets: true)
                        var usedOffsets = true
                        let overflow = (cues.last?.endMs ?? 0) - durationMs
                        if overflow > 500 {
                            let plain = assemble(applyOffsets: false)
                            let plainOverflow = (plain.last?.endMs ?? 0) - durationMs
                            if plainOverflow < overflow {
                                cues = plain
                                usedOffsets = false
                                Log(message: "⚠️ 段偏移后末字超时 \(overflow)ms，改用上游绝对时间（超时 \(plainOverflow)ms）")
                            } else {
                                Log(message: "⚠️ 段偏移后末字超时 \(overflow)ms，去掉偏移也对不上（\(plainOverflow)ms），保留偏移结果")
                            }
                        }

                        // 诊断：每段「估算时长」与该段上游时间轴末字的对照。
                        // 两者差得远就说明段时长这一环有问题（码率假设 / 拼接丢段），
                        // 下次看日志即可定位，不用再靠猜。
                        for (i, sentences) in segmentTimelines.enumerated() {
                            let upstreamEnd = sentences.map(\.endMs).max() ?? 0
                            Log(message: "段\(i): 估算时长 \(String(format: "%.2f", segmentDurations[i]))s / 上游末字 \(String(format: "%.2f", Double(upstreamEnd) / 1000))s")
                        }
                        Log(message: "段数 \(segmentTimelines.count)，估算合计 \(String(format: "%.2f", segmentDurations.reduce(0, +)))s，实际时长 \(String(format: "%.2f", duration))s")

                        // 段偏移就是「各段实测时长」的累加，所以合计必须和合并后音频的真实
                        // 时长吻合（误差只可能来自容器头 / 尾帧对齐，通常是毫秒级）。
                        // 超过 6% 说明这一环根本不成立（丢段、格式判断错），沿着它算出来的
                        // 偏移会把后半段整体推偏 —— 宁可这次不写时间轴、让阅读区走静态原文，
                        // 也不要把「对不上的高亮」交给用户。
                        let measuredTotalMs = Int((segmentDurations.reduce(0, +) * 1000).rounded())
                        let driftMs = abs(measuredTotalMs - durationMs)
                        let toleranceMs = max(400, Int(Double(durationMs) * 0.06))
                        let offsetsTrustworthy = !usedOffsets || driftMs <= toleranceMs

                        if offsetsTrustworthy {
                            let timeline = AudioTimeline(durationMs: durationMs, sentences: cues)
                            let saved = AudioTimelineStore.save(timeline, fileName: finalFileName)
                            Log(message: "字级时间轴: \(cues.count) 句 / \(timeline.anchorCount) 锚点, duration=\(duration)s, 保存=\(saved)")
                        } else {
                            Log(message: "⚠️ 段长合计 \(measuredTotalMs)ms 与音频实际时长 \(durationMs)ms 相差 \(driftMs)ms（容差 \(toleranceMs)ms），段偏移不可信，本次不写时间轴")
                        }
                    } else {
                        Log(message: "字级时间轴: 本次生成未获得完整 words[]，播放器将显示静态原文")
                    }

                    // 保存音频 ID 用于后续重命名
                    self.generatedAudioId = audio.id

                    // 扣减积分（与预估、入库记录用同一个值，按实际字符数计费，最多 2 位小数）
                    CreditManager.shared.deduct(points: points)
                    
                    // 保存消耗记录
                    CreditsService.shared.addConsumptionRecord(
                        voiceName: voice.name,
                        voiceKey: voice.key,
                        audioDuration: duration,
                        points: points
                    )

                    self.generatedAudioURL = finalAudioURL
                    self.generatedAudioDuration = duration  // 保存音频时长供播放使用
                    self.stats.markProgress(1.0)
                    self.isGenerating = false
                    self.generationStartedAt = nil
                    // 弹窗可能早就被关掉了：发一个完成信号，由全局浮层把它重新唤起
                    self.generationCompletedSignal &+= 1
                    // 注意：不要清空 text — 需求 1 要求保留输入
                    completion(true)
                }

            } catch {
                await MainActor.run {
                    self.isGenerating = false
                    self.generationStartedAt = nil
                    self.stats.reset()
                    self.alertItem = AlertItem(
                        title: "生成失败，请重新尝试".localized(),
                        message: ""
                    )
                    Log(message: "TTS 生成失败: \(error.localizedDescription)")
                    completion(false)
                }
            }
        }
    }

    // MARK: - 私有

    /// 将文本中所有 `[中文标签]` 转换为 `[english_tag]`（按 Constants.emotions + richLanguageTags 表查找）
    private func convertLocalizedTagsToEnglish(_ text: String) -> String {
        let pattern = "\\[([^\\]]+)\\]"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }

        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))

        var result = text
        // 反向处理以保证前面替换不会影响后续 range
        for match in matches.reversed() {
            guard match.numberOfRanges >= 2,
                  let swiftRange = Range(match.range(at: 1), in: text) else { continue }
            let content = String(text[swiftRange])
            if let english = Constants.tagForLabel(content), english != content {
                result = (result as NSString).replacingCharacters(in: match.range, with: "[\(english)]")
            }
        }
        return result
    }

    /// 取消生成
    func cancelGeneration() {
        isGenerating = false
        generationStartedAt = nil
        stats.reset()
        BailianTTSService.shared.closeConnection()
    }

    /// 保持 TTS 连接（用于连接复用场景）
    func keepConnectionAlive() {
        ttsService.ping()
    }
    
    /// 检测音频数据的实际格式
    /// - Parameter data: 音频二进制数据
    /// - Returns: 格式字符串（wav/mp3/m4a 等）
    private func detectAudioFormat(from data: Data) -> String {
        guard data.count >= 12 else {
            return selectedFormat.lowercased()
        }
        
        // 检测 WAV (RIFF header)
        if data[0] == 0x52 && data[1] == 0x49 && data[2] == 0x46 && data[3] == 0x46 {
            // RIFF...WAVE
            if data.count >= 12 &&
               data[8] == 0x57 && data[9] == 0x41 && data[10] == 0x56 && data[11] == 0x45 {
                return "wav"
            }
        }
        
        // 检测 MP3 (ID3 header 或 0xFF 0xFB 等)
        if data[0] == 0x49 && data[1] == 0x44 && data[2] == 0x33 { // ID3
            return "mp3"
        }
        if data[0] == 0xFF && (data[1] & 0xE0) == 0xE0 {
            return "mp3"
        }
        
        // 检测 M4A/AAC (ftyp box)
        if data[4] == 0x66 && data[5] == 0x74 && data[6] == 0x79 && data[7] == 0x70 {
            return "m4a"
        }
        
        // 默认返回用户选择的格式
        return selectedFormat.lowercased()
    }
}

/// Alert 内容（用于 .alert(item:) 绑定）
struct AlertItem: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let message: String
}

// MARK: - 创作参数持久化（iOS / macOS 共用）

/// 工作台四项音频参数的一组默认值。
///
/// iOS 没有「设置页默认值 → 工作台」这条联动，用 `.factory`（出厂常量）；
/// macOS 设置页能配「默认格式 / 采样率」，由 `VoiceStudioView` 注入那两项，
/// 语速 / 音量仍用出厂值。设置页因此仍是「重置目标 + 全新安装的起始参数」。
struct StudioParamValues {
    var rate: Double
    var volume: Double
    var format: String
    var sampleRate: Int

    static var factory: StudioParamValues {
        StudioParamValues(rate: 1.0,
                          volume: 100,
                          format: Constants.defaultFormat.lowercased(),
                          sampleRate: Constants.defaultSampleRate)
    }
}

/// 工作台四项音频参数（语速 / 音量 / 格式 / 采样率）的持久化。
///
/// ⚠️ 刻意**不把 `AppState.defaultFormat` / `defaultSampleRate` 当存储**：
/// 那是「设置页默认值」语义，工作台调参数不该改写用户的全局默认设置。
/// 这里存的是「上次用的参数」；macOS 只在「无存档起点」时读设置页的值，
/// 「重置」两端一律回 `.factory` 出厂默认（当前 mp3）—— 重置不该被设置页旧值污染。
/// ⚠️ 放在已有 Shared 文件里：新增 .swift 要手工改 pbxproj 四处 × 两个 target。
@MainActor
final class StudioParamStore {

    static let shared = StudioParamStore()

    private enum Key {
        static let rate = "studioParam.rate"
        static let volume = "studioParam.volume"
        static let format = "studioParam.format"
        static let sampleRate = "studioParam.sampleRate"
    }

    /// 2026-11-06 首版只在 iOS 落地时用的键。统一到平台无关命名后搬一次，
    /// 免得已经调过参数的用户升级后「记忆丢了」。
    private enum LegacyKey {
        static let rate = "iosStudioParam.rate"
        static let volume = "iosStudioParam.volume"
        static let format = "iosStudioParam.format"
        static let sampleRate = "iosStudioParam.sampleRate"
    }

    private let ud = UserDefaults.standard
    /// 冷启动只恢复一次：切标签 / 切换侧边栏回来 `onAppear` 会再跑，
    /// 那时 VM 里是本次会话的实时值，不能被磁盘上的旧值重新盖掉。
    private var didRestore = false

    private init() { migrateLegacyKeysIfNeeded() }

    private func migrateLegacyKeysIfNeeded() {
        let pairs = [(LegacyKey.rate, Key.rate),
                     (LegacyKey.volume, Key.volume),
                     (LegacyKey.format, Key.format),
                     (LegacyKey.sampleRate, Key.sampleRate)]
        for (old, new) in pairs {
            guard ud.object(forKey: new) == nil,
                  let value = ud.object(forKey: old) else { continue }
            ud.set(value, forKey: new)
            ud.removeObject(forKey: old)
        }
    }

    /// 把调用方给的默认值净化到工作台 UI 能表达的范围。
    /// 例：macOS 设置页能选 PCM / Opus，但工作台只有 MP3 / WAV 两个按钮，
    /// 原样塞进去会出现「两个都不选中」。
    private func sanitize(_ d: StudioParamValues) -> StudioParamValues {
        var result = d
        let format = d.format.lowercased()
        result.format = ["mp3", "wav"].contains(format) ? format : StudioParamValues.factory.format
        if !(0.5...2.0).contains(result.rate) { result.rate = StudioParamValues.factory.rate }
        if !(0.0...100.0).contains(result.volume) { result.volume = StudioParamValues.factory.volume }
        if !Constants.sampleRates.contains(where: { $0.rate == result.sampleRate }) {
            result.sampleRate = StudioParamValues.factory.sampleRate
        }
        return result
    }

    /// 从磁盘恢复到 VM。缺键 / 越界 / 非法枚举值都回落到 `defaults`。
    func restoreIfNeeded(to vm: VoiceStudioViewModel, defaults: StudioParamValues? = nil) {
        guard !didRestore else { return }
        didRestore = true
        let d = sanitize(defaults ?? StudioParamValues.factory)

        // 用 object(forKey:) 判「有没有存过」：double/integer(forKey:) 缺键时返回 0，
        // 那正好是合法的音量值，直接读会把「从没存过」误判成「用户存了 0」。
        let rate: Double? = ud.object(forKey: Key.rate) != nil ? ud.double(forKey: Key.rate) : nil
        let volume: Double? = ud.object(forKey: Key.volume) != nil ? ud.double(forKey: Key.volume) : nil
        let format = ud.string(forKey: Key.format)?.lowercased()
        let sampleRate: Int? = ud.object(forKey: Key.sampleRate) != nil ? ud.integer(forKey: Key.sampleRate) : nil

        vm.rate = rate.flatMap { (0.5...2.0).contains($0) ? $0 : nil } ?? d.rate
        vm.volume = volume.flatMap { (0.0...100.0).contains($0) ? $0 : nil } ?? d.volume
        vm.selectedFormat = format.flatMap { ["mp3", "wav"].contains($0) ? $0 : nil } ?? d.format

        if let sampleRate, Constants.sampleRates.contains(where: { $0.rate == sampleRate }) {
            vm.sampleRate = sampleRate
        } else {
            vm.sampleRate = d.sampleRate
        }
    }

    /// 实时落盘。四项一起写，保证任意一项在别处被改动也不会漏。
    func save(from vm: VoiceStudioViewModel) {
        ud.set(vm.rate, forKey: Key.rate)
        ud.set(vm.volume, forKey: Key.volume)
        ud.set(vm.selectedFormat.lowercased(), forKey: Key.format)
        ud.set(vm.sampleRate, forKey: Key.sampleRate)
    }

    /// 「重置」：四项一起回 `defaults`（不传即 `.factory` 出厂默认）并立刻落盘，
    /// 否则重启后又变回旧参数。音色、语音指令、语言 / 预设不在重置范围内。
    /// ⚠️ 调用方一般不要传 `defaults`：设置页配的 WAV / PCM 会让「重置」看起来没生效。
    func reset(on vm: VoiceStudioViewModel, to defaults: StudioParamValues? = nil) {
        let d = sanitize(defaults ?? StudioParamValues.factory)
        vm.rate = d.rate
        vm.volume = d.volume
        vm.selectedFormat = d.format
        vm.sampleRate = d.sampleRate
        save(from: vm)
    }
}

// MARK: - 草稿（Drafts）
//
// 设计依据：UI/草稿功能-双端设计图.html
// ⚠️ 存储约定：
//   * 目录 `Documents/Drafts/`（与 `Documents/GeneratedAudio` 同级，拼路径沿用
//     `kGeneratedAudioSubdirectory` 的写法）。
//       - `index.json`     —— 每条草稿的**元数据**（标题 / 时间 / 字数 / 音色参数…）。
//                             启动、列表、角标只读它，正文不进这条链路。
//       - `<id>.json`      —— 单条草稿的**正文** `[TTSContentItem]`，恢复 / 复制时才读。
//       - `index.corrupt-*` / `<id>.corrupt-*` —— 解码失败时的留档，绝不静默删除。
//   * 不进 SQLite：改 `createTables()` 必须 bump schemaVersion 并会 DROP 重建，草稿是
//     用户资产，丢不起；也不塞 `AudioFlagStore`（那是收藏 / 软删，30 天 purge）。
//   * 正文存 `[TTSContentItem]`：双 target 共用且已 Codable，就是设计稿要求的
//     「平台无关中间格式」。macOS 的 NSTextAttachment 与 iOS 的 doc+marks 各自编解码，
//     ⚠️ 绝不降成纯文本，否则情绪 / 拟声 / 中断标签的插入位置全丢。
//   * 本期本机存储；接云同步时按 id 粒度合并即可（一条草稿就是一个文件）。
// ⚠️ 全部塞在已有 Shared 文件里：新增 .swift 要手工改 pbxproj 四处 × 两个 target。
//
// ⚠️ 为什么不再用一个 `drafts.v1.json` 存整库（旧方案已废弃）：
//   1. 写放大：每存一次草稿（含切页 / 退后台的**静默自动保存**）都要把整库 encode +
//      原子重写一遍。N 条 × M KB 的正文全压在写路径上，草稿越多、正文越长，保存越慢，
//      而原子写是「先写临时文件再替换」，整库重写失败的窗口也越大。
//   2. 单点损坏：一个字节解码失败 = 整库读不出来（旧代码只能留个 .corrupt 备份，用户资产全丢）。
//   3. 启动成本：列表只要元数据，却必须把全部正文一起反序列化、常驻内存。
//   新方案：保存一条 = 写一个 KB 级正文文件 + 重写 KB 级索引；坏一条只坏那一条；
//   启动只解析索引，正文按需读盘（`DraftStore.load(id:)`）。

/// 草稿目录（相对于 Documents/），与 `kGeneratedAudioSubdirectory` 同一套约定。
nonisolated let kDraftsSubdirectory = "Drafts"

/// 例：file:///…/Documents/Drafts
nonisolated func draftsDirectoryURL() -> URL {
    let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    return docs.appendingPathComponent(kDraftsSubdirectory, isDirectory: true)
}

enum DraftSource: String, Codable, Hashable {
    case manual
    case auto
}

/// 一次编辑态的完整快照（平台无关）。由两端各自的创作台从当前编辑器 / VM 组装。
struct DraftSnapshot {
    var items: [TTSContentItem]
    var voiceKey: String
    var voiceName: String
    var rate: Double
    var volume: Double
    var format: String
    var sampleRate: Int
    /// 语音指令只存语义值：语言 / 预设是中文 key，恢复时按当前界面语言重新本地化拼接。
    /// `customInstruction` 仅在用户手改过指令框、内容与自动拼接不一致时非空。
    var nlLanguage: String?
    var nlPreset: String?
    var customInstruction: String?

    var plainText: String { items.toPlainText() }
    var charCount: Int { TextSplitter.calculateCharCount(plainText) }
    var tagCount: Int { items.filter { $0.isEmotion }.count }

    /// 保存主按钮禁用态的共同判据：正文为空**且**无标签。
    var isEmpty: Bool {
        items.allSatisfy { item in
            guard case .text(let s) = item else { return false }
            return s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    /// 首行标题 / 两行摘要共用的一段纯文本。
    var trimmedText: String {
        plainText
            .replacingOccurrences(of: "\n+", with: "\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// macOS / ⌘S / 生成链路共用：VM 的 `ttsItems` 就是权威结构化内容。
    /// iOS 打字期间 `ttsItems` 不是最新的，组装后要用 `TokenDocument.contentItems` 覆盖 items。
    /// ⚠️ 四配置默认 MainActor：`DraftSnapshot` 不是 @MainActor 类型，
    /// 这个静态方法访问 VM 的隔离属性，必须显式标注（Swift 5 只报 warning，Swift 6 是 error）。
    @MainActor
    static func capture(from vm: VoiceStudioViewModel) -> DraftSnapshot {
        let nl = vm.exportNLInstruction()
        return DraftSnapshot(items: vm.ttsItems,
                             voiceKey: vm.selectedVoiceKey,
                             voiceName: vm.voice?.localizedName ?? "",
                             rate: vm.rate,
                             volume: vm.volume,
                             format: vm.selectedFormat.lowercased(),
                             sampleRate: vm.sampleRate,
                             nlLanguage: nl.language,
                             nlPreset: nl.preset,
                             customInstruction: nl.custom)
    }
}

/// 一条草稿：**元数据**（写 `index.json`）+ **运行时正文缓存**（正文单独一个 `<id>.json`）。
struct Draft: Codable, Identifiable, Hashable {
    var id: String
    var title: String
    var preview: String
    var voiceKey: String
    var voiceName: String
    var rate: Double
    var volume: Double
    var format: String
    var sampleRate: Int
    var nlLanguage: String?
    var nlPreset: String?
    var customInstruction: String?
    var charCount: Int
    var tagCount: Int
    var createdAt: Date
    var updatedAt: Date
    var source: DraftSource
    /// 生成成功后打标，30 天后由 `purgeExpiredGenerated()` 清理。
    var generatedAt: Date?
    /// 正文缓存。⚠️ 不参与 Codable：索引里读出来的条目是 nil（没读盘），
    /// `DraftStore.load(id:)` 读到正文后回填。写索引时必须保持 KB 级，正文走独立文件。
    var loadedItems: [TTSContentItem]?

    /// ⚠️ 可能是空的：索引条目只有元数据。恢复 / 复制 / 生成前请走 `DraftStore.load(id:)`。
    var items: [TTSContentItem] { loadedItems ?? [] }
    /// 正文是否已载入。
    var hasBody: Bool { loadedItems != nil }

    var isAuto: Bool { source == .auto }
    var isGenerated: Bool { generatedAt != nil }

    init(id: String,
         title: String,
         preview: String,
         voiceKey: String,
         voiceName: String,
         rate: Double,
         volume: Double,
         format: String,
         sampleRate: Int,
         nlLanguage: String?,
         nlPreset: String?,
         customInstruction: String?,
         charCount: Int,
         tagCount: Int,
         createdAt: Date,
         updatedAt: Date,
         source: DraftSource,
         generatedAt: Date? = nil,
         loadedItems: [TTSContentItem]? = nil) {
        self.id = id
        self.title = title
        self.preview = preview
        self.voiceKey = voiceKey
        self.voiceName = voiceName
        self.rate = rate
        self.volume = volume
        self.format = format
        self.sampleRate = sampleRate
        self.nlLanguage = nlLanguage
        self.nlPreset = nlPreset
        self.customInstruction = customInstruction
        self.charCount = charCount
        self.tagCount = tagCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.source = source
        self.generatedAt = generatedAt
        self.loadedItems = loadedItems
    }

    enum CodingKeys: String, CodingKey {
        case id, title, preview, voiceKey, voiceName, rate, volume, format, sampleRate
        case nlLanguage, nlPreset, customInstruction, charCount, tagCount
        case createdAt, updatedAt, source, generatedAt
        /// 已废弃：旧单文件格式（`drafts.v1.json`）把正文内联在这里。
        /// ⚠️ 只用来兼容读取迁移，`encode` 绝不写回。
        case legacyItemsJSON = "itemsJSON"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        preview = try c.decodeIfPresent(String.self, forKey: .preview) ?? ""
        voiceKey = try c.decodeIfPresent(String.self, forKey: .voiceKey) ?? ""
        voiceName = try c.decodeIfPresent(String.self, forKey: .voiceName) ?? ""
        rate = try c.decodeIfPresent(Double.self, forKey: .rate) ?? 1.0
        volume = try c.decodeIfPresent(Double.self, forKey: .volume) ?? 1.0
        format = try c.decodeIfPresent(String.self, forKey: .format) ?? "mp3"
        sampleRate = try c.decodeIfPresent(Int.self, forKey: .sampleRate) ?? 22050
        nlLanguage = try c.decodeIfPresent(String.self, forKey: .nlLanguage)
        nlPreset = try c.decodeIfPresent(String.self, forKey: .nlPreset)
        customInstruction = try c.decodeIfPresent(String.self, forKey: .customInstruction)
        charCount = try c.decodeIfPresent(Int.self, forKey: .charCount) ?? 0
        tagCount = try c.decodeIfPresent(Int.self, forKey: .tagCount) ?? 0
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt) ?? createdAt
        source = try c.decodeIfPresent(DraftSource.self, forKey: .source) ?? .manual
        generatedAt = try c.decodeIfPresent(Date.self, forKey: .generatedAt)
        // 旧格式里正文内联在 itemsJSON：顺手解成正文，迁移时不用再多写一套模型。
        if let json = try c.decodeIfPresent(String.self, forKey: .legacyItemsJSON), !json.isEmpty {
            loadedItems = [TTSContentItem].from(jsonString: json) ?? []
        } else {
            loadedItems = nil
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(preview, forKey: .preview)
        try c.encode(voiceKey, forKey: .voiceKey)
        try c.encode(voiceName, forKey: .voiceName)
        try c.encode(rate, forKey: .rate)
        try c.encode(volume, forKey: .volume)
        try c.encode(format, forKey: .format)
        try c.encode(sampleRate, forKey: .sampleRate)
        try c.encodeIfPresent(nlLanguage, forKey: .nlLanguage)
        try c.encodeIfPresent(nlPreset, forKey: .nlPreset)
        try c.encodeIfPresent(customInstruction, forKey: .customInstruction)
        try c.encode(charCount, forKey: .charCount)
        try c.encode(tagCount, forKey: .tagCount)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(updatedAt, forKey: .updatedAt)
        try c.encode(source, forKey: .source)
        try c.encodeIfPresent(generatedAt, forKey: .generatedAt)
    }

    /// 只按 id 比：列表 ForEach、弹窗目标都是同一条草稿的不同快照，
    /// 让正文参与比较会为了判等去比几十 KB 的数组。
    static func == (lhs: Draft, rhs: Draft) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    static func make(from s: DraftSnapshot, title: String?, source: DraftSource) -> Draft? {
        let now = Date()
        let text = s.trimmedText
        let firstLine = text.split(separator: "\n").first.map(String.init) ?? ""
        let given = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let resolved: String
        if source == .auto {
            resolved = "上次编辑".localized()
        } else if !given.isEmpty {
            resolved = given
        } else if !firstLine.isEmpty {
            resolved = String(firstLine.prefix(30))
        } else {
            resolved = "未命名草稿".localized()
        }
        return Draft(id: UUID().uuidString,
                     title: resolved,
                     preview: String(text.prefix(120)),
                     voiceKey: s.voiceKey,
                     voiceName: s.voiceName,
                     rate: s.rate,
                     volume: s.volume,
                     format: s.format,
                     sampleRate: s.sampleRate,
                     nlLanguage: s.nlLanguage,
                     nlPreset: s.nlPreset,
                     customInstruction: s.customInstruction,
                     charCount: s.charCount,
                     tagCount: s.tagCount,
                     createdAt: now,
                     updatedAt: now,
                     source: source,
                     generatedAt: nil,
                     loadedItems: s.items)
    }

    /// 覆盖式更新（自动保存复用同一条 id / createdAt，恒定单条）。
    mutating func update(from s: DraftSnapshot) {
        loadedItems = s.items
        preview = String(s.trimmedText.prefix(120))
        voiceKey = s.voiceKey
        voiceName = s.voiceName
        rate = s.rate
        volume = s.volume
        format = s.format
        sampleRate = s.sampleRate
        nlLanguage = s.nlLanguage
        nlPreset = s.nlPreset
        customInstruction = s.customInstruction
        charCount = s.charCount
        tagCount = s.tagCount
        updatedAt = Date()
        generatedAt = nil
        if isAuto { title = "上次编辑".localized() }
    }
}

/// 编辑器「待提交内容」的同步结算钩子。
///
/// 内容从编辑器同步进 VM 都带一拍延迟（macOS 0.35s 去抖），而 ⌘S / 文件菜单这些
/// **没有 View 上下文**的保存入口直接读 `VoiceStudioViewModel.shared` 取快照，
/// 读到的可能还是上一版。编辑器挂载时把自己的结算闭包注册到这里，保存前统一调一次，
/// 保证「落盘的一定是屏幕上最新的一份」。
///
/// ⚠️ 闭包必须弱捕获视图：编辑器销毁后自动失效，不需要额外注销。
@MainActor
enum PendingEditorCommit {

    /// 由当前编辑器注册（macOS：`EmotionTokenTextView.commitPendingChangesNow()`）。
    static var handler: (() -> Void)?

    /// 把编辑器里还没同步出去的输入当场写进 binding / VM。
    static func flush() { handler?() }
}

/// 草稿仓库。入口只读 `count`（低频）；⛔ 禁止把播放器的 10Hz 发布者挂到入口或列表上。
///
/// 磁盘布局见本节顶部注释：`index.json`（元数据）+ `<id>.json`（正文）。
/// 内存里 `drafts` 只保证元数据齐全，正文在 `save` / `load(id:)` 时才有；
/// ⛔ 别在列表 cell 里访问 `draft.items`（那会触发读盘）。
@MainActor
final class DraftStore: ObservableObject {

    static let shared = DraftStore()
    static let retentionDays = 30

    @Published private(set) var drafts: [Draft] = []
    /// 当前工作区由哪条草稿恢复而来 → 列表里的「编辑中」标记。
    @Published private(set) var editingDraftID: String? = nil
    /// 手动保存完成信号：⌘S（KeyboardShortcuts）/ 文件菜单 / 卡片按钮都走这里，View 借它弹提示。
    @Published private(set) var saveSignal: Int = 0

    private let dirURL: URL
    private let indexURL: URL
    /// 索引：只排 key、不 prettyPrint（元数据很小，但没必要为可读性多写几 KB）。
    private let indexEncoder = JSONEncoder()
    /// 正文：同样不 prettyPrint —— 正文可能几十上百 KB，缩进会让文件体积翻倍。
    private let bodyEncoder = JSONEncoder()
    private let decoder = JSONDecoder()

    var count: Int { drafts.count }
    var manual: [Draft] { drafts.filter { !$0.isAuto }.sorted { $0.updatedAt > $1.updatedAt } }
    var auto: [Draft] { drafts.filter { $0.isAuto }.sorted { $0.updatedAt > $1.updatedAt } }

    private init() {
        let fm = FileManager.default
        let dir = draftsDirectoryURL()
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)

        dirURL = dir
        indexURL = dir.appendingPathComponent("index.json")
        indexEncoder.outputFormatting = [.sortedKeys]
        bodyEncoder.outputFormatting = [.sortedKeys]

        drafts = Self.readIndex(from: indexURL, using: decoder, fm: fm)
        migrateLegacyStoreIfNeeded(fm: fm)
        purgeExpiredGenerated()
    }

    // MARK: 路径

    /// 正文文件：`<id>.json`。
    private func bodyURL(for id: String) -> URL {
        dirURL.appendingPathComponent(Self.fileName(for: id))
    }

    /// id 是 UUID 字符串，但仍过滤一遍：旧数据 / 手改文件名别让 `/` 跑出草稿目录。
    private static func fileName(for id: String) -> String {
        let safe = id.map { ch -> Character in
            ch.isLetter || ch.isNumber || ch == "-" || ch == "_" ? ch : "_"
        }
        return String(safe) + ".json"
    }

    // MARK: 读写

    private static func readIndex(from url: URL, using decoder: JSONDecoder, fm: FileManager) -> [Draft] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        do {
            return try decoder.decode([Draft].self, from: data)
        } catch {
            // 解码失败绝不静默清空覆盖：坏文件留档，避免一次升级把用户资产抹掉。
            let backup = url.deletingLastPathComponent()
                .appendingPathComponent("index.corrupt-\(Int(Date().timeIntervalSince1970)).json")
            try? fm.copyItem(at: url, to: backup)
            #if DEBUG
            print("[DraftStore] index decode failed, backup kept at \(backup.path): \(error)")
            #endif
            return []
        }
    }

    /// 重写索引（KB 级）。**不含正文** —— `Draft.encode` 不写 `loadedItems`。
    private func writeIndex() {
        do {
            try indexEncoder.encode(drafts).write(to: indexURL, options: .atomic)
        } catch {
            #if DEBUG
            print("[DraftStore] write index failed: \(error)")
            #endif
        }
    }

    /// 只重写这一条正文。索引里的副本同步保留 `loadedItems`，方便同一会话内再次读取。
    private func writeBody(_ d: Draft) {
        guard let items = d.loadedItems else { return }
        do {
            try bodyEncoder.encode(items).write(to: bodyURL(for: d.id), options: .atomic)
        } catch {
            #if DEBUG
            print("[DraftStore] write body failed(\(d.id)): \(error)")
            #endif
        }
    }

    private func readBody(id: String) -> [TTSContentItem]? {
        let url = bodyURL(for: id)
        guard let data = try? Data(contentsOf: url) else { return nil }
        do {
            return try decoder.decode([TTSContentItem].self, from: data)
        } catch {
            let backup = url.deletingPathExtension()
                .appendingPathExtension("corrupt-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.copyItem(at: url, to: backup)
            #if DEBUG
            print("[DraftStore] body decode failed(\(id)), backup kept at \(backup.path): \(error)")
            #endif
            return nil
        }
    }

    private func removeBody(id: String) {
        try? FileManager.default.removeItem(at: bodyURL(for: id))
    }

    /// 旧方案（单文件 `Application Support/EmotionVoice/drafts.v1.json`）→ 新目录。
    /// ⚠️ 只在「新目录还没有索引」时搬一次；搬完把旧文件改名留档（不删，用户还能手工找回）。
    private func migrateLegacyStoreIfNeeded(fm: FileManager) {
        guard !fm.fileExists(atPath: indexURL.path) else { return }
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.temporaryDirectory
        let legacy = base.appendingPathComponent("EmotionVoice", isDirectory: true)
            .appendingPathComponent("drafts.v1.json")
        guard fm.fileExists(atPath: legacy.path),
              let data = try? Data(contentsOf: legacy),
              let old = try? decoder.decode([Draft].self, from: data) else { return }

        // 旧格式正文内联在 itemsJSON：`Draft.init(from:)` 已顺手解成 loadedItems。
        // 解不出正文的条目（json 损坏）不迁 —— 没有正文的草稿恢复出来是空的，只会误导用户。
        drafts = old.filter { $0.hasBody }
        for d in drafts { writeBody(d) }
        writeIndex()

        let archived = legacy.deletingLastPathComponent()
            .appendingPathComponent("drafts.v1.migrated.json")
        try? fm.removeItem(at: archived)
        try? fm.moveItem(at: legacy, to: archived)
        #if DEBUG
        print("[DraftStore] migrated \(drafts.count) legacy drafts → \(dirURL.path)")
        #endif
    }

    // MARK: 增删改查

    /// 存一份草稿。`.auto` 恒定覆盖单条且不发信号（静默兜底，不打断心流）。
    @discardableResult
    func save(_ s: DraftSnapshot,
              title: String? = nil,
              source: DraftSource = .manual,
              notify: Bool = true) -> Draft? {
        guard !s.isEmpty else { return nil }

        if source == .auto, let idx = drafts.firstIndex(where: { $0.isAuto }) {
            drafts[idx].update(from: s)
            let saved = drafts[idx]
            writeBody(saved)   // 只重写这一条正文
            writeIndex()       // 索引 KB 级，重写可忽略
            return saved
        }

        guard let d = Draft.make(from: s, title: title, source: source) else { return nil }
        if source == .auto {
            for old in drafts where old.isAuto { removeBody(id: old.id) }
            drafts.removeAll { $0.isAuto }
        }
        drafts.append(d)
        writeBody(d)
        if source == .manual { editingDraftID = d.id }
        writeIndex()
        if notify && source == .manual { saveSignal &+= 1 }
        return d
    }

    /// 恢复草稿前的兜底：把编辑器里的现有内容存成**一条新的手动草稿**。
    ///
    /// ⚠️ 不覆盖「上次编辑」那个单槽位：那条槽位每次静默自动保存都会重写，
    ///    连续切换几份草稿时中间的内容会被后一次覆盖掉。这里每条都独立成文件，谁都不会丢。
    ///
    /// 去重（避免反复切换堆积一堆同内容草稿）：
    ///  * 当前编辑态 == 「编辑中」那条草稿 → 内容与参数都已存档，不复制；
    ///  * == 「上次编辑」那条 → 同上。
    ///  ⚠️ 判据是「正文 **+ 音色 + 四项参数 + 语音指令**全同」，只比正文会让
    ///     「恢复草稿 → 只调参数 → 再切走」被误判成重复：新快照不落盘，
    ///     用户看到的那条草稿还是旧参数。
    ///
    /// - Note: 新草稿标题走 `Draft.make` 的默认规则（首行前 30 字），方便在列表里认出是哪段。
    @discardableResult
    func stashBeforeRestore(_ s: DraftSnapshot) -> Draft? {
        guard !s.isEmpty else { return nil }
        if isEditStateAlreadyStored(s) { return nil }

        // `save` 会把「编辑中」标到新草稿上；恢复动作紧接着就会标到目标草稿，
        // 这里先还原，避免中间那一瞬的错位被 SwiftUI 读到。
        let previous = editingDraftID
        let d = save(s, title: nil, source: .manual, notify: false)
        editingDraftID = previous
        return d
    }

    /// 现有**编辑态**是否已经原封不动地存在某条草稿里。
    /// 判据见 `Draft.isSameEditState(as:)`：正文 + 音色 + 参数 + 语音指令全同才算重复。
    private func isEditStateAlreadyStored(_ s: DraftSnapshot) -> Bool {
        if let id = editingDraftID, let d = load(id: id), d.isSameEditState(as: s) { return true }
        if let auto = drafts.first(where: { $0.isAuto }),
           let d = load(id: auto.id), d.isSameEditState(as: s) { return true }
        return false
    }

    /// 元数据（索引里的那份，正文可能是 nil）。
    func draft(id: String) -> Draft? { drafts.first { $0.id == id } }

    /// 取一条**带正文**的草稿：索引条目没读盘，这里按需读正文并回填内存。
    /// ⚠️ 恢复 / 复制一律走这里 —— 直接拿列表里的 `Draft` 只有元数据，`items` 是空的。
    /// ⚠️ 正文文件缺失 / 解码失败时返回 nil（**不是空正文**）：调用方不得拿它去覆盖编辑器。
    @discardableResult
    func load(id: String) -> Draft? {
        guard let idx = drafts.firstIndex(where: { $0.id == id }) else { return nil }
        if drafts[idx].hasBody { return drafts[idx] }
        guard let body = readBody(id: id) else { return nil }
        drafts[idx].loadedItems = body
        return drafts[idx]
    }

    /// 标「编辑中」并返回带正文的草稿（恢复入口）。
    @discardableResult
    func restore(_ id: String) -> Draft? {
        guard let d = load(id: id) else { return nil }
        editingDraftID = id
        return d
    }

    func markEditing(_ id: String?) { editingDraftID = id }

    func rename(id: String, title: String) {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty, let idx = drafts.firstIndex(where: { $0.id == id }) else { return }
        drafts[idx].title = t
        drafts[idx].updatedAt = Date()
        writeIndex()
    }

    @discardableResult
    func duplicate(id: String) -> Draft? {
        // 复制要正文；复制出来的是一条新文件，原草稿的文件不动。
        guard var copy = load(id: id) else { return nil }
        copy.id = UUID().uuidString
        copy.title = "\(copy.title) \("副本".localized())"
        copy.source = .manual
        copy.createdAt = Date()
        copy.updatedAt = Date()
        copy.generatedAt = nil
        drafts.append(copy)
        writeBody(copy)
        writeIndex()
        return copy
    }

    func delete(id: String) {
        drafts.removeAll { $0.id == id }
        removeBody(id: id)
        if editingDraftID == id { editingDraftID = nil }
        writeIndex()
    }

    /// 删除全部草稿：正文文件 + 索引一起清，并摘掉「编辑中」标记。
    /// ⚠️ 只清草稿存档，**不动工作区正文** —— 用户删的是草稿，不是当前正在写的内容。
    func deleteAll() {
        guard !drafts.isEmpty else { return }
        for d in drafts { removeBody(id: d.id) }
        drafts.removeAll()
        editingDraftID = nil
        writeIndex()
    }

    /// 生成成功：把当前工作区对应的草稿打标，30 天后清理（草稿 ≠ 项目，不混列）。
    func markGenerated() {
        guard let id = editingDraftID,
              let idx = drafts.firstIndex(where: { $0.id == id }) else { return }
        drafts[idx].generatedAt = Date()
        writeIndex()
    }

    private func purgeExpiredGenerated() {
        let cutoff = Date().addingTimeInterval(-Double(Self.retentionDays) * 86400)
        let expired = drafts.filter { d in
            guard let g = d.generatedAt else { return false }
            return g < cutoff
        }
        guard !expired.isEmpty else { return }
        for d in expired { removeBody(id: d.id) }
        let ids = Set(expired.map(\.id))
        drafts.removeAll { ids.contains($0.id) }
        writeIndex()
    }
}

extension VoiceStudioViewModel {

    /// 把草稿逐字段写回 VM。
    /// ⚠️ 四项参数必须同时写 `StudioParamStore`，否则「界面变了、冷启动 restoreIfNeeded 又拉回旧值」。
    /// ⚠️ 列表里的 `Draft` 只有元数据，正文在独立文件里：这里兜底按需读盘，
    ///    正常路径调用方应当已经 `DraftStore.load(id:)` 过了（别让这里反复读盘）。
    /// - Returns: true 表示草稿里的音色已下架、回落到了默认音色（调用方应提示用户）。
    @discardableResult
    func apply(_ draft: Draft, appState: AppState?) -> Bool {
        let resolved: Draft
        if draft.hasBody {
            resolved = draft
        } else if let loaded = DraftStore.shared.load(id: draft.id) {
            resolved = loaded
        } else {
            // 正文文件没了（手删 / 损坏）：宁可编辑区不动，也不能用空正文把它清掉。
            return false
        }
        let items = resolved.items
        ttsItems = items
        text = items.toPlainText()
        selectedVoiceKey = resolved.voiceKey
        rate = resolved.rate
        volume = resolved.volume
        selectedFormat = resolved.format.lowercased()
        sampleRate = resolved.sampleRate
        StudioParamStore.shared.save(from: self)
        restoreNLInstruction(language: resolved.nlLanguage,
                             preset: resolved.nlPreset,
                             custom: resolved.customInstruction)

        var fellBack = false
        if let appState {
            if let v = VoiceService.shared.voice(forKey: resolved.voiceKey) {
                appState.selectedVoice = v
            } else {
                selectedVoiceKey = appState.defaultVoiceKey
                appState.selectedVoice = appState.defaultVoice
                fellBack = true
            }
        }
        return fellBack
    }
}

extension Draft {

    /// 与快照是否属于**同一份编辑态**：正文 + 音色 + 四项参数 + 语音指令全同。
    ///
    /// ⚠️ 只比正文不够：用户在恢复出来的草稿上只调参数（不改字）再切走时，
    ///    旧判据会认定「内容已有归属」→ 新快照不入库，参数改动等于白调。
    /// 浮点用容差比较：slider 走 UserDefaults / JSON 往返可能有 1e-15 级误差。
    func isSameEditState(as s: DraftSnapshot) -> Bool {
        guard items == s.items, voiceKey == s.voiceKey else { return false }
        guard abs(rate - s.rate) < 0.0001, abs(volume - s.volume) < 0.0001 else { return false }
        guard format.lowercased() == s.format.lowercased() else { return false }
        guard sampleRate == s.sampleRate else { return false }
        return (nlLanguage ?? "") == (s.nlLanguage ?? "")
            && (nlPreset ?? "") == (s.nlPreset ?? "")
            && (customInstruction ?? "") == (s.customInstruction ?? "")
    }

    /// 列表里的保存时间：**日期 + 时间**（当年省略年份）。
    /// ⚠️ 不写「今天 / 昨天」这种模糊说法：草稿可能放很久，只给时刻会分不清是哪天。
    var timeText: String {
        let cal = Calendar.current
        let sameYear = cal.component(.year, from: updatedAt) == cal.component(.year, from: Date())
        return sameYear
            ? updatedAt.formatted(.dateTime.month().day().hour().minute())
            : updatedAt.formatted(date: .numeric, time: .shortened)
    }

    /// 列表副标题：正文首行之后的剩余内容。
    /// ⚠️ 首行已经当标题用了，若把整段再截一遍就会出现「标题和副标题是同一句话」。
    /// 取「第一个换行之后」而不是按 title 前缀裁剪：标题只保留首行前 30 字，
    /// 按前缀裁会从一行中间切开，看起来像半句话。
    var subtitle: String {
        let p = preview.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !p.isEmpty else { return "" }
        if let nl = p.firstIndex(where: { $0.isNewline }) {
            return String(p[p.index(after: nl)...])
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // 没有换行 = 整段只有一行（TTS 输入最常见的形态）：
        // 从标题长度往后接着显示，既不是重复也不是半句丢失。
        guard p.hasPrefix(title) else { return p }
        return String(p.dropFirst(title.count)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 元信息一行：字数 · 音色。标签数量不展示，时间由列表单独放右侧。
    var metaText: String {
        let voice = voiceName.isEmpty ? "—" : voiceName
        return "\( "%d 字".localized(charCount)) · \(voice)"
    }
}

extension DraftStore {
    /// 快捷键 / 文件菜单没有 View 上下文，直接从共享 VM 组装快照。
    ///
    /// ⚠️ 取快照前必须先 `PendingEditorCommit.flush()`：编辑器内容同步进 VM 有 0.35s 去抖，
    ///    少了这步会「刚打完字立刻 ⌘S，存进去的是上一版正文」。
    func saveFromSharedVM() {
        PendingEditorCommit.flush()
        save(DraftSnapshot.capture(from: .shared), source: .manual)
    }
}
