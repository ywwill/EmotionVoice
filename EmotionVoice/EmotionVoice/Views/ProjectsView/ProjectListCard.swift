//
//  ProjectListCard.swift
//  EmotionVoice
//
//  历史记录页面使用的音频卡片
//  （类型已从 ProjectListCard 重命名为 AudioListCard，文件保留旧名以便最小化 Xcode 工程变更）
//
//  展示：显示名（可编辑）、时长、格式、创建时间、播放 / 删除。
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
        VStack(alignment: .leading, spacing: 12) {
            header

            Divider().background(AppColor.borderSubtle)

            statsRow

            actions
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColor.bgSecondary)
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.large)
                .stroke(AppColor.borderSubtle, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.large))
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
                            .frame(maxWidth: 260)
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
                            Image(systemName: "pencil")
                                .font(.system(size: 10))
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
                let isPlaying = url.map { player.isPlaying(url: $0) } ?? false
                Button {
                    if isPlaying {
                        AudioPreviewPlayer.shared.stop()
                    } else if let url {
                        AudioPreviewPlayer.shared.play(url: url)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                            .font(.system(size: 11))
                        Text(isPlaying ? "停止".localized() : "播放".localized())
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

    // MARK: - 重命名提交

    private func commitRename() {
        let trimmed = editingName.trimmingCharacters(in: .whitespaces)
        let newDisplay: String? = trimmed.isEmpty ? nil : trimmed
        onRename?(newDisplay)
        isRenaming = false
    }
}
