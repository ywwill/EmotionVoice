//
//  VoiceStudioViewModel.swift
//  EmotionVoice
//
//  Created by young on 2026/8/8.
//

import Foundation
import SwiftUI
import Combine
import AppKit

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

    // 音色
    @Published var selectedVoiceKey: String = Constants.defaultVoice

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
    func toggleLanguage(_ language: String) {
        if selectedLanguage == language {
            selectedLanguage = nil
        } else {
            selectedLanguage = language
        }
        updateNLInstruction()
    }

    /// 更新指令文本：拼接语言和预设
    private func updateNLInstruction() {
        let parts: [String] = [
            selectedLanguage,
            selectedPreset.flatMap { Constants.instructionForPreset($0) }
        ].compactMap { $0 }

        nlInstruction = parts.joined(separator: "，")
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
        VoiceService.shared.fetchAll().first(where: { $0.key == selectedVoiceKey })
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

        Task {
            do {
                // 每个片段的进度窗口：片段 i 占 [i/n, (i+1)/n]，映射到 0.05 -> 0.95，
                // 保证整体进度单调递增（不会因为切段而回退）。
                let segmentCount = max(1, ttsSegments.count)
                var audioChunks: [Data] = []

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

                    let chunk: Data = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
                        ttsService.synthesizeStream(
                            text: segment.apiText,
                            voice: voice.key,
                            emotion: nil,
                            rate: rate,
                            volume: volume,
                            sampleRate: sampleRate,
                            format: self.selectedFormat.lowercased(),
                            nlInstruction: nlInstruction.isEmpty ? nil : nlInstruction,
                            onAudio: onAudio,
                            completion: { result in
                                cont.resume(with: result)
                            }
                        )
                    }
                    try Task.checkCancellation()
                    // 单个片段为空说明这一段没合成出音频，合并后会造成「缺了一段」的静默错误
                    guard !chunk.isEmpty else { throw TTSError.noAudioData }
                    audioChunks.append(chunk)
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

                // 计算真实时长
                let duration = AudioDuration.read(
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
                        title: "生成失败".localized(),
                        message: error.localizedDescription
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
