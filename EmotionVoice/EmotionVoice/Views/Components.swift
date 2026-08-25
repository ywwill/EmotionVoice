//
//  Components.swift
//  EmotionVoice
//
//  Created by young by 2026/8/8.
//

import SwiftUI

// MARK: - 主按钮

struct PrimaryButton: View {
    enum Size { case regular, large }

    let title: String
    var icon: String? = nil
    var size: Size = .regular
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: iconFontSize, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: textFontSize, weight: .semibold))
            }
            .padding(.horizontal, hPadding)
            .padding(.vertical, vPadding)
            .background(
                LinearGradient(
                    colors: [AppColor.accentPrimary, AppColor.accentSecondary],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .foregroundStyle(AppColor.bgPrimary)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.small))
            .shadow(
                color: AppColor.accentPrimary.opacity(0.28),
                radius: size == .large ? 12 : 8,
                x: 0,
                y: size == .large ? 6 : 4
            )
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
    }

    private var iconFontSize: CGFloat {
        size == .large ? 14 : 12
    }
    private var textFontSize: CGFloat {
        size == .large ? 15 : 13
    }
    private var hPadding: CGFloat {
        size == .large ? 28 : 20
    }
    private var vPadding: CGFloat {
        size == .large ? 14 : 10
    }
}

// MARK: - 次按钮

struct SecondaryButton: View {
    let title: String
    var icon: String? = nil
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .medium))
                }
                Text(title)
                    .font(.system(size: 13, weight: .medium))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .background(Color.clear)
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.small)
                    .stroke(AppColor.borderMedium, lineWidth: 1)
            )
            .foregroundStyle(AppColor.textPrimary)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.small))
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
    }
}

// MARK: - 工具栏小按钮

struct ToolbarButton: View {
    let title: String
    var icon: String? = nil
    var shortcut: String? = nil
    var isPrimary: Bool = false
    var action: () -> Void = {}

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon {
                    Text(icon)
                        .font(.system(size: 12))
                }
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                if let shortcut {
                    Text(shortcut)
                        .font(.system(size: 10, design: .monospaced))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.white.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(toolbarBackground(isPrimary: isPrimary))
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.small)
                    .stroke(
                        isPrimary ? Color.clear : AppColor.borderMedium,
                        lineWidth: 1
                    )
            )
            .foregroundStyle(isPrimary ? AppColor.bgPrimary : AppColor.textPrimary)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.small))
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
    }

    private func toolbarBackground(isPrimary: Bool) -> AnyShapeStyle {
        if isPrimary {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [AppColor.accentPrimary, AppColor.accentSecondary],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
        } else {
            return AnyShapeStyle(Color.clear)
        }
    }
}

// MARK: - 区块标题

struct SectionTitle: View {
    let title: String
    var action: String? = nil
    var actionIcon: String? = nil

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(AppColor.textPrimary)

            Spacer()

            if let action {
                Button {
                    // no-op
                } label: {
                    HStack(spacing: 4) {
                        Text(action)
                            .font(.system(size: 12, weight: .medium))
                        if let actionIcon {
                            Image(systemName: actionIcon)
                                .font(.system(size: 10, weight: .medium))
                        }
                    }
                    .foregroundStyle(AppColor.accentPrimary)
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
            }
        }
    }
}

// MARK: - 标签（状态用）

struct StatusBadge: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(AppFont.caption)
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(color.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}

// MARK: - 波形图（装饰用）

struct WaveformView: View {
    var barCount: Int = 15
    var animated: Bool = true

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(0..<barCount, id: \.self) { i in
                WaveBar(
                    delay: Double(i) * 0.1,
                    animated: animated
                )
            }
        }
        .frame(height: 80)
    }
}

struct WaveBar: View {
    let delay: Double
    let animated: Bool

    @State private var phase: Double = 0

    var body: some View {
        Capsule()
            .fill(
                LinearGradient(
                    colors: [AppColor.accentPrimary, AppColor.accentGlow],
                    startPoint: .bottom,
                    endPoint: .top
                )
            )
            .frame(width: 4)
            .frame(maxHeight: .infinity)
            .scaleEffect(y: animated ? (0.6 + 0.4 * abs(sin(phase))) : 0.7)
            .onAppear {
                guard animated else { return }
                withAnimation(
                    .easeInOut(duration: 1.2)
                    .repeatForever(autoreverses: true)
                    .delay(delay)
                ) {
                    phase = .pi / 2
                }
            }
    }
}

// MARK: - 头像（按首字生成渐变色）

struct AvatarView: View {
    let text: String
    var size: CGFloat = 32
    var gradientColors: [Color]? = nil

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: AppRadius.small)
                .fill(
                    LinearGradient(
                        colors: gradientColors ?? resolvedGradient,
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            Text(text)
                .font(.system(size: size * 0.45, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }

    // 哈希色板缓存：避免每次 body 都重新计算 hash & 选取颜色对
    private var resolvedGradient: [Color] {
        let palettes: [[Color]] = [
            [Color(hex: 0xE8A968), Color(hex: 0xD49559)],
            [Color(hex: 0x6A9FB0), Color(hex: 0x4D8499)],
            [Color(hex: 0xB07A9F), Color(hex: 0x955A82)],
            [Color(hex: 0x8AA868), Color(hex: 0x6B8A4D)],
            [Color(hex: 0xC68F6B), Color(hex: 0xA0714D)],
            [Color(hex: 0x7A8AB0), Color(hex: 0x5A6A90)],
        ]
        return palettes[abs(text.hashValue) % palettes.count]
    }
}

// MARK: - 滑块

struct LabeledSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let unit: String
    var displayValue: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(label)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textTertiary)
                Spacer()
                Text(displayValue ?? String(format: "%.\(step < 1 ? 1 : 0)f%@", value, unit))
                    .font(AppFont.monoMedium)
                    .foregroundStyle(AppColor.accentPrimary)
            }
            HStack(spacing: 8) {
                Text(minLabel)
                    .font(AppFont.monoSmall)
                    .foregroundStyle(AppColor.textTertiary)
                Slider(value: $value, in: range, step: step)
                    .tint(AppColor.accentPrimary)
                Text(maxLabel)
                    .font(AppFont.monoSmall)
                    .foregroundStyle(AppColor.textTertiary)
            }
        }
    }

    private var minLabel: String {
        if step < 1 { return String(format: "%.1f%@", range.lowerBound, unit) }
        return "\(Int(range.lowerBound))\(unit)"
    }

    private var maxLabel: String {
        if step < 1 { return String(format: "%.1f%@", range.upperBound, unit) }
        return "\(Int(range.upperBound))\(unit)"
    }
}

// MARK: - 单选按钮组

struct SegmentedOption<Item: Hashable & Identifiable, Label: View>: View {
    let items: [Item]
    @Binding var selection: Item
    let label: (Item) -> Label

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items) { item in
                Button {
                    selection = item
                } label: {
                    label(item)
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            selection == item
                            ? AppColor.bgElevated
                            : Color.clear
                        )
                        .foregroundStyle(
                            selection == item
                            ? AppColor.textPrimary
                            : AppColor.textSecondary
                        )
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
            }
        }
        .background(AppColor.bgTertiary)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}