//
//  HistoryComponents.swift
//  iOSEmora
//
//  历史记录页的展示组件（对应 UI/iOS/history-redesign.html 第 04 章规格）。
//  色板 / 圆角 / 字体全部沿用 AuroraPalette.swift，不引入新颜色；
//  玫红强调统一用 `AuroraDecor.rose`，与音色库 heart.fill 同一套视觉语言。
//

import SwiftUI
import Combine

// MARK: - 统计条

/// 总条数 / 占用空间 / 本月新增，三等分。数值恒为全量（不含已软删条目）。
struct HistoryStatBar: View {
    @Environment(\.aurora) private var c
    let count: Int
    let bytes: Int
    let monthly: Int

    var body: some View {
        HStack(spacing: 0) {
            stat("%d 条音频".localized(count))
            divider
            stat(sizeText)
            divider
            stat("%d 条本月".localized(monthly))
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(c.surface2)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(c.line, lineWidth: 0.5)
                )
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 9)
    }

    private func stat(_ text: String) -> some View {
        HStack(spacing: 5) {
            // 数值段用等宽粗体，单位段用常规小字
            let parts = text.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            if let first = parts.first {
                Text(first)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(c.textPrimary)
            }
            if parts.count > 1 {
                Text(parts[1])
                    .font(.system(size: 11.5))
                    .foregroundStyle(c.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var divider: some View {
        Rectangle().fill(c.line2).frame(width: 0.5, height: 16)
            .padding(.horizontal, 10)
    }

    private var sizeText: String {
        let u = autoByteUnit(Double(bytes))
        return "\(u.value) \(u.unit)"
    }
}

// MARK: - 筛选胶囊

/// 全部 / 收藏，单选互斥；计数恒为全量。
/// ⚠️ 整条胶囊都是热区：外层 contentShape + onTapGesture，不用内部 Button；
///    选完分类不再出现 ×，清除走「全部」。
struct HistoryFilterChips: View {
    @Environment(\.aurora) private var c
    let allCount: Int
    let favoriteCount: Int
    let selection: HistoryFilter
    let onSelect: (HistoryFilter) -> Void

    var body: some View {
        HStack(spacing: 7) {
            chip(title: "全部".localized(), count: allCount,
                 systemImage: nil, on: selection == .all) { onSelect(.all) }
            chip(title: "收藏".localized(), count: favoriteCount,
                 systemImage: "heart", on: selection == .favorites) { onSelect(.favorites) }
        }
        // ⚠️ VStack 默认 .center：不显式撑满，两个胶囊会整体居中而不是左对齐
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }

    private func chip(title: String, count: Int, systemImage: String?,
                      on: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 5) {
            if let systemImage {
                Image(systemName: on ? "heart.fill" : systemImage)
                    .font(.system(size: 12))
            }
            Text(title)
                .font(.system(size: 12.5, weight: on ? .semibold : .regular))
            Text("\(count)")
                .font(.system(size: 11, design: .monospaced))
                .opacity(0.75)
        }
        .foregroundStyle(on ? c.accent : c.textSecondary)
        .padding(.horizontal, 11)
        .frame(height: 29)
        .background(
            Capsule(style: .continuous)
                .fill(on ? c.accentSoft : c.surface)
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(on ? c.accent.opacity(0.42) : c.line, lineWidth: 0.5)
                )
        )
        .contentShape(Capsule(style: .continuous))
        .onTapGesture(perform: action)
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }
}

// MARK: - 搜索范围 / 结果条

struct HistoryScopeChips: View {
    @Environment(\.aurora) private var c
    let selection: HistorySearchScope
    let onSelect: (HistorySearchScope) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(HistorySearchScope.allCases) { scope in
                let on = scope == selection
                Text(scope.title)
                    .font(.system(size: 11.5, weight: on ? .semibold : .regular))
                    .foregroundStyle(on ? c.accent : c.textSecondary)
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(on ? c.accentSoft : c.surface2)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(on ? c.accent.opacity(0.42) : c.line, lineWidth: 0.5)
                            )
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { onSelect(scope) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }
}

struct HistoryResultBar: View {
    @Environment(\.aurora) private var c
    let count: Int
    let sortOrder: HistorySortOrder

    var body: some View {
        HStack {
            Text("全库命中 %d 条".localized(count))
                .font(.system(size: 11.5))
                .foregroundStyle(c.textSecondary)
            Spacer(minLength: 0)
            Text(sortOrder.title)
                .font(.system(size: 11.5))
                .foregroundStyle(c.textTertiary)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 9)
    }
}

// MARK: - 分组头

struct HistorySectionHeader: View {
    @Environment(\.aurora) private var c
    let section: HistorySection

    var body: some View {
        HStack(spacing: 8) {
            Text(section.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(c.textTertiary)
            if let detail = section.detail {
                Text(detail)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(c.textTertiary.opacity(0.8))
            }
            Text("%d 条".localized(section.count))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(c.textTertiary.opacity(0.8))
            Rectangle().fill(c.line).frame(height: 0.5)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 7)
        .background(c.backgroundGrouped)
    }
}

// MARK: - 行卡片

/// 只有「正在播放」那一行会挂这个订阅：10Hz 进度只重算这一条 2pt 渐变条，
/// 不牵动整行 / 整个列表（macOS `VoiceRowPlayback` 同款订阅下沉）。
private struct RowProgressTrack: View {
    @Environment(\.aurora) private var c
    @ObservedObject private var player = AudioPreviewPlayer.shared

    var body: some View {
        Rectangle()
            .fill(c.ctaGradient)
            .scaleEffect(x: max(min(player.progress, 1), 0.001), anchor: .leading)
    }
}

/// 行高 ≈68pt：头像 44 / 名称 15 / 音色·时长·大小 / 时间 / 播放按钮 32。
/// 不显示情绪；生成中 / 失败 / 文件丢失用状态胶囊表达。
struct HistoryRow: View {
    @Environment(\.aurora) private var c

    let audio: AudioItem
    let voiceName: String
    let favorite: Bool
    let isPlaying: Bool
    let isSelecting: Bool
    let selected: Bool
    let query: String
    let onPreview: () -> Void
    let onOpen: () -> Void
    let onRetry: () -> Void

    private enum RowState {
        case normal, generating, failed, missing
    }

    private var state: RowState {
        switch audio.status {
        case .generating, .pending: return .generating
        case .failed: return .failed
        case .completed: return audio.isOnDisk ? .normal : .missing
        }
    }

    private var playable: Bool { state == .normal }

    var body: some View {
        HStack(spacing: 11) {
            if isSelecting { selectionCircle }

            avatar

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    highlightedName
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                        .foregroundStyle(c.textPrimary)
                    Spacer(minLength: 4)
                    Text(HistoryListViewModel.rowTime(audio.createdAt))
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(c.textTertiary)
                        .lineLimit(1)
                }
                metaLine
            }

            playButton
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: AuroraRadius.md, style: .continuous)
                .fill(isPlaying ? c.surface2 : c.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: AuroraRadius.md, style: .continuous)
                        .strokeBorder(isPlaying ? c.accent.opacity(0.42) : c.line, lineWidth: 0.5)
                )
        )
        // ⚠️ 播放中不再画左侧竖条：3pt 渐变竖线贴着卡片边缘对比太强、和圆角也接不上，
        //    视觉上很突兀。状态完全交给 surface2 底 + accent 描边 + 渐变播放按钮
        //    （pause 图标）+ 底部渐变进度条表达，信息一点不少。
        .overlay(alignment: .bottom) {
            if isPlaying {
                RowProgressTrack()
                    .frame(height: 2)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: AuroraRadius.md, style: .continuous))
        .opacity(state == .missing ? 0.6 : 1)
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
    }

    // MARK: 头像 + 收藏角标

    private var avatar: some View {
        VoiceAvatar(text: avatarText, seed: audio.voice, size: 44, corner: 12)
            .overlay(alignment: .topTrailing) {
                if favorite {
                    ZStack {
                        Circle().fill(c.surface)
                        Image(systemName: "heart.fill")
                            .font(.system(size: 9))
                            .foregroundStyle(AuroraDecor.rose)
                    }
                    .frame(width: 17, height: 17)
                    .shadow(color: .black.opacity(0.18), radius: 2, x: 0, y: 1)
                    .offset(x: 4, y: -4)
                }
            }
    }

    private var avatarText: String {
        voiceName.isEmpty ? "声" : String(voiceName.suffix(1))
    }

    // MARK: 名称高亮

    private var highlightedName: Text {
        let name = audio.shownName
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty,
              let range = name.range(of: q, options: .caseInsensitive) else {
            return Text(name)
        }
        let before = Text(name[name.startIndex..<range.lowerBound])
        let hit = Text(name[range])
            .foregroundColor(c.accent)
            .bold()
        let after = Text(name[range.upperBound..<name.endIndex])
        return before + hit + after
    }

    // MARK: 第二行

    @ViewBuilder
    private var metaLine: some View {
        HStack(spacing: 6) {
            switch state {
            case .normal:
                voicePill
                mono(formatDuration(audio.duration))
                dot
                mono(formatDataSize(audio.fileSize))
            case .generating:
                HistoryStatusPill(text: "生成中".localized(), tone: .info, dot: true)
                mono("\(audio.format.uppercased()) · \(audio.sampleRate / 1000)kHz")
            case .failed:
                HistoryStatusPill(text: "失败".localized(), tone: .danger, dot: false)
                Button(action: onRetry) {
                    Text("重新编辑".localized())
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(c.accent)
                }
                .buttonStyle(.plain)
            case .missing:
                HistoryStatusPill(text: "文件已丢失".localized(), tone: .warning, dot: false)
                mono("无法播放".localized())
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var voicePill: some View {
        Text(voiceName)
            .font(.system(size: 10.5, weight: .semibold))
            .foregroundStyle(c.accent)
            .padding(.horizontal, 7)
            .frame(height: 19)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(c.accentSoft)
            )
            .lineLimit(1)
    }

    private func mono(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10.5, design: .monospaced))
            .foregroundStyle(c.textTertiary)
            .lineLimit(1)
    }

    private var dot: some View {
        Text("·")
            .font(.system(size: 10))
            .foregroundStyle(c.textTertiary.opacity(0.55))
    }

    // MARK: 播放按钮

    private var playButton: some View {
        Button(action: onPreview) {
            ZStack {
                if isPlaying {
                    Circle().fill(c.ctaGradient)
                } else {
                    Circle().fill(c.surface3)
                }
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(isPlaying ? .white : c.accent)
            }
            .frame(width: 32, height: 32)
            .overlay(
                Circle().strokeBorder(c.line, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .disabled(!playable)
        .opacity(playable ? 1 : 0.4)
        .accessibilityLabel(isPlaying ? "暂停".localized() : "播放".localized())
    }

    private var selectionCircle: some View {
        ZStack {
            Circle()
                .fill(selected ? c.accent : Color.clear)
                .overlay(Circle().strokeBorder(selected ? Color.clear : c.line2, lineWidth: 1.5))
            if selected {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 23, height: 23)
    }
}

// MARK: - 状态胶囊

struct HistoryStatusPill: View {
    @Environment(\.aurora) private var c

    enum Tone { case info, danger, warning }

    let text: String
    let tone: Tone
    var dot: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            if dot {
                Circle().fill(tint).frame(width: 5, height: 5)
            }
            Text(text)
                .font(.system(size: 10.5, weight: .semibold))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 7)
        .frame(height: 19)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(tint.opacity(0.13))
        )
    }

    private var tint: Color {
        switch tone {
        case .info: return c.info
        case .danger: return c.danger
        case .warning: return c.warning
        }
    }
}

// MARK: - 骨架屏

struct HistorySkeletonRow: View {
    @Environment(\.aurora) private var c
    @State private var on = false

    var body: some View {
        HStack(spacing: 11) {
            block(width: 44, height: 44, radius: 12)
            VStack(alignment: .leading, spacing: 8) {
                block(width: 180, height: 12, radius: 6)
                block(width: 120, height: 10, radius: 6)
            }
            Spacer(minLength: 0)
            block(width: 32, height: 32, radius: 16)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: AuroraRadius.md, style: .continuous)
                .fill(c.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: AuroraRadius.md, style: .continuous)
                        .strokeBorder(c.line, lineWidth: 0.5)
                )
        )
        .opacity(on ? 1 : 0.45)
        .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: on)
        .onAppear { on = true }
    }

    private func block(width: CGFloat, height: CGFloat, radius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(c.surface3)
            .frame(width: width, height: height)
    }
}

// MARK: - 空态

struct HistoryEmptyState: View {
    @Environment(\.aurora) private var c
    let isSearching: Bool
    let onCreate: () -> Void
    let onClearSearch: () -> Void
    let onClearFilter: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(c.surface2)
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .strokeBorder(c.line, lineWidth: 0.5)
                    )
                    .frame(width: 92, height: 92)
                Image(systemName: isSearching ? "magnifyingglass" : "waveform")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(c.accent)
                Circle()
                    .strokeBorder(c.line2, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .frame(width: 120, height: 120)
            }

            Text(isSearching ? "没有匹配的音频".localized() : "还没有生成过音频".localized())
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(c.textPrimary)

            if isSearching {
                Text("换个关键词，或清除筛选条件再试试。".localized())
                    .font(.system(size: 12.5))
                    .foregroundStyle(c.textTertiary)
                    .multilineTextAlignment(.center)
                HStack(spacing: 10) {
                    SecondaryButton(title: "换个关键词".localized(), isFullWidth: false, action: onClearSearch)
                    SecondaryButton(title: "清除筛选".localized(), isFullWidth: false, action: onClearFilter)
                }
            } else {
                Text("写一段文字、挑一个音色，第一条作品就会出现在这里。".localized())
                    .font(.system(size: 12.5))
                    .foregroundStyle(c.textTertiary)
                    .multilineTextAlignment(.center)
                Button(action: onCreate) {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 14, weight: .semibold))
                        Text("去创作".localized())
                            .font(.system(size: 13.5, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .frame(height: 38)
                    .background(Capsule(style: .continuous).fill(c.ctaGradient))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 44)
    }
}

// MARK: - mini player（全局常驻）

/// ⚠️ 这是**浮层**而不是列表卡片：品牌渐变底 + 白字 + 彩色投影，
/// 和列表里的白底行卡一眼区分开。整卡点击即展开，不需要单独的展开箭头。
struct MiniPlayerView: View {
    @Environment(\.aurora) private var c
    @ObservedObject private var player = AudioPreviewPlayer.shared

    /// 列表底部占位按这个高度算，避免两处写死数字对不上。
    static let height: CGFloat = 56

    let item: AudioItem
    let voiceName: String
    let onExpand: () -> Void
    let onToggle: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            VoiceAvatar(text: String(voiceName.suffix(1)), seed: item.voice, size: 36, corner: 10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(.white.opacity(0.38), lineWidth: 0.8)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(item.shownName)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text("\(voiceName) · \(formatDuration(player.currentTime)) / \(formatDuration(max(player.duration, item.duration)))")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 4) {
                Button(action: onToggle) {
                    ZStack {
                        Circle().fill(.white)
                        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(c.ctaStart)
                    }
                    .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(player.isPlaying ? "暂停".localized() : "播放".localized())

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.82))
                        .frame(width: 26, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("关闭".localized())
            }
        }
        .padding(.horizontal, 12)
        .frame(height: Self.height)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(c.ctaGradient)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.24), lineWidth: 0.8)
        }
        // ⚠️ 进度条不要自带 clipShape（对齐 `RowProgressTrack`）：2pt 高的条套 16pt
        //    连续圆角，裁剪路径会向左右溢出卡片。圆角交给下面整卡唯一这一层统一裁。
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(.white.opacity(0.85))
                .frame(height: 2)
                .scaleEffect(x: max(min(player.progress, 1), 0.001), anchor: .leading)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        // ⚠️ shadow 必须挂在 clipShape 之后，挂在 background 里会连阴影一起被裁掉
        .shadow(color: c.ctaStart.opacity(0.34), radius: 20, x: 0, y: 8)
        // 整卡展开：子 Button 的命中优先级更高，不会连带触发 onExpand
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture(perform: onExpand)
    }
}

// MARK: - ⋯ 菜单

/// 导航栏「⋯」菜单。
/// ⚠️ 它是 overlay 里就地插入的（没有系统 Sheet 动画），所以自己带
///    缩放 + 淡入 + 下移的进场；`appeared` 由 onAppear 翻转，每次新建视图都会重跑。
///    「排序方式」点开后原地展开两个可选项，选中项打勾 —— 不是盲切排序。
struct HistoryMoreMenu: View {
    @Environment(\.aurora) private var c
    let deletedCount: Int
    let sortOrder: HistorySortOrder
    let onTrash: () -> Void
    let onSortChange: (HistorySortOrder) -> Void
    let onDismiss: () -> Void

    @State private var appeared = false
    @State private var sortExpanded = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // 淡遮罩：既给菜单层次，也拦截列表点击
            c.scrim
                .opacity(appeared ? 0.42 : 0)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: onDismiss)
                .animation(.easeOut(duration: 0.22), value: appeared)

            VStack(spacing: 0) {
                menuRow(icon: "clock", tint: c.info,
                        title: "最近删除".localized(),
                        badge: "%d 条".localized(deletedCount),
                        action: { onTrash(); onDismiss() })

                menuRow(icon: "slider.horizontal.3", tint: c.accent,
                        title: "排序方式".localized(),
                        badge: sortOrder.title,
                        expanded: sortExpanded) {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                        sortExpanded.toggle()
                    }
                }

                if sortExpanded { sortOptions }

                Text("已删除的项目保留 30 天，到期自动清除".localized())
                    .font(.system(size: 11))
                    .foregroundStyle(c.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(c.surface2)
            }
            .frame(width: 252)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(c.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(c.line, lineWidth: 0.5)
                    )
            )
            // ⚠️ footer 是矩形铺满，会把卡片底部两个圆角盖成直角；整张卡裁成圆角。
            //    阴影必须画在裁剪之后（挂在 background 里会一起被裁掉）。
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: c.shadow, radius: 28, x: 0, y: 14)
            // overlay 的坐标从导航栏下方的内容区顶部算起：菜单紧贴 ⋯ 按钮下沿即可，
            // 之前 52pt 把菜单推到离按钮快 100pt 的地方。
            .padding(.trailing, 12)
            .padding(.top, 8)
            .scaleEffect(appeared ? 1 : 0.85, anchor: .topTrailing)
            .offset(y: appeared ? 0 : -10)
            .opacity(appeared ? 1 : 0)
            .animation(.spring(response: 0.3, dampingFraction: 0.82), value: appeared)
        }
        .onAppear { appeared = true }
    }

    // MARK: 排序子选项

    private var sortOptions: some View {
        VStack(spacing: 0) {
            ForEach(HistorySortOrder.allCases, id: \.rawValue) { order in
                Button {
                    onSortChange(order)
                    onDismiss()
                } label: {
                    let selected = order == sortOrder
                    HStack(spacing: 10) {
                        Image(systemName: order == .newest ? "arrow.down.to.line" : "arrow.up.to.line")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(selected ? c.accent : c.textTertiary)
                            .frame(width: 26)
                        Text(order.title)
                            .font(.system(size: 13))
                            .foregroundStyle(selected ? c.accent : c.textPrimary)
                        Spacer(minLength: 0)
                        if selected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(c.accent)
                        }
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 38)
                    .background(selected ? c.accentSoft.opacity(0.6) : Color.clear)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .background(c.surface2.opacity(0.6))
        .overlay(alignment: .bottom) { Rectangle().fill(c.line).frame(height: 0.5) }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: 菜单行

    private func menuRow(icon: String, tint: Color, title: String, badge: String,
                         expanded: Bool = false,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(tint.opacity(0.13))
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(tint)
                }
                .frame(width: 26, height: 26)

                Text(title)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(c.textPrimary)
                Spacer(minLength: 0)
                Text(badge)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(c.textTertiary)
                Image(systemName: expanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(c.textTertiary)
            }
            .padding(.horizontal, 12)
            .frame(height: 46)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) { Rectangle().fill(c.line).frame(height: 0.5) }
    }
}

// MARK: - 撤销 Toast（底部，5 秒倒计时）

struct UndoToastView: View {
    @Environment(\.aurora) private var c
    let message: UndoToastMessage
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 15))
                .foregroundStyle(c.success)
            Text(message.text)
                .font(.system(size: 12.5))
                .foregroundStyle(c.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 0)
            Button(action: onUndo) {
                Text("撤销".localized())
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(c.accent)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 13)
        .frame(height: 46)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(c.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(c.line, lineWidth: 0.5)
                )
                .shadow(color: c.shadow, radius: 16, x: 0, y: 6)
        )
        .overlay(alignment: .bottom) {
            TimelineView(.periodic(from: message.createdAt, by: 0.05)) { context in
                let elapsed = context.date.timeIntervalSince(message.createdAt)
                let remain = max(0, 1 - elapsed / message.duration)
                Rectangle()
                    .fill(c.success.opacity(0.8))
                    .frame(height: 2)
                    .scaleEffect(x: max(remain, 0.001), anchor: .leading)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
