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
        .background(
            RoundedRectangle(cornerRadius: AuroraRadius.md, style: .continuous)
                .fill(c.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: AuroraRadius.md, style: .continuous)
                        .strokeBorder(isPreviewing ? c.accent.opacity(0.4) : c.line,
                                      lineWidth: isPreviewing ? 1 : 0.5)
                )
                .shadow(color: isPreviewing ? c.accent.opacity(0.16) : .clear,
                        radius: 12, x: 0, y: 4)
        )
        .contentShape(Rectangle())
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
        .foregroundStyle(AuroraDecor.amber)
        .padding(.horizontal, 6)
        .frame(height: 16)
        .background(
            Capsule(style: .continuous).fill(AuroraDecor.amber.opacity(0.16))
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

/// 单根呼吸条：确定性延迟，不用 TimelineView（几百张卡同时跑会掉帧）
private struct PreviewBar: View {
    let index: Int
    let color: Color
    @State private var animating = false

    private var heights: [CGFloat] { [8, 14, 6, 12] }

    var body: some View {
        RoundedRectangle(cornerRadius: 1, style: .continuous)
            .fill(color)
            .frame(width: 2, height: animating ? heights[index % 4] : 4)
            .animation(
                .easeInOut(duration: 0.6)
                    .repeatForever(autoreverses: true)
                    .delay(Double(index) * 0.1),
                value: animating
            )
            .onAppear { animating = true }
    }
}

// MARK: - 骨架卡

/// 首屏骨架（避免一次性同步查全表导致的白屏）
struct VoiceCardSkeleton: View {
    @Environment(\.aurora) private var c

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(c.surface3)
                    .frame(width: 38, height: 38)
                Spacer(minLength: 0)
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(c.surface3)
                    .frame(width: 44, height: 11)
            }
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(c.surface3)
                .frame(width: 72, height: 13)
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(c.surface3)
                .frame(height: 10)
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(c.surface3)
                .frame(width: 96, height: 10)
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(c.surface3).frame(width: 28, height: 28)
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(c.surface3).frame(width: 28, height: 28)
                Spacer(minLength: 0)
                Circle().fill(c.surface3).frame(width: 26, height: 26)
            }
        }
        .padding(12)
        .frame(height: 168)
        .background(
            RoundedRectangle(cornerRadius: AuroraRadius.md, style: .continuous)
                .fill(c.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: AuroraRadius.md, style: .continuous)
                        .strokeBorder(c.line, lineWidth: 0.5)
                )
        )
        .redacted(reason: .placeholder)
    }
}
