//
//  Sidebar.swift
//  EmotionVoice
//
//  Created by young on 2026/8/8.
//

import SwiftUI

/// 左侧导航栏
struct Sidebar: View {

    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 主导航
            VStack(alignment: .leading, spacing: 2) {
                ForEach([SidebarSection.voiceStudio, SidebarSection.voices]) { section in
                    SidebarItem(section: section,
                                badge: section == .voices ? "\(appState.voices.count)" : nil)
                }
            }
            .padding(.horizontal, 12)
            .padding(.top, 16)

            Divider()
                .background(AppColor.borderSubtle)
                .padding(.vertical, 8)

            // 项目管理
            VStack(alignment: .leading, spacing: 2) {
                sectionHeader("资源管理".localized())
                SidebarItem(section: .projects,
                            badge: "\(ProjectService.shared.fetchAllAudios().count)")
                SidebarItem(section: .credits)
                SidebarItem(section: .stats)
            }
            .padding(.horizontal, 12)

            Divider()
                .background(AppColor.borderSubtle)
                .padding(.vertical, 8)

            // 设置
            VStack(alignment: .leading, spacing: 2) {
                SidebarItem(section: .settings)
            }
            .padding(.horizontal, 12)

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

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(AppFont.label)
            .foregroundStyle(AppColor.textTertiary)
            .textCase(.uppercase)
            .tracking(0.06)
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
    }
}

/// 侧边栏单条
struct SidebarItem: View {

    let section: SidebarSection
    var badge: String? = nil

    @EnvironmentObject var appState: AppState

    var body: some View {
        let isActive = appState.selectedSection == section

        Button {
            withAnimation(.easeInOut(duration: 0.22)) {
                appState.selectedSection = section
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: section.icon)
                    .font(.system(size: 14, weight: .medium))
                    .frame(width: 20)

                Text(section.title)
                    .font(AppFont.bodyMedium)
                    .fontWeight(.medium)

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
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isActive ? AppColor.bgElevated : Color.clear
            )
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.small, style: .continuous))
            .overlay(alignment: .leading) {
                if isActive {
                    Capsule()
                        .fill(AppColor.accentPrimary)
                        .frame(width: 3, height: 16)
                        .offset(x: -15)
                }
            }
            .foregroundStyle(isActive ? AppColor.textPrimary : AppColor.textSecondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
    }
}
