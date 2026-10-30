//
//  CategoryFilterSheet.swift
//  iOSEmora
//
//  全部分类 Sheet：29 个 `VoiceCategory` case 按 5 个维度分组，
//  再加视图层的「全部音色 / 仅看收藏」，一共 31 项。
//
//  与 macOS chip 的差异：**单选互斥**（`selectCategory` 语义不变），
//  但 iOS 上关闭 Sheet 不清除选择，只有「重置」才清空 —— 所以进来时必须把
//  上次的选择**回显三处**：吸顶条 / 自动滚动定位 / 该行 ✓ + 强调底色。
//
//  ⚠️ 每行右侧恒留 17pt 勾位（未选中时 `Color.clear`），否则打勾会让文字横向跳动。
//

import SwiftUI

struct CategoryFilterSheet: View {
    @Environment(\.aurora) private var c

    @Binding var selectedCategory: VoiceCategory?
    @Binding var showFavoritesOnly: Bool

    /// 全量统计（counts[cat.rawValue] / all / favorite）
    let counts: [String: Int]
    let totalAll: Int
    let favoriteCount: Int

    let onCommit: () -> Void
    let onDismiss: () -> Void

    /// 「视图级筛选」分组的锚点 id（滚动定位用）
    private static let allRowID = "__row_all__"
    private static let favRowID = "__row_fav__"

    @State private var flashTick = 0

    private var activeLabel: String? {
        if showFavoritesOnly { return "仅看收藏".localized() }
        guard let cat = selectedCategory else { return nil }
        return "\(cat.icon) \(cat.displayName)"
    }

    private var activeCount: Int {
        if showFavoritesOnly { return favoriteCount }
        guard let cat = selectedCategory else { return totalAll }
        return counts[cat.rawValue] ?? 0
    }

    private var hasSelection: Bool { selectedCategory != nil || showFavoritesOnly }

    var body: some View {
        VStack(spacing: 0) {
            SheetNavBar(
                title: "全部分类".localized(),
                leading: {
                    Button {
                        selectedCategory = nil
                        showFavoritesOnly = false
                        onCommit()
                    } label: {
                        Text("重置".localized())
                            .font(.system(size: 16))
                            .foregroundStyle(hasSelection ? c.accent : c.textTertiary)
                    }
                    .buttonStyle(.plain)
                },
                trailing: {
                    Button { onDismiss() } label: {
                        Text("完成".localized())
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(c.accent)
                    }
                    .buttonStyle(.plain)
                }
            )

            if let label = activeLabel {
                currentSelectionBar(label: label)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0, pinnedViews: []) {
                        groupTitle("视图级筛选".localized(), top: 6)
                        rowsBlock {
                            catRow(icon: nil,
                                   name: "全部音色".localized(),
                                   count: totalAll,
                                   checked: selectedCategory == nil && !showFavoritesOnly,
                                   id: Self.allRowID) {
                                selectedCategory = nil
                                showFavoritesOnly = false
                                onCommit()
                            }
                            catRow(icon: nil,
                                   name: "仅看收藏".localized(),
                                   count: favoriteCount,
                                   checked: showFavoritesOnly,
                                   systemIcon: "heart.fill",
                                   id: Self.favRowID) {
                                showFavoritesOnly.toggle()
                                if showFavoritesOnly { selectedCategory = nil }
                                onCommit()
                            }
                        }

                        ForEach(VoiceCategory.grouped(), id: \.0) { dim, cats in
                            groupTitle(dim.displayName, top: 18)
                            rowsBlock {
                                ForEach(cats, id: \.self) { cat in
                                    catRow(icon: cat.icon,
                                           name: cat.displayName,
                                           count: counts[cat.rawValue] ?? 0,
                                           checked: selectedCategory == cat && !showFavoritesOnly,
                                           id: cat.rawValue) {
                                        // 单选互斥：再点一次同一个才回到「全部」
                                        selectedCategory = (selectedCategory == cat) ? nil : cat
                                        showFavoritesOnly = false
                                        onCommit()
                                    }
                                }
                            }
                        }
                    }
                    .padding(.bottom, 24)
                }
                .onAppear {
                    guard let cat = selectedCategory, !showFavoritesOnly else { return }
                    // 已选项自动滚到可见处；延迟一拍等列表布局完成
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        withAnimation(.easeOut(duration: 0.25)) {
                            proxy.scrollTo(cat.rawValue, anchor: .center)
                        }
                        flashTick += 1
                    }
                }
            }
        }
        .background(c.backgroundGrouped)
    }

    // MARK: 吸顶「当前选择」

    private func currentSelectionBar(label: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 15))
                .foregroundStyle(c.accent)
            Text(String(format: "当前选择 · %@ · %d 个".localized(), label, activeCount))
                .font(.system(size: 12.5))
                .foregroundStyle(c.textSecondary)
                .lineLimit(1)
            Spacer(minLength: 0)
            Button {
                selectedCategory = nil
                showFavoritesOnly = false
                onCommit()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(c.textTertiary)
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(c.surface3))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .frame(height: 34)
        .background(
            RoundedRectangle(cornerRadius: AuroraRadius.sm, style: .continuous)
                .fill(c.accentSoft)
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    // MARK: 行

    private func groupTitle(_ text: String, top: CGFloat) -> some View {
        Text(text)
            .font(.system(size: 11.5, weight: .semibold))
            .tracking(0.6)
            .foregroundStyle(c.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, top)
            .padding(.bottom, 7)
    }

    private func rowsBlock<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            content()
        }
        .background(
            RoundedRectangle(cornerRadius: AuroraRadius.md, style: .continuous)
                .fill(c.surface)
        )
        .clipShape(RoundedRectangle(cornerRadius: AuroraRadius.md, style: .continuous))
        .padding(.horizontal, 16)
    }

    private func catRow(icon: String?,
                        name: String,
                        count: Int,
                        checked: Bool,
                        systemIcon: String? = nil,
                        id: String,
                        action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if let systemIcon {
                    Image(systemName: systemIcon)
                        .font(.system(size: 13))
                        .foregroundStyle(c.accent)
                        .frame(width: 20, alignment: .leading)
                } else if let icon {
                    Text(icon)
                        .font(.system(size: 15))
                        .frame(width: 20, alignment: .leading)
                } else {
                    Color.clear.frame(width: 20)
                }

                Text(name)
                    .font(.system(size: 15))
                    .foregroundStyle(c.textPrimary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                Text("\(count)")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(c.textTertiary)

                // 恒留 17pt 勾位
                Group {
                    if checked {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(c.accent)
                    } else {
                        Color.clear
                    }
                }
                .frame(width: 17, height: 17)
            }
            .padding(.horizontal, 14)
            .frame(height: 44)
            .contentShape(Rectangle())
            .background(checked ? c.accentSoft : Color.clear)
            // 首次出现时高亮闪一下 0.4s
            .id(id)
            .modifier(FlashHighlight(trigger: flashTick, active: checked))
        }
        .buttonStyle(.plain)
    }
}

/// 选中行首次可见时的 0.4s 高亮闪烁
private struct FlashHighlight: ViewModifier {
    let trigger: Int
    let active: Bool
    @State private var opacity: Double = 0

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: AuroraRadius.xs, style: .continuous)
                    .fill(Color(hex: 0x8A5BFF).opacity(opacity))
            )
            .onChange(of: trigger) { _, _ in
                guard active else { return }
                opacity = 0.28
                withAnimation(.easeOut(duration: 0.4)) { opacity = 0 }
            }
    }
}
