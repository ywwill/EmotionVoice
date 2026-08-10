//
//  VoiceRow.swift
//  EmotionVoice
//
//  Created: young on 2026/8/8.
//

import SwiftUI

// MARK: - 备选音色行（备选音色卡片中的紧凑行）

struct VoiceRow: View {
    let voice: Voice
    let isSelected: Bool
    let isPlaying: Bool
    let action: () -> Void
    let onPreview: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            // 头像
            AvatarView(text: voice.avatar, size: 28)

            // 名称 / 描述
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(voice.name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppColor.textPrimary)
                        .lineLimit(1)
                    if voice.isPremium {
                        Text("⭐")
                            .font(.system(size: 9))
                    }
                }
                if !voice.desc.isEmpty {
                    Text(voice.desc)
                        .font(AppFont.monoSmall)
                        .foregroundStyle(AppColor.textTertiary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // 试听按钮：图标样式，与 VoiceCard 一致
            Button(action: onPreview) {
                Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                    .font(.system(size: 10))
                    .frame(width: 24, height: 24)
                    .background(
                        isPlaying
                            ? AppColor.accentPrimary.opacity(0.2)
                            : AppColor.bgTertiary
                    )
                    .foregroundStyle(
                        isPlaying ? AppColor.accentPrimary : AppColor.textSecondary
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .contentShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            isSelected ? AppColor.bgTertiary : Color.clear
        )
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.small))
        .contentShape(RoundedRectangle(cornerRadius: AppRadius.small))
        // 整行响应选中：点击行内任意非试听按钮区域都触发 action
        .onTapGesture {
            action()
        }
        .pointingHandCursor()
    }
}
