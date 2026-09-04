//
//  VoiceCard.swift
//  EmotionVoice
//
//  Created by young on 2026/8/8.
//
//  音色卡片（已优化）：

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

// MARK: - 音色卡片

struct VoiceCard: View {

    let item: VoiceCardItem
    let isSelected: Bool
    let isPlaying: Bool
    var isFeatured: Bool = false
    let onFavorite: () -> Void
    let onPreview: () -> Void
    let onUse: () -> Void

    @State private var isHovered: Bool = false

    // Equatable 让 SwiftUI 在 item / 选中 / 播放状态未变化时跳过 body 重算
    static func == (lhs: VoiceCard, rhs: VoiceCard) -> Bool {
        lhs.item == rhs.item
            && lhs.isSelected == rhs.isSelected
            && lhs.isPlaying == rhs.isPlaying
            && lhs.isFeatured == rhs.isFeatured
    }

    var body: some View {
        cardContent
            .padding(14)
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

            // 名称 + 描述
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppColor.textPrimary)
                    .lineLimit(1)
            }

            actionRow
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // 背景层：仅在该层做动画，不传播到卡片内容（避免滚动时 hover 抖动重绘文字）
    private var cardBackground: some View {
        Group {
            if isFeatured {
                // 旗舰音色采用琥珀色微渐变，呼应 voices.html 的 .voice-card.featured
                LinearGradient(
                    colors: [
                        AppColor.bgSecondary,
                        AppColor.accentPrimary.opacity(isSelected || isHovered ? 0.08 : 0.04)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            } else if isSelected || isHovered {
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
                          : (isHovered ? AppColor.borderMedium
                                       : (isFeatured ? AppColor.accentPrimary.opacity(0.25)
                                                     : AppColor.borderSubtle)),
                lineWidth: 1
            )
            .animation(.easeInOut(duration: 0.15), value: isHovered)
            .animation(.easeInOut(duration: 0.15), value: isSelected)
    }

    // MARK: - 子视图（轻量化）

    private var header: some View {
        HStack(alignment: .top) {
            AvatarView(text: item.avatar, size: 40)
            Spacer()
            VStack(alignment: .trailing) {
                if item.isPremium {
                    Text("⭐ 旗舰".localized())
                        .font(AppFont.monoSmall)
                        .foregroundStyle(AppColor.accentGlow)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(AppColor.accentPrimary.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
                
                if !item.scene.isEmpty || item.age != nil || !item.gender.isEmpty {
                    metaTags
                }
                
                Text(item.desc)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
                    .lineLimit(2)
            }
        }
    }

    private var metaTags: some View {
        HStack(spacing: 6) {
            
            Spacer()
            
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
                HStack() {
                    Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                        .font(.system(size: 11))
                        .contentTransition(.symbolEffect(.replace))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(
                    isPlaying
                    ? AppColor.emotionHappy.opacity(0.22)
                    : Color.clear
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(
                            isPlaying
                            ? AppColor.emotionHappy.opacity(0.6)
                            : AppColor.borderMedium,
                            lineWidth: 1
                        )
                )
                .foregroundStyle(
                    isPlaying ? AppColor.emotionHappy : AppColor.textSecondary
                )
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .animation(.easeInOut(duration: 0.2), value: isPlaying)
            .buttonStyle(.plain)
            .pointingHandCursor()

            Button(action: onFavorite) {
                Image(systemName: item.isFavorite ? "heart.fill" : "heart")
                    .font(.system(size: 12))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        item.isFavorite ? AppColor.accentPrimary.opacity(0.2) : Color.clear
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(
                                item.isFavorite
                                ? AppColor.accentPrimary.opacity(0.6)
                                : AppColor.borderMedium,
                                lineWidth: 1
                            )
                    )
                    .foregroundStyle(
                        item.isFavorite ? AppColor.accentPrimary : AppColor.textSecondary
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
            .pointingHandCursor()

            Spacer()
            
            // 播放波形（仅播放时展示，替代静态预览按钮位置）
            if isPlaying {
                playingWaveform
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            
            Spacer()

            Button(action: onUse) {
                Label("使用".localized(), systemImage: "arrow.right.circle.fill")
                    .font(.system(size: 11, weight: .medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(AppColor.accentPrimary)
                    .foregroundStyle(AppColor.bgPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .contentShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(StaticButtonStyle())
            .pointingHandCursor()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 播放波形

    /// 10 条柱状波形，播放时高低随机抖动；非播放时不渲染（避免抢空间）
    private var playingWaveform: some View {
        PlayingWaveform()
            .frame(height: 18)
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

// MARK: - 播放波形

private struct PlayingWaveform: View {
    private let barCount: Int = 12
    private let heights: [CGFloat] = [0.4, 0.65, 0.85, 0.5, 0.95, 0.7, 0.4, 0.8, 0.55, 0.9, 0.6, 0.45]

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(0..<barCount, id: \.self) { i in
                PlayingWaveBar(
                    baseHeight: heights[i % heights.count],
                    delay: Double(i) * 0.07
                )
            }
        }
    }
}

private struct PlayingWaveBar: View {
    let baseHeight: CGFloat
    let delay: Double

    @State private var animating: Bool = false

    var body: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(AppColor.accentPrimary)
            .frame(width: 2, height: max(4, 18 * baseHeight))
            .scaleEffect(y: animating ? 1.0 : baseHeight, anchor: .center)
            .onAppear {
                withAnimation(
                    .easeInOut(duration: 0.55)
                    .repeatForever(autoreverses: true)
                    .delay(delay)
                ) {
                    animating.toggle()
                }
            }
    }
}
