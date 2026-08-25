//
//  VoiceCard.swift
//  EmotionVoice
//
//  Created by young on 2026/8/8.
//
//  音色卡片（已优化）：
//  - 用 Identifiable VO 传递数据，body 内不再读取外部 observable
//  - hover/选中的动画仅作用于背景/边框层；不触发 scaleEffect/shadow 全树重绘
//  - pointingHandCursor 仅在卡片根层一次性绑定，不再每行按钮重复 push/pop
//  - desc 中已包含年龄时，metaTags 不再重复显示年龄
//

import SwiftUI

// MARK: - 卡片输入 VO（避免父视图传入的可比较 Voice 影响 SwiftUI diff）

struct VoiceCardItem: Identifiable, Equatable {
    let id: String           // voice.key
    let name: String
    let desc: String
    let avatar: String
    let scene: String
    let age: Int?
    let gender: String
    let isFavorite: Bool
    let isPremium: Bool

    init(voice: Voice) {
        self.id = voice.key
        self.name = voice.name
        self.desc = voice.desc
        self.avatar = voice.avatar
        self.scene = voice.scene
        self.age = voice.age
        self.gender = voice.gender
        self.isFavorite = voice.isFavorite
        self.isPremium = voice.isPremium
    }
}

// MARK: - 共享静态资源

private enum CardStyle {
    // 为未来可能的功能保留（如需要可重新启用）
}

// MARK: - 音色卡片

struct VoiceCard: View {

    let item: VoiceCardItem
    let isSelected: Bool
    let isPlaying: Bool
    let onFavorite: () -> Void
    let onPreview: () -> Void
    let onUse: () -> Void

    @State private var isHovered: Bool = false

    // Equatable 让 SwiftUI 在 item / 选中 / 播放状态未变化时跳过 body 重算
    static func == (lhs: VoiceCard, rhs: VoiceCard) -> Bool {
        lhs.item == rhs.item
            && lhs.isSelected == rhs.isSelected
            && lhs.isPlaying == rhs.isPlaying
    }

    var body: some View {
        cardContent
            .padding(12)
            .background(cardBackground)
            .overlay(cardBorder)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium))
            .overlay(alignment: .topTrailing) {
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
            .onHover { hovering in
                // 仅在状态真正变化时触发，避免鼠标移动过程中反复触发 body
                if hovering != isHovered {
                    isHovered = hovering
                }
            }
            .pointingHandCursor()
    }

    // MARK: - 内容（独立可复用 body）

    private var cardContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppColor.textPrimary)
                    .lineLimit(1)
                Text(item.desc)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
                    .lineLimit(2)
            }

            if !item.scene.isEmpty || item.age != nil || !item.gender.isEmpty {
                metaTags
            }

            actionRow
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // 背景层：仅在该层做动画，不传播到卡片内容（避免滚动时 hover 抖动重绘文字）
    private var cardBackground: some View {
        Group {
            if isSelected || isHovered {
                AppColor.bgTertiary
            } else {
                AppColor.bgSecondary
            }
        }
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }

    // 边框层：同上，动画只作用于描边
    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: AppRadius.medium)
            .stroke(
                isSelected ? AppColor.accentPrimary.opacity(0.5)
                          : (isHovered ? AppColor.borderMedium : AppColor.borderSubtle),
                lineWidth: 1
            )
            .animation(.easeInOut(duration: 0.15), value: isHovered)
            .animation(.easeInOut(duration: 0.15), value: isSelected)
    }

    // MARK: - 子视图（轻量化）

    private var header: some View {
        HStack {
            AvatarView(text: item.avatar, size: 40)
            Spacer()
            if item.isPremium {
                Text("⭐ 旗舰".localized())
                    .font(AppFont.monoSmall)
                    .foregroundStyle(AppColor.accentGlow)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(AppColor.accentPrimary.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
    }

    private var metaTags: some View {
        HStack(spacing: 6) {
            if !item.scene.isEmpty {
                sceneTag(item.scene)
            }
            // desc 中已包含年龄的（如旗舰音色），不再重复显示
            if item.age != nil && !item.desc.contains("岁") {
                Text("\(item.age!) 岁")
                    .font(AppFont.monoSmall)
                    .foregroundStyle(AppColor.textTertiary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(AppColor.bgTertiary)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            if !item.gender.isEmpty {
                Text(item.gender)
                    .font(AppFont.monoSmall)
                    .foregroundStyle(AppColor.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var actionRow: some View {
        HStack(spacing: 6) {
            Button(action: onPreview) {
                Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                    .font(.system(size: 12))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(isPlaying ? AppColor.accentPrimary.opacity(0.2) : AppColor.bgTertiary)
                    .foregroundStyle(isPlaying ? AppColor.accentPrimary : AppColor.textSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)

            Button(action: onFavorite) {
                Image(systemName: item.isFavorite ? "heart.fill" : "heart")
                    .font(.system(size: 12))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        item.isFavorite ? AppColor.accentPrimary.opacity(0.2) : AppColor.bgTertiary
                    )
                    .foregroundStyle(
                        item.isFavorite ? AppColor.accentPrimary : AppColor.textSecondary
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)

            Spacer()

            Button(action: onUse) {
                Label("使用".localized(), systemImage: "arrow.right.circle.fill")
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(AppColor.accentPrimary)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .contentShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(StaticButtonStyle())
        }
        .frame(maxWidth: .infinity)
    }

    private func sceneTag(_ scene: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: "tag.fill")
                .font(.system(size: 8, weight: .semibold))
            Text(scene)
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(AppColor.bgTertiary)
        .foregroundStyle(AppColor.textSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .frame(maxWidth: 110)
    }
}
