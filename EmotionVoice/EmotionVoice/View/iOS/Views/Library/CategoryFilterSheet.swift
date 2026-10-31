//
//  CategoryFilterSheet.swift
//  iOSEmora
//
//  全部分类 Sheet：29 个 `VoiceCategory` case 按 5 个维度分组，
//  再加视图层的「全部音色 / 仅看收藏」，一共 31 项。
//
//  与 macOS chip 的差异：**单选互斥**（`selectCategory` 语义不变），
//  但 iOS 上关闭 Sheet 不清除选择，只有「重置」才清空 —— 所以进来时要把
//  上次的选择**回显两处**：自动滚动定位 / 该行紫色 ✓ + 强调底色。
//
//  ⚠️ 点一行 = 选中并立刻收起：分类是「选一个就走」的操作，
//  再让用户点一次「完成」纯属多余（右上的 ✕ 只用于不改选择直接退出）。
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

    private var hasSelection: Bool { selectedCategory != nil || showFavoritesOnly }

    /// 选中一行：写回选择 → 让外面刷新列表 → 直接收起（不再需要「完成」）
    private func commit(_ apply: () -> Void) {
        apply()
        onCommit()
        onDismiss()
    }

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
                    // 没有「完成」了：点行即选中并收起，这里只留一个「不改选择直接退出」
                    Button { onDismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(c.textTertiary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("关闭".localized())
                }
            )

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
                                commit {
                                    selectedCategory = nil
                                    showFavoritesOnly = false
                                }
                            }
                            catRow(icon: nil,
                                   name: "仅看收藏".localized(),
                                   count: favoriteCount,
                                   checked: showFavoritesOnly,
                                   systemIcon: "heart.fill",
                                   id: Self.favRowID) {
                                commit {
                                    showFavoritesOnly.toggle()
                                    if showFavoritesOnly { selectedCategory = nil }
                                }
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
                                        commit {
                                            selectedCategory = (selectedCategory == cat) ? nil : cat
                                            showFavoritesOnly = false
                                        }
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

                // 恒留 17pt 勾位（选中 = 紫色对勾，这是唯一的选中指示）
                Group {
                    if checked {
                        Image(systemName: "checkmark")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(AuroraDecor.violet)
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
