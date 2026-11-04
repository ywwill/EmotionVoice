//
//  PlayerDetailView.swift
//  iOSEmora
//
//  播放详情（push 进项目标签的导航栈）
//
//  与 macOS 右侧详情面板的差异：
//  - macOS 的四列 meta 条在 iPhone 上折成 **2×2**（宽屏回到 4 列）
//  - 底部状态栏**去掉三组键帽提示**（iOS 没有键盘快捷键），只留播放状态
//  - 倍速菜单 0.5–2x 六档保留（macOS 的 `playbackRateOptions`）
//  - 波形整卡可点击 / 拖动定位（44pt 触摸高度）
//  - 时间行改成音频播放器的常规排布：**左边已播放 / 右边总时长**；
//    拖动频谱时左边跟着手指实时走，并在频谱上方浮出当前落点的时间气泡，松手即恢复。
//

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

    /// 快进 / 快退步长（秒）。详情页是精听场景，15 秒太粗，5 秒刚好够定位一句话。
    private static let skipStep: Double = 5

    private var url: URL { item.absoluteURL }

    /// ⚠️ 时长以播放器拿到的为准：流式文件的 `item.duration` 可能是入库时的估值，
    /// 取 `max` 才能保证右侧「总时长」在播放开始后不再跳变。
    private var totalDuration: Double { max(status.duration, item.duration) }

    /// ⚠️ 必须用 identifier（`item.fileName`）判定，不能用 `player.isPlaying(url:)`：
    /// 详情页是用 `play(url:identifier: item.fileName)` 起的播，`playingKey` 存的是文件名，
    /// 拿 `url.path` 去比永远不等 —— 正是「点了暂停图标不变、只会从头重播」的根因。
    private var isThisPlaying: Bool { status.playingKey == item.fileName && status.isPlaying }
    private var isThisPaused: Bool { status.playingKey == item.fileName && status.isPaused }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                waveformCard
                    .padding(.horizontal, metrics.pageMargin)
                    .padding(.top, 12)

                transportRow

                controlRow

                metaCard
                    .padding(.horizontal, metrics.pageMargin)

                textCard
                    .padding(.horizontal, metrics.pageMargin)
                    .padding(.top, 12)

                Spacer(minLength: 24)
            }
        }
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
                            : "已取消收藏".localized()))
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
            sentenceCount = Self.countSentences(item.text)
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
            // 状态徽章固定在卡片右上角：单独占一行，避免和拖动时从左滑到右的时间气泡抢位置
            statusLine
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.bottom, 6)

            scrubTimeLane

            WaveformScrubber(tint: c.accent,
                             trackTint: c.slot,
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

            HStack {
                ElapsedTimeLabel(scrubFraction: scrubFraction, duration: totalDuration)
                Spacer(minLength: 0)
                Text(formatDuration(totalDuration))
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(c.textTertiary)
            }
            .padding(.top, 8)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: AuroraRadius.lg, style: .continuous)
                .fill(c.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: AuroraRadius.lg, style: .continuous)
                        .strokeBorder(c.line, lineWidth: 0.5)
                )
        )
    }

    /// 拖动时跟随手指的时间气泡（落在频谱正上方）。
    ///
    /// ⚠️ 这条 24pt 的轨道**恒占位**（拖动与否都在）：只在按下时才把高度让出来，
    /// 整张卡会在手指落下的那一帧突然长高一截、波形跟着往下跳 —— 手感比没有气泡还差。
    ///
    /// ⚠️ 气泡横向位置按落点百分比算，并夹在轨道内（`0 … width - 气泡宽`），
    /// 否则拖到两端时气泡会探出卡片外面被裁掉。
    private var scrubTimeLane: some View {
        GeometryReader { geo in
            if let f = scrubFraction {
                let laneWidth = max(geo.size.width, 1)
                let bubbleWidth: CGFloat = 64
                let x = min(max(f * laneWidth - bubbleWidth / 2, 0), max(laneWidth - bubbleWidth, 0))
                Text(formatDuration(f * totalDuration))
                    .font(.system(size: 12.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(c.accent)
                    .padding(.horizontal, 9)
                    .frame(height: 24)
                    .background(
                        Capsule(style: .continuous)
                            .fill(c.accentSoft)
                            .overlay(
                                Capsule(style: .continuous)
                                    .strokeBorder(c.accent.opacity(0.32), lineWidth: 0.5)
                            )
                    )
                    // ⚠️ 顺序别反：先「撑满轨道 + 靠左」再 offset，
                    //    反过来写的话 offset 会被外层 frame 的 alignment 抵消掉。
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .offset(x: x)
                    .animation(.easeOut(duration: 0.08), value: x)
            }
        }
        .frame(height: 24)
    }

    // MARK: 走带

    private var transportRow: some View {
        HStack(spacing: 22) {
            transportButton("backward.end.fill", size: 30) { player.seek(to: 0) }
            transportButton("gobackward.5", size: 24) { player.skip(by: -Self.skipStep) }

            Button {
                player.togglePlayback(url: url, identifier: item.fileName)
            } label: {
                ZStack {
                    Circle().fill(c.ctaGradient)
                    Image(systemName: isThisPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 26, weight: .semibold))
                        // ⚠️ 图标随状态切换要带动画：不带的话按钮像是「点了没反应」，
                        // 而真正的问题（见 `isThisPlaying` 注释）已经修在判定上了。
                        .animation(.easeOut(duration: 0.14), value: isThisPlaying)
                        .foregroundStyle(c.ctaForeground)
                }
                .frame(width: 64, height: 64)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isThisPlaying ? "暂停".localized() : "播放".localized())

            transportButton("goforward.5", size: 24) { player.skip(by: Self.skipStep) }
            transportButton("forward.end.fill", size: 30) {
                player.seek(to: max(player.duration, item.duration))
            }
        }
        .padding(.top, 16)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity)
    }

    private func transportButton(_ systemName: String, size: CGFloat,
                                 action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(c.textSecondary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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
        .padding(.top, 10)
        .padding(.bottom, 14)
    }

    private var rateLabel: String {
        let r = status.playbackRate
        if r == r.rounded() { return String(format: "%.0fx", r) }
        return String(format: "%.2fx", r)
    }

    // MARK: meta 卡（手机 2×2 / 宽屏 4 列）

    private var metaCard: some View {
        let cols = metrics.metaColumns
        let items: [(String, String, String)] = [
            ("clock", "时长".localized(), formatDuration(max(item.duration, status.duration))),
            ("waveform", "格式".localized(), item.format.uppercased()),
            ("diamond.fill", "积分".localized(), formatCredits(item.pointsCost)),
            ("person.wave.2.fill", "音色".localized(), voiceName)
        ]
        let rows = Int(ceil(Double(items.count) / Double(cols)))

        return VStack(spacing: 0) {
            ForEach(0..<rows, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<cols, id: \.self) { col in
                        let idx = row * cols + col
                        if idx < items.count {
                            metaCell(icon: items[idx].0, key: items[idx].1, value: items[idx].2)
                            if col < cols - 1 { separator(vertical: true) }
                        } else {
                            Spacer(minLength: 0)
                        }
                    }
                }
                if row < rows - 1 { separator(vertical: false) }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: AuroraRadius.lg, style: .continuous)
                .fill(c.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: AuroraRadius.lg, style: .continuous)
                        .strokeBorder(c.line, lineWidth: 0.5)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: AuroraRadius.lg, style: .continuous))
    }

    private func separator(vertical: Bool) -> some View {
        Group {
            if vertical {
                Rectangle().fill(c.line).frame(width: 0.5)
            } else {
                Rectangle().fill(c.line).frame(height: 0.5)
            }
        }
    }

    private func metaCell(icon: String, key: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundStyle(c.textTertiary)
                Text(key)
                    .font(.system(size: 11))
                    .foregroundStyle(c.textTertiary)
            }
            Text(value)
                .font(.system(size: 16, weight: .semibold, design: .monospaced))
                .foregroundStyle(c.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: 文本卡

    private var textCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("%d 字 · %d 句".localized(item.text.count, sentenceCount))
                    .font(.system(size: 11.5))
                    .foregroundStyle(c.textTertiary)
                Spacer(minLength: 0)
                Button {
                    UIPasteboard.general.string = item.text
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 11))
                        Text("复制".localized())
                            .font(.system(size: 12))
                    }
                    .foregroundStyle(c.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule(style: .continuous).fill(c.surface3)
                    )
                }
                .buttonStyle(.plain)
            }
            Text(item.text)
                .font(.system(size: 14.5))
                .lineSpacing(1.62 * 14.5 - 14.5)
                .foregroundStyle(c.textPrimary)
                .textSelection(.enabled)
                .padding(.top, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: AuroraRadius.lg, style: .continuous)
                .fill(c.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: AuroraRadius.lg, style: .continuous)
                        .strokeBorder(c.line, lineWidth: 0.5)
                )
        )
    }

    // MARK: 固定底栏（重命名 / 复制音频 / 删除）

    private var actionBar: some View {
        HStack(spacing: 8) {
            detailAction("pencil", "重命名".localized(), tint: c.textSecondary) {
                renameText = currentName.isEmpty ? item.shownName : currentName
                showRename = true
            }
            detailAction("doc.on.doc", "复制音频".localized(), tint: c.textSecondary) {
                duplicateCurrent()
            }
            detailAction("trash", "删除".localized(), tint: c.danger) {
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
            uiState.showToast(.success("已复制音频".localized()))
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

    // MARK: 状态行（卡片右上角徽章）

    /// ⚠️ 这里不能带内部 `Spacer`：外层用 `.frame(maxWidth: .infinity, alignment: .trailing)`
    /// 把它推到右上角，撑满的 Spacer 会把文字挤回左边。
    private var statusLine: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(isThisPlaying ? c.success : c.textTertiary)
                .frame(width: 6, height: 6)
            Text(statusText)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(c.textSecondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(
            Capsule(style: .continuous).fill(c.surface3)
        )
        .accessibilityElement(children: .combine)
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
