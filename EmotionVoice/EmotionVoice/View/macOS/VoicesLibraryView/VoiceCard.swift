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
    /// 当前语言下的音色名
    let name: String
    /// 当前语言下的特质描述
    let desc: String
    /// 当前语言下的头像字
    let avatar: String
    /// 场景（展示时取 scene.displayName）
    let scene: VoiceSceneCode
    let age: Int?
    /// 当前语言下的性别
    let gender: String
    let isFavorite: Bool
    let isPremium: Bool

    init(voice: Voice) {
        self.id = voice.key
        self.name = voice.localizedName
        self.desc = voice.localizedDesc
        self.avatar = voice.localizedAvatar
        self.scene = voice.scene
        self.age = voice.age
        self.gender = voice.localizedGender
        self.isFavorite = voice.isFavorite
        self.isPremium = voice.isPremium
    }
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
            .padding(14)
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium))
            .shadow(
                color: isSelected ? AppColor.accentPrimary.opacity(0.2) : Color.black.opacity(0.05),
                radius: isSelected ? 8 : 4,
                x: 0,
                y: isSelected ? 4 : 2
            )
            .overlay(alignment: .topTrailing) {
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(AppColor.accentPrimary)
                        .font(.system(size: 16))
                        .background(
                            Circle()
                                .fill(AppColor.bgSecondary)
                                .frame(width: 18, height: 18)
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

            // 名称 + 年龄 / 性别（meta 标签右对齐到名称同一行）
            nameRow

            actionRow
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // 背景层：所有卡片（普通 / 旗舰）统一采用琥珀色微渐变，
    // 仅在该层做动画，不传播到卡片内容（避免滚动时 hover 抖动重绘文字）
    private var cardBackground: some View {
        LinearGradient(
            colors: [
                AppColor.bgSecondary,
                AppColor.accentPrimary.opacity(isSelected || isHovered ? 0.08 : 0.04)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
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
                Text(item.desc)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.trailing)
            }
        }
    }

    /// 名称行：左侧音色名，右侧年龄 / 性别标签
    private var nameRow: some View {
        HStack(spacing: 6) {
            Text(item.name)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppColor.textPrimary)
                .lineLimit(1)

            Spacer(minLength: 6)

            // fixedSize：窄卡片时优先截断名称，保证 meta 标签不被压缩
            metaTags
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    /// 年龄 / 性别标签（与名称同一行，右对齐）
    private var metaTags: some View {
        HStack(spacing: 6) {
            if let age = item.age {
                metaTag("%d 岁".localized(age))
            }
            if !item.gender.isEmpty {
                metaTag(item.gender)
            }
        }
    }

    private func metaTag(_ text: String) -> some View {
        Text(text)
            .font(AppFont.monoSmall)
            .foregroundStyle(AppColor.textTertiary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(AppColor.bgTertiary)
            .clipShape(RoundedRectangle(cornerRadius: 4))
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
                .contentShape(Rectangle())
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
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("收藏")
            .pointingHandCursor()

            Spacer()

            // 播放波形：始终占位，仅在播放时可见。
            // 这样 isPlaying 切换时不会插入/移除视图，整个 VoiceCard 的 frame 完全不变。
            playingWaveform
                .frame(maxWidth: .infinity, alignment: .leading)
                .opacity(isPlaying ? 1 : 0)
                .allowsHitTesting(false)

            Spacer()

            Button(action: onUse) {
                Image(systemName: "arrow.right.circle.fill")
                    .font(.system(size: 16))
                    .padding(6)
                    .background(AppColor.accentPrimary)
                    .foregroundStyle(AppColor.bgPrimary)
                    .clipShape(Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("点击使用")
            .pointingHandCursor()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 播放波形

    /// 12 条柱状波形，播放时高低随机抖动。
    /// 视图本身始终渲染，由调用方用 opacity 控制可见性，
    /// 以保证 isPlaying 切换时整个 VoiceCard 的 frame 不变。
    private var playingWaveform: some View {
        PlayingWaveform()
            .frame(height: 18)
    }

    private func sceneTag(_ scene: VoiceSceneCode) -> some View {
        HStack(spacing: 3) {
            Image(systemName: "tag.fill")
                .font(.system(size: 8, weight: .semibold))
            Text(scene.displayName)
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

// MARK: - 骨架屏卡片

/// 单块占位（灰底圆角矩形）；宽度传 nil 时按容器宽度自适应（用于整行描述条）。
/// 非 private：分页栏骨架等非卡片场景也要复用同一占位样式。
struct SkeletonBlock: View {
    var width: CGFloat?
    var height: CGFloat
    var radius: CGFloat = 4

    var body: some View {
        RoundedRectangle(cornerRadius: radius)
            .fill(AppColor.bgTertiary)
            .frame(width: width, height: height)
    }
}

/// 音色卡片骨架：**直接复用真实 VoiceCard 的布局**，用占位数据 + `.redacted(reason: .placeholder)`
/// 把内部文本 / 图标渲染成灰块，再叠一层扫光。
/// 这样尺寸由 SwiftUI 保证与真实卡片一致（占位块 frame = 原文本 frame），
/// 不必手写 SkeletonBlock 去猜字号行高，加载完成时不会出现行高跳动。
struct VoiceCardSkeleton: View {
    /// 扫光相位：从 -0.6 平移到 1.6，形成一次完整的横向扫过。
    @State private var shimmerPhase: CGFloat = -0.6

    var body: some View {
        VoiceCard(
            item: Self.placeholderItem,
            isSelected: false,
            // isPlaying = false：波形不可见，骨架不会露出彩色波形条
            isPlaying: false,
            onFavorite: {},
            onPreview: {},
            onUse: {}
        )
        // 先禁用交互（屏蔽 hover / 点击 / 手型光标），再 redact，
        // 最后叠扫光（overlay 在 redacted 之外，不会被一起灰化）
        .allowsHitTesting(false)
        .redacted(reason: .placeholder)
        .overlay(shimmerOverlay)
    }

    /// 骨架占位数据：按真实音色的**最常见形态**取值——
    /// 名字 4 字、特质 4 字（均单行，与真实 catalog 文案长度一致）、
    /// 带年龄 + 性别两个 meta 标签、旗舰标记，
    /// 使骨架高度与真实卡片一致，切换到真实数据时不发生行高跳动。
    private static let placeholderItem = VoiceCardItem(voice: Voice(
        key: "__skeleton__",
        name: "音色名称",
        nameEn: "Voice",
        desc: "特质描述",
        descEn: "Trait",
        tier: .premium,
        isFavorite: false,
        scene: .daily,
        age: 26,
        gender: .female
    ))

    /// 横向扫光：一条半透明高光带在卡片内平移（普通 alpha 合成，不走离屏混合）。
    private var shimmerOverlay: some View {
        GeometryReader { geo in
            let w = geo.size.width
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0),
                            Color.white.opacity(0.12),
                            Color.white.opacity(0)
                        ],
                        startPoint: .init(x: 0, y: 0),
                        endPoint: .init(x: 1, y: 0)
                    )
                )
                .frame(width: w * 0.5)
                .offset(x: shimmerPhase * w)
                // 不用 .blendMode(.screen)：混合模式会让每张骨架卡单独走一次离屏合成，
                // 20 张同时扫光时逐帧开销显著，切开页面时能吃掉侧边栏滑动动画的帧。
                // 暗色底上普通 alpha 合成的观感几乎一致。
                .animation(
                    .linear(duration: 1.3).repeatForever(autoreverses: false),
                    value: shimmerPhase
                )
        }
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium))
        .allowsHitTesting(false)
        .onAppear {
            shimmerPhase = 1.6
        }
    }
}
