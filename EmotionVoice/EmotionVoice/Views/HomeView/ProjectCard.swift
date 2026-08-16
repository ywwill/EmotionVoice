//
//  ProjectCard.swift
//  EmotionVoice
//
//  Created: young on 2026/8/8.
//
//  首页最近音频卡片（历史上名为 ProjectCard，类型已重命名为 AudioCard）。
//

import SwiftUI

// MARK: - 音频卡

struct AudioCard: View {

    let audio: AudioItem

    var body: some View {
        Button {
            // 后续可跳转到音频详情页
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Text("🎧")
                        .font(.system(size: 20))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(audio.shownName)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(AppColor.textPrimary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Text(metaLine)
                            .font(AppFont.monoSmall)
                            .foregroundStyle(AppColor.textTertiary)
                            .lineLimit(1)
                    }
                    Spacer()
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColor.bgSecondary)
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.medium)
                    .stroke(AppColor.borderSubtle, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium))
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
    }

    private var metaLine: String {
        let dur = audio.duration.durationString
        let fmt = (audio.format.isEmpty ? audio.fileExtension : audio.format).uppercased()
        let voiceName = VoiceService.shared.fetchAll()
            .first(where: { $0.key == audio.voice })?.name ?? "—"
        return "\(fmt) · \(dur) · \(voiceName)"
    }
}