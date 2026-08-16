//
//  VoiceStudioViewModel.swift
//  EmotionVoice
//
//  Created by young on 2026/8/8.
//

import Foundation
import SwiftUI
import Combine

/// 语音合成工作台视图模型
@MainActor
final class VoiceStudioViewModel: ObservableObject {

    // 文本
    @Published var text: String = ""

    // 音色
    @Published var selectedVoiceKey: String = Constants.defaultVoice

    // 情感/语速/音量
    @Published var rate: Double = 1.0    // 0.5 - 2.0
    @Published var volume: Double = 100  // 0 - 100
    
    // 情感标签使用次数统计 [tag: count]
    @Published var emotionUsageCounts: [String: Int] = [:]

    // 语言/采样率
    @Published var language: LanguageItem = Constants.languages[0]
    @Published var sampleRate: Int = Constants.defaultSampleRate

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
    @Published var generationProgress: Double = 0.0

    // TTS 服务
    private let ttsService = BailianTTSService.shared

    // MARK: - 计算属性

    /// 文本字符数（不含空白）
    var charCount: Int {
        text.replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .count
    }

    /// 预估积分消耗
    var estimatedPoints: Int {
        ProjectService.shared.estimatePoints(forText: text)
    }

    /// 当前音色
    var voice: Voice? {
        VoiceService.shared.fetchAll().first(where: { $0.key == selectedVoiceKey })
    }

    // MARK: - 操作

    /// 在文本末尾插入情感标签，并统计使用次数
    func appendEmotion(tag: String) {
        // 累积使用次数
        emotionUsageCounts[tag, default: 0] += 1
        
        if text.isEmpty || text.hasSuffix(" ") || text.hasSuffix("\n") {
            text += "[\(tag)]"
        } else {
            text += " [\(tag)]"
        }
    }
    
    /// 获取指定情感标签的使用次数
    func usageCount(for tag: String) -> Int {
        return emotionUsageCounts[tag] ?? 0
    }

    /// 清空文本
    func clearText() {
        text = ""
        emotionUsageCounts.removeAll()
        alertItem = nil
        generatedAudioURL = nil
        generationProgress = 0.0
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
    func generate(completion: @escaping (Bool) -> Void) {
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty else {
            alertItem = AlertItem(title: "无法生成".localized(),
                                   message: "请先输入要合成的文本".localized())
            completion(false)
            return
        }
        guard let voice else {
            alertItem = AlertItem(title: "无法生成".localized(),
                                   message: "请先选择一个音色".localized())
            completion(false)
            return
        }

        // 检查积分
        let points = estimatedPoints
        guard CreditsService.shared.canConsume(points) else {
            alertItem = AlertItem(title: "积分不足".localized(),
                                   message: "本次合成需要约 %d 积分，请先充值".localized(points))
            completion(false)
            return
        }

        isGenerating = true
        alertItem = nil
        generationProgress = 0.0
        generatedAudioURL = nil

        // 提前确定文件名（按时间戳），便于落盘 + 入库
        let now = Date()
        let fileName = "\(now.filenameTimestamp).\(Constants.defaultFormat)"

        // 落盘目录：Documents/GeneratedAudio/
        ensureGeneratedAudioDirectoryExists()
        let audioURL = generatedAudioDirectoryURL().appendingPathComponent(fileName)

        Task {
            do {
                Log(message: "开始 TTS 合成，文本长度: \(self.text.count) 字符")

                // 准备流式回调：每收到一块音频就把进度往上推
                // 由于事先不知道最终大小，按"已用时间 / 经验上限"模拟一条平滑曲线
                let startedAt = Date()
                let approxDuration: TimeInterval = max(2.5, Double(self.text.count) / 12.0)
                let onAudio: (Data) -> Void = { [weak self] _ in
                    guard let self else { return }
                    let elapsed = Date().timeIntervalSince(startedAt)
                    // 0.05 (已建连) -> 0.95 (接近完成)；剩余 5% 留给落盘 + 入库
                    let p = min(0.95, 0.05 + 0.90 * (elapsed / approxDuration))
                    Task { @MainActor in
                        self.generationProgress = max(self.generationProgress, p)
                    }
                }

                // 调用 TTS 流式接口（替代一次性 await）
                let audioData: Data = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Data, Error>) in
                    ttsService.synthesizeStream(
                        text: text,
                        voice: voice.key,
                        emotion: extractEmotionTag(from: text),
                        rate: rate,
                        volume: volume,
                        sampleRate: sampleRate,
                        language: language.code,
                        nlInstruction: nlInstruction.isEmpty ? nil : nlInstruction,
                        onAudio: onAudio,
                        completion: { result in
                            cont.resume(with: result)
                        }
                    )
                }

                generationProgress = 0.95

                // 写入磁盘
                try audioData.write(to: audioURL)
                Log(message: "音频已保存到: \(audioURL.path)")

                generationProgress = 0.98

                // 计算真实时长：优先使用 AVAudioFile 读取 PCM 帧数；
                // 失败时（如非 WAV/无法解析）回退到按 data 大小粗略估算。
                let duration = AudioDuration.read(
                    url: audioURL,
                    sampleRate: self.sampleRate,
                    bytes: audioData.count,
                    format: Constants.defaultFormat
                )
                Log(message: "音频时长: \(duration)s")

                await MainActor.run {
                    // 直接创建音频条目（不再需要先建项目；不再保存完整路径）
                    guard ProjectService.shared.createAudio(
                        fileName: fileName,
                        text: self.text,
                        voice: voice.key,
                        format: Constants.defaultFormat,
                        sampleRate: self.sampleRate,
                        pointsCost: points,
                        status: .completed,
                        duration: duration
                    ) != nil else {
                        self.alertItem = AlertItem(title: "保存失败".localized(),
                                                    message: "无法写入音频条目，请稍后重试".localized())
                        self.isGenerating = false
                        self.generationProgress = 0.0
                        completion(false)
                        return
                    }

                    // 扣减积分
                    CreditsService.shared.consume(points)

                    self.generatedAudioURL = audioURL
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

    /// 从文本中提取情感标签
    private func extractEmotionTag(from text: String) -> String? {
        // 提取最后一个情感标签作为主要情感
        let pattern = "\\[([a-zA-Z]+)\\]"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }

        let range = NSRange(text.startIndex..., in: text)
        let matches = regex.matches(in: text, range: range)

        // 返回最后一个匹配的情感标签
        if let lastMatch = matches.last,
           let range = Range(lastMatch.range(at: 1), in: text) {
            return String(text[range])
        }

        return nil
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
}

/// Alert 内容（用于 .alert(item:) 绑定）
struct AlertItem: Identifiable, Equatable {
    let id = UUID()
    let title: String
    let message: String
}
