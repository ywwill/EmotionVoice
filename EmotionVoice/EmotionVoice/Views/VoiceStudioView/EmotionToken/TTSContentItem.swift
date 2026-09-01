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
            self = .emotion(EmotionToken(label: content, emoji: emoji, englishTag: englishTag))
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

/// 情感 Tag 的展示 + API 数据
struct EmotionToken: Codable, Equatable, Hashable {
    /// 中文 label（显示用）
    let label: String
    /// emoji（UI 装饰用）
    let emoji: String
    /// 英文 tag（最终交给 TTS API）
    let englishTag: String

    /// 把内部的 `String` 形式包装为 token
    static func wrap(label: String, emoji: String = "", englishTag: String? = nil) -> EmotionToken {
        EmotionToken(label: label, emoji: emoji, englishTag: englishTag ?? label)
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
    func toTTSAPIString() -> String {
        var out = ""
        for item in self {
            switch item {
            case .text(let s):
                out.append(s)
            case .emotion(let token):
                out.append("[\(token.englishTag)]")
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
