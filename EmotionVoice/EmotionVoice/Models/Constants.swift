//
//  Constants.swift
//  EmotionVoice
//
//  Created by young on 2026/8/8.
//

import Foundation

/// 应用常量
enum Constants {

    // MARK: - 标签本地化（中文 label ↔ 英文 tag）

    /// 根据中文 label 查找对应的英文 tag（如 "开心" -> "happy"）。
    /// 同时支持英文 tag 原值（"happy" -> "happy"）以保证已经用英文标签的旧文本也能继续工作。
    static func tagForLabel(_ label: String) -> String? {
        let trimmed = label.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        let combined = emotions + richLanguageTags
        if let hit = combined.first(where: { $0.label == trimmed }) {
            return hit.tag
        }
        // 兼容：用户已经写好的英文标签
        if combined.contains(where: { $0.tag == trimmed }) {
            return trimmed
        }
        return nil
    }

    /// 根据英文 tag 查找对应的中文 label（如 "happy" -> "开心"）。找不到时返回 nil。
    static func labelForTag(_ tag: String) -> String? {
        let combined = emotions + richLanguageTags
        return combined.first(where: { $0.tag == tag })?.label
    }

    // MARK: - 默认音色
    static let defaultVoice = "longanlingxin"

    // MARK: - 默认采样率
    static let defaultSampleRate = 48000
    static let defaultFormat = "wav"

    // MARK: - 积分换算
    /// 每 1000 字符 = 1 积分，最低 1 积分
    static let pointsPerThousandChars = 1.0

    /// 当前用户积分余额（演示用，本地存储）
    static let defaultCreditsBalance = 1280

    /// 当前用户本月已用积分（演示用）
    static let defaultMonthlyUsed = 4560

    // MARK: - 情感标签
    /// 控制类情感标签
    /// 与 [xxx] 文本标签一一对应；description 为官方说明，供悬浮提示使用。
    /// 这类标签会改变周围文本的情感基调（如 [excited] 让后续所有文本都带兴奋语气）。
    static let emotions: [EmotionItem] = [
        EmotionItem(label: "悲伤", emoji: "😢", tag: "sad",
                   description: "悲伤低落的语气，带有忧愁、沮丧的情感基调。"),
        EmotionItem(label: "惊叹", emoji: "😮", tag: "amazed",
                   description: "惊讶的语气，带有意外、震惊的情感色彩。"),
        EmotionItem(label: "呐喊", emoji: "📣", tag: "deep and loud shouting",
                   description: "深沉大声呐喊"),
        EmotionItem(label: "颤抖", emoji: "😨", tag: "trembling",
                   description: "声音颤抖的语气，带有害怕、紧张或激动的情绪。"),
        EmotionItem(label: "愤怒", emoji: "😠", tag: "angry",
                   description: "愤怒激动的语气，带有强烈不满的情绪色彩。"),
        EmotionItem(label: "兴奋", emoji: "⚡", tag: "excited",
                   description: "兴奋激动的语气，带有强烈的热情和期待感。"),
        EmotionItem(label: "讽刺", emoji: "🙃", tag: "sarcastic",
                   description: "讽刺的语气，带有反讽、挖苦的意味。"),
        EmotionItem(label: "好奇", emoji: "🤔", tag: "curious",
                   description: "好奇的语气"),
        EmotionItem(label: "低沉", emoji: "🧛", tag: "like dracula",
                   description: "德古拉风格（低沉、阴森）"),
        EmotionItem(label: "无聊", emoji: "💤", tag: "bored",
                   description: "无聊的语气"),
        EmotionItem(label: "疲惫", emoji: "😴", tag: "tired",
                   description: "疲惫的语气，语速偏慢、语调低沉，传达疲惫感。"),
        EmotionItem(label: "轻蔑", emoji: "😒", tag: "scornful",
                   description: "轻蔑的语气"),
        EmotionItem(label: "大喊", emoji: "🗣️", tag: "shouting",
                   description: "大喊"),
        EmotionItem(label: "ASMR", emoji: "🎧", tag: "asmr",
                   description: "ASMR 风格的柔和低声，适合助眠、放松类内容。"),
        EmotionItem(label: "惊恐", emoji: "😱", tag: "panicked",
                   description: "惊恐慌张的语气，带有惊慌失措的紧迫感。"),
        EmotionItem(label: "调皮", emoji: "😈", tag: "mischievously",
                   description: "调皮的语气，带有戏谑、捉弄的趣味感。"),
        EmotionItem(label: "共情", emoji: "💚", tag: "empathetic",
                   description: "共情的语气"),
        EmotionItem(label: "耳语", emoji: "🤫", tag: "whispers",
                   description: "轻声低语的风格，适合私密、神秘或亲密的场景。"),
        EmotionItem(label: "不情愿", emoji: "🙄", tag: "reluctantly",
                   description: "不情愿的语气"),
        EmotionItem(label: "哭泣", emoji: "😭", tag: "crying",
                   description: "哭泣中的语气，带有哽咽、抽泣的强烈情感。"),
        EmotionItem(label: "严肃", emoji: "😐", tag: "serious",
                   description: "严肃认真的语气，适合播报、朗读等正式场景。"),
        EmotionItem(label: "极慢", emoji: "🐢", tag: "very slowly",
                   description: "极慢的语速，适合强调、沉思或戏剧性的停顿场景。"),
        EmotionItem(label: "极快", emoji: "🔥", tag: "very fast",
                   description: "极快的语速，适合紧张、激动或急促的对话场景。"),
    ]

    // MARK: - 富语言标签
    /// 仅在该位置插入一段声音效果（大笑、叹息、咳嗽等），
    /// 不改变周围文本的情感基调。
    /// 控制类与富语言类分开维护：富语言永远只有这 7 个官方拟声。
    static let richLanguageTags: [EmotionItem] = [
        EmotionItem(label: "大笑", emoji: "😆", tag: "laughing",
                   description: "大笑"),
        EmotionItem(label: "咯咯笑", emoji: "🤭", tag: "giggles",
                   description: "咯咯轻"),
        EmotionItem(label: "叹息", emoji: "😮‍💨", tag: "sighing",
                   description: "叹息声"),
        EmotionItem(label: "倒吸气", emoji: "😲", tag: "gasp",
                   description: "倒吸一口气"),
        EmotionItem(label: "清嗓", emoji: "🗣️", tag: "clears throat",
                   description: "清嗓"),
        EmotionItem(label: "咳嗽", emoji: "😷", tag: "cough",
                   description: "咳嗽"),
        EmotionItem(label: "哼声", emoji: "😤", tag: "snorts",
                   description: "哼声、嗤笑"),
    ]

    // MARK: - 语言/方言
    static let languages: [LanguageItem] = [
        LanguageItem(name: "中文普通话", code: "mandarin"),
        LanguageItem(name: "粤语", code: "cantonese"),
        LanguageItem(name: "四川话", code: "sichuan"),
        LanguageItem(name: "英文", code: "english"),
    ]

    // MARK: - 采样率
    static let sampleRates: [SampleRateItem] = [
        SampleRateItem(rate: 8000,  displayName: "8 kHz",    useCase: "语音通话"),
        SampleRateItem(rate: 16000, displayName: "16 kHz",   useCase: "AI 语音"),
        SampleRateItem(rate: 22050, displayName: "22.05 kHz", useCase: "网络语音"),
        SampleRateItem(rate: 24000, displayName: "24 kHz",   useCase: "语音合成"),
        SampleRateItem(rate: 32000, displayName: "32 kHz",   useCase: "音乐剪辑"),
        SampleRateItem(rate: 44100, displayName: "44.1 kHz", useCase: "CD 级音频"),
        SampleRateItem(rate: 48000, displayName: "48 kHz",   useCase: "专业音频"),
    ]

    // MARK: - 积分套餐
    static let creditsPackages: [CreditsPackage] = [
        CreditsPackage(id: "trial",
                       icon: "🌱",
                       name: "体验包",
                       price: 9.9,
                       points: 500,
                       unitPrice: 0.020,
                       features: ["适合尝鲜体验", "12 个月有效"],
                       isRecommended: false),
        CreditsPackage(id: "basic",
                       icon: "⭐",
                       name: "基础包",
                       price: 49,
                       points: 3000,
                       unitPrice: 0.016,
                       features: ["个人创作首选", "12 个月有效"],
                       isRecommended: false),
        CreditsPackage(id: "pro",
                       icon: "💎",
                       name: "专业包",
                       price: 199,
                       points: 15000,
                       unitPrice: 0.013,
                       features: ["高频使用推荐", "12 个月有效", "优先客服支持"],
                       isRecommended: true),
        CreditsPackage(id: "ultimate",
                       icon: "👑",
                       name: "旗舰包",
                       price: 599,
                       points: 50000,
                       unitPrice: 0.012,
                       features: ["专业创作者", "12 个月有效", "企业级 API"],
                       isRecommended: false),
    ]

    // MARK: - 积分消耗参考
    static let costReference: [CostItem] = [
        CostItem(type: "短句 / 文案",  range: "50-200 字",   points: "1-5",   scene: "客服回复、朋友圈"),
        CostItem(type: "中等段落",    range: "200-500 字",  points: "5-15",  scene: "产品介绍、短视频"),
        CostItem(type: "长文本",      range: "500-2,000 字", points: "15-60", scene: "文章朗读、广告"),
        CostItem(type: "有声书章节",  range: "2,000-5,000 字", points: "60-150", scene: "有声书、广播剧"),
        CostItem(type: "完整节目",    range: "5,000+ 字",   points: "150+",  scene: "播客、纪录片"),
    ]

    // MARK: - 月度统计默认值（首次启动演示）
    static let defaultMonthlyStats = MonthlyStats(
        month: monthKey(Date()),
        pointsUsed: 4560,
        audioCount: 28,
        voiceCount: 18
    )

    static func monthKey(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM"
        return f.string(from: date)
    }
}

/// 情感条目（用于网格选择）
struct EmotionItem: Identifiable, Hashable {
    let label: String
    let emoji: String
    let tag: String      // 对应 [xxx] 标签
    let description: String // 描述
    var id: String { tag }
}

/// 语言条目
struct LanguageItem: Identifiable, Hashable {
    let name: String
    let code: String
    var id: String { code }
}

/// 采样率条目
struct SampleRateItem: Identifiable, Hashable {
    let rate: Int           // 采样率（Hz）
    let displayName: String // 显示名称（如 "48 kHz"）
    let useCase: String     // 典型用途
    var id: Int { rate }
}

/// 积分消耗参考条目
struct CostItem: Identifiable, Hashable {
    let type: String
    let range: String
    let points: String
    let scene: String
    var id: String { type }
}
