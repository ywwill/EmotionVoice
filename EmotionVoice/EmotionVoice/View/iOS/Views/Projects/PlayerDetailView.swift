//
//  PlayerDetailView.swift
//  iOSEmora
//
//  播放详情

import SwiftUI

struct PlayerDetailView: View {
    @Environment(\.aurora) private var c
    @Environment(\.screenMetrics) private var metrics
    @Environment(\.dismiss) private var dismiss

    @EnvironmentObject private var uiState: IOSUIState

    let item: AudioItem

    // ⚠️ 整页不订阅播放器：10Hz progress 会把长文本 / metaCard / 倍速 Menu / 工具栏
    //    一起拖着重算（macOS `AudioPlayerDetailView` 开头注释写的就是这个坑）。
    //    宿主用非观察的 let 调方法，播放态走低频代理；高频显示各自下沉到小 View。
    private let player = AudioPreviewPlayer.shared
    @StateObject private var status = PlaybackStatus.shared
    @ObservedObject private var flags = AudioFlagStore.shared
    @State private var isSharing = false
    @State private var voiceName: String = ""
    @State private var currentName: String = ""
    /// 详情页底部操作条：重命名 / 复制音频 / 删除
    @State private var showRename = false
    @State private var renameText = ""
    @State private var showDeleteConfirm = false
    /// 按下频谱那一刻是否正在播放（松手后据此恢复，避免拖动中反复 seek 掉帧）
    @State private var resumeAfterScrub = false
    /// 拖动中的落点（0~1）。`nil` = 没在拖，时间行跟播放器走。
    ///
    /// ⚠️ 拖动期间**不 seek**（每帧 seek 会让解码器反复丢缓冲，实测掉到 20fps 以下），
    /// 所以 `player.currentTime` 在这段时间里是不动的 —— 左边那个「已播放」必须由
    /// `scrubFraction` 顶上，否则拖到哪儿数字都不变，用户会以为拖动没生效。
    @State private var scrubFraction: Double? = nil
    /// 断句数只算一次。原来写在 `textCard` 的计算属性里，播放器 0.1s 一次进度刷新
    /// 会把整段文案反复 `components(separatedBy:)` + trim，长文案下是白烧主线程。
    @State private var sentenceCount: Int = 0
    /// 字级时间轴（sidecar）。`init` 里预热一次（排版分支依赖它），`onAppear` 只做缓存命中式的刷新；
    /// body 里绝不读盘。
    @State private var timeline: AudioTimeline?

    private var url: URL { item.absoluteURL }

    init(item: AudioItem) {
        self.item = item
        // ⚠️ 时间轴必须在 init 里就绪，不能等 `onAppear`：`page` 按「有没有时间轴」
        //    分成两条排版（有 → 不滚整页；没有 → 整页滚动）。晚一帧才知道就会先按降级
        //    排版铺一遍、随后整棵树换掉，文本区在 push 动画里会闪一下再重排。
        //    `AudioTimelineStore.load` 带 NSCache，重复构造只是缓存命中。
        _timeline = State(initialValue: item.timeline)
    }

    private var isAligned: Bool { timeline?.isAligned == true }

    /// 文本卡与底部操作条之间的间距（剩下的一截由 `actionBar` 自己的 10pt 内边距补上）
    private static let cardBottomGap: CGFloat = 8

    // MARK: 页面骨架
    //
    // ⚠️ 两个分支的差别不是排版偏好，而是「**谁负责滚动**」——这是这一版的核心修正：
    //
    //   上一版整页套了一个 ScrollView，而文本卡的阅读区是**固定高度**。ScrollView 的
    //   内容高度永远由子视图的自然高度决定、不会撑满视口，于是「卡片底边 → 操作条」
    //   之间恒留一截空白：固定阅读区 + 20pt Spacer + 操作条 10pt 内边距 ≈ 40pt。
    //   只删 Spacer 没用 —— 空白只是从「Spacer 撑的」变成「ScrollView 没填满剩下的」，
    //   屏幕上一样空着。
    //
    //   对齐态：阅读区自己就能滚（`AlignedTranscriptReader` 内部是 ScrollView），
    //          所以整页不需要滚动。去掉外层 ScrollView 后卡片拿到的是**确定高度**，
    //          阅读区 `frame(maxHeight: .infinity)` 才能真正吃掉剩余空间，卡片底边
    //          也就自动贴到操作条上方 —— 不留任何多余空白，且不依赖任何屏高常量。
    //   降级态：静态原文长度不可控，必须保留整页滚动。
    @ViewBuilder
    private var page: some View {
        if isAligned {
            VStack(spacing: 0) {
                fixedBlocks

                TranscriptCard(
                    item: item,
                    timeline: timeline,
                    sentenceCount: sentenceCount,
                    readerHeight: nil
                )
                .frame(maxHeight: .infinity)
                .padding(.horizontal, metrics.pageMargin)
                .padding(.bottom, Self.cardBottomGap)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        } else {
            ScrollView {
                VStack(spacing: 0) {
                    fixedBlocks

                    TranscriptCard(
                        item: item,
                        timeline: timeline,
                        sentenceCount: sentenceCount,
                        readerHeight: nil
                    )
                    .padding(.horizontal, metrics.pageMargin)

                    Spacer(minLength: Self.cardBottomGap)
                }
            }
        }
    }

    /// 波形卡 / 走带 / 倍速行 / 属性行：高度都是固定的，不参与任何弹性分配
    @ViewBuilder
    private var fixedBlocks: some View {
        waveformCard
            .padding(.horizontal, metrics.pageMargin)
            .padding(.top, 10)

        transportRow

        controlRow

        // 属性行不再是卡片：纯只读信息，一行带过（原来是 2×2 卡，白占 ~90pt）
        metaRow
            .padding(.top, 2)
            .padding(.bottom, 8)
    }

    /// ⚠️ 时长以播放器拿到的为准：流式文件的 `item.duration` 可能是入库时的估值，
    /// 取 `max` 才能保证右侧「总时长」在播放开始后不再跳变。
    private var totalDuration: Double { max(status.duration, item.duration) }

    /// ⚠️ 必须用 identifier（`item.fileName`）判定，不能用 `player.isPlaying(url:)`：
    /// 详情页是用 `play(url:identifier: item.fileName)` 起的播，`playingKey` 存的是文件名，
    /// 拿 `url.path` 去比永远不等 —— 正是「点了暂停图标不变、只会从头重播」的根因。
    private var isThisPlaying: Bool { status.playingKey == item.fileName && status.isPlaying }
    private var isThisPaused: Bool { status.playingKey == item.fileName && status.isPaused }

    var body: some View {
        page
            .background(c.backgroundGrouped)
            // ⚠️ 三个操作按钮原来排在 ScrollView 内容末尾，长文案会把它们推到屏幕外
            //    （要一路滚到底才看得见）。改成固定底栏，文案再长也够得着。
            .safeAreaInset(edge: .bottom) { actionBar }
            .navigationTitle(currentName.isEmpty ? item.shownName : currentName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    HStack(spacing: 8) {
                        // 收藏主入口：实心玫红 = 已收藏（与列表左滑共用同一个 store）
                        Button {
                            let on = flags.toggleFavorite(item.id)
                            uiState.showToast(.success(on
                                ? "已加入收藏".localized()
                                : "已取消收藏".localized(), duration: 1))
                        } label: {
                            let on = flags.isFavorite(item.id)
                            Image(systemName: on ? "heart.fill" : "heart")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(on ? AuroraDecor.rose : c.accent)
                                .frame(width: 32, height: 32)
                                .background(
                                    Circle().fill(on ? AuroraDecor.rose.opacity(0.13) : c.surface3)
                                )
                                .contentShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(flags.isFavorite(item.id) ? "取消收藏".localized() : "收藏".localized())

                        Button { isSharing = true } label: {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(c.accent)
                                .frame(width: 32, height: 32)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .sheet(isPresented: $isSharing) {
                ShareSheet(items: [url])
            }
            .overlay {
                if showRename {
                    RenameDialog(text: $renameText,
                                 onCancel: { showRename = false },
                                 onSave: { commitRename() })
                }
            }
            .alert("移入最近删除？".localized(), isPresented: $showDeleteConfirm) {
                Button("取消".localized(), role: .cancel) {}
                Button("移入最近删除".localized(), role: .destructive) { softDeleteCurrent() }
            } message: {
                Text("「%@」将保留 30 天，期间可随时恢复。".localized(item.shownName))
            }
            .onAppear {
                // 有 sidecar 就用它的句数（与句卡一一对应）；没有才退回按标点估算
                let loaded = item.timeline
                timeline = loaded
                if let loaded, loaded.isAligned {
                    // 只有标签的句子（`[clears throat]`）在阅读区不占位，句数跟着正文走
                    sentenceCount = loaded.transcriptSentenceCount
                } else {
                    sentenceCount = Self.countSentences(item.text)
                }
                voiceName = VoiceService.shared.fetchByKeys([item.voice]).first?.localizedName ?? item.voice
                currentName = item.shownName
                NowPlayingStore.shared.attach(item, voiceName: voiceName)
                guard item.isOnDisk else { return }
                // ⚠️ 列表用 identifier = fileName 起播，`isPlaying(url:)` 比的是 url.path，
                //    恒为 false —— 用它判定会把列表里正在播的这条从头重播。
                //    播放跨页保留（不再 onDisappear stop），mini player 才能常驻。
                if status.playingKey == item.fileName {
                    // 已经在播这条：只接管，不重播
                } else if !isThisPlaying {
                    NowPlayingStore.shared.start(item, voiceName: voiceName)
                }
            }
    }

    // MARK: 波形卡

    private var waveformCard: some View {
        VStack(spacing: 0) {
            WaveformScrubber(tint: c.ctaStart,
                             tintEnd: c.ctaEnd,
                             trackTint: AuroraDecor.violet.opacity(0.22),
                             onScrubStart: {
                                 // 播放中按下 → 先暂停，拖动期间只跟手不出声
                                 resumeAfterScrub = isThisPlaying
                                 if isThisPlaying { player.pause() }
                             },
                             onScrubChanged: { fraction in
                                 scrubFraction = fraction
                             },
                             onScrubEnd: { fraction in
                                 player.seek(to: fraction * max(player.duration, item.duration))
                                 if resumeAfterScrub { player.resume() }
                                 resumeAfterScrub = false
                                 // 松手 → 交还给播放进度（下一帧 player.currentTime 已经是新位置）
                                 scrubFraction = nil
                             })
            .frame(height: 52)
            // 拖动气泡浮在波形上方的留白里，由外层 top padding 兜住，不占布局高度
            .overlay(alignment: .topLeading) { scrubBubble }

            HStack(spacing: 8) {
                playbackStateIcon

                ElapsedTimeLabel(scrubFraction: scrubFraction, duration: totalDuration)

                Spacer(minLength: 4)

                SentenceProgressLabel(timeline: timeline,
                                      scrubFraction: scrubFraction,
                                      duration: totalDuration)

                Spacer(minLength: 4)

                Text(formatDuration(totalDuration))
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(c.textTertiary)
            }
            .padding(.top, 8)
        }
        .padding(.horizontal, 16)
        // 顶部这段留白专门给拖动气泡（气泡高 20 + 2pt 间隙）。
        // 原来是「12pt padding + 一条 24pt 恒占位空轨道」= 36pt，删掉轨道后省 14pt。
        .padding(.top, Self.scrubBubbleHeight + 2)
        .padding(.bottom, 10)
        .background(
            RoundedRectangle(cornerRadius: AuroraRadius.lg, style: .continuous)
                .fill(c.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: AuroraRadius.lg, style: .continuous)
                        .strokeBorder(c.line, lineWidth: 0.5)
                )
        )
    }

    /// 气泡高度（顶部留白按它 + 2pt 计算，改这里留白会跟着变）
    private static let scrubBubbleHeight: CGFloat = 20

    /// 拖动时跟随手指的落点时间气泡。
    ///
    /// ⚠️ **不占布局**（overlay 到波形上，靠卡片 top padding 兜住），
    ///    这是这一版最重要的改动：上一版把状态徽章删了、却在波浪上方留着一条
    ///    24pt 的恒占位空轨道（那是气泡原来的"专用车道"），于是卡片高度几乎没变，
    ///    看起来就像"状态删了但空间没省下来"。
    /// ⚠️ 也不能改成「按下才占位」：那会让卡片在手指落下的那一帧突然长高、波形往下跳。
    /// ⚠️ 横向按落点百分比算并夹在宽度内（`0 … width - 气泡宽`），
    ///    否则拖到两端时气泡会探出卡片外。
    private var scrubBubble: some View {
        GeometryReader { geo in
            if let f = scrubFraction {
                let laneWidth = max(geo.size.width, 1)
                let bw: CGFloat = 60
                let x = min(max(f * laneWidth - bw / 2, 0), max(laneWidth - bw, 0))
                Text(formatDuration(f * totalDuration))
                    .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(c.accent)
                    .frame(width: bw, height: Self.scrubBubbleHeight)
                    .background(
                        Capsule(style: .continuous)
                            .fill(c.accentSoft)
                            .overlay(
                                Capsule(style: .continuous)
                                    .strokeBorder(c.accent.opacity(0.32), lineWidth: 0.5)
                            )
                    )
                    // 上浮「气泡高 + 2pt 间隙」：底边距波形上缘 2pt，整块落在 top padding 内
                    .offset(x: x, y: -(Self.scrubBubbleHeight + 2))
            }
        }
        .allowsHitTesting(false)
    }

    // MARK: 走带（与 macOS PlayerTransportView 同构：±15 / ±5；15 秒档也是锁屏远程命令的步长）

    private var transportRow: some View {
        HStack(spacing: 22) {
            transportButton("gobackward.15", size: 28, title: "后退 15 秒".localized()) {
                player.skip(by: -15)
            }
            transportButton("gobackward.5", size: 21, title: "后退 5 秒".localized()) {
                player.skip(by: -5)
            }

            Button {
                player.togglePlayback(url: url, identifier: item.fileName)
            } label: {
                ZStack {
                    Circle().fill(c.ctaGradient)
                    Image(systemName: isThisPlaying ? "pause.fill" : "play.fill")
                        // 主键从 64 收到 56，字号同步 26 → 23（保持图标占直径 ≈ 0.41）
                        .font(.system(size: 23, weight: .semibold))
                        // ⚠️ 图标随状态切换要带动画：不带的话按钮像是「点了没反应」，
                        // 而真正的问题（见 `isThisPlaying` 注释）已经修在判定上了。
                        .animation(.easeOut(duration: 0.14), value: isThisPlaying)
                        .foregroundStyle(c.ctaForeground)
                }
                // 56 仍高于 44pt 最小热区，触摸不会变难
                .frame(width: 56, height: 56)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isThisPlaying ? "暂停".localized() : "播放".localized())

            transportButton("goforward.5", size: 21, title: "前进 5 秒".localized()) {
                player.skip(by: 5)
            }
            transportButton("goforward.15", size: 28, title: "前进 15 秒".localized()) {
                player.skip(by: 15)
            }
        }
        .padding(.top, 12)
        .padding(.bottom, 2)
        .frame(maxWidth: .infinity)
    }

    /// 15 秒档图标比 5 秒档大（28 / 21），维持原来的 2:1.5 层级（64:32:24 → 56:28:21）；
    /// 热区仍统一 44pt，只缩可见图标不缩可点范围。
    /// SF Symbol 名字不会被 VoiceOver 正确朗读，所以要显式给标签。
    private func transportButton(_ systemName: String, size: CGFloat, title: String,
                                 action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(c.textSecondary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
    }

    // MARK: 倍速 / 剩余 / 从头播放

    private var controlRow: some View {
        HStack(spacing: 10) {
            Menu {
                ForEach(AudioPreviewPlayer.playbackRateOptions, id: \.rate) { option in
                    Button {
                        player.setPlaybackRate(option.rate)
                    } label: {
                        HStack {
                            Text(option.label)
                            if abs(status.playbackRate - option.rate) < 0.001 {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "speedometer")
                        .font(.system(size: 13, weight: .semibold))
                    Text(rateLabel)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                }
                .foregroundStyle(c.accent)
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background(
                    Capsule(style: .continuous)
                        .fill(c.accentSoft)
                )
            }

            Spacer(minLength: 0)

            RemainingTimeLabel(fallbackDuration: item.duration)

            Spacer(minLength: 0)

            Button { player.seek(to: 0) } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 12, weight: .semibold))
                    Text("从头播放".localized())
                        .font(.system(size: 12.5))
                }
                .foregroundStyle(c.textSecondary)
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background(
                    Capsule(style: .continuous)
                        .fill(c.surface3)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, metrics.pageMargin)
        .padding(.top, 8)
        .padding(.bottom, 8)
    }

    private var rateLabel: String {
        let r = status.playbackRate
        if r == r.rounded() { return String(format: "%.0fx", r) }
        return String(format: "%.2fx", r)
    }

    // MARK: 属性行（只读信息，单行带过）

    /// 四个字段都是「看一眼就够」的次要信息，不该像原文那样占一整张卡：
    /// 原来是 2×2 卡片（iPhone 上约 90pt），现在压成一行 ~22pt，省下的全给对齐阅读区。
    /// 与 macOS `PlayerMetaStrip` 同构；触摸设备没有 hover tooltip，
    /// 所以积分带单位「积分」、其余靠图标 + 值的形态辨识。
    private var metaRow: some View {
        HStack(spacing: 9) {
            metaMetric(icon: "clock", value: formatDuration(max(item.duration, status.duration)))
            metaDivider
            metaMetric(icon: "waveform", value: item.format.uppercased())
            metaDivider
            metaMetric(icon: "diamond.fill",
                       value: formatCredits(item.pointsCost),
                       unit: "积分".localized())
            metaDivider
            metaMetric(icon: "person.wave.2.fill", value: voiceName, flexes: true)

            Spacer(minLength: 0)
        }
        .frame(height: 22)
        .padding(.horizontal, metrics.pageMargin)
        .accessibilityElement(children: .combine)
    }

    private var metaDivider: some View {
        Rectangle()
            .fill(c.line2)
            .frame(width: 1, height: 11)
    }

    private func metaMetric(icon: String, value: String, unit: String? = nil,
                            flexes: Bool = false) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 10.5))
                .foregroundStyle(c.textTertiary)

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(c.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if let unit {
                    Text(unit)
                        .font(.system(size: 10.5))
                        .foregroundStyle(c.textTertiary)
                }
            }
        }
        // 音色名长度不可控：只让它成为可压缩项，时长 / 格式 / 积分保持固定宽
        .layoutPriority(flexes ? -1 : 1)
    }

    // MARK: 固定底栏（重命名 / 复制音频 / 删除）

    private var actionBar: some View {
        HStack(spacing: 8) {
            detailAction("square.and.pencil", "重命名".localized(), tint: c.textSecondary) {
                renameText = currentName.isEmpty ? item.shownName : currentName
                showRename = true
            }
            detailAction("square.on.square", "复制语音".localized(), tint: c.textSecondary) {
                duplicateCurrent()
            }
            detailAction("trash.fill", "删除".localized(), tint: c.danger) {
                showDeleteConfirm = true
            }
        }
        .padding(.horizontal, metrics.pageMargin)
        .padding(.top, 10)
        .padding(.bottom, 10)
        .background(c.bar)
        .overlay(alignment: .top) { Hairline() }
    }

    private func detailAction(_ icon: String, _ title: String, tint: Color,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                Text(title)
                    .font(.system(size: 12.5, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
            .frame(height: 34)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(c.surface3)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: 详情页操作

    private func commitRename() {
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        showRename = false
        guard !trimmed.isEmpty, trimmed != (currentName.isEmpty ? item.shownName : currentName) else { return }
        ProjectService.shared.renameAudio(id: item.id, displayName: trimmed)
        currentName = trimmed
        uiState.showToast(.success("已重命名".localized()))
    }

    /// 磁盘复制在后台线程，主线程只写库 + Toast（与列表左滑「复制」同一套取舍）。
    private func duplicateCurrent() {
        let sourceURL = item.absoluteURL
        let ext = item.fileExtension
        let source = item
        Task { @MainActor in
            let staged = await Task.detached(priority: .userInitiated) {
                ProjectService.stageDuplicatedFile(sourceURL: sourceURL, fileExtension: ext)
            }.value
            guard let name = staged,
                  ProjectService.shared.finishDuplicate(source: source, newFileName: name) != nil else {
                uiState.showToast(.failure("复制失败".localized()))
                return
            }
            uiState.showToast(.success("已复制语音".localized()))
        }
    }

    /// 与列表一致走软删：只打标，文件保留 30 天；撤销即清标记。
    private func softDeleteCurrent() {
        let id = item.id
        flags.markDeleted([id])
        NowPlayingStore.shared.clearIfMatches([id])
        let store = flags
        let state = uiState
        state.showUndoToast(text: "已移入最近删除 · 30 天内可恢复".localized()) {
            store.restore([id])
            // ⚠️ 列表页在删除那一刻就已 onAppear 过，撤销后必须主动发信号让它重算
            state.requestHistoryReload()
            state.showToast(.success("已撤销删除".localized()))
        }
        dismiss()
    }

    // MARK: 播放状态图标（并进时间行，只占一个图标的宽度）

    /// 原实现是卡片右上角一整行「● 正在播放 · 1.0x」胶囊徽章：24pt 高 + 6pt 间距，
    /// 只为说一句随时都看得出来的话。现在压成一个 14pt 图标，贴着「已播时间」读：
    /// `▶ 00:12.3 ── 第 3 / 12 句 ── 03:21`。
    ///
    /// ⚠️ 三态用**不同字形**（喇叭 / 暂停 / 播放），不是只换颜色 ——
    ///    纯靠颜色区分状态对色弱用户无效。
    /// ⚠️ 状态文字没有删，只是不再上屏：转进 `accessibilityLabel`，
    ///    VoiceOver 仍然念完整的「正在播放 · 1.0x」。
    private var playbackStateIcon: some View {
        Image(systemName: stateSymbol)
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(stateTint)
            .frame(width: 14)
            .accessibilityLabel(statusText)
    }

    private var stateSymbol: String {
        if isThisPlaying { return "speaker.wave.2.fill" }
        if isThisPaused { return "pause.fill" }
        return "play.fill"
    }

    private var stateTint: Color {
        if isThisPlaying { return c.success }
        if isThisPaused { return c.textSecondary }
        return c.textTertiary
    }

    private var statusText: String {
        if isThisPlaying { return "正在播放 · %@".localized(rateLabel) }
        if isThisPaused { return "已暂停".localized() }
        return "待播放".localized()
    }

    private static func countSentences(_ text: String) -> Int {
        text.components(separatedBy: CharacterSet(charactersIn: "。！？!?；;\n"))
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .count
    }
}
