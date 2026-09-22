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

    /// 触发 EmotionTokenEditor 清空所有 token
    @Published var clearTokensTrigger: Int = 0

    // 音色
    @Published var selectedVoiceKey: String = Constants.defaultVoice

    // 情感/语速/音量
    @Published var rate: Double = 1.0    // 0.5 - 2.0
    @Published var volume: Double = 100  // 0 - 100

    // 语言/采样率/格式
    @Published var language: LanguageItem = Constants.languages[0]
    @Published var sampleRate: Int = Constants.defaultSampleRate
    @Published var selectedFormat: String = Constants.defaultFormat

    // 自然语言指令
    @Published var nlInstruction: String = ""

    // 预设芯片
    let nlPresets: [String] = [
        "温柔女声".localized(),
        "活泼男声".localized(),
        "新闻播报".localized(),
        "有声书".localized(),
        "广告配音".localized(),
        "教学讲解".localized(),
    ]

    // 生成状态
    @Published var isGenerating: Bool = false
    @Published var alertItem: AlertItem? = nil
    @Published var generatedAudioURL: URL? = nil
    @Published var generatedAudioId: Int64? = nil  // 用于保存编辑的名称
    @Published var generatedAudioDuration: TimeInterval = 0  // 生成的音频时长
    @Published var generationProgress: Double = 0.0
    @Published var receivedBytes: Int = 0  // 已接收的音频数据字节数

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

    /// 预估积分消耗（使用 CreditManager 计算真实的积分消耗）
    var estimatedPoints: Int {
        let charCount = TextSplitter.calculateCharCount(text)
        return CreditManager.shared.calculateCredits(for: .normalTTS(characterCount: charCount))
    }

    /// 当前音色
    var voice: Voice? {
        VoiceService.shared.fetchAll().first(where: { $0.key == selectedVoiceKey })
    }

    // MARK: - 操作

    /// 在 EmotionTokenEditor 的光标位置插入情感标签。
    /// 触发 EmotionTokenEditor.updateNSView → insertToken(token)
    func insertEmotion(tag: String) {
        let combined = Constants.emotions + Constants.richLanguageTags
        guard let item = combined.first(where: { $0.tag == tag }) else { return }
        insertTokenLabel = item.label
        insertTokenEmoji = item.emoji
        insertTokenEnglishTag = item.tag
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
        generationProgress = 0.0
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

            if let emotionItem = (Constants.emotions + Constants.richLanguageTags)
                .first(where: { $0.label == label || $0.tag == label }) {
                let token = EmotionToken(label: emotionItem.label,
                                        emoji: emotionItem.emoji,
                                        englishTag: emotionItem.tag)
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

    /// 应用预设
    func applyPreset(_ preset: String) {
        switch preset {
        case "温柔女声": nlInstruction = "温柔的女性声音，语速适中，音色柔和亲切"
        case "活泼男声": nlInstruction = "年轻活泼的男性声音，语速偏快，语调积极"
        case "新闻播报": nlInstruction = "标准播音风格，吐字清晰，字正腔圆"
        case "有声书":   nlInstruction = "知性沉稳的讲述风格，富有感染力"
        case "广告配音": nlInstruction = "充满激情和说服力的广告风格，节奏明快"
        case "教学讲解": nlInstruction = "耐心细致的教学讲解风格，逻辑清晰"
        default: break
        }
    }

    /// 生成音频（集成阿里云 TTS 服务，无字符数限制）
    /// 验证已在 VoiceStudioView 中完成，此处直接开始生成并显示弹窗进度
    func generate(completion: @escaping (Bool) -> Void) {
        // 验证已在 VoiceStudioView.validateInputs() 中完成，此处直接开始生成
        
        // 直接使用结构化的 ttsItems 生成 TTS API 字符串。
        // 文本中已经包含所有 [english_tag] 标签，由 API 自己解析处理。
        // 不再提取单个 emotion 参数，避免覆盖文本中的多标签。
        let ttsText = ttsItems.toTTSAPIString()

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
        alertItem = nil
        generationProgress = 0.0
        receivedBytes = 0  // 重置已接收字节数
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
                Log(message: "开始 TTS 合成，文本长度: \(ttsText.count) 字符")

                // 准备流式回调：每收到一块音频就把进度往上推
                // 由于事先不知道最终大小，按"已用时间 / 经验上限"模拟一条平滑曲线
                let startedAt = Date()
                let approxDuration: TimeInterval = max(2.5, Double(ttsText.count) / 12.0)
                let onAudio: (Data) -> Void = { [weak self] audioChunk in
                    guard let self else { return }
                    let elapsed = Date().timeIntervalSince(startedAt)
                    // 0.05 (已建连) -> 0.95 (接近完成)；剩余 5% 留给落盘 + 入库
                    let p = min(0.95, 0.05 + 0.90 * (elapsed / approxDuration))
                    Task { @MainActor in
                        self.generationProgress = max(self.generationProgress, p)
                        self.receivedBytes += audioChunk.count  // 累计已接收字节数
                    }
                }

                // 调用 TTS 流式接口（替代一次性 await）
                // emotion 传 nil：完全由文本中的 [tag] 标签驱动情感/拟声，
                // 避免覆盖用户输入的多标签。
                let audioData: Data = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
                    ttsService.synthesizeStream(
                        text: ttsText,
                        voice: voice.key,
                        emotion: nil,
                        rate: rate,
                        volume: volume,
                        sampleRate: sampleRate,
                        language: language.code,
                        format: self.selectedFormat.lowercased(),
                        nlInstruction: nlInstruction.isEmpty ? nil : nlInstruction,
                        onAudio: onAudio,
                        completion: { result in
                            cont.resume(with: result)
                        }
                    )
                }

                generationProgress = 0.95

                // 写入磁盘（先用临时 wav 文件名）
                try audioData.write(to: tempAudioURL)
                Log(message: "音频已保存到: \(tempAudioURL.path)")

                generationProgress = 0.98
                
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
                    let createdAudio = ProjectService.shared.createAudio(
                        fileName: finalFileName,
                        text: self.text,
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
                        self.generationProgress = 0.0
                        completion(false)
                        return
                    }

                    // 保存音频 ID 用于后续重命名
                    self.generatedAudioId = audio.id

                    // 扣减积分
                    CreditsService.shared.consume(points)
                    
                    // 保存消耗记录
                    CreditsService.shared.addConsumptionRecord(
                        voiceName: voice.name,
                        voiceKey: voice.key,
                        audioDuration: duration,
                        points: points
                    )

                    self.generatedAudioURL = finalAudioURL
                    self.generatedAudioDuration = duration  // 保存音频时长供播放使用
                    self.generationProgress = 1.0
                    self.isGenerating = false
                    // 注意：不要清空 text — 需求 1 要求保留输入
                    completion(true)
                }

            } catch {
                await MainActor.run {
                    self.isGenerating = false
                    self.generationProgress = 0.0
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
        generationProgress = 0.0
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