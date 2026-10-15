//
//  Sidebar.swift
//  EmotionVoice
//
//  Created by young on 2026/8/8.
//

import SwiftUI

/// 滑动高亮的共享几何 id。
///
/// 只有「当前选中项」会渲染带这个 id 的高亮块。切换选中时，该 id 的高亮块
/// 在旧菜单项上消失、在新菜单项上出现，SwiftUI 依据 `matchedGeometryEffect`
/// 在这两个几何之间插值，于是背景色从上一项「移动」到新项。
private enum SidebarHighlight {
    static let id = "sidebarHighlight"
}

/// 左侧导航栏
struct Sidebar: View {

    @EnvironmentObject var appState: AppState

    /// 滑动高亮用的几何命名空间
    @Namespace private var ns

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 创作
            sidebarGroup(
                title: "创作".localized(),
                sections: [.voiceStudio, .voices, .projects],
                topPadding: 15
            )

            // 资源
            sidebarGroup(
                title: "设置".localized(),
                sections: [.credits, .settings],
                topPadding: 14
            )
            
            Spacer()
        }
        .frame(width: 220)
        .background(AppColor.bgSidebar.opacity(0.6))
        .overlay(
            Rectangle()
                .fill(AppColor.borderSubtle)
                .frame(width: 1),
            alignment: .trailing
        )
    }

    // MARK: - 分组

    /// 一个分组 = 分组标题 + 菜单项列表。
    /// 用标题做视觉分区，取代原来的 Divider（分隔线在半透明侧栏上会切出一条硬边）。
    private func sidebarGroup(
        title: String,
        sections: [SidebarSection],
        topPadding: CGFloat
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            groupLabel(title)

            ForEach(sections) { section in
                SidebarItem(section: section, namespace: ns)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, topPadding)
    }

    /// 分组标题：小号半粗 + 三级文字色，左侧再补 12 与菜单项图标左边缘对齐
    private func groupLabel(_ title: String) -> some View {
        Text(title.localized())
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(AppColor.textTertiary)
            .padding(.leading, 12)
            .padding(.bottom, 6)
    }
}

/// 侧边栏单条
///
/// 交互动效：
/// - **悬浮**：背景淡入 + 图标/文字提亮 + 内容轻微放大（缓动 0.18s）
/// - **点击**：选中高亮块在旧菜单消失、在新菜单出现，由 `matchedGeometryEffect`
///   做几何插值，表现为背景色（含左侧琥珀指示条）从上一个菜单滑动到当前菜单
struct SidebarItem: View {

    let section: SidebarSection
    var badge: String? = nil
    /// 供滑动高亮对齐的命名空间
    let namespace: Namespace.ID

    @EnvironmentObject var appState: AppState
    @State private var isHovered = false

    var body: some View {
        let isActive = appState.selectedSection == section

        Button {
            // 切换选中：高亮块在此事务中从旧项滑动到当前项
            withAnimation(.spring(response: 0.36, dampingFraction: 0.82)) {
                appState.selectedSection = section
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: section.icon)
                    .font(.system(size: 14, weight: isActive ? .semibold : .medium))
                    .frame(width: 20)
                    .foregroundStyle(iconColor(isActive: isActive, isHovered: isHovered))

                Text(section.title)
                    .font(AppFont.bodyMedium)
                    .fontWeight(isActive ? .semibold : .medium)

                Spacer()

                if let badge {
                    Text(badge)
                        .font(AppFont.monoSmall)
                        .foregroundStyle(AppColor.textTertiary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(AppColor.bgElevated)
                        .clipShape(Capsule())
                }
            }
            // 悬浮时轻微放大内容：放在背景层之前，
            // 使高亮块的几何不随缩放变化，避免滑动对齐抖动
            .scaleEffect(isHovered && !isActive ? 1.015 : 1.0)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                if isActive {
                    // 选中高亮：背景 + 左侧琥珀指示条作为一个整体滑动
                    RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous)
                        .fill(AppColor.bgElevated)
                        .overlay(alignment: .leading) {
                            Capsule()
                                .fill(AppColor.accentPrimary)
                                .frame(width: 3, height: 16)
                                .offset(x: -15)
                        }
                        .matchedGeometryEffect(id: SidebarHighlight.id, in: namespace)
                } else if isHovered {
                    // 悬浮弱背景：本地淡入淡出，不参与几何匹配
                    RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous)
                        .fill(AppColor.bgElevated.opacity(0.45))
                }
            }
            .foregroundStyle(titleColor(isActive: isActive, isHovered: isHovered))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .onHover { hovering in
            // 悬浮：缓动淡入背景与提亮，离开时平滑回落
            withAnimation(.easeInOut(duration: 0.18)) {
                isHovered = hovering
            }
        }
    }

    // MARK: - 视觉派生

    private func iconColor(isActive: Bool, isHovered: Bool) -> Color {
        if isActive { return AppColor.accentPrimary }
        if isHovered { return AppColor.textPrimary }
        return AppColor.textSecondary
    }

    private func titleColor(isActive: Bool, isHovered: Bool) -> Color {
        if isActive { return AppColor.textPrimary }
        if isHovered { return AppColor.textPrimary }
        return AppColor.textSecondary
    }
}
