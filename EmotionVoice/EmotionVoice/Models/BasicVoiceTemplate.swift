//
//  BasicVoiceTemplate.swift
//  EmotionVoice
//
//  Created by young on 2026/8/9.
//

import Foundation

/// 基础音色模板（来源：qwen-audio-3.0-tts-plus 基础音色.xlsx）
struct BasicVoiceTemplate: Codable, Hashable {
    /// 序号
    let idx: String
    /// 名称（如 龙璨竹月）
    let name: String
    /// voice 参数 key（去除模型前缀）
    let key: String
    /// 性别（男 / 女）
    let gender: String
    /// 年龄
    let age: String
    /// 特质（如 平实质朴音）
    let feature: String
    /// 适用场景（如 日常对话）
    let scene: String
    /// 语种（中文 / 英文）
    let lang: String
    /// 预览音频文件名
    let audio: String

    /// 自动归类：默认按语言分类（旗舰音色由调用方注入 .premium 覆盖）
    var category: VoiceCategory {
        if lang.contains("英文") {
            return .english
        }
        return .chinese
    }

    /// 展示用的描述（仅 feature）
    var displayDesc: String {
        // 简洁形式：去除冗余的"音"字
        let shortFeature = feature.hasSuffix("音") ? String(feature.dropLast()) : feature
        return shortFeature
    }

    /// 单字头像
    var avatar: String {
        // 中文名取最后一字
        if let lastChar = name.last { return String(lastChar) }
        return String(name.prefix(1))
    }
}
