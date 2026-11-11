//
//  Project.swift
//  EmotionVoice
//
//  Created by young on 2026/8/8.
//

import Foundation

/// 音频条目磁盘存储目录（相对于 Documents/）
/// 与 DatabaseManager 的路径约定保持一致，避免散落多处拼接。
/// ⚠️ `nonisolated`：同上，拼路径的那一串要能在后台线程上跑。
nonisolated let kGeneratedAudioSubdirectory = "GeneratedAudio"

/// 计算音频条目所在的完整目录 URL。
/// 例：file:///…/Documents/GeneratedAudio
/// ⚠️ `nonisolated`：它只拼路径、不碰主线程状态，复制音频文件那段要脱离主线程跑。
nonisolated func generatedAudioDirectoryURL() -> URL {
    let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    return docs.appendingPathComponent(kGeneratedAudioSubdirectory, isDirectory: true)
}

/// 确保目录存在（不存在则创建）
func ensureGeneratedAudioDirectoryExists() {
    let dir = generatedAudioDirectoryURL()
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
}

/// 音频状态
enum AudioStatus: String, CaseIterable, Identifiable {
    case completed = "completed"
    case generating = "generating"
    case pending = "pending"
    case failed = "failed"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .completed: return "已完成".localized()
        case .generating: return "生成中".localized()
        case .pending: return "待处理".localized()
        case .failed: return "失败".localized()
        }
    }
}

/// 音频条目
/// 一个音频文件 = 一条记录，本身就是"项目"。
/// 没有更上层的项目分组概念。
struct AudioItem: Identifiable, Hashable {
    let id: Int64
    /// 真实文件名（含扩展名，例如 "2026-08-16_11-35-42.wav"），始终存在
    let fileName: String
    /// 用户可编辑的显示名；为空时使用 fileName
    var displayName: String?
    var text: String
    var voice: String
    var format: String
    var sampleRate: Int
    var duration: Double
    /// 音频文件大小（字节，整数存储，展示时再格式化）
    var fileSize: Int = 0
    var pointsCost: Double
    var status: AudioStatus
    var createdAt: Date

    /// UI 显示名：displayName 非空则用 displayName，否则用 fileName
    var shownName: String {
        if let d = displayName, !d.isEmpty { return d }
        return fileName
    }

    /// 扩展名（如 "wav" / "mp3"），无扩展名则为空
    var fileExtension: String {
        let url = URL(fileURLWithPath: fileName)
        return url.pathExtension
    }

    /// 磁盘上的绝对 URL：Documents/GeneratedAudio/<fileName>
    /// 不存在时返回 URL 但 isPlayable 由调用方另判。
    var absoluteURL: URL {
        generatedAudioDirectoryURL().appendingPathComponent(fileName)
    }

    /// 音频文件是否真实存在于磁盘上
    var isOnDisk: Bool {
        !fileName.isEmpty && FileManager.default.fileExists(atPath: absoluteURL.path)
    }

    /// 从完整路径中提取文件名（最后一段）。找不到则返回原串。
    /// （保留此工具方法以便旧调用方/外部数据兼容）
    static func deriveFileName(fromPath path: String?) -> String {
        guard let path, !path.isEmpty else { return "" }
        return (path as NSString).lastPathComponent
    }
}

// MARK: - 字级时间戳（sidecar，不入库）
//
// 数据契约（对齐 Qwen-Audio-TTS 服务端事件 / UI/macOS/audio-player.html）：
//   result-generated / sentence-end → payload.output.sentence.words[] =
//     { text, begin_index, end_index, begin_time, end_time }，单位毫秒。
//
// ⚠️ 不碰 audio_items 表：项目约定「SQLite 永不迁移、禁止 DROP 重建」，
//    时间戳一律写成 `<fileName>.timestamps.json` 与音频同目录的 sidecar。
//    没有 sidecar 的历史音频自动走「静态原文」降级态，绝不用字数÷语速伪造对齐。
//
// ⚠️ 段偏移：生成按 [break] / 控制标签切成多次独立合成请求，每段 words 的时间
//    是「段内相对时间」；落盘前由 VoiceStudioViewModel 按每段实际音频时长累加
//    offset，下面所有时间都是最终合成音频的绝对毫秒。

/// 一个字（英文可能是一个词）的时间锚点
struct AudioWordCue: Codable, Hashable, Sendable {
    var text: String
    var beginIndex: Int
    var endIndex: Int
    var beginMs: Int
    var endMs: Int

    var begin: Double { Double(beginMs) / 1000.0 }
    var end: Double { Double(endMs) / 1000.0 }
}

/// 一句 = 一组 words；起止取首/末 word 的时间
struct AudioSentenceCue: Codable, Hashable, Sendable {
    var index: Int
    var text: String
    var words: [AudioWordCue]

    var beginMs: Int { words.map(\.beginMs).min() ?? 0 }
    var endMs: Int { words.map(\.endMs).max() ?? 0 }
    var begin: Double { Double(beginMs) / 1000.0 }
    var end: Double { Double(endMs) / 1000.0 }
}

/// 一次生成的时间轴：所有句子的时间已归一化为最终音频绝对时间
struct AudioTimeline: Codable, Hashable, Sendable {
    /// sidecar 格式版本。低于此值的旧文件在 `AudioTimelineStore.load` 里自动升级。
    ///
    /// - v2：切分把句首标点**前移**进上一句最后一个 word 的 `text`。
    /// - v3：`words[].text` 是**用户原文**的片段（见 `TTSTimestampParser.alignToOriginal`），
    ///   不再是上游 `normalized_text` 的简体形态。
    /// - v4：对齐时**保留词间空白**。v3 是「把原文的空白全部剥掉再按字数回填」，
    ///   中文没有影响，英文就变成 `Today,AIIspoweredbydeeplearning,…`（单词全粘成一串）。
    /// - v5：**切句规则**补上「句末标点落在词尾」的西文分支（`brain.` / `driving."`）。
    ///   之前只认「前导标点簇」，中文把标点粘在下一个词开头所以能切，英文把 `.` 放在
    ///   词尾，`cut` 恒为 -1 → 整段只切出 1 张句卡、点哪儿都回开头。
    ///   同时序号通道放宽为「单调不减」并统一两条通道的兜底顺序。
    /// - v6：对齐新增**通道 ②（按词内占号字符数累计）**，排在「逐位」与「上游 index」之间。
    ///   上游 normalize 会删 `「」`、把 `\n\n` 换成 `。`（同为不占号字符，但会让非空白
    ///   字数 353 → 350），还会把英文按「词」编号 —— 这两件事让 ① 和 ③ 同时失败，
    ///   1251 字长文因此整条退回简体。而两边「占号单元数」始终相等（319 == 319）。
    ///
    /// ⚠️ v2 的切分让 word 文本「不再等于上游原始划分」，所以对 v2 产物重切会退化。
    /// v2 → v3 的迁移必须**先用原文按 begin_index 重新分配文本（`remap` 的 ② 通道），
    /// 再重切**；remap 失败时一律原样返回，绝不能直接重切。
    /// v3 → v4 同路（都要用原文重排），只是 v4 的 remap 会把空格留在词间。
    /// v4 → v5 只需要**重切**（文本已是原文），但仍然走 `realign`：它对 v4 文本
    /// 会先尝试 ② 通道、失败后落到 ① 通道，两种情况都只是把文本重新摆到同一批锚点上。
    ///
    /// ⚠️ **切句规则也必须进版本号**：`textMatches` 为真时只说明「文本对了」，
    /// 不代表「句子切分是当前规则」。只 bump 文本对齐、不 bump 切句，v4 的历史英文
    /// sidecar 会一直保留「整段 1 张卡」的旧切分，永远不会自愈。
    /// 同理，对齐算法（通道数量 / 优先级）一改也要 bump —— 否则旧 sidecar 会一直用
    /// 上一套算法产出的文本，靠 `textMatches` 也拦不住（它只能发现「文本不等」）。
    static let currentVersion = 6

    var version: Int
    /// 最终音频时长（毫秒），用于波形刻度归一化
    var durationMs: Int
    var sentences: [AudioSentenceCue]

    init(version: Int = AudioTimeline.currentVersion, durationMs: Int, sentences: [AudioSentenceCue]) {
        self.version = version
        self.durationMs = durationMs
        self.sentences = sentences
    }

    var duration: Double { Double(durationMs) / 1000.0 }
    var anchorCount: Int { sentences.reduce(0) { $0 + $1.words.count } }
    var isAligned: Bool { !sentences.isEmpty && anchorCount > 0 }
    var lastEndMs: Int { sentences.last?.endMs ?? 0 }

    /// 当前句的定位结果。`index == nil` 表示 t 落在句间停顿（或播放结束），不高亮任何句。
    struct Location: Hashable, Sendable {
        var index: Int?
        var previous: Int?
        var next: Int?
    }

    /// 二分查找：最后一个 begin <= t 的句；t 超过该句 end 时视为句间停顿。
    nonisolated func location(at t: Double) -> Location {
        guard !sentences.isEmpty else { return Location(index: nil, previous: nil, next: nil) }
        let ms = Int((t * 1000).rounded())
        var lo = 0, hi = sentences.count - 1, idx = -1
        while lo <= hi {
            let mid = (lo + hi) / 2
            if sentences[mid].beginMs <= ms { idx = mid; lo = mid + 1 }
            else { hi = mid - 1 }
        }
        if idx >= 0 && ms > sentences[idx].endMs {
            let next: Int? = idx + 1 < sentences.count ? idx + 1 : nil
            return Location(index: nil, previous: idx, next: next)
        }
        if idx < 0 {
            return Location(index: nil, previous: nil, next: 0)
        }
        return Location(index: idx, previous: idx > 0 ? idx - 1 : nil, next: idx + 1 < sentences.count ? idx + 1 : nil)
    }

    /// 二分查找句内当前字；t 落在第一个字之前返回 nil。
    nonisolated func wordIndex(in sentenceIndex: Int, at t: Double) -> Int? {
        guard sentences.indices.contains(sentenceIndex) else { return nil }
        let words = sentences[sentenceIndex].words
        let ms = Int((t * 1000).rounded())
        var lo = 0, hi = words.count - 1, idx = -1
        while lo <= hi {
            let mid = (lo + hi) / 2
            if words[mid].beginMs <= ms { idx = mid; lo = mid + 1 }
            else { hi = mid - 1 }
        }
        return idx >= 0 ? idx : nil
    }
}

// MARK: - 上游事件解析

enum TTSTimestampParser {

    /// 从一条 WebSocket 文本帧里解析 `result-generated / sentence-end` 的 words[]。
    /// 非该事件（task-started / sentence-begin / sentence-synthesis / 音频前导帧）一律返回 nil。
    nonisolated static func sentenceEnd(from jsonText: String) -> AudioSentenceCue? {
        guard let data = jsonText.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              (json["header"] as? [String: Any])?["event"] as? String == "result-generated",
              let output = (json["payload"] as? [String: Any])?["output"] as? [String: Any],
              output["type"] as? String == "sentence-end",
              let sentence = output["sentence"] as? [String: Any],
              let rawWords = sentence["words"] as? [[String: Any]],
              !rawWords.isEmpty else { return nil }

        var words: [AudioWordCue] = []
        words.reserveCapacity(rawWords.count)
        for raw in rawWords {
            let text = raw["text"] as? String ?? ""
            guard !text.isEmpty else { continue }
            let beginMs = (raw["begin_time"] as? NSNumber)?.intValue ?? 0
            let endMs = (raw["end_time"] as? NSNumber)?.intValue ?? beginMs
            words.append(AudioWordCue(
                text: text,
                beginIndex: (raw["begin_index"] as? NSNumber)?.intValue ?? 0,
                endIndex: (raw["end_index"] as? NSNumber)?.intValue ?? 0,
                beginMs: beginMs,
                endMs: max(beginMs, endMs)
            ))
        }
        guard !words.isEmpty else { return nil }

        // sentence-end 通常带 original_text；缺失时用 words 拼回，保证句卡永远有可读文本。
        let original = output["original_text"] as? String
        let text = (original?.isEmpty == false) ? original! : words.map(\.text).joined()
        return AudioSentenceCue(index: 0, text: text, words: words)
    }

    /// 把按到达顺序收集的 sentence-end 归一化成单调递增的「段内绝对时间」。
    ///
    /// 上游有两种可能的时钟：① 整段音频绝对时间（正常）；② 每个 continue-task /
    /// 每个句子都从 0 重启。检测到本句起点早于上一句终点时，把 offset 抬到
    /// 「上一句终点」，两种协议都能得到连续时间轴，不需要猜测服务端实现。
    /// index 也重新编号（同一任务里多个 continue-task 的 sentence.index 会重启）。
    nonisolated static func normalize(_ raw: [AudioSentenceCue]) -> [AudioSentenceCue] {
        var result: [AudioSentenceCue] = []
        var offsetMs = 0
        var lastEndMs = 0

        for sentence in raw where !sentence.words.isEmpty {
            let firstBegin = sentence.words.map(\.beginMs).min() ?? 0
            if firstBegin + offsetMs < lastEndMs {
                offsetMs = lastEndMs - firstBegin
            }
            let words = sentence.words.map { w -> AudioWordCue in
                var x = w
                x.beginMs += offsetMs
                x.endMs += offsetMs
                return x
            }
            result.append(AudioSentenceCue(index: result.count, text: sentence.text, words: words))
            lastEndMs = max(lastEndMs, words.map(\.endMs).max() ?? lastEndMs)
        }
        return result
    }

    /// 把任意空白（含 `\n\n`、制表符）压成一个半角空格，并去掉首尾空白。
    ///
    /// 字幕按句卡展示、本身不带换行，所以 `\n\n` 必须折成空格而不是保留；
    /// 但**不能整体删除**——英文的单词边界全靠空格，删了就会粘成一串。
    nonisolated static func normalizeWhitespace(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.count)
        var pendingSpace = false
        for ch in text {
            if ch.isWhitespace {
                pendingSpace = !out.isEmpty
            } else {
                if pendingSpace { out.append(" "); pendingSpace = false }
                out.append(ch)
            }
        }
        return out
    }

    /// 把每个 word 的 `text` 换成**用户原文**里对应的字符片段。
    ///
    /// 上游 `words[].text` 取自 `normalized_text`：繁体被转成简体（实测
    /// `午後`→`午后`、`陽光`→`阳光`），直接拼 `word.text` 当字幕就会把原文
    /// 显示成另一套字形。这里只用原文重新分配 words 的文本，
    /// **时间锚点一个不动、不插值、不猜**。
    ///
    /// 对齐源优先级：
    /// 1. `source`：**我们真正发出去的那段文本**（用户输入，字形由用户决定）。
    ///    上游的 `original_text` 是服务端视角的「原文」，不保证和发送内容逐字一致。
    /// 2. `cues[].text`：上游 `original_text`（拿不到发送文本时的次选）。
    /// 都不成（没回 original_text、数字/英文被展开导致字数对不上）就原样返回，
    /// 宁可用上游文本，也不做错误的逐字对应。
    nonisolated static func alignToOriginal(_ cues: [AudioSentenceCue],
                                           source: String? = nil) -> [AudioSentenceCue] {
        guard !cues.isEmpty else { return cues }
        let flat = cues.flatMap(\.words)

        // 首选发送文本；其次上游 original_text —— 只有单条 cue 时它才是整段原文，
        // 多句时每个 cue 的 text 只是本句，拿去对齐全量 words 必然失败，不必浪费一次计算。
        var candidates: [String] = []
        if let source, !source.isEmpty { candidates.append(source) }
        if cues.count == 1, let whole = cues.first?.text, !whole.isEmpty { candidates.append(whole) }

        for candidate in candidates {
            if let aligned = remap(flat, to: candidate), let grouped = regroup(aligned, like: cues) {
                return grouped
            }
        }

        // 兜底：每句各带本句原文时逐条对齐（对不上的那条保持上游文本）
        var result: [AudioSentenceCue] = []
        result.reserveCapacity(cues.count)
        for cue in cues {
            var copy = cue
            if let aligned = remap(cue.words, to: cue.text) { copy.words = aligned }
            result.append(copy)
        }
        return result
    }

    /// 把整段对齐后的 words 按原来的 cue 结构切回去。
    private nonisolated static func regroup(_ aligned: [AudioWordCue],
                                            like cues: [AudioSentenceCue]) -> [AudioSentenceCue]? {
        var cursor = 0
        var result: [AudioSentenceCue] = []
        result.reserveCapacity(cues.count)
        for cue in cues {
            let end = cursor + cue.words.count
            guard end <= aligned.count else { return nil }
            var copy = cue
            copy.words = Array(aligned[cursor..<end])
            cursor = end
            result.append(copy)
        }
        return cursor == aligned.count ? result : nil
    }

    /// 该字符是否占一个「字级时间戳序号」——即会被真正读出来的字符。
    ///
    /// 上游的 `begin_index / end_index` 只数发音单元：标点（`，` `。`）、符号
    /// （`~` `$` `%` `=`）、emoji 都不占号。见 `remap` 序号通道里对官方示例的核对。
    ///
    /// ⚠️ 这里按 grapheme cluster（Swift 的 `Character`）判，与上游按 UTF-16 / 码点
    /// 计数在含组合字符或 emoji ZWJ 序列时会不一致。不一致的后果是「末尾总量校验不过
    /// → 返回 nil → 保持上游文本」，不会产出错位的对齐，所以不需要额外做编码转换。
    private nonisolated static func isSpokenUnit(_ ch: Character) -> Bool {
        ch.isLetter || ch.isNumber
    }

    /// 用 `source`（原文）给 `words` 重新分配文本；返回 nil 表示无法可靠对齐，调用方必须保持原样。
    ///
    /// 三条通道，按「精确度 → 鲁棒性」排序，前一条成功就不再往下走：
    /// ① 逐字符：去空白后字数**完全相等**（繁简一一对应时成立）。最精确，连标点都按
    ///    原文位置分配。上游只要删/加过一个标点就会失效（实测 353 vs 350）。
    /// ② 按占号单元累计：只数 `word.text` 里有多少个占号字符，累加后把原文一段段切给
    ///    words。**不看上游 index，也不要求字数相等**，只要求「两边占号总数相同」。
    ///    标点增删、`\n\n`→`。`、`「」` 被删都无影响，是当前的主力通道。
    /// ③ 上游 `begin_index / end_index`：占号单元的全文连续序号（跨句累加）。
    ///    英文被上游按「词」编号时总量会对不上，所以排在 ② 之后兜底。
    ///
    /// `allowSurfaceMatch: false` 用于 v2/v4 sidecar 迁移：那里的 word 文本已被切分改动过
    /// （句末标点被前移），逐位映射会从第一个锚点起整体错位，所以跳过 ① 直接走 ②③。
    ///
    /// ⚠️ **空白必须保留**：中文靠标点断句，英文靠空格断词。早期实现把原文的空白全部
    /// 剥掉（`filter { !$0.isWhitespace }`）再按字数回填，中文无损，但英文会粘成
    /// `Today,AIIspoweredbydeeplearning,…`，整段没有一处空格。
    /// 现在只把「连续空白压成一个空格」做归一（`\n\n` → 空格，句卡里不会出现空行），
    /// 计数仍按非空白字符，切片则从归一后的原文取，词间空格自然留在两个词之间。
    nonisolated static func remap(_ words: [AudioWordCue],
                                 to source: String,
                                 allowSurfaceMatch: Bool = true) -> [AudioWordCue]? {
        let normalized = normalizeWhitespace(source)
        let chars = Array(normalized)
        // visible[k] = 第 k 个非空白字符在 chars 里的下标：把「去空白计数」换算成真实切片位置
        var visible: [Int] = []
        visible.reserveCapacity(chars.count)
        for (i, ch) in chars.enumerated() where !ch.isWhitespace { visible.append(i) }
        guard !visible.isEmpty, !words.isEmpty else { return nil }

        func visibleCount(_ text: String) -> Int {
            text.reduce(0) { $1.isWhitespace ? $0 : $0 + 1 }
        }

        var pieces: [String]?

        if allowSurfaceMatch {
            let surfaceCount = words.reduce(0) { $0 + visibleCount($1.text) }
            if surfaceCount == visible.count {
                var cursor = 0
                var lo = 0
                var out: [String] = []
                out.reserveCapacity(words.count)
                var valid = true
                for word in words {
                    let n = visibleCount(word.text)
                    guard n > 0 else { valid = false; break }
                    let hi = visible[cursor + n - 1] + 1
                    out.append(String(chars[lo..<hi]))
                    cursor += n
                    lo = hi
                }
                if valid, cursor == visible.count { pieces = out }
            }
        }

        if pieces == nil {
            // 下面两条通道都建立在「占号单元」这个概念上：只有**会被读出来的字符**
            // （字母、数字、表意文字）占号；标点（`，` `。` `「」`）、符号
            // （`~` `$` `%` `=`）、emoji 都不发音、不占号。
            // 早期用 `!isPunctuation` 判，会把 `isSymbol` 的 `%` `$` 误算成占号，
            // 原文里出现货币/百分比符号时整条对齐会判失败（静默退回上游文本）。
            var unitVisible: [Int] = []
            for (k, i) in visible.enumerated() where isSpokenUnit(chars[i]) { unitVisible.append(k) }
            guard !unitVisible.isEmpty else { return nil }

            // 通道 ②：**完全不看上游 index**，只按「每个词里有几个占号字符」累加。
            //
            // 这是 2026-11-10 那条 1251 字繁中长文（含英文括注）的对齐主路径。上游
            // normalize 时做了两件会让另外两条通道同时失效的事：
            //   a) 删掉 `「」`（4 个）、把段间 `\n\n` 换成 `。`（+1）→ 非空白字符数
            //      353 → 350，逐位通道「字数相等」的前提直接不成立；
            //   b) 英文 `Default Mode Network` 的 index 按「词」给，我们按「字母」数
            //      占号单元 → 上游 index 总量与我们算的 319 个单元对不上。
            // 而这两件事**都不占号**：只要「words 里占号字符总数 == 原文占号字符总数」
            // （实测 319 == 319），就能把原文按占号单元一段段切给 words，
            // 字形（含 `謐`→`密` 这类同音归一化）与标点位置全部取自原文。
            pieces = sliceByUnitEnds(words, unitEnds: countedUnitEnds(words),
                                     chars: chars, visible: visible, unitVisible: unitVisible)

            // 通道 ③：上游 `begin_index / end_index`。语义是「占号单元的**全文**连续序号」
            // —— 跨句累加、标点不占号。官方文档文字写「该字在整句中的开始位置」是错的，
            // 它自己的示例（`阿里巴巴。达摩院。` 里 `达` 是 index 4 而非句内 0）就否证了，
            // 用户已确认。所以官方建议的「sentence_offset + begin_index」在这里等价于
            // 直接用它；真去累加句长反而要假设「上游回传的句子长度 = 原文该句长度」。
            if pieces == nil, let ends = upstreamUnitEnds(words) {
                pieces = sliceByUnitEnds(words, unitEnds: ends,
                                         chars: chars, visible: visible, unitVisible: unitVisible)
            }
        }

        guard let pieces else { return nil }
        // 校验只看「非空白字符」：允许补回/丢掉空白，绝不允许改字或丢字
        let expected = String(chars.filter { !$0.isWhitespace })
        guard pieces.joined().filter({ !$0.isWhitespace }) == expected else { return nil }

        var result: [AudioWordCue] = []
        result.reserveCapacity(words.count)
        for (word, text) in zip(words, pieces) {
            var copy = word
            copy.text = text
            result.append(copy)
        }
        return result
    }

    /// 通道 ② 的单元终点：把每个词里**占号字符**的个数累计起来。
    ///
    /// 完全不依赖上游 `begin_index`。繁简/同音归一化是一一对应的（`謐`→`密`、`癒`→`愈`
    /// 都是 1 换 1），标点增删也不占号，所以这个累计值天然与原文对得上。
    private nonisolated static func countedUnitEnds(_ words: [AudioWordCue]) -> [Int] {
        var cumulative = 0
        return words.map { word in
            cumulative += word.text.reduce(0) { isSpokenUnit($1) ? $0 + 1 : $0 }
            return cumulative
        }
    }

    /// 通道 ③ 的单元终点：用上游 `begin_index / end_index`（`[break]` 分段时每段归零，
    /// 段间累加前一段的末 index）。返回 nil 表示序号语义明显不对（end < begin）。
    ///
    /// ⚠️ 纯标点词（`begin == end`）的 index 也是 0，**不能**当成段边界，否则一句会被切断。
    private nonisolated static func upstreamUnitEnds(_ words: [AudioWordCue]) -> [Int]? {
        var result: [Int] = []
        result.reserveCapacity(words.count)
        var base = 0
        var previousEnd = 0
        for (i, word) in words.enumerated() {
            guard word.endIndex >= word.beginIndex else { return nil }
            if i > 0, word.beginIndex == 0, word.endIndex > 0 {
                base += previousEnd
            }
            result.append(base + word.endIndex)
            previousEnd = word.endIndex
        }
        return result
    }

    /// 把「每个词消费到第几个占号单元」翻译成原文上的连续切片。
    ///
    /// - 消费了单元的词：切到第 `end` 个占号字符为止（其后的标点留给下一个词，
    ///   与上游「标点前置」的形态一致）。
    /// - 没消费单元的词（独立 `。`）：吃掉「到下一个占号单元之前」的字符，
    ///   否则它会切出空串、标点整段丢失，末尾总量校验必然失败。
    /// - 段内必须单调不减，**不要求首尾严格相接**：上游丢了空 text 占位词或跳号会
    ///   留下空洞，空洞里的字符并入下一个词的词首（切片是连续的 `lo..<hi`），
    ///   比整条放弃对齐要好。
    /// - 末尾残留的标点（`…` / 句末 `。`）不属于任何占号单元，补到最后一个词上。
    ///
    /// 最后的 `previousEnd == unitVisible.count` 是**总量校验**：对不上就返回 nil，
    /// 由调用方保持上游文本 —— 宁可显示另一套字形，也不做错位的逐字对应。
    private nonisolated static func sliceByUnitEnds(_ words: [AudioWordCue],
                                                    unitEnds: [Int],
                                                    chars: [Character],
                                                    visible: [Int],
                                                    unitVisible: [Int]) -> [String]? {
        guard !words.isEmpty, unitEnds.count == words.count, !unitVisible.isEmpty else { return nil }
        var lo = 0
        var previousEnd = 0
        var out: [String] = []
        out.reserveCapacity(words.count)
        for end in unitEnds {
            guard end >= previousEnd, end <= unitVisible.count else { return nil }
            let hi: Int
            if end == previousEnd {
                hi = end < unitVisible.count ? visible[unitVisible[end]] : chars.count
            } else {
                hi = visible[unitVisible[end - 1]] + 1
            }
            guard hi >= lo, hi <= chars.count else { return nil }
            out.append(String(chars[lo..<hi]))
            lo = hi
            previousEnd = end
        }
        guard previousEnd == unitVisible.count else { return nil }
        if lo < chars.count, !out.isEmpty { out[out.count - 1] += String(chars[lo...]) }
        return out
    }

    /// 把「一个 sentence-end 覆盖整段文本」的粗粒度结果，按句末标点细分成多张句卡。
    ///
    /// 上游的句子切分非常粗：实测 43 字、明显含两句话的文本只返回 **1 个
    /// sentence-end（index = 0）**，`original_text` 是整段。于是阅读区只有一张
    /// 句卡，点哪儿都只能回到整段开头（用户反馈的「点文本框从头开始播放」）。
    ///
    /// 断句点靠 word 的**前导**标点簇判断，不靠行尾。
    ///
    /// ⚠️ 上游把标点粘在「后一个字」前面，不是前一个字的末尾。实测 words：
    ///     `想` / `啥` / `呢` / `。"星` / `河` / `推` / …
    /// 即「？」这类标点出现在下一个 word 的**开头**，所以 `word.text.last` 永远是汉字，
    /// 按行尾判断会导致整段只切出 1 张卡（曾经踩过，273 字只显示「1 句」）。
    ///
    /// 切分方式：在「前导标点簇里含句末标点」的 word 之前断句，切点落在标点簇内部。
    /// 只改 `text`，`beginMs/endMs` 一个都不动，所以时间轴零估算、零插值。
    ///
    /// 切点是标点簇内的一位，由「句末标点」和「引号配对状态」共同决定：
    ///     `。"星`  → 引号是台词收尾的**闭引号**，前句得 `。"`，后句从 `星` 开始
    ///     `。"哥`  → 引号是下一句台词的**开引号**，前句只到 `。`，后句从 `"哥` 开始
    /// 两者字面完全相同，只能靠前面出现过的开引号来判断方向，所以要跨 word 维护
    /// `inQuote`。整簇一律归上一句会让下一句丢掉开引号（实测第 6 句变成 `哥！它咬我！`），
    /// 一律归下一句又会让上一句丢掉闭引号（第 1 句变成 `"想啥呢。`）。
    nonisolated static func splitBySentenceEnding(_ cues: [AudioSentenceCue]) -> [AudioSentenceCue] {
        // 句末标点：中文 + 西文（`……`、`——` 这类连续符号会整体落进同一个前导标点簇）
        let terminal: Set<Character> = ["。", "！", "？", "!", "?", "；", ";", "．", ".", "…"]
        // 只认双引号 / 直角引号；不含单引号，避免英文撇号（don't）把状态翻错
        let quoteMarks: Set<Character> = ["\"", "\u{201C}", "\u{201D}", "「", "」", "『", "』"]
        var result: [AudioSentenceCue] = []
        var inQuote = false

        // 词尾是否以句末标点收尾（允许尾巴上有空白和引号：`brain.` / `driving."` / `brain. `）
        func endsWithTerminal(_ chars: [Character]) -> Bool {
            var k = chars.count - 1
            while k >= 0, chars[k].isWhitespace || quoteMarks.contains(chars[k]) { k -= 1 }
            return k >= 0 && terminal.contains(chars[k])
        }

        for cue in cues {
            var group: [AudioWordCue] = []

            func flush() {
                guard !group.isEmpty else { return }
                // 对齐保留了空格，句首那个词可能带前导空格（前一词的词间空格）。
                // 卡片是左对齐的，留着会凭空多出一截缩进，这里只削掉首词的空白。
                if var first = group.first, first.text.first?.isWhitespace == true {
                    first.text = String(first.text.drop(while: { $0.isWhitespace }))
                    group[0] = first
                }
                result.append(AudioSentenceCue(
                    index: result.count,
                    text: group.map(\.text).joined(),
                    words: group
                ))
                group.removeAll(keepingCapacity: true)
            }

            for word in cue.words {
                let chars = Array(word.text)
                // 英文的词可能带前导空格（对齐时保留了词间空白），先跳过再扫标点簇，
                // 否则 `。" Next` 这种前导空格会把句末标点挡在簇外、整段切不开。
                var punctStart = 0
                while punctStart < chars.count, chars[punctStart].isWhitespace { punctStart += 1 }
                var p = punctStart
                while p < chars.count, chars[p].isPunctuation { p += 1 }

                // 边扫标点簇边定切点：句末标点后切一刀，紧跟其后的引号再修正方向
                var cut = -1
                for i in punctStart..<p {
                    let c = chars[i]
                    if quoteMarks.contains(c) {
                        inQuote.toggle()
                        // 紧跟在句末标点后的引号：闭引号归前句，开引号留给后句
                        if i > 0, terminal.contains(chars[i - 1]) {
                            cut = inQuote ? i : i + 1
                        }
                    } else if terminal.contains(c) {
                        cut = i + 1
                    }
                }

                // 补扫正文里的引号（上游一般把标点都放前缀，这里只是防状态漂移）
                if p < chars.count {
                    for i in p..<chars.count where quoteMarks.contains(chars[i]) {
                        inQuote.toggle()
                    }
                }

                // 句末标点落在**词尾**（西文 `brain.` / `driving."`、或纯标点词 `。`）：
                // 这个词说完就断句。上游中文把标点粘在下一个词的**开头**（`，阳`），走上
                // 面的切点分支；西文放在词尾，词内没有「标点簇 + 正文」的结构，cut 恒为 -1，
                // 必须在这里单独判一次，否则英文整段只会切出 1 张卡。
                if !group.isEmpty, cut < 0 || cut == chars.count, endsWithTerminal(chars) {
                    group.append(word)
                    flush()
                    continue
                }

                guard cut > 0, cut < chars.count, !group.isEmpty else {
                    group.append(word)
                    continue
                }

                // 到切点为止归上一句（只改展示文本，时间锚点不动）。
                // 从标点簇起点开始取、丢掉前导空白：`， Next` 里那个空格是词间分隔，
                // 拼到上一句末尾会让句卡右边缘凭空多出一截空白。
                var tail = group[group.count - 1]
                tail.text += String(chars[punctStart..<cut])
                group[group.count - 1] = tail
                flush()

                // 剩下的（开引号 + 字）沿用原 word 的 begin/end，整句时间总和不变
                var head = word
                head.text = String(chars[cut...])
                group.append(head)
            }
            flush()
        }
        return result
    }
}

// MARK: - Sidecar 读写

/// NSCache 只能装 class；AudioTimeline 是值类型，包一层。
private final class AudioTimelineBox: NSObject, @unchecked Sendable {
    let value: AudioTimeline
    init(_ value: AudioTimeline) { self.value = value }
}

enum AudioTimelineStore {

    static let fileSuffix = ".timestamps.json"

    /// NSCache 自身线程安全；播放器多处（波形刻度 / 阅读区 / 状态栏）读同一份时间轴，
    /// 有了缓存就不会在 10Hz 重绘里反复读磁盘。
    nonisolated(unsafe) private static let cache = NSCache<NSString, AudioTimelineBox>()

    nonisolated static func url(for fileName: String) -> URL {
        generatedAudioDirectoryURL().appendingPathComponent(fileName + fileSuffix)
    }

    /// `sourceText` 是该条音频的用户原文（`audio_items.text`）：
    /// v2 → v3 迁移靠它把 words 换回原文，v3 也靠它自愈「文本不是用户原文」的历史数据。
    /// 拿不到原文时旧 sidecar 原样返回，绝不冒险重切。
    nonisolated static func load(fileName: String, sourceText: String? = nil) -> AudioTimeline? {
        guard !fileName.isEmpty else { return nil }
        let key = fileName as NSString
        // 缓存里存的是「结论」：对不上原文（无法修复）也会缓存，避免 10Hz 重绘反复读盘
        if let box = cache.object(forKey: key) { return box.value }
        guard let data = try? Data(contentsOf: url(for: fileName)),
              let timeline = try? JSONDecoder().decode(AudioTimeline.self, from: data),
              // 高于当前版本（未来格式）一律不认，走静态原文，避免误读成错位的对齐
              timeline.version <= AudioTimeline.currentVersion,
              timeline.isAligned else { return nil }

        let source = (sourceText?.isEmpty == false) ? sourceText : nil

        let resolved: AudioTimeline
        if timeline.version >= AudioTimeline.currentVersion {
            // 已是当前版本：只在「文本不是用户原文」时自愈重排。
            // 早期 v3 是拿上游 original_text 写的，那段文本不一定等于用户原文，
            // 所以即便版本号相同也要用原文比对一次。
            if let source, !textMatches(timeline, source) {
                resolved = realign(timeline, fileName: fileName, source: source)
            } else {
                resolved = timeline
            }
        } else if let source {
            // 旧版本 + 有原文：文本重排 + 按当前规则重切，一次到位。
            // ⚠️ 不看 `textMatches`：文本对了不代表切分是当前规则（v4 → v5 就是纯切句升级）。
            resolved = realign(timeline, fileName: fileName, source: source)
        } else {
            // 旧版本、拿不到原文：只重切、不改文本。
            // v5 起「句末标点落在词尾」有独立分支（`endsWithTerminal`），所以即便
            // v2/v4 的切分把标点前移过，重切也不会退化成一整段 —— 早期只有
            // 「前导标点簇」一条路，才会把整段切成 1 句，因此当年只能原样返回。
            resolved = regrade(timeline, fileName: fileName)
        }
        cache.setObject(AudioTimelineBox(resolved), forKey: key)
        return resolved
    }

    /// sidecar 里的文本是否已经就是用户原文（忽略空白：`\n\n` 在句卡里本来就不保留）。
    private nonisolated static func textMatches(_ timeline: AudioTimeline, _ sourceText: String) -> Bool {
        let current = timeline.sentences.flatMap(\.words).map(\.text).joined()
        return current.filter { !$0.isWhitespace } == sourceText.filter { !$0.isWhitespace }
    }

    /// 用用户原文重新分配所有 word 的文本，再按当前规则重切句卡并回写。
    ///
    /// 两条通道的顺序：v1 的文本是上游原样，逐位通道最精确，先走 ①；
    /// v2 起的文本被切分改动过（句末标点前移），先走 ② 序号通道。
    /// 任何一条成功都会接着 `rebuild` 重切 —— 所以这个方法同时承担
    /// 「文本修复」和「切句规则升级」两件事，**旧版本 sidecar 一律走它**。
    /// 两条都失败就原样返回（宁可保留旧文本，也不做错位的逐字对应）。
    private nonisolated static func realign(_ timeline: AudioTimeline,
                                            fileName: String,
                                            source: String) -> AudioTimeline {
        let words = timeline.sentences.flatMap(\.words)
        guard !words.isEmpty else { return timeline }

        // v1 的文本仍是上游原样，允许逐位通道优先；v2 起先走序号通道
        let contaminated = timeline.version >= 2
        var realigned = TTSTimestampParser.remap(words, to: source, allowSurfaceMatch: !contaminated)
        // 序号通道对不上时**无条件**退回逐位通道。
        //
        // 早期这条兜底只在「v3 英文被洗掉词间空格」时才放行，结果 v4 的英文 sidecar
        // （文本已是原文、空格也在）在序号通道失败后直接放弃 → 连带 v4 → v5 的重切
        // 也做不成，历史数据里「英文整段只有 1 张句卡」永远修不好。
        //
        // 兜底是安全的：两条通道收尾都要求「拼回去的文本去空白后与原文逐字相等」，
        // 最坏情况只是某个词的边界偏一个字符（影响逐字高亮的分段，不影响上屏内容）。
        if realigned == nil {
            realigned = TTSTimestampParser.remap(words, to: source, allowSurfaceMatch: true)
        }
        guard let realigned,
              let rebuilt = rebuild(realigned, durationMs: timeline.durationMs) else {
            Log(message: "字级时间轴对齐失败：原文与 words 对不上（v\(timeline.version)），保持原文本与旧切分")
            return timeline
        }
        _ = save(rebuilt, fileName: fileName)
        Log(message: "字级时间轴升级 v\(timeline.version) → v\(AudioTimeline.currentVersion): \(timeline.sentences.count) → \(rebuilt.sentences.count) 句 / \(rebuilt.anchorCount) 锚点")
        return rebuilt
    }

    /// 旧版 sidecar 的句子切分过粗（整段只有 1 个 sentence-end），用当前规则重切并回写。
    ///
    /// 只改切分、不换文本，所以**不需要原文**：`begin_index` 那套信息在切分里用不到。
    /// 之前只在 v1 敢调用它，是因为 v2/v4 的切分把句末标点前移过，而当时只有「前导
    /// 标点簇」一条断句通道，重切会退化成一整段。v5 补了「句末标点在词尾」的分支
    /// （`endsWithTerminal`），这样任意版本的 words 都能被正确切分。
    private nonisolated static func regrade(_ timeline: AudioTimeline, fileName: String) -> AudioTimeline {
        let words = timeline.sentences.flatMap(\.words)
        guard let rebuilt = rebuild(words, durationMs: timeline.durationMs) else { return timeline }
        _ = save(rebuilt, fileName: fileName)
        Log(message: "字级时间轴升级 v\(timeline.version) → v\(AudioTimeline.currentVersion): \(timeline.sentences.count) → \(rebuilt.sentences.count) 句")
        return rebuilt
    }

    /// 拍平 → 按句末标点重切 → 新的 v3 时间轴（时间全部沿用原 word，不插值）。
    private nonisolated static func rebuild(_ words: [AudioWordCue], durationMs: Int) -> AudioTimeline? {
        guard !words.isEmpty else { return nil }
        let merged = AudioSentenceCue(index: 0, text: words.map(\.text).joined(), words: words)
        let sentences = TTSTimestampParser.splitBySentenceEnding([merged])
        guard !sentences.isEmpty else { return nil }
        return AudioTimeline(durationMs: durationMs, sentences: sentences)
    }

    /// 旧版 sidecar 的句子切分过粗（整段只有 1 个 sentence-end），用当前规则重切并回写。
    /// 这样已有音频不需要重新合成就能看到新的多句阅读区，也不额外消耗额度。
    ///
    @discardableResult
    nonisolated static func save(_ timeline: AudioTimeline, fileName: String) -> Bool {
        guard timeline.isAligned, !fileName.isEmpty else { return false }
        do {
            let data = try JSONEncoder().encode(timeline)
            try data.write(to: url(for: fileName), options: .atomic)
            cache.setObject(AudioTimelineBox(timeline), forKey: fileName as NSString)
            return true
        } catch {
            Log(message: "AudioTimelineStore.save 失败: \(error.localizedDescription)")
            return false
        }
    }

    nonisolated static func delete(fileName: String) {
        guard !fileName.isEmpty else { return }
        cache.removeObject(forKey: fileName as NSString)
        try? FileManager.default.removeItem(at: url(for: fileName))
    }

    /// 复制音频时把时间轴一起复制到新文件名，否则「副本」会莫名降级成静态文本。
    nonisolated static func duplicate(from source: String, to target: String, sourceText: String? = nil) {
        if let timeline = load(fileName: source, sourceText: sourceText) {
            _ = save(timeline, fileName: target)
        }
    }
}

extension AudioItem {
    /// 该音频的字级时间轴；没有 sidecar（历史音频 / 时间戳不可用的降级生成）时为 nil。
    nonisolated var timeline: AudioTimeline? {
        guard let timeline = AudioTimelineStore.load(fileName: fileName, sourceText: text) else {
            return nil
        }
        // 时间轴不该比音频本身还长：末字超出音频时长说明**生成时的段偏移算错了**
        // （多段拼接按旧版 32 kbps 粗估段长，见 `AudioConcatenator.durationSeconds`），
        // 播到后半段时高亮永远追不上声音。这种 sidecar 宁可退回静态原文 ——
        // 项目约定是「宁可没有逐字高亮，也不显示错位的对齐」。
        // 留 20% 余量给「上游把末尾停顿也算进时间戳」这类正常偏差。
        if duration > 1, timeline.lastEndMs > Int(duration * 1200) {
            Log(message: "⚠️ 时间轴末字 \(timeline.lastEndMs)ms 超出音频时长 \(Int(duration * 1000))ms（\(fileName)），判定不可用，退回静态原文")
            return nil
        }
        return timeline
    }
}

// MARK: - 字幕里的语气 / 拟声标签

/// 阅读区把 `[serious]` / `[clears throat]` 这类 TTS 控制标签从正文里摘出来。
///
/// 背景：`audio_items.text` 落库时已经是纯台词（`toPlainText()`），但 sidecar 里的
/// `words[].text` 直接来自上游 —— 语气标签会作为一个「词」混在句首
/// （实测 `[serious]手机又震。`），拟声标签甚至独占一整句（`[clears throat]`）。
/// 它们只是发给合成引擎的指令，不是台词，摆在正文里既抢眼又打断阅读，
/// 所以这里按句摘出来、交给 UI 渲染成一枚小徽标。
///
/// ⚠️ 只认 `Constants` 里的官方标签（24 语气 + 7 拟声）：
/// 用户自己写的 `[注]` / `[1]` 不是 TTS 指令，必须原样保留 ——
/// 不能用「任意方括号」一刀切，否则会把正常文本吃掉。
///
/// ⚠️ 只摘文本、**不动时间锚点**：`words` 与 `cue.words` 严格一一对应（整词就是标签时
/// 给空串），逐字高亮的 `activeWordIndex` 才能照旧按下标取色。
enum TranscriptTagMarkup {

    struct Tag: Hashable {
        /// 官方 tag（如 `serious` / `clears throat`）
        let tag: String
        /// 编辑器里同一套中文 label，同时是本地化 key（`严肃` → Serious）
        let label: String
        let emoji: String
        /// 拟声（富语言）标签：只在那一处插一段声音，不改变语气
        let isSoundEffect: Bool
    }

    /// 一句的展示形态：标签按出现顺序收集，正文保留原来的词边界。
    struct Line {
        let tags: [Tag]
        /// 与 `cue.words` 一一对应；整个词就是标签时为空串
        let words: [String]

        /// 整句只有标签（拟声独占一句）：正文区不画，避免多空出一行
        var hasBody: Bool {
            words.contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        }
    }

    /// 扫描一句话，摘出标签、保留词边界。
    ///
    /// ⚠️ 必须**跨词**扫，不能逐词扫。上游的 `words[]` 是按「要读出来的词」切的，
    /// `[clears throat]` / `[deep and loud shouting]` 这类**含空格的标签**经常被劈成
    /// 两个词（实测 `[clears` + `throat]但真正决定…`）。逐词看的时候两边都不成对：
    /// 前一个词有 `[` 没有 `]`，后一个词有 `]` 没有 `[`，于是标签原样漏进正文 ——
    /// 这正是用户反馈的「拟声标签没有处理」。
    /// 所以这里把整句拼成一条字符流再扫，同时记住每个字符属于第几个词；摘掉标签后
    /// 按原归属把字符还回各自的词 —— `words` 仍与 `cue.words` **一一对应**
    /// （整词都是标签时给空串），逐字高亮的下标一个都不用改。
    ///
    /// 绝大多数句子一个 `[` 都没有，走最前面的 `contains` 快路径直接原样返回，
    /// 10Hz 的逐字高亮路径没有额外开销。
    static func line(for cue: AudioSentenceCue) -> Line {
        let texts = cue.words.map(\.text)
        guard texts.contains(where: { $0.contains("[") || $0.contains("［") }) else {
            return Line(tags: [], words: texts)
        }

        var chars: [Character] = []
        var owner: [Int] = []
        chars.reserveCapacity(texts.reduce(0) { $0 + $1.count })
        for (i, text) in texts.enumerated() {
            for ch in text {
                chars.append(ch)
                owner.append(i)
            }
        }

        var dropped = [Bool](repeating: false, count: chars.count)
        var touched = [Bool](repeating: false, count: texts.count)
        var tags: [Tag] = []
        var i = 0
        while i < chars.count {
            guard isOpening(chars[i]) else { i += 1; continue }
            guard let close = closingIndex(chars, after: i) else { i += 1; continue }
            if let tag = officialTag(String(chars[(i + 1)..<close])) {
                tags.append(tag)
                for k in i...close {
                    dropped[k] = true
                    touched[owner[k]] = true
                }
                i = close + 1
            } else {
                // 不是官方标签（`[注]` / `[1]`）：连 `[` 一起当普通字符，继续往后扫
                i += 1
            }
        }
        guard !tags.isEmpty else { return Line(tags: [], words: texts) }

        var words = [String](repeating: "", count: texts.count)
        for (k, ch) in chars.enumerated() where !dropped[k] {
            words[owner[k]].append(ch)
        }
        // 标签跨词时，被摘掉的那半截可能只剩空白：清成空串，别在正文里留个缺口。
        // 只清「确实被摘过」的词，普通英文词间的空白词不受影响。
        for (k, text) in words.enumerated() where touched[k] && text.allSatisfy({ $0.isWhitespace }) {
            words[k] = ""
        }
        // 正文第一个词开头的空白也去掉（那个空格本来属于被摘掉的标签）
        if let firstBody = words.firstIndex(where: { !$0.isEmpty }) {
            var body = words[firstBody]
            while let f = body.first, f.isWhitespace { body.removeFirst() }
            words[firstBody] = body
        }
        return Line(tags: tags, words: words)
    }

    /// 单段文本的便捷入口（预览 / 调试用）：等价于把整段文本当成「一个词」。
    static func scan(_ text: String) -> (body: String, tags: [Tag]) {
        let cue = AudioSentenceCue(
            index: 0,
            text: text,
            words: [AudioWordCue(text: text, beginIndex: 0, endIndex: 0, beginMs: 0, endMs: 0)]
        )
        let line = line(for: cue)
        return (line.words.first ?? "", line.tags)
    }

    private static func isOpening(_ ch: Character) -> Bool {
        ch == "[" || ch == "［"
    }

    /// 从 `open` 之后找第一个右括号。跨词拼接后 `[` 与 `]` 可以分属两个词，
    /// 所以必须在整条字符流上找；但标签不会跨行，遇到换行就放弃。
    private static func closingIndex(_ chars: [Character], after open: Int) -> Int? {
        var i = open + 1
        while i < chars.count {
            if chars[i] == "]" || chars[i] == "］" { return i }
            if chars[i] == "\n" || chars[i] == "\r" { return nil }
            i += 1
        }
        return nil
    }

    /// 官方标签匹配：忽略大小写、忽略**所有空白**。
    ///
    /// 忽略空白有两个现实原因：① 标签被劈成两个词后拼回来的内容可能没有空格
    /// （`deepandloudshouting`）；② 上游/输入法会给 NBSP 之类的「隐形空格」。
    /// 两边都去空白后比较，`[shouting ]` `[Serious]` `[clears throat]` 都能认出来。
    private static func officialTag(_ raw: String) -> Tag? {
        let key = compact(raw)
        guard !key.isEmpty else { return nil }
        if let item = Constants.emotions.first(where: { compact($0.tag) == key }) {
            return Tag(tag: item.tag, label: item.label, emoji: item.emoji, isSoundEffect: false)
        }
        if let item = Constants.richLanguageTags.first(where: { compact($0.tag) == key }) {
            return Tag(tag: item.tag, label: item.label, emoji: item.emoji, isSoundEffect: true)
        }
        return nil
    }

    private static func compact(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.count)
        for ch in text where !ch.isWhitespace {
            out.append(ch)
        }
        return out.lowercased()
    }
}
