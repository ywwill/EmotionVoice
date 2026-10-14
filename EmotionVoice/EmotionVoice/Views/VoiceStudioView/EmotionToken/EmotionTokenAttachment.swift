//
//  EmotionTokenAttachment.swift
//  EmotionVoice
//
//  Created by young on 2026/9/1.
//
//  Emotion Token 的数据模型 + Attachment 工厂。
//  Token 在 NSTextStorage 中以 `NSTextAttachment` 形式占据一个字符位（U+FFFC）。
// 真实的 emotion 信息存在 `FileWrapper.preferredFilename`（sentinel）
// 和 `FileWrapper.regularFileContents`（UTF-8 编码的 JSON）中，避免把它们当字符串处理。
//

import AppKit

// MARK: - 文件级 sentinel 标识
//
// FileWrapper.preferredFilename 是创建时设置的字符串，
// 经过 RTF round-trip 后只会保留 filename（应用不会保留 preferredFilename）。
// 用 sentinel 字符串作为 filename，让任何附件实例都能被识别为「本编辑器的 emotion token」。
private let kEmotionSentinelFilename = "emotionvoice.token"

// MARK: - File-scope 状态表
//
// NSTextAttachmentCell 继承 @MainActor from NSCell，但 AppKit 在 nonisolated 渲染管道里
// 调用绘制 override。所有「cell 在绘制时需要的运行时状态」必须放在文件级，并用
// nonisolated(unsafe) 修饰 —— 不能放在 cell 的 stored property 里。

/// 每个 attachment 对应的「身份」（基础色 + 家族，按对象身份 key）。
/// 真正的颜色在绘制时由 EmotionTokenStyle.resolved(for:dark:) 结合外观解析，
/// 因此这里只存与外观无关的身份信息。
nonisolated(unsafe) var kEmotionAttachmentIdentity: [ObjectIdentifier: EmotionTokenIdentity] = [:]

/// 当前被指针悬停的 attachment（同一时刻最多一个）。cell 据此决定 × 是否高亮、pill 是否抬升。
nonisolated(unsafe) var kEmotionAttachmentHovered: NSTextAttachment?

/// 命中测试时是否处于 token 选中态（用于高亮）
nonisolated(unsafe) var kEmotionAttachmentSelectionStates: [ObjectIdentifier: Bool] = [:]

// MARK: - EmotionTokenAttachment

/// 自定义 NSTextAttachment 子类。
/// 关键点：
///   * override `image`/`attachmentBounds` 等是不必要的 —— 自定义 cell 在 `draw(withFrame:in:)`
///     里负责绘制。
///   * payload 存在 FileWrapper 中，可以从 NSTextStorage 反复提取 → 满足 export/import 的需求。
final class EmotionTokenAttachment: NSTextAttachment {

    /// 解析 FileWrapper 得到 token 数据
    static func parse(from attachment: NSTextAttachment) -> EmotionToken? {
        guard isEmotionToken(attachment),
              let data = attachment.fileWrapper?.regularFileContents,
              let payload = try? JSONDecoder().decode(EmotionTokenPayload.self, from: data) else {
            return nil
        }
        return EmotionToken(label: payload.label,
                            emoji: payload.emoji,
                            englishTag: payload.englishTag,
                            category: payload.category)
    }

    /// 判断某个 attachment 是不是 emotion token
    static func isEmotionToken(_ attachment: NSTextAttachment) -> Bool {
        guard let fw = attachment.fileWrapper else { return false }
        // preferredFilename 是创建时设置的字符串, filename 是 RTF round-trip 后保留的字段
        return fw.preferredFilename == kEmotionSentinelFilename
            || fw.filename == kEmotionSentinelFilename
    }

    /// 工厂方法：根据一个 EmotionToken 构造可被插入 NSTextStorage 的 attachment。
    /// 样式不在构造时写死，而是存「身份」（基础色 + 家族），绘制时结合外观实时解析。
    @MainActor
    static func makeAttachment(for token: EmotionToken) -> NSTextAttachment {
        let cell = EmotionTokenAttachmentCell()
        cell.tokenLabel = token.label
        cell.tokenEmoji = token.emoji
        cell.tokenCategory = token.category

        let attachment = EmotionTokenAttachment()
        attachment.attachmentCell = cell

        // 把 token payload 写到 FileWrapper，sentinel 作 filename
        let payload = EmotionTokenPayload(label: token.label,
                                          emoji: token.emoji,
                                          englishTag: token.englishTag,
                                          category: token.category)
        if let data = try? JSONEncoder().encode(payload) {
            let wrapper = FileWrapper(regularFileWithContents: data)
            wrapper.preferredFilename = kEmotionSentinelFilename
            attachment.fileWrapper = wrapper
        }

        // 保存身份到文件级字典（绘制时据此 + 外观解析颜色）
        let base = EmotionTokenStyle.baseColor(for: token.englishTag.isEmpty ? token.label : token.englishTag)
        kEmotionAttachmentIdentity[ObjectIdentifier(attachment)] =
            EmotionTokenIdentity(baseColor: base, category: token.category)
        return attachment
    }
}

// MARK: - EmotionTokenPayload
/// 写到 FileWrapper 中的 payload。轻量、encode/decode 容错。
private struct EmotionTokenPayload: Codable {
    let label: String
    let emoji: String
    let englishTag: String
    let category: EmotionCategory

    init(label: String, emoji: String, englishTag: String, category: EmotionCategory) {
        self.label = label
        self.emoji = emoji
        self.englishTag = englishTag
        self.category = category
    }

    enum CodingKeys: String, CodingKey {
        case label, emoji, englishTag, category
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        label = try c.decode(String.self, forKey: .label)
        emoji = try c.decodeIfPresent(String.self, forKey: .emoji) ?? ""
        englishTag = try c.decodeIfPresent(String.self, forKey: .englishTag) ?? label
        category = try c.decodeIfPresent(EmotionCategory.self, forKey: .category) ?? .emotion
    }
}
