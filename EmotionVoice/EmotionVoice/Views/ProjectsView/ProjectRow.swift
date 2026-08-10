//
//  ProjectRow.swift
//  EmotionVoice
//
//  Created: young on 2026/8/8.
//

import SwiftUI

// MARK: - 项目行

struct ProjectRow: View {

    let project: Project
    @State private var audios: [AudioItem] = []
    @State private var isExpanded: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Text("📄")
                    .font(.system(size: 18))

                VStack(alignment: .leading, spacing: 2) {
                    Text(project.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppColor.textPrimary)
                    Text(audioMetaLine)
                        .font(AppFont.monoSmall)
                        .foregroundStyle(AppColor.textTertiary)
                }

                Spacer()

                Text(durationLabel)
                    .font(AppFont.monoMedium)
                    .foregroundStyle(AppColor.textSecondary)
                    .frame(width: 60, alignment: .trailing)

                Text(voiceName)
                    .font(AppFont.monoSmall)
                    .foregroundStyle(AppColor.textTertiary)
                    .frame(width: 100, alignment: .leading)

                Text(project.updatedAt.shortDateString)
                    .font(AppFont.monoSmall)
                    .foregroundStyle(AppColor.textTertiary)
                    .frame(width: 90, alignment: .leading)

                StatusBadge(text: statusText, color: statusColor)
                    .frame(width: 70)

                HStack(spacing: 6) {
                    Button {
                        // 播放
                    } label: {
                        Image(systemName: "play.circle")
                            .font(.system(size: 14))
                            .foregroundStyle(AppColor.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .pointingHandCursor()
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            isExpanded.toggle()
                        }
                    } label: {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 12))
                            .foregroundStyle(AppColor.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .pointingHandCursor()
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            if isExpanded && !audios.isEmpty {
                Divider()
                    .background(AppColor.borderSubtle)
                VStack(spacing: 0) {
                    ForEach(audios.prefix(3)) { audio in
                        audioDetailRow(audio)
                        if audio.id != audios.prefix(3).last?.id {
                            Divider()
                                .background(AppColor.borderSubtle.opacity(0.5))
                                .padding(.horizontal, 16)
                        }
                    }
                }
            }
        }
        .onAppear {
            audios = ProjectService.shared.fetchAudios(projectId: project.id)
        }
    }

    private var durationLabel: String {
        let total = audios.reduce(0.0) { $0 + $1.duration }
        if total == 0 { return "--" }
        return total.durationString
    }

    private var voiceName: String {
        if let voice = audios.first?.voice,
           let v = VoiceService.shared.fetchAll().first(where: { $0.key == voice }) {
            return v.name
        }
        return "--"
    }

    private var audioMetaLine: String {
        if audios.isEmpty {
            return "未生成".localized()
        }
        let totalChars = audios.reduce(0) { $0 + $1.text.count }
        let totalPoints = audios.reduce(0) { $0 + $1.pointsCost }
        return "\(audios.count) 个音频 · \(totalChars) 字 · \(totalPoints) 积分".localized()
    }

    private var statusText: String {
        if audios.isEmpty { return "待处理".localized() }
        return "已完成".localized()
    }

    private var statusColor: Color {
        if audios.isEmpty { return AppColor.statusInfo }
        return AppColor.statusSuccess
    }

    private func audioDetailRow(_ audio: AudioItem) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "waveform")
                .font(.system(size: 11))
                .foregroundStyle(AppColor.accentPrimary)
            Text(audio.title)
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
            Spacer()
            Text(audio.duration.durationString)
                .font(AppFont.monoSmall)
                .foregroundStyle(AppColor.textTertiary)
            Text("\(audio.pointsCost) 积分".localized())
                .font(AppFont.monoSmall)
                .foregroundStyle(AppColor.accentPrimary)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
    }
}
