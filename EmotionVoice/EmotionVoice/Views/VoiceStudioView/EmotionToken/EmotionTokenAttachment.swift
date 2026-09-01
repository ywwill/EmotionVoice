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

/// 每个 attachment 对应的样式（按对象身份 key）
nonisolated(unsafe) var kEmotionAttachmentStyles: [ObjectIdentifier: EmotionTokenStyle] = [:]

/// 删除按钮 hover 状态（按对象身份 key）
nonisolated(unsafe) var kEmotionAttachmentDeleteHoverStates: [ObjectIdentifier: Bool] = [:]

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
                            englishTag: payload.englishTag)
    }

    /// 判断某个 attachment 是不是 emotion token
    static func isEmotionToken(_ attachment: NSTextAttachment) -> Bool {
        guard let fw = attachment.fileWrapper else { return false }
        // preferredFilename 是创建时设置的字符串, filename 是 RTF round-trip 后保留的字段
        return fw.preferredFilename == kEmotionSentinelFilename
            || fw.filename == kEmotionSentinelFilename
    }

    /// 工厂方法：根据一个 EmotionToken + 样式，构造一个可以被插入 NSTextStorage 的 attachment
    @MainActor
    static func makeAttachment(for token: EmotionToken, style: EmotionTokenStyle = .default) -> NSTextAttachment {
        let cell = EmotionTokenAttachmentCell()
        cell.tokenLabel = token.label
        cell.tokenEmoji = token.emoji

        let attachment = EmotionTokenAttachment()
        attachment.attachmentCell = cell

        // 把 token payload 写到 FileWrapper，sentinel 作 filename
        let payload = EmotionTokenPayload(label: token.label,
                                          emoji: token.emoji,
                                          englishTag: token.englishTag)
        if let data = try? JSONEncoder().encode(payload) {
            let wrapper = FileWrapper(regularFileWithContents: data)
            wrapper.preferredFilename = kEmotionSentinelFilename
            attachment.fileWrapper = wrapper
        }

        // 保存样式到文件级字典
        kEmotionAttachmentStyles[ObjectIdentifier(attachment)] = style
        return attachment
    }
}

// MARK: - EmotionTokenPayload
/// 写到 FileWrapper 中的 payload。轻量、encode/decode 容错。
private struct EmotionTokenPayload: Codable {
    let label: String
    let emoji: String
    let englishTag: String
}
