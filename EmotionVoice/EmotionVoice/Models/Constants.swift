//
//  Constants.swift
//  EmotionVoice
//
//  Created by young on 2026/8/8.
//

import Foundation

/// 应用常量
enum Constants {

    // MARK: - 模型
    static let modelPlus = "qwen-audio-3.0-tts-plus"
    static let modelFlash = "qwen-audio-3.0-tts-flash"
    static let defaultModel = modelPlus

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
    /// 可视化选择的 20 个情感标签
    /// 与 [xxx] 文本标签一一对应
    static let emotions: [EmotionItem] = [
        EmotionItem(label: "开心",   emoji: "😊", tag: "happy"),
        EmotionItem(label: "悲伤",   emoji: "😢", tag: "sad"),
        EmotionItem(label: "愤怒",   emoji: "😠", tag: "angry"),
        EmotionItem(label: "惊讶",   emoji: "😮", tag: "amazed"),
        EmotionItem(label: "疲惫",   emoji: "😴", tag: "tired"),
        EmotionItem(label: "调皮",   emoji: "🎭", tag: "mischievously"),
        EmotionItem(label: "耳语",   emoji: "🤫", tag: "whispers"),
        EmotionItem(label: "严肃",   emoji: "🎙️", tag: "serious"),
        EmotionItem(label: "兴奋",   emoji: "⚡", tag: "excited"),
        EmotionItem(label: "恳求",   emoji: "🥺", tag: "pleading"),
        EmotionItem(label: "厌恶",   emoji: "🤢", tag: "disgusted"),
        EmotionItem(label: "痴迷",   emoji: "🤩", tag: "obsessed"),
        EmotionItem(label: "放松",   emoji: "😌", tag: "relaxed"),
        EmotionItem(label: "思考",   emoji: "🤔", tag: "thinking"),
        EmotionItem(label: "尴尬",   emoji: "😅", tag: "embarrassed"),
        EmotionItem(label: "傲慢",   emoji: "😏", tag: "smug"),
        EmotionItem(label: "困倦",   emoji: "😴", tag: "sleepy"),
        EmotionItem(label: "感恩",   emoji: "🙏", tag: "grateful"),
        EmotionItem(label: "好奇",   emoji: "🧐", tag: "curious"),
        EmotionItem(label: "讽刺",   emoji: "🙃", tag: "sarcastic"),
    ]

    // MARK: - 富语言标签
    static let richLanguageTags: [EmotionItem] = [
        EmotionItem(label: "大笑",   emoji: "😆", tag: "laughing"),
        EmotionItem(label: "咯咯笑", emoji: "🤭", tag: "giggles"),
        EmotionItem(label: "叹息",   emoji: "😮‍💨", tag: "sighing"),
        EmotionItem(label: "倒吸气", emoji: "😲", tag: "gasp"),
        EmotionItem(label: "清嗓",   emoji: "🗣️", tag: "clears throat"),
        EmotionItem(label: "咳嗽",   emoji: "😷", tag: "cough"),
        EmotionItem(label: "哼声",   emoji: "😤", tag: "snorts"),
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
