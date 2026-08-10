//
//  VoiceCard.swift
//  EmotionVoice
//
//  Created by young on 2026/8/8.
//

import SwiftUI

// MARK: - 音色卡片

struct VoiceCard: View {

    let voice: Voice
    let isSelected: Bool
    let isPlaying: Bool
    let onFavorite: () -> Void
    let onPreview: () -> Void
    let onUse: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                AvatarView(text: voice.avatar, size: 40)
                Spacer()
                if voice.isPremium {
                    Text("⭐ 旗舰".localized())
                        .font(AppFont.monoSmall)
                        .foregroundStyle(AppColor.accentGlow)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(AppColor.accentPrimary.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(voice.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppColor.textPrimary)
                Text(voice.desc)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
            }

            // 适用场景标签 + 年龄小标
            if !voice.scene.isEmpty || voice.age != nil {
                HStack(spacing: 6) {
                    if !voice.scene.isEmpty {
                        sceneTag(voice.scene)
                    }
                    if let age = voice.age {
                        Text("\(age) 岁")
                            .font(AppFont.monoSmall)
                            .foregroundStyle(AppColor.textTertiary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AppColor.bgTertiary)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    if !voice.gender.isEmpty {
                        Text(voice.gender)
                            .font(AppFont.monoSmall)
                            .foregroundStyle(AppColor.textTertiary)
                    }
                }
            }

            // 简易波形
            HStack(spacing: 2) {
                ForEach(0..<12, id: \.self) { i in
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [AppColor.accentPrimary.opacity(0.5), AppColor.accentGlow.opacity(0.7)],
                                startPoint: .bottom, endPoint: .top
                            )
                        )
                        .frame(width: 3, height: CGFloat(8 + (i % 5) * 4))
                }
            }
            .frame(height: 28)

            HStack(spacing: 6) {
                Button(action: onPreview) {
                    Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                        .font(.system(size: 12))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(isPlaying ? AppColor.accentPrimary.opacity(0.2) : AppColor.bgTertiary)
                        .foregroundStyle(isPlaying ? AppColor.accentPrimary : AppColor.textSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .pointingHandCursor()

                Button(action: onFavorite) {
                    Image(systemName: voice.isFavorite ? "heart.fill" : "heart")
                        .font(.system(size: 12))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            voice.isFavorite
                            ? AppColor.accentPrimary.opacity(0.2)
                            : AppColor.bgTertiary
                        )
                        .foregroundStyle(
                            voice.isFavorite ? AppColor.accentPrimary : AppColor.textSecondary
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .pointingHandCursor()

                Spacer()

                // 使用按钮 - 跳转到语音合成
                Button(action: onUse) {
                    Label("使用".localized(), systemImage: "arrow.right.circle.fill")
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(AppColor.accentPrimary)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .contentShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(StaticButtonStyle())
                .fixedSize()
                .pointingHandCursor()
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            isSelected
                ? AppColor.bgSecondary
                : (isHovered ? AppColor.bgTertiary : AppColor.bgSecondary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.medium)
                .stroke(
                    isSelected
                        ? AppColor.accentPrimary.opacity(0.5)
                        : (isHovered ? AppColor.borderMedium : AppColor.borderSubtle),
                    lineWidth: 1
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium))
        .overlay(alignment: .topTrailing) {
            // 选中标识：固定在卡片右上角，不挤压布局
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(AppColor.accentPrimary)
                    .font(.system(size: 14))
                    .background(
                        Circle()
                            .fill(AppColor.bgSecondary)
                            .frame(width: 16, height: 16)
                    )
                    .offset(x: 6, y: -6)
                    .allowsHitTesting(false)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .scaleEffect(isHovered ? 1.015 : 1.0)
        .shadow(
            color: isHovered ? AppColor.accentPrimary.opacity(0.15) : .clear,
            radius: isHovered ? 8 : 0,
            x: 0,
            y: isHovered ? 4 : 0
        )
        .animation(.easeInOut(duration: 0.18), value: isHovered)
        .animation(.easeInOut(duration: 0.18), value: isSelected)
        .onHover { hovering in
            isHovered = hovering
        }
        .pointingHandCursor()
    }

    private func sceneTag(_ scene: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: "tag.fill")
                .font(.system(size: 8, weight: .semibold))
            Text(scene)
                .font(.system(size: 10, weight: .medium))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(AppColor.bgTertiary)
        .foregroundStyle(AppColor.textSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}
