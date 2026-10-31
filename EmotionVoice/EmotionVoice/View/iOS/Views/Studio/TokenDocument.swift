//
//  TokenDocument.swift
//  iOSEmora
//
//  iOS 编辑器的文档模型。
//
//  macOS 那套把标签塞进 `NSTextStorage` 作为 `NSTextAttachment` 的实现无法直接搬到 iOS
//  （NSTextAttachmentCell 是 AppKit 专属），所以 iOS 改成「纯文本 + 位置标记」：
//
//   * **每个标记都在文档里占一个可见占位**（1 字符的 `NSTextAttachment`，U+FFFC）：
//     - 拟声：占位撑出 pill 的宽度，虚线 pill 画在那块矩形中间；
//     - 语气 / 中断：占位只撑出一段**空白宽度**（`TokenTextEditor.toneSpacing`）。
//
//  ⚠️ 语气 / 中断**必须**占位，早年做成「纯位置、零宽标记」留下了两个至今修不干净的问题：
//   * 胶囊 (`capsulePadX`) 只能靠**侵入邻居文本**换空间 —— 于是字体 / kern 稍一变化
//     就会「紧贴上一段的末尾」，这正是「语气标签里的文本离标签左右没有间距」的根因；
//   * 相邻两段作用域之间**没有物理空隙**，接缝收敛只能把另一侧的胶囊按到自己的文字边界上，
//     于是右半边的内边距恒为 0。macOS 侧的同一个标记是 5×1 的可见占位，天然就有这段距离，
//     从来没这些问题 —— 现在 iOS 与之对齐。
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

    /// 该标记在文档里占几个字符：统一 1 个占位符（拟声是 pill、语气 / 中断是一段空白宽度）。
    ///
    /// ⚠️ 语气 / 中断早年返回 0（零宽），代价是胶囊拿不到任何左右空间，见文件头的说明。
    var occupiedLength: Int { 1 }
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
            // 每个标记都占 1 个占位符，它本身不进正文
            if cursor < chars.count, String(chars[cursor]) == placeholder { cursor += 1 }
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
                // 三类标记都占 1 个占位符，位置就是插入它的那个字符下标
                marks.append(EmotionMark(location: (doc as NSString).length, token: token))
                doc += placeholder
            }
        }
        return (doc, marks)
    }

    // MARK: - 标记位置维护

    /// 文本被替换后修正标记位置。
    ///
    /// ⚠️ 三类标记**都占 1 个真实字符**（`mark.location` 就是那个占位符的下标），
    /// 所以规则与 macOS 保持一致 —— 占位符被换掉，标记跟着没。
    /// 零宽版本那条「落在替换区间内部要夹回区间起点」的特殊规则已经用不着了
    /// （它没有可依附的字符，才需要被拽回起点保命）。
    static func adjust(marks: [EmotionMark], editedRange: NSRange, replacementLength: Int) -> [EmotionMark] {
        let delta = replacementLength - editedRange.length
        guard delta != 0 || editedRange.length > 0 else { return marks }
        guard !marks.isEmpty else { return marks }

        return marks.compactMap { mark -> EmotionMark? in
            // ⚠️ 必须用 `>=` 而不是 `>`：退格删到占位符本身时 `editedRange` 的**起点**
            // 正好等于标记位置（`range.length == 1`）。写成 `>` 就会留下没有字符可依附的
            // 孤儿标记 —— 表现是 pill / 徽章还在，点它报标记找不到。
            if mark.location >= editedRange.location && mark.location < editedRange.upperBound {
                return nil
            }
            // 占位符落在编辑点之后 → 整体平移（标记与它占的那个字符不能错位）
            if mark.location >= editedRange.upperBound {
                var m = mark
                m.location = max(editedRange.location, mark.location + delta)
                return m
            }
            // 占位符在编辑点之前 → 原地不动。
            // ⚠️ 这一支同时覆盖「在占位符之后打字」：`editedRange.location` 是 `loc + 1`，
            // 标记不参与平移，新输入的文本自然落在它的作用域里 —— 也就是
            // 「选完标签一输入，标签就没了」的反面。
            return mark
        }
    }

    // MARK: - 作用域

    /// 是不是「作用域边界」标记（语气 / 中断）：它们把自己的占位符作为作用域的起点，
    /// 靠位置划分文本归属（拟声不是边界，它只是在当前位置插一个声音事件）。
    ///
    /// ⚠️ 必须标 `nonisolated`：工程开了 `MainActor` 默认隔离，这个方法既要被
    /// `@MainActor` 的 Coordinator 调，也要被同为 static 的 `boundaryEmptiness` 当**函数值**
    /// 传进 `contains(where:)` —— 后者的闭包参数是非隔离的，隔离方法传不进去。
    nonisolated static func isBoundary(_ mark: EmotionMark) -> Bool {
        mark.token.category == .emotion || mark.token.category == .interrupt
    }

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

    /// 作用域空 / 非空的边界标记分组（语气 / 中断）。
    ///
    /// ⚠️ 这里**只判定、不回收** —— 回收时机交给调用方（见 `TokenTextEditor.Coordinator`）。
    /// 判据历经三版，前两版都会被真实操作打穿：
    ///  * 「当前作用域为空就回收」→ 刚插入的标签作用域天然为空，等于标签一插就没；
    ///  * 「本次编辑删过字就回收」→ ① 第二个标签还没输入内容时，回头去删第一个标签里的
    ///    一个错字，第二个标签会被连带删掉；② 中文改候选词是「先删上屏的字、再插新候选」
    ///    两步，中间那一帧同样会误伤 —— 也就是
    ///    **「插入第二个语气标签 → 打字 → 标签消失、文本并进第一个标签」**；
    ///  * 现在这一版只输出「空 / 非空」两组 id，翻转判定与结算时机全部上移到 Coordinator：
    ///    只有 **非空 → 空** 翻转过的标记才会被回收。
    ///
    /// - Returns: `empty` = 作用域里已经没有文本（含只剩占位符 / 空白）；`nonEmpty` = 还有文本
    static func boundaryEmptiness(marks: [EmotionMark], doc: String)
        -> (empty: Set<UUID>, nonEmpty: Set<UUID>) {
        var empty = Set<UUID>()
        var nonEmpty = Set<UUID>()

        // 拟声占 1 个字符，字符没了标记由 `adjust()` 负责删；这里只处理零宽的作用域边界。
        let ordered = orderedMarks(marks)
        guard ordered.contains(where: isBoundary) else { return (empty, nonEmpty) }

        let chars = Array(doc)
        for (i, mark) in ordered.enumerated() where isBoundary(mark) {
            // ⚠️ 跳过自己占的那个占位符：它是 14pt 的空白宽度，不是文本。
            // 作用域的**正文**从 `location + 1` 开始，下一个边界的位置是下一个占位符的
            // 起点（它也占 1 个字符），所以 `[start, end)` 天然不含任何邻居的占位符。
            let owner = min(max(mark.location + 1, 0), chars.count)
            let start = min(owner, chars.count)
            let end = min(max(scopeEnd(at: i, in: ordered, docLength: chars.count), owner), chars.count)
            var hasText = false
            if end > start {
                // 只剩占位符 / 空白（含全角空格、换行）也算「文本删完了」
                let text = chars[start..<end]
                    .filter { String($0) != placeholder }
                    .map(String.init)
                    .joined()
                hasText = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            if hasText { nonEmpty.insert(mark.id) } else { empty.insert(mark.id) }
        }
        return (empty, nonEmpty)
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
