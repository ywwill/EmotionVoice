//
//  HistoryRowViews.swift
//  iOSEmora
//
//  历史记录行卡片：进度条 / 行本体 / 状态胶囊 / 骨架行。
//  从 HistoryComponents.swift 拆出：代码逐字搬移，未改动任何逻辑（原 private 类型按需放开为 internal）。
//

import SwiftUI
import Combine

// MARK: - 行卡片

/// 只有「正在播放」那一行会挂这个订阅：10Hz 进度只重算这一条 2pt 渐变条，
/// 不牵动整行 / 整个列表（macOS `VoiceRowPlayback` 同款订阅下沉）。
struct RowProgressTrack: View {
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
