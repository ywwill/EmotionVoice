//
//  AuroraComponents.swift
//  iOSEmora
//
//  Aurora Pop 的通用组件。规格取自设计稿「组件规范（pt）」：
//  主按钮 高 44 / 圆角 12 / 135° 紫→玫瑰渐变 + 白字；
//  次按钮 Surface-3 底 + 描边；危险次按钮仅描边；列表行最小高 44、左右 16、分隔线 inset 16；
//  分类按钮 高 38 / 圆角 11。
//

import SwiftUI

// MARK: - 卡片

/// 卡片容器：Surface 底 + 细描边 + 圆角
struct AuroraCard<Content: View>: View {
    @Environment(\.aurora) private var c
    var radius: CGFloat = AuroraRadius.md
    var padding: CGFloat? = nil
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .applyCardPadding(padding)
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(c.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: radius, style: .continuous)
                            .strokeBorder(c.line, lineWidth: 0.5)
                    )
            )
    }
}

private extension View {
    @ViewBuilder
    func applyCardPadding(_ p: CGFloat?) -> some View {
        if let p {
            self.padding(p)
        } else {
            self
        }
    }
}

// MARK: - 按钮

/// 主按钮：135° 紫 → 玫瑰渐变 + 白字 + 同色投影，高 44 / 圆角 12
struct PrimaryButton: View {
    @Environment(\.aurora) private var c
    let title: String
    var systemImage: String? = nil
    var height: CGFloat = 44
    var isFullWidth: Bool = true
    /// 固定宽度（给了就不再撑满，也不再按内容长短变化）。
    /// 底部条里几个按钮并排时用得着：主操作不该跟着旁边的数字长短伸缩。
    var width: CGFloat? = nil
    var isEnabled: Bool = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 14, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 15.5, weight: .semibold))
                    // ⚠️ 固定宽度下，长语种（英文 Generate Audio）要比中文长不少 ——
                    // 不缩放就会被切掉尾巴
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(c.ctaForeground)
            .frame(minWidth: width, maxWidth: width ?? (isFullWidth ? .infinity : nil))
            .frame(height: height)
            .padding(.horizontal, (width != nil || isFullWidth) ? 0 : 16)
            .background(
                RoundedRectangle(cornerRadius: AuroraRadius.md, style: .continuous)
                    .fill(c.ctaGradient)
                    .shadow(color: c.ctaStart.opacity(isEnabled ? 0.32 : 0),
                            radius: 10, x: 0, y: 4)
            )
            .opacity(isEnabled ? 1 : 0.45)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}

/// 次按钮：Surface-3 底 + 描边
struct SecondaryButton: View {
    @Environment(\.aurora) private var c
    let title: String
    var systemImage: String? = nil
    var height: CGFloat = 44
    var isFullWidth: Bool = true
    var tint: Color? = nil
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 14, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(tint ?? c.textPrimary)
            .frame(maxWidth: isFullWidth ? .infinity : nil)
            .frame(height: height)
            .padding(.horizontal, isFullWidth ? 0 : 14)
            .background(
                RoundedRectangle(cornerRadius: AuroraRadius.md, style: .continuous)
                    .fill(c.surface3)
                    .overlay(
                        RoundedRectangle(cornerRadius: AuroraRadius.md, style: .continuous)
                            .strokeBorder(c.line2, lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

/// 危险次按钮：仅描边
struct DangerBorderButton: View {
    @Environment(\.aurora) private var c
    let title: String
    var systemImage: String? = nil
    var height: CGFloat = 44
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: 14, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(c.danger)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(
                RoundedRectangle(cornerRadius: AuroraRadius.md, style: .continuous)
                    .strokeBorder(c.danger.opacity(0.55), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

/// 图标按钮（28 视觉 + 44 热区）
struct IconButton: View {
    @Environment(\.aurora) private var c
    let systemImage: String
    var tint: Color? = nil
    var size: CGFloat = 28
    var background: Color? = nil
    var border: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: size * 0.45, weight: .semibold))
                .foregroundStyle(tint ?? c.textSecondary)
                .frame(width: size, height: size)
                .background(
                    RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
                        .fill(background ?? Color.clear)
                        .overlay(
                            RoundedRectangle(cornerRadius: size * 0.32, style: .continuous)
                                .strokeBorder(border ? (tint ?? c.accent).opacity(0.45) : Color.clear, lineWidth: 1)
                        )
                )
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Chip

/// 通用胶囊（可选中）
struct AuroraChip: View {
    @Environment(\.aurora) private var c
    let title: String
    var systemImage: String? = nil
    var isSelected: Bool = false
    var fontSize: CGFloat = 12.5
    var height: CGFloat = 30
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: fontSize - 1.5, weight: .semibold))
                }
                Text(title)
                    .font(.system(size: fontSize, weight: isSelected ? .semibold : .regular))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? c.accent : c.textSecondary)
            .padding(.horizontal, 11)
            .frame(height: height)
            .background(
                Capsule(style: .continuous)
                    .fill(isSelected ? c.accentSoft : c.surface3)
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(isSelected ? c.accent.opacity(0.32) : c.line, lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 分组标题 / 行

/// 分组标题（列表上方的小字标题，inset 16）
struct GroupTitle: View {
    @Environment(\.aurora) private var c
    let text: String
    var topPadding: CGFloat = 22

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11.5, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(c.textTertiary)
            .padding(.horizontal, 20)
            .padding(.top, topPadding)
            .padding(.bottom, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 列表行：最小高 44，左右 16，分隔线 inset 16
struct AuroraRow<Leading: View, Trailing: View>: View {
    @Environment(\.aurora) private var c
    var isSelected: Bool = false
    var showsSeparator: Bool = true
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 12) {
            leading()
            Spacer(minLength: 0)
            trailing()
        }
        .frame(minHeight: 44)
        .padding(.horizontal, 14)
        .background(isSelected ? c.accentSoft : Color.clear)
        .overlay(alignment: .bottom) {
            if showsSeparator {
                Rectangle()
                    .fill(c.line)
                    .frame(height: 0.5)
                    .padding(.leading, 16)
            }
        }
    }
}

/// 带图标 + 标题 + 值 + 箭头的导航行（设置页用）
struct NavigationRow: View {
    @Environment(\.aurora) private var c
    let title: String
    var iconSystemName: String? = nil
    var iconGradient: [Color] = [Color(hex: 0x8A5BFF), Color(hex: 0x6D3BF5)]
    var value: String? = nil
    var accessory: Accessory = .chevron
    /// 组内最后一行关掉分隔线（分组圆角卡内不需要底部的线）
    var showsSeparator: Bool = true

    enum Accessory {
        case chevron
        case check
        case none
    }

    var body: some View {
        AuroraRow(
            showsSeparator: showsSeparator,
            leading: {
                HStack(spacing: 12) {
                    if let iconSystemName {
                        ZStack {
                            RoundedRectangle(cornerRadius: 7, style: .continuous)
                                .fill(LinearGradient(colors: iconGradient,
                                                     startPoint: .topLeading,
                                                     endPoint: .bottomTrailing))
                                .frame(width: 29, height: 29)
                            Image(systemName: iconSystemName)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                    }
                    Text(title)
                        .font(.system(size: 16))
                        .foregroundStyle(c.textPrimary)
                }
            },
            trailing: {
                HStack(spacing: 6) {
                    if let value {
                        Text(value)
                            .font(AuroraFont.mono15)
                            .foregroundStyle(c.textTertiary)
                    }
                    switch accessory {
                    case .chevron:
                        Image(systemName: "chevron.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(c.textTertiary)
                    case .check:
                        Image(systemName: "checkmark")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(c.accent)
                    case .none:
                        EmptyView()
                    }
                }
            }
        )
    }
}

// MARK: - 搜索框

/// iOS 搜索框（占位为 `.searchable` 之外的内嵌样式，音色库用）
struct AuroraSearchField: View {
    @Environment(\.aurora) private var c
    @Binding var text: String
    var placeholder: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(c.textTertiary)
            TextField(placeholder, text: $text)
                .font(.system(size: 15))
                .foregroundStyle(c.textPrimary)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(c.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(c.surface3)
        )
    }
}

// MARK: - 统计格

/// 四宫格单元
struct StatCell: View {
    @Environment(\.aurora) private var c
    let key: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(key)
                .font(.system(size: 11))
                .foregroundStyle(c.textTertiary)
            Text(value)
                .font(AuroraFont.mono15)
                .foregroundStyle(c.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// 四宫格（2×2 / 一行四列）
struct StatGrid: View {
    @Environment(\.aurora) private var c
    let items: [(String, String)]
    var columns: Int = 4

    var body: some View {
        let grid = Array(repeating: GridItem(.flexible(), spacing: 2), count: min(columns, max(items.count, 1)))
        LazyVGrid(columns: grid, alignment: .leading, spacing: 12) {
            ForEach(items.indices, id: \.self) { i in
                StatCell(key: items[i].0, value: items[i].1)
            }
        }
    }
}

// MARK: - 分段控件

/// 轻量分段控件（样式贴近 iOS `UISegmentedControl`）
struct AuroraSegmented: View {
    @Environment(\.aurora) private var c
    let options: [String]
    @Binding var selection: String

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                Button {
                    withAnimation(.easeOut(duration: 0.16)) { selection = option }
                } label: {
                    Text(option)
                        .font(.system(size: 13.5, weight: selection == option ? .semibold : .regular))
                        .foregroundStyle(selection == option ? c.accent : c.textSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 30)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(selection == option ? c.surface : Color.clear)
                                .shadow(color: c.shadow.opacity(selection == option ? 0.6 : 0),
                                        radius: 3, x: 0, y: 1)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(c.surface3)
        )
    }
}

// MARK: - 头像

/// 音色头像：末字 / 首字母 + 确定性渐变（同一音色永远同色）
struct VoiceAvatar: View {
    let text: String
    let seed: String
    var size: CGFloat = 40
    var corner: CGFloat = 11

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(
                    LinearGradient(colors: VoiceAvatar.gradient(for: seed),
                                   startPoint: .topLeading,
                                   endPoint: .bottomTrailing)
                )
            Text(text)
                .font(.system(size: size * 0.44, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
    }

    /// 8 组配色轮换，按 key 哈希取，保证稳定且相邻音色尽量不同色
    private static let palettes: [[UInt32]] = [
        [0x8A5BFF, 0x6D3BF5],
        [0x74B9FF, 0x3B74D9],
        [0xFF8FC5, 0xE23C86],
        [0x5FE0C0, 0x12A88C],
        [0xFFC7A8, 0xE2703C],
        [0xC77DFF, 0x7A3FF2],
        [0x5BC8FF, 0x2E7BE0],
        [0xFFD37A, 0xF0932B],
    ]

    static func gradient(for seed: String) -> [Color] {
        var hash: UInt64 = 1469598103934665603
        for byte in seed.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1099511628211
        }
        let palette = palettes[Int(hash % UInt64(palettes.count))]
        return palette.map { Color(hex: $0) }
    }
}

// MARK: - 其它

/// 呼吸圆点（后台接收 / 状态指示）
struct PulseDot: View {
    @Environment(\.aurora) private var c
    var color: Color? = nil
    var size: CGFloat = 7

    @State private var on = false

    var body: some View {
        Circle()
            .fill(color ?? c.accent)
            .frame(width: size, height: size)
            .opacity(on ? 1 : 0.35)
            .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true),
                       value: on)
            .onAppear { on = true }
    }
}

/// 细分隔线
struct Hairline: View {
    @Environment(\.aurora) private var c
    var body: some View {
        Rectangle().fill(c.line).frame(height: 0.5)
    }
}

/// Sheet 顶部导航条（grabber 36×5 + 标题 + 左右按钮）
struct SheetNavBar<Leading: View, Trailing: View>: View {
    @Environment(\.aurora) private var c
    let title: String
    @ViewBuilder var leading: () -> Leading
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(c.textTertiary.opacity(0.45))
                .frame(width: 36, height: 5)
                .padding(.top, 6)
                .padding(.bottom, 6)
            HStack {
                leading().frame(minWidth: 44, alignment: .leading)
                Spacer(minLength: 0)
                Text(title)
                    .font(.system(size: 16.5, weight: .semibold))
                    .foregroundStyle(c.textPrimary)
                Spacer(minLength: 0)
                trailing().frame(minWidth: 44, alignment: .trailing)
            }
            .padding(.horizontal, 16)
            .frame(height: 42)
        }
    }
}
