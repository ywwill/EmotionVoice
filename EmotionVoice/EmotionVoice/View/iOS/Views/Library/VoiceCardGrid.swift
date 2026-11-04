//
//  VoiceCardGrid.swift
//  iOSEmora
//
//  音色卡片（照 macOS `VoiceCard` 的字段，重排成手机两列网格）
//
//  字段顺序：头像 + 旗舰徽章（或右上特质）→ 名称 → 2 行特质 → 年龄 / 性别 meta
//  → 试听 / 收藏 / 使用。
//  试听中的卡片整张转强调描边 + 投影，与 macOS 的 hover 高亮等价（iOS 没有 hover）。
//

import SwiftUI

struct VoiceCardGrid: View {
    @Environment(\.aurora) private var c
    @Environment(\.screenMetrics) private var metrics

    let voice: Voice
    /// 是否正在试听这张卡的预览音频
    let isPreviewing: Bool
    /// 试听
    let onPreview: () -> Void
    /// 收藏 / 取消收藏
    let onFavorite: () -> Void
    /// 使用该音色（回创作页）
    let onUse: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerRow
            nameBlock
            metaRow
            actionRow
        }
        .padding(12)
        .background { cardBackground }
        .contentShape(Rectangle())
        // ⚠️ 试听态的描边 / 投影要渐变，硬切会让人以为点错了卡。
        //    用 `value:` 限定只在这一个布尔变化时动画：不带 `value` 的 `.animation`
        //    会把卡片里所有属性变化（含 LazyVGrid 复用时的重排）都变成动画。
        .animation(.easeOut(duration: 0.18), value: isPreviewing)
    }

    // MARK: 卡片背景

    /// 旗舰卡用品牌紫→玫瑰渐变打底，右上角只留一层极淡的暖金柔光做氛围，
    /// 配琥珀描边和淡紫投影拉开层级。
    /// ⚠️ 柔光不能压过「旗舰」徽章：强度与半径都收小，且徽章自带不透明底 +
    ///    主题自适应的高对比金字（见 `premiumBadge`）。早年两层金色直接叠在一起，
    ///    浅色下亮金 #FFB457 对白底只有约 1.7:1，标识基本糊成一片。
    @ViewBuilder
    private var cardBackground: some View {
        let shape = RoundedRectangle(cornerRadius: AuroraRadius.md, style: .continuous)
        ZStack {
            if voice.isPremium {
                shape.fill(premiumGradient)
                shape.fill(premiumGlow)
            } else {
                shape.fill(c.surface)
            }
            shape.strokeBorder(borderColor, lineWidth: borderWidth)
        }
        .shadow(color: shadowColor, radius: 12, x: 0, y: 4)
    }

    private var premiumGradient: LinearGradient {
        LinearGradient(colors: [
            c.ctaStart.opacity(0.18),
            c.ctaEnd.opacity(0.12),
            c.surface
        ], startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// 右上角暖金柔光：只做角上的一点氛围，不再铺满徽章所在的整个右上区域。
    /// 0.22/150 时正好把「旗舰」胶囊整块泡在金光里，和徽章的金色字同色相撞。
    private var premiumGlow: RadialGradient {
        RadialGradient(colors: [AuroraDecor.amber.opacity(0.10), Color.clear],
                       center: .topTrailing, startRadius: 4, endRadius: 96)
    }

    private var borderColor: Color {
        if isPreviewing { return c.accent.opacity(0.5) }
        if voice.isPremium { return AuroraDecor.amber.opacity(0.42) }
        return c.line
    }

    private var borderWidth: CGFloat {
        (isPreviewing || voice.isPremium) ? 1 : 0.5
    }

    private var shadowColor: Color {
        if isPreviewing { return c.accent.opacity(0.16) }
        if voice.isPremium { return c.ctaStart.opacity(0.18) }
        return .clear
    }

    // MARK: 头部

    private var headerRow: some View {
        HStack(alignment: .top, spacing: 8) {
            VoiceAvatar(text: voice.localizedAvatar, seed: voice.key, size: 38, corner: 11)
            Spacer(minLength: 0)
            if voice.isPremium {
                premiumBadge
            } else {
                Text(voice.localizedDesc)
                    .font(.system(size: 11))
                    .foregroundStyle(c.textSecondary)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
                    .frame(height: 30, alignment: .topTrailing)
            }
        }
    }

    private var premiumBadge: some View {
        HStack(spacing: 2) {
            Image(systemName: "star.fill")
                .font(.system(size: 8))
            Text("旗舰".localized())
                .font(.system(size: 10, weight: .semibold))
        }
        // `c.warning` 随主题给足对比：浅色 #B87200（对白 ≈4.6:1）、深色 #FFC24B。
        // 不再用半透明琥珀底 —— 它会把下面的暖金柔光透上来，字和光同色就没边界了。
        .foregroundStyle(c.warning)
        .padding(.horizontal, 6)
        .frame(height: 16)
        .background(
            Capsule(style: .continuous)
                .fill(c.surface)       // 不透明底：把柔光完全隔在徽章之外
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(c.warning.opacity(0.35), lineWidth: 0.5)
                )
        )
    }

    // MARK: 名称 + 特质

    private var nameBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(voice.localizedName)
                .font(.system(size: 14.5, weight: .semibold))
                .foregroundStyle(c.textPrimary)
                .lineLimit(1)
                .padding(.top, 9)
            Text(voice.localizedDesc)
                .font(.system(size: 11))
                .foregroundStyle(voice.isPremium ? c.textSecondary : c.textTertiary)
                .lineLimit(2)
                .frame(height: 28, alignment: .topLeading)
        }
    }

    // MARK: meta

    private var metaRow: some View {
        HStack(spacing: 6) {
            if let age = voice.age, age > 0 {
                metaChip("%d 岁".localized(age))
            }
            metaChip(voice.localizedGender)
        }
        .padding(.top, 7)
    }

    private func metaChip(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10))
            .foregroundStyle(c.textSecondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(
                RoundedRectangle(cornerRadius: 4, style: .continuous).fill(c.surface3)
            )
    }

    // MARK: 操作行

    private var actionRow: some View {
        HStack(spacing: 6) {
            squareButton(systemImage: isPreviewing ? "pause.fill" : "play.fill",
                         highlighted: isPreviewing,
                         size: 12) { onPreview() }

            squareButton(systemImage: voice.isFavorite ? "heart.fill" : "heart",
                         highlighted: voice.isFavorite,
                         size: 13,
                         tint: voice.isFavorite ? AuroraDecor.rose : nil) { onFavorite() }

            if isPreviewing { previewBars }

            Spacer(minLength: 0)

            Button(action: onUse) {
                ZStack {
                    Circle().fill(c.ctaGradient)
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(c.ctaForeground)
                }
                .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 10)
    }

    private func squareButton(systemImage: String,
                              highlighted: Bool,
                              size: CGFloat,
                              tint: Color? = nil,
                              action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(tint ?? (highlighted ? c.accent : c.textSecondary))
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(highlighted ? c.accentSoft : Color.clear)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(highlighted ? c.accent.opacity(0.45) : c.line2,
                                              lineWidth: 0.5)
                        )
                )
        }
        .buttonStyle(.plain)
    }

    /// 试听中的呼吸波形（替代 macOS 的 hover 态指示）
    private var previewBars: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<4, id: \.self) { i in
                PreviewBar(index: i, color: c.accent)
            }
        }
        .frame(height: 14)
    }
}
