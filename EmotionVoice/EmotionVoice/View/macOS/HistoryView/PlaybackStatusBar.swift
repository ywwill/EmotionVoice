//
//  PlaybackStatusBar.swift
//  EmotionVoice
//
//  播放面板底部状态栏：播放状态 + 快捷键提示
//  对齐 UI/audio-player.html 的 .statusbar
//

import SwiftUI
import Combine

struct PlaybackStatusBar: View {

    @ObservedObject var player: AudioPreviewPlayer
    /// 字级时间轴（由 AudioPlayerDetailView 下发）；nil 时徽标显示「未对齐」
    let timeline: AudioTimeline?

    var body: some View {
        HStack(spacing: 12) {
            // 状态：圆点 + 文案
            HStack(spacing: 7) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 6, height: 6)
                    .shadow(color: statusGlow, radius: player.isPlaying ? 8 : 0)

                Text(statusText)
                    .font(.system(size: 11))
                    .foregroundStyle(AppColor.textTertiary)
            }

            Spacer(minLength: 8)

            // 快捷键提示
            HStack(spacing: 14) {
                hint(caps: ["空格"], text: "播放 / 暂停")
                hint(caps: ["←", "→"], text: "5 秒")
                hint(caps: ["⌘", "←", "→"], text: "15 秒")
            }
            .layoutPriority(1)
        }
        .padding(.horizontal, 18)
        .frame(height: 34)
        .background(Color(hex: 0x0C0D10).opacity(0.7))
        .overlay(alignment: .top) {
            Divider().background(AppColor.borderSubtle)
        }
    }

    // MARK: - 状态

    private var statusColor: Color {
        if player.isPlaying { return AppColor.statusSuccess }
        if player.isPaused { return AppColor.accentPrimary }
        return AppColor.textTertiary
    }

    private var statusGlow: Color {
        player.isPlaying ? AppColor.statusSuccess.opacity(0.7) : .clear
    }

    private var statusText: String {
        if player.isPlaying {
            return "正在播放".localized() + " · " + PlayerTextMetrics.formatRate(player.playbackRate)
        }
        if player.isPaused {
            return "已暂停".localized() + " · " +  PlayerTextMetrics.formatTime(player.currentTime)
        }
        if player.isFinished {
            return "播放结束".localized()
        }
        return "已就绪".localized()
    }

    // MARK: - 快捷键提示

    private func hint(caps: [String], text: String) -> some View {
        HStack(spacing: 5) {
            HStack(spacing: 3) {
                ForEach(caps, id: \.self) { keyCap($0) }
            }
            Text(text.localized())
        }
        .font(.system(size: 11))
        .foregroundStyle(AppColor.textTertiary)
    }

    private func keyCap(_ label: String) -> some View {
        Text(label.localized())
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(AppColor.textSecondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(AppColor.bgTertiary)
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(AppColor.borderSubtle, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}

// MARK: - 离开历史页后的迷你播放器
//
// 需求：在「我的项目」里播放音频后切到别的分区，播放不能变成「看不见的声音」，
// 要留一个缩小的播放器继续控制（对齐 iOS `MiniPlayerView` 的心智模型）。
//
// 放**侧边栏底部**而不是内容区浮层，两个原因：
//  1. 内容区每个分区自己的底部都有东西（工作台右侧是生成栏 / 参数面板，音色库是
//     分页页脚），浮块压上去一定挡操作；
//  2. 浮层想不挡就只能 `safeAreaInset` 让页面让位，那会让工作台的 NSTextView 重新
//     排版——正是本项目明令禁止的「切页 / 改尺寸触发重排」。
//  侧栏底部本来就是一段空白（`Sidebar` 只有一个 Spacer），不参与任何页面的布局。
//
// ⚠️ 播放本身仍归 `AudioPreviewPlayer` 单例，这里只记「当前展示的是哪一条」：
//    `playingKey` 是字符串标识（历史页用 `url.path`），不足以渲染名称 / 音色 / 进度。
// ⚠️ 显隐只由 `item` 决定，不跟 `player.playingKey` 联动 —— 播到结尾 / 被音色库试听
//    顶掉 key 都属于「不是用户意图」的时刻，浮层一消失用户反而找不到刚才那条。
//    只有点 ✕ 才收起（与 iOS 同一心智模型）。

@MainActor
final class NowPlayingMiniStore: ObservableObject {

    static let shared = NowPlayingMiniStore()

    /// 迷你播放器展示的那一条（nil = 不显示浮层）
    @Published private(set) var item: AudioItem?
    /// 音色名在 attach 时解析一次：body 里绝不查库
    @Published private(set) var voiceName: String = ""
    /// 点浮层主体时要求历史页定位到这一条，历史页消费后置空
    @Published private(set) var pendingSelectionID: Int64?

    private let player = AudioPreviewPlayer.shared

    private init() {}

    func attach(_ audio: AudioItem, voiceName: String? = nil) {
        let resolved = voiceName ?? VoiceService.shared.displayName(forKey: audio.voice) ?? audio.voice
        if !resolved.isEmpty { self.voiceName = resolved }
        item = audio
    }

    /// 请求历史页定位（点浮层主体时调用）
    func requestSelection() {
        guard let item else { return }
        pendingSelectionID = item.id
    }

    /// 历史页取走待定位的条目（取一次即清空，避免每次 onAppear 都重新选中）
    func consumePendingSelection() -> Int64? {
        defer { pendingSelectionID = nil }
        return pendingSelectionID
    }

    /// 删掉条目时同步收起浮层
    func clearIfMatches(_ ids: Set<Int64>) {
        guard let item, ids.contains(item.id) else { return }
        close()
    }

    /// 关闭：停播 + 清空
    func close() {
        player.stop()
        item = nil
        voiceName = ""
        pendingSelectionID = nil
    }
}

/// 侧栏底部的迷你播放器。
///
/// **只订阅 store（低频）**；播放态 / 进度分别关在两个几十行的小 View 里，
/// 免得 0.1s 一次的 `progress` 把外层重算一遍（本项目最强的一条性能约定）。
struct MiniPlayerBar: View {

    @EnvironmentObject private var appState: AppState
    @ObservedObject private var store = NowPlayingMiniStore.shared

    @State private var isHovered = false

    /// 侧栏宽 220，左右各留 10 → 卡片 200
    static let cardWidth: CGFloat = 200
    static let cardHeight: CGFloat = 54

    var body: some View {
        Group {
            // 历史页本身就是完整播放器，不用再挂一个缩小的
            if let item = store.item, appState.selectedSection != .projects {
                card(item)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 12)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: store.item?.id)
        .animation(.easeInOut(duration: 0.2), value: appState.selectedSection)
    }

    private func card(_ item: AudioItem) -> some View {
        HStack(spacing: 8) {
            artwork(item)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.shownName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppColor.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                MiniPlayerTimeLabel(item: item, voiceName: store.voiceName)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            MiniPlayerPlayButton(item: item)

            Button {
                store.close()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(AppColor.textTertiary)
                    .frame(width: 16, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
            .help("关闭".localized())
        }
        .padding(.leading, 8)
        .padding(.trailing, 6)
        .frame(width: Self.cardWidth, height: Self.cardHeight)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(isHovered ? AppColor.bgElevated : AppColor.bgTertiary)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(AppColor.borderMedium, lineWidth: 1)
                )
        )
        // ⚠️ 进度条不带自己的 clipShape：2pt 高的条套 12pt 连续圆角会向左右溢出卡片，
        //    圆角交给整卡这一层统一裁。
        .overlay(alignment: .bottom) {
            MiniPlayerProgress(item: item)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        // ⚠️ 阴影必须挂在 clipShape 之后，挂在 background 里会连阴影一起被裁掉
        .shadow(color: .black.opacity(0.28), radius: 12, x: 0, y: 5)
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onHover { isHovered = $0 }
        // 整卡点击 = 回到历史页；子 Button 命中优先级更高，不会连带触发
        .onTapGesture(perform: expand)
        .help("回到我的项目".localized())
    }

    /// 点卡片主体：回到「我的项目」，并由历史页把这条重新选中展开。
    /// `pendingSelectionID` 会被 `HistoryView.onAppear` 取走（见 `applyPendingSelection`）。
    private func expand() {
        store.requestSelection()
        appState.selectedSection = .projects
    }

    /// 音色色块：与列表 / 音色库同一套 seed 取色，浮层一眼能认出是哪条
    private func artwork(_ item: AudioItem) -> some View {
        let colors = VoiceAvatarPalette.gradient(for: item.voice)
        let letter = store.voiceName.isEmpty ? "♪" : String(store.voiceName.suffix(1))
        return Text(letter)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 30, height: 30)
            .background(
                LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(.white.opacity(0.22), lineWidth: 1)
            )
    }
}

/// 「音色 · 00:12 / 00:34」：只有这一行需要 10Hz 刷新
private struct MiniPlayerTimeLabel: View {

    @ObservedObject private var player = AudioPreviewPlayer.shared

    let item: AudioItem
    let voiceName: String

    /// ⚠️ 历史页用 `url.path` 当 playingKey（`play(url:)` 不传 identifier），
    /// 判定必须比 path；用 `fileName` 会永远 false，时间停在 00:00。
    private var isCurrent: Bool { player.playingKey == item.absoluteURL.path }

    var body: some View {
        let current = isCurrent ? player.currentTime : 0
        let total = isCurrent ? max(player.duration, item.duration) : item.duration
        Text("\(voiceName) · \(formatDuration(current))/\(formatDuration(total))")
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(AppColor.textTertiary)
            .lineLimit(1)
            .truncationMode(.middle)
    }
}

/// 播放 / 暂停：同一条就切换，停了就从头起播（走 path 判定，与历史页一致）
private struct MiniPlayerPlayButton: View {

    @ObservedObject private var player = AudioPreviewPlayer.shared

    let item: AudioItem

    private var isCurrent: Bool { player.playingKey == item.absoluteURL.path }
    private var showsPause: Bool { isCurrent && player.isPlaying }

    var body: some View {
        Button {
            // ⚠️ 不要传 identifier：历史页的播放态判定全按 `url.path`，
            //    这里改口径会让列表行高亮 / 状态栏对不上。
            player.togglePlayback(url: item.absoluteURL)
        } label: {
            ZStack {
                Circle().fill(
                    LinearGradient(
                        colors: [AppColor.accentGlow, AppColor.accentSecondary],
                        startPoint: UnitPoint(x: 0.15, y: 0),
                        endPoint: UnitPoint(x: 0.85, y: 1)
                    )
                )
                Image(systemName: showsPause ? "pause.fill" : "play.fill")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color(hex: 0x241505))
            }
            .frame(width: 26, height: 26)
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .help(showsPause ? "暂停".localized() : "播放".localized())
    }
}

/// 卡片底部 2pt 进度条：只订阅播放器，scaleEffect 不触发任何重绘
private struct MiniPlayerProgress: View {

    @ObservedObject private var player = AudioPreviewPlayer.shared

    let item: AudioItem

    private var isCurrent: Bool { player.playingKey == item.absoluteURL.path }

    var body: some View {
        Rectangle()
            .fill(AppColor.accentPrimary)
            .frame(height: 2)
            .scaleEffect(x: isCurrent ? max(min(player.progress, 1), 0.001) : 0.001, anchor: .leading)
    }
}
