//
//  PlayerTranscriptView.swift
//  EmotionVoice
//
//  音频文本卡片：
//  · 有字级时间戳 → 句卡 + 时间码 gutter + 逐字三态高亮 + 自动跟随（对齐阅读区）
//  · 无字级时间戳 → 提示条 + 静态原文（降级态，禁止用字数÷语速伪造对齐）
//  对齐 UI/macOS/audio-player.html 的 .transcript / .cue / .w。
//
//  性能要点（沿用本项目「高频订阅必须收敛」的约定）：
//  1. 本视图**不订阅**播放器；只有内部 AlignedTranscript 订阅 currentTime。
//  2. 高频状态被收敛成离散的「当前句 / 当前字 / 句内进度」，句卡实现 Equatable
//     并挂 .equatable()：非当前句的参数逐帧完全相同，SwiftUI 直接跳过它们的 body，
//     每帧只重绘一个句卡，不会把整篇 500+ 字重新 diff 一遍。
//  3. 降级态的句数用 NLTokenizer 算一次缓存，绝不在重绘路径里分词。
//

import SwiftUI
import AppKit
import Combine

struct PlayerTranscriptView: View {

    let audio: AudioItem
    /// 刻意不做 @ObservedObject：父级不应该跟着 10Hz 的 currentTime 重绘
    let player: AudioPreviewPlayer
    /// 由 AudioPlayerDetailView 统一读一次再下发（nil = 降级态）
    let timeline: AudioTimeline?

    @State private var follow: Bool = true
    @State private var didCopy: Bool = false
    @State private var staticSentenceCount: Int = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if let timeline, timeline.isAligned {
                AlignedTranscript(timeline: timeline, player: player, follow: $follow)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                staticContent
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .background(AppColor.bgSecondary)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(AppColor.borderSubtle, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .task(id: audio.id) {
            follow = true
            // 句数只在切换音频时算一次：分词绝不能进重绘路径
            staticSentenceCount = PlayerTextMetrics.sentenceCount(of: audio.text)
        }
    }

    // MARK: - 标题行

    private var header: some View {
        HStack(spacing: 10) {
            Text("%d 字 · %d 句".localized(audio.text.count, sentenceCountForHeader))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(AppColor.textTimecode)

            Spacer()

            if timeline?.isAligned == true { followButton }
            copyButton
        }
    }

    private var followButton: some View {
        Button {
            follow.toggle()
        } label: {
            HStack(spacing: 6) {
                Circle()
                    .fill(follow ? AppColor.accentGlow : AppColor.textTertiary)
                    .frame(width: 6, height: 6)
                Text("跟随播放".localized())
                    .font(.system(size: 11))
            }
            .foregroundStyle(follow ? AppColor.accentGlow : AppColor.textSecondary)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(follow ? AppColor.accentDim : AppColor.bgTertiary)
            .overlay(
                Capsule().stroke(follow ? AppColor.accentLine : AppColor.borderSubtle, lineWidth: 1)
            )
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .help("文本区自动滚动，让正在播放的句子保持在视野中央；手动滚动会暂时关闭跟随。".localized())
    }

    private var copyButton: some View {
        Button {
            copyText()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: didCopy ? "checkmark" : "square.on.square")
                    .font(.system(size: 11))
                Text(didCopy ? "已复制" : "复制")
                    .font(.system(size: 11))
            }
            .foregroundStyle(didCopy ? AppColor.statusSuccess : AppColor.textSecondary)
            .padding(.horizontal, 9)
            .frame(height: 26)
            .background(AppColor.bgTertiary)
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(AppColor.borderSubtle, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
    }

    // MARK: - 降级态（无 words[]）

    private var staticContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 13))
                        .foregroundStyle(AppColor.accentPrimary)
                    Text("该音频没有字级时间戳，文本按原文静态展示，不使用估算时间伪造对齐。".localized())
                        .font(.system(size: 11.5))
                        .foregroundStyle(AppColor.textSecondary)
                }
                .padding(10)
                .background(AppColor.bgTertiary)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(AppColor.borderSubtle, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                Text(audio.text.isEmpty ? "暂无原文内容".localized() : audio.text)
                    .font(.system(size: 14.5))
                    .foregroundStyle(audio.text.isEmpty ? AppColor.textTertiary : AppColor.textSecondary)
                    .lineSpacing(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // 正文卡片不需要可见滚动条：内容溢出时直接滚轮 / 触控板滚动，滚动行为不变
        .scrollIndicators(.hidden)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 派生数据 / 行为

    private var sentenceCountForHeader: Int {
        if let timeline, timeline.isAligned { return timeline.sentences.count }
        return staticSentenceCount
    }

    private func copyText() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(audio.text, forType: .string)
        didCopy = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            didCopy = false
        }
    }
}

// MARK: - 对齐阅读区

/// 唯一订阅 currentTime 的阅读区。所有高频状态在 body 里一次性派生为离散值，
/// 再传给句卡；配合 Equatable + .equatable() 把重绘限制在当前句。
private struct AlignedTranscript: View {

    let timeline: AudioTimeline
    @ObservedObject var player: AudioPreviewPlayer
    @Binding var follow: Bool

    @State private var recenterTick: Int = 0

    var body: some View {
        let t = player.currentTime
        let location = timeline.location(at: t)
        let activeIndex = location.index
        let activeWord = activeIndex.flatMap { timeline.wordIndex(in: $0, at: t) }
        let wordProgress = wordProgress(at: t, sentence: activeIndex, word: activeWord)
        // 刚结束那一句的末字还在褪色时才有值；其余句一律拿 1（常量，不参与每帧重绘）
        let tail = tailFade(at: t, previous: location.previous)
        let tailIndex = tail?.index
        let tailProgress = tail?.progress ?? 1

        return ScrollViewReader { proxy in
            ZStack(alignment: .bottomTrailing) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(timeline.sentences, id: \.index) { cue in
                            SentenceCueRow(
                                cue: cue,
                                isActive: cue.index == activeIndex,
                                isDone: cue.endMs <= Int((t * 1000).rounded()),
                                activeWordIndex: cue.index == activeIndex ? (activeWord ?? -1) : -1,
                                wordProgress: wordProgress,
                                tailFade: cue.index == tailIndex ? tailProgress : 1,
                                player: player
                            )
                            .equatable()
                            .id(cue.index)
                        }
                    }
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                // 阅读区不显示滚动条：句卡窄、滚动位置由「跟随播放」接管，条反而遮挡时间码
                .scrollIndicators(.hidden)
                // 用户滚轮 / 触控板开始滚动 → 打断跟随；程序化 scrollTo 不会发这个通知
                .onReceive(NotificationCenter.default.publisher(
                    for: NSScrollView.willStartLiveScrollNotification
                )) { _ in
                    if follow { follow = false }
                }

                if !follow {
                    recenterButton {
                        follow = true
                        scrollCurrent(proxy, at: activeIndex, next: location.next)
                        recenterTick &+= 1
                    }
                    .padding(.trailing, 14)
                    .padding(.bottom, 14)
                }
            }
            .onChange(of: activeIndex ?? -1) { _, _ in
                if follow { scrollCurrent(proxy, at: activeIndex, next: location.next) }
            }
            .onChange(of: recenterTick) { _, _ in
                if follow { scrollCurrent(proxy, at: activeIndex, next: location.next) }
            }
        }
    }

    /// 当前字在**自身时间窗**内的进度（0→1）。
    /// 用于把颜色从「离散跳变」变成逐帧插值：10Hz 刷新下每次只变一点点。
    private func wordProgress(at t: Double, sentence: Int?, word: Int?) -> Double {
        guard let s = sentence, let w = word,
              timeline.sentences.indices.contains(s),
              timeline.sentences[s].words.indices.contains(w) else { return 0 }
        let cue = timeline.sentences[s].words[w]
        let span = max(1, cue.endMs - cue.beginMs)
        return min(max((t * 1000 - Double(cue.beginMs)) / Double(span), 0), 1)
    }

    /// 句间停顿里的「末字褪色进度」：刚结束那一句的最后一个字，
    /// 要从高亮色平滑褪到已读色，否则跨行换句时文字是硬跳。
    ///
    /// 为什么需要单独一路插值：句子一旦不再是「当前句」，`activeWordIndex` 立刻变 -1，
    /// 整句颜色落到「已读色」常量上——末字上一帧还是全亮的 accentGlow，下一帧就是
    /// 0xA8ABB4，中间没有过渡。而背景（accentWash）有 0.18s 淡出动画，观感上就成了
    /// 「底色还在慢慢退，文字先灭了」。
    ///
    /// 返回 nil 表示这一句不需要插值（还没结束、或已经褪完），调用方拿到常量 1，
    /// 这样非当前句 / 已静止的句子不会因为每帧变化而重绘。
    private func tailFade(at t: Double, previous: Int?) -> (index: Int, progress: Double)? {
        guard let i = previous, timeline.sentences.indices.contains(i) else { return nil }
        let elapsedMs = t * 1000 - Double(timeline.sentences[i].endMs)
        // 只覆盖句末之后的一小段：比句间停顿短时先褪成已读再静止，比停顿长时
        // 与下一句首字的渐亮重叠，视觉上像高亮色从上一行末尾「流」到下一行开头。
        // 曲线取 smoothstep：末字先「落定」一下再褪，避免采样正好跨过 endMs 时
        // 上一帧还没全亮、这一帧就被拉暗的突兀感
        guard elapsedMs >= 0, elapsedMs < Self.tailFadeWindowMs else { return nil }
        let k = elapsedMs / Self.tailFadeWindowMs
        return (i, k * k * (3 - 2 * k))
    }

    /// 末字褪色窗口（毫秒）。播放进度是 10Hz 刷新，窗口取 400ms ≈ 4 帧，
    /// 既能抹掉硬跳又不会让「已读字还亮着」拖太久
    private static let tailFadeWindowMs: Double = 400

    private func scrollCurrent(_ proxy: ScrollViewProxy, at index: Int?, next: Int?) {
        // t 落在句间停顿时不高亮任何句，但跟随滚动仍指向下一句，避免视图停在两句之间
        guard let target = index ?? next, timeline.sentences.indices.contains(target) else { return }
        withAnimation(.easeOut(duration: 0.22)) {
            proxy.scrollTo(target, anchor: .center)
        }
    }

    private func recenterButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 11))
                Text("回到当前句".localized())
                    .font(.system(size: 11))
            }
            .foregroundStyle(AppColor.accentGlow)
            .padding(.horizontal, 12)
            .frame(height: 28)
            .background(AppColor.bgElevated)
            .overlay(Capsule().stroke(AppColor.accentLine, lineWidth: 1))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
    }
}

// MARK: - 句卡

private struct SentenceCueRow: View, Equatable {

    let cue: AudioSentenceCue
    let isActive: Bool
    let isDone: Bool
    /// -1 表示该句没有当前字
    let activeWordIndex: Int
    /// 当前字在自身时间窗内的进度 0...1，仅在 activeWordIndex >= 0 时有意义
    let wordProgress: Double
    /// 句末最后一个字在句间停顿里的褪色进度 0...1：
    /// 1 = 已完全是已读色（不需要过渡）；< 1 = 这一句刚结束，末字仍在从高亮色过渡。
    /// 只对「刚结束的那一句」有非 1 值，其余句恒为 1 → 不会干扰 Equatable 的复用。
    let tailFade: Double
    /// 只用于点击定位；不参与相等判断（引用恒定），避免每帧误判为「已变化」
    let player: AudioPreviewPlayer

    static func == (lhs: SentenceCueRow, rhs: SentenceCueRow) -> Bool {
        lhs.cue == rhs.cue
            && lhs.isActive == rhs.isActive
            && lhs.isDone == rhs.isDone
            && lhs.activeWordIndex == rhs.activeWordIndex
            && lhs.wordProgress == rhs.wordProgress
            && lhs.tailFade == rhs.tailFade
    }

    var body: some View {
        // 语气 / 拟声标签从正文里摘出来单独成徽标（见 `TranscriptTagMarkup`）。
        // 只在 body 重算时扫一次，且没有 `[` 的词直接原样返回，所以逐字高亮那条
        // 10Hz 路径的开销与从前一致；`line.words` 与 `cue.words` 下标一一对应，
        // `wordColor(at:)` 一个都不用改。
        let line = TranscriptTagMarkup.line(for: cue)

        return HStack(alignment: .top, spacing: 10) {
            // 只显示句首时间码：句末与下一句句首之间还有停顿，两列并排容易被读成
            // 「这句话一直持续到第二个时间」。句内进度交给逐字高亮本身表达。
            Text(PlayerTextMetrics.formatPrecise(cue.begin))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(isActive ? AppColor.accentGlow : AppColor.textTimecode)
                .frame(width: 50, alignment: .trailing)
                .padding(.top, 3)

            VStack(alignment: .leading, spacing: line.tags.isEmpty ? 0 : 6) {
                if !line.tags.isEmpty {
                    tagRow(line.tags)
                }
                // 整句只有标签（拟声独占一句）时不画正文，避免多出半行空白
                if line.hasBody {
                    wordLine(line.words)
                        .font(.system(size: 14))
                        .lineSpacing(9)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(isActive ? AppColor.accentWash : Color.clear)
        // 句切换时让底色 / 左侧竖条淡入淡出，而不是硬切
        .animation(.easeInOut(duration: 0.18), value: isActive)
        .overlay(alignment: .leading) {
            if isActive {
                Rectangle()
                    .fill(AppColor.accentPrimary)
                    .frame(width: 2)
                    .padding(.vertical, 6)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            player.seek(to: cue.begin)
        }
    }

    /// 标签徽标行：一句里可能有多个（`[clears throat][curious]…`），按出现顺序排开
    private func tagRow(_ tags: [TranscriptTagMarkup.Tag]) -> some View {
        HStack(spacing: 5) {
            ForEach(Array(tags.enumerated()), id: \.offset) { _, tag in
                TranscriptTagBadge(tag: tag)
            }
        }
    }

    /// 三态：已读 / 当前字 / 未播
    ///
    /// ⚠️ 必须拼 `word.text`，**禁止**用 begin_index / end_index 去切 `cue.text`。
    /// 上游的 index 是「非标点字符的连续序号」，不是原文里的字符位置。实测：
    /// 原文「第一句话。\n\n第二句话，带标点。」16 字符 / 11 个 word / max end_index = 11，
    /// 按 index 切原文会有 7 个词错位。
    /// 标点已附着在相邻 word 的 text 上，所以拼接不会丢标点。v3 起 sidecar 里的 word.text
    /// 已是**用户原文**的片段（见 `TTSTimestampParser.alignToOriginal`），不再有「繁体原文
    /// 显示成简体」的问题；v4 起词间空白也原样保留（`Today, AI is …`），
    /// 只把 `\n\n` 折成一个空格（句卡按句分段展示本来也不需要保留换行）。
    /// ⚠️ 别再把 word.text 做 `filter { !$0.isWhitespace }` 之类的处理——英文会被粘成一串。
    ///
    /// ⚠️ 也不要给当前字加 `.bold()`：字重变化会改变单字宽度，导致整段文本重新
    /// 折行、左右轻微位移（用户反馈的「文字偶尔左右晃动」）。区分度全部交给颜色。
    ///
    /// `words` 是 `TranscriptTagMarkup` 摘掉官方标签后的正文（与 `cue.words` 同长度），
    /// 语气 / 拟声标签已经另行渲染成徽标，不出现在这里。
    private func wordLine(_ words: [String]) -> Text {
        // 句末褪色的落点是「最后一个**看得见**的词」：整句以标签收尾时，
        // 末词是空串（标签已变徽标），拿它当落点会让真正的末字直接硬切成已读色。
        let lastBody = words.lastIndex { !$0.isEmpty } ?? -1
        var result = Text("")
        for (i, text) in words.enumerated() {
            result = result + Text(text).foregroundColor(wordColor(at: i, lastBody: lastBody))
        }
        return result
    }

    /// 颜色随「字内进度」逐帧插值，而不是在三个色值之间硬跳：
    /// - 当前字：未播色 → 高亮色（按 wordProgress 渐亮）
    /// - 上一个字：高亮色 → 已读色（同一进度），接手瞬间正好与当前字衔接，无跳变
    /// - 更早的字：已读色
    /// - 未到的字：未播色
    /// - 句末最后一个字：句子结束后按 tailFade 继续从高亮色褪到已读色，
    ///   让颜色跨行换句时是连续的，而不是「上一帧还亮着，下一帧就灭了」
    ///
    /// `lastBody` 是最后一个有正文的词下标（标签词已摘成徽标，不参与褪色落点）。
    private func wordColor(at i: Int, lastBody: Int) -> Color {
        guard activeWordIndex >= 0 else {
            guard isDone else {
                return AppColor.blend(AppColor.WordTone.unplayed, AppColor.WordTone.unplayed, 0)
            }
            // 句末那一字的收尾过渡：起点颜色就是它作为「当前字」的终点色（高亮色），
            // 所以和上一帧完全衔接；与下一句首字的渐亮在时间上重叠
            if i == lastBody, tailFade < 1 {
                return AppColor.blend(AppColor.WordTone.active, AppColor.WordTone.read, tailFade)
            }
            return AppColor.blend(AppColor.WordTone.read, AppColor.WordTone.read, 0)
        }
        if i == activeWordIndex {
            return AppColor.blend(AppColor.WordTone.unplayed, AppColor.WordTone.active, wordProgress)
        }
        if i == activeWordIndex - 1 {
            return AppColor.blend(AppColor.WordTone.active, AppColor.WordTone.read, wordProgress)
        }
        return i < activeWordIndex
            ? AppColor.blend(AppColor.WordTone.read, AppColor.WordTone.read, 0)
            : AppColor.blend(AppColor.WordTone.unplayed, AppColor.WordTone.unplayed, 0)
    }
}

// MARK: - 标签徽标

/// 语气 / 拟声标签徽标：emoji + 本地化名字（与编辑器里的标签同源同色系）。
///
/// 语气用暖色（accent）、拟声用冷色（statusInfo）—— 只是「一眼分清两类」的弱区分，
/// 文字色仍压在正文之下，不跟逐字高亮抢注意力。
private struct TranscriptTagBadge: View {

    let tag: TranscriptTagMarkup.Tag

    private var tint: Color {
        tag.isSoundEffect ? AppColor.statusInfo : AppColor.accentPrimary
    }

    var body: some View {
        HStack(spacing: 4) {
            Text(tag.emoji)
                .font(.system(size: 10))
            Text(tag.label.localized())
                .font(.system(size: 10.5, weight: .medium))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 7)
        .frame(height: 18)
        .background(Capsule().fill(tint.opacity(0.12)))
        .overlay(Capsule().strokeBorder(tint.opacity(0.30), lineWidth: 1))
        .clipShape(Capsule())
        .fixedSize()
        .accessibilityLabel(tag.label.localized())
    }
}
