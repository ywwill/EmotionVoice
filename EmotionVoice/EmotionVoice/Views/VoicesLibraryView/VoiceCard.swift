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
//  - 波形条用共享的静态 gradient 引用，避免每张卡片每帧新建
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
    static let waveformGradient = LinearGradient(
        colors: [AppColor.accentPrimary.opacity(0.5), AppColor.accentGlow.opacity(0.7)],
        startPoint: .bottom, endPoint: .top
    )
    static let waveformHeights: [CGFloat] = [8, 12, 16, 20, 24].map { $0 - 8 + 8 }  // 8 + (i%5)*4
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

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
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

            waveform
            actionRow
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            isSelected ? AppColor.bgSecondary : (isHovered ? AppColor.bgTertiary : AppColor.bgSecondary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.medium)
                .stroke(
                    isSelected ? AppColor.accentPrimary.opacity(0.5)
                              : (isHovered ? AppColor.borderMedium : AppColor.borderSubtle),
                    lineWidth: 1
                )
        )
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
        // 只在背景/边框层加 hover 动画，去掉全卡 scaleEffect + shadow
        .animation(.easeInOut(duration: 0.15), value: isHovered)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
        .onHover { hovering in
            isHovered = hovering
        }
        .pointingHandCursor()
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
            if let age = item.age {
                Text("\(age) 岁")
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
    }

    private var waveform: some View {
        HStack(spacing: 2) {
            ForEach(0..<12, id: \.self) { i in
                Capsule()
                    .fill(CardStyle.waveformGradient)
                    .frame(width: 3, height: CardStyle.waveformHeights[i % 5])
            }
        }
        .frame(height: 28)
        // 波形是纯装饰，独立 layer 化，避免后续 hover 触发布局失效
        .drawingGroup()
    }

    private var actionRow: some View {
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

            Button(action: onFavorite) {
                Image(systemName: item.isFavorite ? "heart.fill" : "heart")
                    .font(.system(size: 12))
                    .padding(.horizontal, 10)
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
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(AppColor.accentPrimary)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .contentShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(StaticButtonStyle())
            .fixedSize()
        }
    }

    private func sceneTag(_ scene: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: "tag.fill")
                .font(.system(size: 8, weight: .semibold))
            Text(scene)
                .font(.system(size: 10, weight: .medium))
                .lineLimit(1)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(AppColor.bgTertiary)
        .foregroundStyle(AppColor.textSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}
