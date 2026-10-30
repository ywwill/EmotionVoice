//
//  Components.swift
//  EmotionVoice
//
//  Created by young by 2026/8/8.
//

import SwiftUI
import Foundation

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

// MARK: - 可展开搜索框（折叠态仅图标，点击从右往左展开并自动聚焦键盘）

/// 折叠态只显示一个放大镜图标；点击后用 spring 动画从右往左展开为输入框，
/// 并自动聚焦以响应键盘输入。
///
/// 展开后框内右侧只有一个关闭按钮（细叉）：取消搜索 —— 清空并收起，
/// 完全恢复到「仅图标」的初始状态（若只收起不清空，结果仍被看不见的关键词过滤，用户无从察觉）。
///
/// 收起（恢复原状）的路径：点关闭按钮 / 按 Esc / 展开且为空时失焦自动收起。
struct ExpandableSearchField: View {

    @Binding var text: String
    var placeholder: String
    var expandedWidth: CGFloat = 220
    var onChange: ((String) -> Void)? = nil
    var onSubmit: (() -> Void)? = nil

    @FocusState private var isFocused: Bool
    @State private var isExpanded: Bool

    init(
        text: Binding<String>,
        placeholder: String,
        expandedWidth: CGFloat = 220,
        onChange: ((String) -> Void)? = nil,
        onSubmit: (() -> Void)? = nil
    ) {
        self._text = text
        self.placeholder = placeholder
        self.expandedWidth = expandedWidth
        self.onChange = onChange
        self.onSubmit = onSubmit
        // 若已有搜索词（如从持久化恢复），初始即展开
        self._isExpanded = State(initialValue: !text.wrappedValue.isEmpty)
    }

    private let collapsedWidth: CGFloat = 34
    private let fixedHeight: CGFloat = 32

    var body: some View {
        HStack(spacing: 6) {
            // 前导放大镜：折叠态是唯一内容（点击展开），展开态作为输入框的前导图标
            Image(systemName: "magnifyingglass")
                .font(.system(size: isExpanded ? 12 : 14, weight: .medium))
                .foregroundStyle(AppColor.textTertiary)
                .frame(width: isExpanded ? 16 : 18, height: isExpanded ? 16 : 18)
                .contentShape(Rectangle())
                .onTapGesture { handleIconTap() }

            if isExpanded {
                TextField(placeholder, text: $text)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundStyle(AppColor.textPrimary)
                    .focused($isFocused)
                    .onChange(of: text) { _, newValue in onChange?(newValue) }
                    .onSubmit { onSubmit?() }
                    // Esc：取消搜索 —— 清空并收起（对齐 macOS 上 Esc 表示放弃输入的直觉）
                    .onKeyPress(.escape) {
                        collapse(clearingText: true)
                        return .handled
                    }
                    .frame(maxWidth: .infinity)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .move(edge: .trailing)),
                        removal: .opacity
                    ))

                // 关闭按钮：取消搜索 —— 清空并收起，完全恢复初始状态
                // （若只收起不清空，结果仍被看不见的关键词过滤，用户无从察觉）
                iconButton(systemName: "xmark", size: 10, color: AppColor.textTertiary) {
                    collapse(clearingText: true)
                }
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(width: isExpanded ? expandedWidth : collapsedWidth, height: fixedHeight)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.small)
                .fill(isExpanded ? AppColor.bgTertiary : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.small)
                        .stroke(AppColor.borderSubtle, lineWidth: 1)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.small))
        .contentShape(Rectangle())
        .pointingHandCursor()
        .onChange(of: isFocused) { _, focused in
            // 失焦且搜索词为空时自动收起
            if !focused && text.isEmpty {
                collapse(clearingText: false)
            }
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.82), value: isExpanded)
    }

    /// 框内右侧的小图标按钮（目前只有关闭）。
    /// 不单独挂 `pointingHandCursor`：外层容器已统一设置手型，避免 onHover 互相覆盖导致光标闪烁。
    private func iconButton(
        systemName: String,
        size: CGFloat,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(color)
                .frame(width: 16, height: 16)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func handleIconTap() {
        if !isExpanded {
            expandAndFocus()
        } else {
            // 展开态点击前导放大镜：把焦点交还给输入框
            isFocused = true
        }
    }

    /// 收起搜索框，恢复到「仅图标」的初始状态
    /// - Parameter clearingText: 是否同时清空搜索词（Esc 取消搜索时为 true）
    private func collapse(clearingText: Bool) {
        if clearingText {
            text = ""
            onChange?("")
        }
        isFocused = false
        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
            isExpanded = false
        }
    }

    private func expandAndFocus() {
        withAnimation(.spring(response: 0.34, dampingFraction: 0.82)) {
            isExpanded = true
        }
        // TextField 挂载后再聚焦，确保键盘立即响应
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            isFocused = true
        }
    }
}
