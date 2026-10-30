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
        guard !marks.isEmpty else { return marks }

        return marks.compactMap { mark -> EmotionMark? in
            // 拟声：占 1 个真实字符（U+FFFC），字符没了标记就该跟着没（与 macOS 一致）
            if mark.token.category == .richLanguage {
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

            // 语气 / 中断：零宽的**作用域边界**，不占字符，所以规则要反过来 ——
            //
            // ① 落在插入点上的**不右移**（早年是 `>= upperBound` 就平移，于是每敲一个字
            //    标记就被推到光标后面一格，最后永远停在文末、作用域恒为空
            //    → 表现就是「选完标签一输入，标签就没了」）。新输入的文本应当归它管。
            // ② 落在替换区间内部的**夹回区间起点**，而不是删除：零宽标记没有「依附的字符」，
            //    静默删掉会让用户以为标签自己消失了（拼音输入整段替换命中时尤其容易触发）。
            if mark.location <= editedRange.location { return mark }
            if mark.location < editedRange.upperBound {
                var m = mark
                m.location = editedRange.location
                return m
            }
            var m = mark
            m.location = max(editedRange.location, mark.location + delta)
            return m
        }
    }

    // MARK: - 作用域

    /// 位置序（同一位置按插入先后）。作用域边界与接缝收敛都依赖这个顺序。
    ///
    /// ⚠️ 直接用 `sorted { $0.location < $1.location }` 不够：Swift 的 `sorted` 不保证稳定，
    /// 而「两个语气标签插在同一个位置」是合法操作（先插的作用域在前），顺序乱了会让
    /// 两个作用域都一路撑到文末 —— 表现就是两段胶囊完全重叠。
    static func orderedMarks(_ marks: [EmotionMark]) -> [EmotionMark] {
        marks.enumerated().sorted { a, b in
            a.element.location == b.element.location
                ? a.offset < b.offset
                : a.element.location < b.element.location
        }.map { $0.element }
    }

    /// 位置序里第 `index` 个标记的作用域终点（不含）：下一个「语气 / 中断」标记的位置，否则文末。
    ///
    /// 拟声标记不终止语气作用域 —— 它只是在当前位置插一个声音事件。
    static func scopeEnd(at index: Int, in ordered: [EmotionMark], docLength: Int) -> Int {
        guard index < ordered.count else { return docLength }
        var end = docLength
        var j = index + 1
        while j < ordered.count {
            let other = ordered[j]
            // ⚠️ 用「位置序里的下一个」而不是 `other.location > mark.location`：
            // 后者会把同位置的后一个标记漏掉，两段作用域就都撑到文末、完全重叠。
            if other.token.category == .emotion || other.token.category == .interrupt {
                end = other.location
                break
            }
            j += 1
        }
        return min(max(end, ordered[index].location), docLength)
    }

    /// 作用域 `[start, end)` 被拟声占位符切成的一段段连续区间。
    ///
    /// 语气胶囊必须按这个结果分段画 —— 拟声 pill 是实心块，胶囊要在那里**断开**，
    /// 不能垫在 pill 底下（否则虚线 pill 就压在同色背景上，看不清边界）。
    static func scopePieces(start: Int, end: Int, soundLocations: Set<Int>) -> [NSRange] {
        guard end > start else { return [] }
        var pieces: [NSRange] = []
        var cursor = start
        var loc = start
        while loc < end {
            if soundLocations.contains(loc) {
                if loc > cursor { pieces.append(NSRange(location: cursor, length: loc - cursor)) }
                cursor = loc + 1   // 占位符本身不进胶囊
            }
            loc += 1
        }
        if cursor < end { pieces.append(NSRange(location: cursor, length: end - cursor)) }
        return pieces
    }
}
