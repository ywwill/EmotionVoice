//
//  TokenDocument.swift
//  iOSEmora
//
//  iOS 编辑器的文档模型。
//
//  macOS 那套把标签塞进 `NSTextStorage` 作为 `NSTextAttachment` 的实现无法直接搬到 iOS
//  （NSTextAttachmentCell 是 AppKit 专属），所以 iOS 改成「纯文本 + 位置标记」：
//
//   * 语气 / 中断：只记录一个**位置**，文本里不留任何字符，视觉上是「从哪里开始生效」的作用域边界；
//   * 拟声：需要一个实实在在的行内占位，否则 pill 会压在正文上 —— 用一个 1 字符的
//     `NSTextAttachment`（U+FFFC）占出宽度，胶囊层在那块矩形里画虚线 pill。
//
//  生成时再按位置把标记还原成 `[TTSContentItem]`，交给既有的 `toTTSSegments()` 切段。
//

import Foundation

/// 一个情感标记（在文档坐标里的位置 + 标签内容）
struct EmotionMark: Identifiable, Hashable {
    let id: UUID
    /// 在**文档串**（含 U+FFFC 占位）中的字符位置
    var location: Int
    let token: EmotionToken

    init(id: UUID = UUID(), location: Int, token: EmotionToken) {
        self.id = id
        self.location = location
        self.token = token
    }

    /// 该标记在文档里占几个字符（只有拟声占 1 个占位符）
    var occupiedLength: Int {
        token.category == .richLanguage ? 1 : 0
    }
}

/// 文档串与结构化内容之间的双向转换
enum TokenDocument {

    /// 拟声标签在文档串里占位的字符（object replacement character）
    static let placeholder: String = "\u{FFFC}"

    // MARK: - 文档 → 结构化

    /// 把「文档串 + 标记」还原成 `[TTSContentItem]`（占位符会被剔除）
    static func contentItems(doc: String, marks: [EmotionMark]) -> [TTSContentItem] {
        let ordered = marks.sorted { $0.location < $1.location }
        let chars = Array(doc)

        var items: [TTSContentItem] = []
        var cursor = 0

        /// 把 [cursor, upTo) 之间的纯文本追加进结果（跳过占位符）
        func flushText(upTo: Int) {
            guard upTo > cursor else { return }
            let slice = chars[cursor..<min(upTo, chars.count)]
            let plain = slice.filter { String($0) != placeholder }
            if !plain.isEmpty { items.append(.text(String(plain))) }
        }

        for mark in ordered {
            let loc = min(max(mark.location, 0), chars.count)
            flushText(upTo: loc)
            items.append(.emotion(mark.token))
            cursor = loc
            // 拟声占位符本身不进正文
            if mark.token.category == .richLanguage, cursor < chars.count,
               String(chars[cursor]) == placeholder {
                cursor += 1
            }
        }
        flushText(upTo: chars.count)
        return items
    }

    /// 去掉全部占位符后的纯文本（用于字数统计与 `vm.text`）
    static func plainText(doc: String) -> String {
        doc.replacingOccurrences(of: placeholder, with: "")
    }

    // MARK: - 结构化 → 文档

    /// 反向转换：把 `[TTSContentItem]` 还原成「文档串 + 标记」（用于从 VM 恢复编辑器内容）
    static func make(items: [TTSContentItem]) -> (doc: String, marks: [EmotionMark]) {
        var doc = ""
        var marks: [EmotionMark] = []
        for item in items {
            switch item {
            case .text(let s):
                doc += s
            case .emotion(let token):
                let mark = EmotionMark(location: (doc as NSString).length, token: token)
                marks.append(mark)
                if token.category == .richLanguage {
                    doc += placeholder
                }
            }
        }
        return (doc, marks)
    }

    // MARK: - 标记位置维护

    /// 文本被替换后修正标记位置。
    ///
    /// 规则与 macOS 编辑器保持一致：
    ///  * 落在被替换区间**内部**的标记 → 删除（标记依附的字符没了）；
    ///  * 位于替换区间之后的标记 → 整体平移 `delta`；
    ///  * 恰好落在区间起点的标记 → 原地不动。
    static func adjust(marks: [EmotionMark], editedRange: NSRange, replacementLength: Int) -> [EmotionMark] {
        let delta = replacementLength - editedRange.length
        guard delta != 0 || editedRange.length > 0 else { return marks }

        return marks.compactMap { mark in
            if mark.location > editedRange.location && mark.location < editedRange.upperBound {
                return nil
            }
            if mark.location >= editedRange.upperBound {
                var m = mark
                m.location = max(editedRange.location, mark.location + delta)
                return m
            }
            return mark
        }
    }

    // MARK: - 作用域

    /// 语气标记的作用域终点（不含）：遇到下一个「语气」或「中断」标记为止，否则到文末。
    ///
    /// 拟声标记不终止语气作用域 —— 它只是在当前位置插一个声音事件。
    static func scopeEnd(of mark: EmotionMark, in marks: [EmotionMark], docLength: Int) -> Int {
        for other in marks where other.id != mark.id && other.location > mark.location {
            if other.token.category == .emotion || other.token.category == .interrupt {
                return other.location
            }
        }
        return docLength
    }
}
