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

    // 模型
    @Published var model: String = Constants.defaultModel
    @Published var availableModels: [String] = [Constants.modelPlus, Constants.modelFlash]

    // 音色
    @Published var selectedVoiceKey: String = Constants.defaultVoice

    // 情感/语速/音量
    @Published var selectedEmotions: Set<String> = []
    @Published var rate: Double = 1.0    // 0.5 - 2.0
    @Published var volume: Double = 100  // 0 - 100

    // 语言/采样率
    @Published var language: LanguageItem = Constants.languages[0]
    @Published var sampleRate: Int = Constants.defaultSampleRate

    // 自然语言指令
    @Published var nlInstruction: String = "年轻活泼的女性声音，语速适中，带有上扬语调".localized()

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

    /// 在文本末尾插入情感标签
    func appendEmotion(tag: String) {
        if text.isEmpty || text.hasSuffix(" ") || text.hasSuffix("\n") {
            text += "[\(tag)]"
        } else {
            text += " [\(tag)]"
        }
    }

    /// 清空文本
    func clearText() {
        text = ""
        lastError = nil
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

    /// 生成（演示：仅做消耗积分 + 持久化）
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

        isGenerating = true

        // 模拟生成耗时
        Task {
            try? await Task.sleep(nanoseconds: 1_500_000_000)

            await MainActor.run {
                self.isGenerating = false

                // 创建默认项目（如未选择）
                let projectName = "未命名项目".localized() + " " + Date().shortDateString
                guard let project = ProjectService.shared.createProject(
                    name: projectName, folder: nil) else {
                    self.lastError = "项目创建失败"
                    completion(false)
                    return
                }

                // 创建音频条目
                let title = String(text.prefix(20))
                let points = estimatedPoints
                guard ProjectService.shared.createAudio(
                    projectId: project.id,
                    title: title,
                    text: text,
                    voice: voice.key,
                    format: Constants.defaultFormat,
                    sampleRate: sampleRate,
                    pointsCost: points,
                    status: .completed
                ) != nil else {
                    self.lastError = "音频条目保存失败"
                    completion(false)
                    return
                }

                // 扣减积分
                CreditsService.shared.consume(points)
                completion(true)
            }
        }
    }
}
