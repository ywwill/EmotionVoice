//
//  TTSContentItem.swift
//  EmotionVoice
//
//  Created by young on 2026/9/1.
//
//  TTS 编辑器的结构化数据模型。
//  用于在「编辑器内部状态 (NSTextStorage 中混合了文本 + 附件)」与
//  「业务侧结构化数据」之间进行双向转换。
//

import Foundation

/// TTS 内容项 — 编辑器可导出的最小结构化单元
///
/// 编辑器内部使用 NSTextStorage 同时包含：
///   * 普通文本 (NSAttributedString)
///   * 语气 Tag (NSTextAttachment)
///
/// 导出为 API / JSON 时，统一为这种结构化数据。
enum TTSContentItem: Codable, Equatable, Hashable {

    /// 普通文本片段
    case text(String)

    /// 情感 Tag（显示用的中文 label / emoji 已经冗余在 item 内部，按需使用）
    case emotion(EmotionToken)

    enum CodingKeys: String, CodingKey {
        case type
        case content
        case emoji
        case englishTag
        case category
    }

    enum ItemType: String, Codable {
        case text
        case emotion
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(ItemType.self, forKey: .type)
        switch type {
        case .text:
            let content = try container.decode(String.self, forKey: .content)
            self = .text(content)
        case .emotion:
            let content = try container.decode(String.self, forKey: .content)
            let emoji = try container.decodeIfPresent(String.self, forKey: .emoji) ?? ""
            let englishTag = try container.decodeIfPresent(String.self, forKey: .englishTag) ?? content
            let category = try container.decodeIfPresent(EmotionCategory.self, forKey: .category) ?? .emotion
            self = .emotion(EmotionToken(label: content, emoji: emoji, englishTag: englishTag, category: category))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let s):
            try container.encode(ItemType.text, forKey: .type)
            try container.encode(s, forKey: .content)
        case .emotion(let token):
            try container.encode(ItemType.emotion, forKey: .type)
            try container.encode(token.label, forKey: .content)
            try container.encode(token.emoji, forKey: .emoji)
            try container.encode(token.englishTag, forKey: .englishTag)
            try container.encode(token.category, forKey: .category)
        }
    }

    // MARK: - 便利访问

    /// 是否是文本片段
    var isText: Bool {
        if case .text = self { return true }
        return false
    }

    /// 是否是情感 Tag
    var isEmotion: Bool {
        if case .emotion = self { return true }
        return false
    }

    /// 文本内容（文本片段 = 自身，情感 Tag = label）
    var content: String {
        switch self {
        case .text(let s): return s
        case .emotion(let t): return t.label
        }
    }

    /// 纯字符串长度（用于做 UI 统计等）
    var length: Int { (content as NSString).length }
}

/// 标签家族：决定 token 在编辑器里的视觉风格。
///   - `.emotion`       语气 / 情感控制类（如 `[sad]` `[excited]`）
///                     — 作用域文本包进同色胶囊，左上角挂 emoji+名称徽章
///   - `.richLanguage`  富语言 / 拟声类（如 `[laughing]` `[sighing]`）
///                     — 在当前位置插入虚线声音标记，不打断语气作用域
///   - `.interrupt`       中断类（`[break]`）
///                     — 只作作用域边界：终止前一个语气标签，自身作用域**不画任何装饰**
///                       （文本按普通正文渲染，无胶囊 / 无填充 / 无徽章）
enum EmotionCategory: String, Codable, Equatable, Hashable {
    case emotion
    case richLanguage
    case interrupt
}

/// 情感 Tag 的展示 + API 数据
struct EmotionToken: Codable, Equatable, Hashable {
    /// 中文 label（显示用）
    let label: String
    /// emoji（UI 装饰用）
    let emoji: String
    /// 英文 tag（最终交给 TTS API）
    let englishTag: String
    /// 标签家族（语气 / 拟声），驱动编辑器内的视觉风格
    let category: EmotionCategory

    init(label: String,
         emoji: String = "",
         englishTag: String? = nil,
         category: EmotionCategory = .emotion) {
        self.label = label
        self.emoji = emoji
        self.englishTag = englishTag ?? label
        self.category = category
    }

    /// 把内部的 `String` 形式包装为 token
    static func wrap(label: String, emoji: String = "", englishTag: String? = nil) -> EmotionToken {
        EmotionToken(label: label, emoji: emoji, englishTag: englishTag ?? label)
    }
}

/// 发送给 TTS API 的一个**独立合成片段**。
///
/// 中断标签（`[break]`）不是 API 支持的 tag，所以整段文本要以它为界切成若干片段：
/// 每个片段各自带自己的语气 tag（中断片段 = `nil`，即不带任何 tag），
/// 由 API 独立解析 —— 这样前一个语气标签的作用域就不会越过中断标记继续影响后面的文本。
///
/// 片段数组的顺序即文档顺序，音频合并时按原顺序拼即可。
struct TTSSegment: Equatable, Hashable {
    /// 该片段要合成的文本
    let text: String
    /// 该片段生效的语气 tag（nil = 不带任何语气）
    let emotion: String?

    /// 真正交给 API 的字符串：带语气标签时内联在开头，否则就是纯文本
    var apiText: String {
        guard let emotion, !emotion.isEmpty else { return text }
        return "[\(emotion)]\(text)"
    }
}

extension Array where Element == TTSContentItem {

    /// 序列化为 JSON Data（用于落盘 / HTTP 请求）
    func toJSONData() -> Data? {
        try? JSONEncoder().encode(self)
    }

    /// 序列化为 JSON 字符串
    func toJSONString() -> String? {
        guard let data = toJSONData() else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// 从 JSON Data 反序列化；失败时返回 nil
    static func from(jsonData: Data) -> [TTSContentItem]? {
        try? JSONDecoder().decode([TTSContentItem].self, from: jsonData)
    }

    /// 从 JSON 字符串反序列化
    static func from(jsonString: String) -> [TTSContentItem]? {
        guard let data = jsonString.data(using: .utf8) else { return nil }
        return from(jsonData: data)
    }

    /// 用于 TTS API 的「标签化」字符串：把 emotion 段转换为 `[englishTag]`，
    /// 其余文本原样拼接（仍保留用户实际输入的字符，包括换行）。
    ///
    /// 例如：
    ///   [.text("你好"), .emotion(.init(label: "开心", emoji: "😊", englishTag: "happy")), .text("世界")]
    ///   → "你好[happy]世界"
    ///
    /// ⚠️ 中断标签会被**丢掉**——API 不认识它，它也没有对应的 tag。
    /// 但注意：光拼成一条字符串是无法保留中断语义的（前一个语气标签会越过它继续生效），
    /// 所以生成链路用的是 `toTTSSegments()`，以中断标记为界切成多次独立请求。
    func toTTSAPIString() -> String {
        var out = ""
        for item in self {
            switch item {
            case .text(let s):
                out.append(s)
            case .emotion(let token):
                if token.category != .interrupt {
                    out.append("[\(token.englishTag)]")
                }
            }
        }
        return out
    }

    /// 去掉所有情感 / 拟声标签后的纯文本：**只保留 `.text` 片段**。
    ///
    /// 按「中断标签」把 items 切成若干**互不影响**的独立请求片段。
    ///
    /// 背景：控制类标签（如 `[sad]`）会一直作用到下一个控制类标签为止。
    /// 若把所有内容拼成一条请求，中断标记后面的文本仍会带着前面的语气，
    /// 反之中断段也会把「无语气」这件事传递下去 —— 两种污染都要避免。
    ///
    /// 切分规则：
    ///   * 语气标记 / 中断标记 → 提交上一段，开始新片段（这就是作用域边界）
    ///   * 拟声标记 → 留在当前片段里（它是插入的声音事件，不覆盖当前语气）
    ///
    /// 空片段会被丢弃；整段为空时返回单个空片段兜底。调用方按返回顺序依次合成、
    /// 顺序拼接音频即可还原成完整的朗读结果。
    func toTTSSegments() -> [TTSSegment] {
        var segments: [TTSSegment] = []
        var currentText = ""
        var currentEmotion: String? = nil

        func flush() {
            let trimmed = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                segments.append(TTSSegment(text: currentText, emotion: currentEmotion))
            }
            currentText = ""
            currentEmotion = nil
        }

        for item in self {
            switch item {
            case .text(let s):
                currentText += s
            case .emotion(let token):
                switch token.category {
                case .emotion:
                    // 语气标记：上一段到此为止，后面用新的语气
                    flush()
                    currentEmotion = token.englishTag
                case .interrupt:
                    // 中断标记：上一段到此为止，后面回到音色默认状态
                    flush()
                    currentEmotion = nil
                case .richLanguage:
                    // 拟声：留在当前片段里，内联成 [tag]
                    currentText += "[\(token.englishTag)]"
                }
            }
        }
        flush()
        return segments.isEmpty ? [TTSSegment(text: "", emotion: nil)] : segments
    }

    /// 用于入库、复制原文、展示「原文」等场景 —— 标签只是编辑器里的 UI 装饰，
    /// 它的中文 label（如「笑声」「开心」）不是用户输入的台词，
    /// 落库会污染历史原文（也会被当成正文计费、展示、复制出去）。
    ///
    /// 例如：
    ///   [.text("你好"), .emotion(.init(label: "笑声", emoji: "😆", englishTag: "laughing")), .text("世界")]
    ///   → "你好世界"
    func toPlainText() -> String {
        var out = ""
        for item in self {
            if case .text(let s) = item {
                out.append(s)
            }
        }
        return out
    }

    /// 「人类可读」的字符串：用于显示 / 调试
    /// 例如：
    ///   → "你好 [😊 开心] 世界"
    func toDisplayString() -> String {
        var out = ""
        for item in self {
            switch item {
            case .text(let s):
                out.append(s)
            case .emotion(let token):
                let prefix = token.emoji.isEmpty ? "" : "\(token.emoji) "
                out.append("[\(prefix)\(token.label)]")
            }
        }
        return out
    }
}
