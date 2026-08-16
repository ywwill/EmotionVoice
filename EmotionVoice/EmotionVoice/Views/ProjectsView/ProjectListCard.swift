//
//  ProjectListCard.swift
//  EmotionVoice
//
//  "所有项目" 页面使用的项目卡片
//  与 HomeView 的 ProjectCard（用于最近项目）解耦，独立支持播放 / 删除 / 跳转
//

import SwiftUI

// MARK: - 项目卡（所有项目视图）

struct ProjectListCard: View {

    let project: Project
    let onPlay: () -> Void
    let onDelete: () -> Void

    @State private var audios: [AudioItem] = []
    @ObservedObject private var player = AudioPreviewPlayer.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            Divider().background(AppColor.borderSubtle)

            statsRow

            if !audios.isEmpty {
                latestAudioRow
            }

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
        .onAppear { reload() }
    }

    // MARK: - 子视图

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(folderIcon)
                .font(.system(size: 22))
            VStack(alignment: .leading, spacing: 4) {
                Text(project.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppColor.textPrimary)
                    .lineLimit(1)
                Text(project.updatedAt.shortDateString)
                    .font(AppFont.monoSmall)
                    .foregroundStyle(AppColor.textTertiary)
            }
            Spacer()
            if let folder = project.folder {
                Text(folder.rawValue)
                    .font(AppFont.label)
                    .foregroundStyle(AppColor.accentPrimary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(AppColor.accentPrimary.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
    }

    private var statsRow: some View {
        HStack(spacing: 16) {
            stat(label: "音频", value: "\(audios.count)")
            stat(label: "时长", value: durationLabel)
            stat(label: "积分", value: "\(audios.reduce(0) { $0 + $1.pointsCost })")
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var latestAudioRow: some View {
        let latest = audios.first
        if let latest {
            HStack(spacing: 8) {
                Image(systemName: "waveform")
                    .font(.system(size: 11))
                    .foregroundStyle(AppColor.accentPrimary)
                Text(latest.title)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
                    .lineLimit(1)
                Spacer()
                Text(latest.duration.durationString)
                    .font(AppFont.monoSmall)
                    .foregroundStyle(AppColor.textTertiary)
            }
        }
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
            if let audioToPlay = currentPlayableAudio() {
                let url = audioURL(from: audioToPlay)
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
                // 无可播放音频时只展示空状态
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

    private var folderIcon: String {
        project.folder?.icon ?? "📁"
    }

    private var durationLabel: String {
        let total = audios.reduce(0.0) { $0 + $1.duration }
        if total == 0 { return "--" }
        return total.durationString
    }

    /// 用于播放的首条已完成音频
    private func currentPlayableAudio() -> AudioItem? {
        audios.first { $0.status == .completed && ($0.filePath?.isEmpty == false) }
    }

    private func audioURL(from audio: AudioItem) -> URL? {
        guard let p = audio.filePath, !p.isEmpty else { return nil }
        return URL(fileURLWithPath: p)
    }

    private func reload() {
        audios = ProjectService.shared.fetchAudios(projectId: project.id)
    }
}