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
    /// ⚠️ v2 的切分会把句首标点**前移**进上一句最后一个 word 的 `text`，因此对 v2
    /// 产物再跑一次 v2 切分是**不可逆的错误**（拍平后每个 word 都没有前导标点了，
    /// 会退化成一整段）。将来若再改切分规则，必须针对每个旧版本写专门迁移，
    /// 不能直接拿新函数去重切一份已是新格式的 sidecar。
    static let currentVersion = 2

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

        for cue in cues {
            var group: [AudioWordCue] = []

            func flush() {
                guard !group.isEmpty else { return }
                result.append(AudioSentenceCue(
                    index: result.count,
                    text: group.map(\.text).joined(),
                    words: group
                ))
                group.removeAll(keepingCapacity: true)
            }

            for word in cue.words {
                let chars = Array(word.text)
                var p = 0
                while p < chars.count, chars[p].isPunctuation { p += 1 }

                // 边扫标点簇边定切点：句末标点后切一刀，紧跟其后的引号再修正方向
                var cut = -1
                for i in 0..<p {
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

                guard cut > 0, cut < chars.count, !group.isEmpty else {
                    group.append(word)
                    continue
                }

                // 到切点为止归上一句（只改展示文本，时间锚点不动）
                var tail = group[group.count - 1]
                tail.text += String(chars[0..<cut])
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

    nonisolated static func load(fileName: String) -> AudioTimeline? {
        guard !fileName.isEmpty else { return nil }
        let key = fileName as NSString
        if let box = cache.object(forKey: key) { return box.value }
        guard let data = try? Data(contentsOf: url(for: fileName)),
              let timeline = try? JSONDecoder().decode(AudioTimeline.self, from: data),
              // 高于当前版本（未来格式）一律不认，走静态原文，避免误读成错位的对齐
              timeline.version <= AudioTimeline.currentVersion,
              timeline.isAligned else { return nil }

        let resolved: AudioTimeline
        if timeline.version == AudioTimeline.currentVersion {
            resolved = timeline
        } else {
            resolved = upgrade(timeline, fileName: fileName)
        }
        cache.setObject(AudioTimelineBox(resolved), forKey: key)
        return resolved
    }

    /// 旧版 sidecar 的句子切分过粗（整段只有 1 个 sentence-end），用当前规则重切并回写。
    /// 这样已有音频不需要重新合成就能看到新的多句阅读区，也不额外消耗额度。
    private nonisolated static func upgrade(_ timeline: AudioTimeline, fileName: String) -> AudioTimeline {
        let words = timeline.sentences.flatMap(\.words)
        guard !words.isEmpty else { return timeline }

        // 拍平后按当前规则重切：时间已归一化过，这里只动句子边界
        let merged = AudioSentenceCue(index: 0, text: words.map(\.text).joined(), words: words)
        let sentences = TTSTimestampParser.splitBySentenceEnding([merged])
        guard !sentences.isEmpty else { return timeline }

        let upgraded = AudioTimeline(durationMs: timeline.durationMs, sentences: sentences)
        _ = save(upgraded, fileName: fileName)
        Log(message: "字级时间轴升级 v\(timeline.version) → v\(AudioTimeline.currentVersion): \(timeline.sentences.count) → \(sentences.count) 句")
        return upgraded
    }

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
    nonisolated static func duplicate(from source: String, to target: String) {
        if let timeline = load(fileName: source) {
            _ = save(timeline, fileName: target)
        }
    }
}

extension AudioItem {
    /// 该音频的字级时间轴；没有 sidecar（历史音频 / 时间戳不可用的降级生成）时为 nil。
    nonisolated var timeline: AudioTimeline? {
        AudioTimelineStore.load(fileName: fileName)
    }
}
