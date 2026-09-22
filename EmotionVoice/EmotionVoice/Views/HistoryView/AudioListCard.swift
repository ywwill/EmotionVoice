//
//  ProjectListCard.swift
//  EmotionVoice
//
//  历史记录页面使用的音频卡片
//

import SwiftUI

// MARK: - 音频卡片（历史记录视图）

struct AudioListCard: View {

    let audio: AudioItem
    let onPlay: () -> Void
    let onDelete: () -> Void
    let onRename: ((String?) -> Void)?

    @State private var isRenaming: Bool = false
    @State private var editingName: String = ""
    @ObservedObject private var player = AudioPreviewPlayer.shared

    /// 是否展开播放区域
    @State private var isExpanded: Bool = false

    init(audio: AudioItem,
         onPlay: @escaping () -> Void,
         onDelete: @escaping () -> Void,
         onRename: ((String?) -> Void)? = nil) {
        self.audio = audio
        self.onPlay = onPlay
        self.onDelete = onDelete
        self.onRename = onRename
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            Divider().background(AppColor.borderSubtle)

            statsRow

            Divider().background(AppColor.borderSubtle)

            actions
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColor.bgSecondary)
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.large)
                .stroke(isPlayingThisCard ? AppColor.accentPrimary.opacity(0.5) : AppColor.borderSubtle, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.large))
        .overlay(alignment: .top) {
            if isPlayingThisCard {
                playbackOverlay
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isPlayingThisCard)
        .onTapGesture {
            if isPlayable {
                togglePlayback()
            }
        }
    }

    // MARK: - 子视图

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("🎧")
                .font(.system(size: 22))
            VStack(alignment: .leading, spacing: 4) {
                if isRenaming {
                    HStack(spacing: 6) {
                        TextField("显示名".localized(), text: $editingName)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 14, weight: .semibold))
                            .frame(maxWidth: 200)
                            .onSubmit { commitRename() }
                        Button("保存".localized()) { commitRename() }
                            .buttonStyle(.borderless)
                            .font(AppFont.caption)
                        Button("取消".localized()) {
                            isRenaming = false
                            editingName = audio.shownName.strippingExtension
                        }
                        .buttonStyle(.borderless)
                        .font(AppFont.caption)
                    }
                } else {
                    HStack(spacing: 4) {
                        Text(audio.shownName)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppColor.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button {
                            // 重命名时去掉后缀，避免重复
                            editingName = audio.shownName.strippingExtension
                            isRenaming = true
                        } label: {
                            Image(systemName: "square.and.pencil")
                                .font(.system(size: 14))
                                .foregroundStyle(AppColor.textTertiary)
                        }
                        .buttonStyle(.plain)
                        .pointingHandCursor()
                        .help("重命名".localized())
                    }
                }
                // 第二行：显示时间
                Text(audio.createdAt.shortDateTimeString)
                    .font(AppFont.monoSmall)
                    .foregroundStyle(AppColor.textTertiary)
                    .lineLimit(1)
            }
            Spacer()

            // 展开/收起指示器
            if isPlayable {
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppColor.textTertiary)
                    .padding(.top, 4)
            }
        }
    }

    private var statsRow: some View {
        HStack(spacing: 16) {
            stat(label: "音色".localized(), value: voiceName ?? "—")
            stat(label: "时长".localized(), value: audio.duration.durationString)
            stat(label: "格式".localized(), value: formatBadge)
        }
    }

    private func stat(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(AppFont.label)
                .foregroundStyle(AppColor.textTertiary)
            Text(value)
                .font(AppFont.monoMedium)
                .foregroundStyle(AppColor.textSecondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 播放区域（Overlay 方式，不影响卡片高度）

    private var playbackOverlay: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 音频文本
            if !audio.text.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("📝 音频文本".localized())
                        .font(AppFont.label)
                        .foregroundStyle(AppColor.textTertiary)

                    Text(audio.text)
                        .font(.system(size: 13))
                        .foregroundStyle(AppColor.textSecondary)
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            // 进度条
            VStack(spacing: 6) {
                // 进度滑块
                Slider(value: Binding(
                    get: { player.progress },
                    set: { newValue in
                        let time = newValue * player.duration
                        player.seek(to: time)
                    }
                ), in: 0...1)
                .tint(AppColor.accentPrimary)

                // 时间显示
                HStack {
                    Text(formatTime(player.currentTime))
                        .font(AppFont.monoSmall)
                        .foregroundStyle(AppColor.textTertiary)

                    Spacer()

                    Text(formatTime(player.duration))
                        .font(AppFont.monoSmall)
                        .foregroundStyle(AppColor.textTertiary)
                }
            }

            // 倍速选择器
            HStack(spacing: 8) {
                Text("倍速".localized())
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textTertiary)

                ForEach(AudioPreviewPlayer.playbackRateOptions, id: \.rate) { option in
                    Button {
                        player.setPlaybackRate(option.rate)
                    } label: {
                        Text(option.label)
                            .font(.system(size: 12, weight: player.playbackRate == option.rate ? .semibold : .regular))
                            .foregroundStyle(player.playbackRate == option.rate ? .white : AppColor.textSecondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                player.playbackRate == option.rate
                                    ? AppColor.accentPrimary
                                    : AppColor.bgTertiary
                            )
                            .clipShape(RoundedRectangle(cornerRadius: AppRadius.small))
                    }
                    .buttonStyle(.plain)
                }

                Spacer()
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.medium)
                .fill(AppColor.bgElevated)
                .shadow(color: .black.opacity(0.15), radius: 8, x: 0, y: 4)
        )
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: - 操作按钮

    private var actions: some View {
        HStack(spacing: 8) {
            Spacer()

            // 删除
            Button {
                onDelete()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                    Text("删除".localized())
                        .font(AppFont.caption)
                }
                .foregroundStyle(AppColor.textSecondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(AppColor.bgTertiary)
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.small)
                        .stroke(AppColor.borderSubtle, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.small))
            }
            .buttonStyle(.plain)
            .pointingHandCursor()

            // 播放 / 停止
            if isPlayable {
                let url = audioURL
                Button {
                    togglePlayback()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: isPlayingThisCard ? "stop.fill" : "play.fill")
                            .font(.system(size: 11))
                        Text(isPlayingThisCard ? "停止".localized() : "播放".localized())
                            .font(AppFont.caption)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 5)
                    .background(
                        LinearGradient(
                            colors: [AppColor.accentPrimary, AppColor.accentSecondary],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.small))
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "play.slash")
                        .font(.system(size: 11))
                    Text("暂无音频".localized())
                        .font(AppFont.caption)
                }
                .foregroundStyle(AppColor.textTertiary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(AppColor.bgTertiary)
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.small)
                        .stroke(AppColor.borderSubtle, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.small))
            }
        }
    }

    // MARK: - 计算属性

    private var formatBadge: String {
        let raw = audio.format.isEmpty ? audio.fileExtension : audio.format
        return raw.uppercased()
    }

    private var voiceName: String? {
        let key = audio.voice
        guard !key.isEmpty else { return nil }
        return VoiceService.shared.fetchAll()
            .first(where: { $0.key == key })?.name
    }

    private var audioURL: URL? {
        audio.absoluteURL
    }

    private var isPlayable: Bool {
        audio.status == .completed && audio.isOnDisk
    }

    private var isPlayingThisCard: Bool {
        guard let url = audioURL else { return false }
        return player.isPlaying(url: url)
    }

    // MARK: - 辅助方法

    private func togglePlayback() {
        guard let url = audioURL else { return }

        if isPlayingThisCard {
            player.stop()
            isExpanded = false
        } else {
            player.play(url: url)
            isExpanded = true
        }
    }

    private func formatTime(_ time: Double) -> String {
        guard !time.isNaN && time.isFinite else { return "0:00" }
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    // MARK: - 重命名提交

    private func commitRename() {
        let trimmed = editingName.trimmingCharacters(in: .whitespaces)
        let newDisplay: String? = trimmed.isEmpty ? nil : trimmed
        onRename?(newDisplay)
        isRenaming = false
    }
}
