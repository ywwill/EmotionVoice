//
//  ProjectCard.swift
//  EmotionVoice
//
//  Created: young on 2026/8/8.
//

import SwiftUI

// MARK: - 项目卡

struct ProjectCard: View {

    let project: Project

    var body: some View {
        Button {
            // 进入项目详情
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Text("📁")
                        .font(.system(size: 20))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(project.name)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(AppColor.textPrimary)
                            .lineLimit(1)
                        Text(metaLine)
                            .font(AppFont.monoSmall)
                            .foregroundStyle(AppColor.textTertiary)
                    }
                    Spacer()
                }

                ProgressBar(progress: progress)
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

    private var progress: Double {
        // 演示数据：基于 updatedAt 时间距离
        let days = Date().timeIntervalSince(project.updatedAt) / 86400
        if days < 1 { return 1.0 }
        if days < 3 { return 0.6 }
        if days < 7 { return 0.4 }
        return 0.2
    }

    private var metaLine: String {
        let audios = ProjectService.shared.fetchAudios(projectId: project.id)
        let totalDuration = audios.reduce(0.0) { $0 + $1.duration }
        let minutes = Int(totalDuration / 60)
        if audios.isEmpty {
            return "\(project.updatedAt.shortDateString)"
        }
        let voiceName = VoiceService.shared.fetchAll()
            .first(where: { $0.key == audios.first?.voice })?.name ?? "—"
        return "\(audios.count) 个音频 · \(minutes) 分钟 · \(voiceName)"
    }
}
