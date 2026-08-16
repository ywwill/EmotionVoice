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
    @Published var lastError: String? = nil
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
        lastError = nil
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
            lastError = "请输入文本"
            completion(false)
            return
        }
        guard let voice else {
            lastError = "请选择音色"
            completion(false)
            return
        }

        // 检查积分
        let points = estimatedPoints
        guard CreditsService.shared.canConsume(points) else {
            lastError = "积分不足，请先充值"
            completion(false)
            return
        }

        isGenerating = true
        lastError = nil
        generationProgress = 0.0
        generatedAudioURL = nil

        Task {
            do {
                // 更新进度
                generationProgress = 0.1

                // 提取情感标签（从文本中提取 [emotion] 格式的标签）
                let emotionTag = extractEmotionTag(from: text)

                Log(message: "开始 TTS 合成，文本长度: \(self.text.count) 字符")

                // 调用 TTS 服务（无字符数限制，连接复用）
                let audioData = try await ttsService.synthesize(
                    text: text,
                    voice: voice.key,
                    emotion: emotionTag,
                    rate: rate,
                    volume: volume,
                    sampleRate: sampleRate,
                    language: language.code,
                    nlInstruction: nlInstruction.isEmpty ? nil : nlInstruction
                )

                generationProgress = 0.7

                // 保存音频文件
                let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                let audioDir = documentsPath.appendingPathComponent("GeneratedAudio", isDirectory: true)

                // 确保目录存在
                try FileManager.default.createDirectory(at: audioDir, withIntermediateDirectories: true)

                let timestamp = Int(Date().timeIntervalSince1970)
                let fileName = "audio_\(timestamp).wav"
                let audioURL = audioDir.appendingPathComponent(fileName)

                try audioData.write(to: audioURL)
                Log(message: "音频已保存到: \(audioURL.path)")

                generationProgress = 0.9

                await MainActor.run {
                    self.generatedAudioURL = audioURL
                    self.generationProgress = 1.0
                    self.isGenerating = false

                    // 创建默认项目（如未选择）
                    let projectName = "未命名项目".localized() + " " + Date().timestampString
                    guard let project = ProjectService.shared.createProject(
                        name: projectName, folder: nil) else {
                        self.lastError = "项目创建失败"
                        completion(false)
                        return
                    }

                    // 创建音频条目
                    let title = String(self.text.prefix(20))
                    guard ProjectService.shared.createAudio(
                        projectId: project.id,
                        title: title,
                        text: self.text,
                        voice: voice.key,
                        format: Constants.defaultFormat,
                        sampleRate: self.sampleRate,
                        pointsCost: points,
                        status: .completed,
                        audioURL: audioURL
                    ) != nil else {
                        self.lastError = "音频条目保存失败"
                        completion(false)
                        return
                    }

                    // 扣减积分
                    CreditsService.shared.consume(points)
                    completion(true)
                }

            } catch {
                await MainActor.run {
                    self.isGenerating = false
                    self.generationProgress = 0.0
                    self.lastError = error.localizedDescription
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
