//
//  HomeView.swift
//  EmotionVoice
//
//  Created: young on 2026/8/8.
//

import SwiftUI

/// 首页
struct HomeView: View {

    @EnvironmentObject var appState: AppState
    @State private var recentProjects: [Project] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {

            // Hero 区域
            HeroSection()

            // 快速开始
            quickActionsSection

            // 本月统计
            monthlyStatsSection

            // 最近项目
            recentProjectsSection

            Spacer(minLength: 0)
        }
        .padding(32)
        .onAppear {
            recentProjects = ProjectService.shared.fetchAllProjects()
        }
    }

    // MARK: - 快速开始

    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(title: "快速开始".localized())

            HStack(spacing: 12) {
                QuickActionCard(
                    icon: "📝",
                    title: "文本转语音".localized(),
                    desc: "粘贴文字，3秒生成专业音频".localized(),
                    cta: "立即新建".localized(),
                    gradient: [AppColor.accentPrimary, AppColor.accentSecondary]
                ) {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        appState.selectedSection = .voiceStudio
                    }
                }

                QuickActionCard(
                    icon: "🎭",
                    title: "探索音色库".localized(),
                    desc: "浏览500+精选音色，支持方言角色".localized(),
                    cta: "浏览音色".localized(),
                    gradient: [Color(hex: 0x6B8BC9), Color(hex: 0x5577B0)]
                ) {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        appState.selectedSection = .voices
                    }
                }

                QuickActionCard(
                    icon: "📂",
                    title: "打开最近项目".localized(),
                    desc: "继续未完成的创作".localized(),
                    cta: "查看项目".localized(),
                    gradient: [Color(hex: 0x8AA5A0), Color(hex: 0x6F8A85)]
                ) {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        appState.selectedSection = .projects
                    }
                }
            }
        }
    }

    // MARK: - 本月统计

    private var monthlyStatsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(
                title: "本月统计".localized(),
                action: "详细报告".localized(),
                actionIcon: "arrow.right"
            )

            HStack(spacing: 0) {
                StatItem(value: "\(appState.monthlyUsed)", label: "积分消耗".localized())
                Divider().background(AppColor.borderSubtle)
                StatItem(value: "28", label: "音频生成".localized())
                Divider().background(AppColor.borderSubtle)
                StatItem(value: "12.4", unit: "h", label: "总音频时长".localized())
                Divider().background(AppColor.borderSubtle)
                StatItem(value: "18", label: "音色使用".localized())
            }
            .padding(20)
            .background(AppColor.bgSecondary)
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.large)
                    .stroke(AppColor.borderSubtle, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.large))
        }
    }

    // MARK: - 最近项目

    private var recentProjectsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(
                title: "最近项目".localized(),
                action: "查看全部".localized(),
                actionIcon: "arrow.right"
            )

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 12),
                          GridItem(.flexible(), spacing: 12)],
                spacing: 12
            ) {
                if recentProjects.isEmpty {
                    emptyProjectsHint
                } else {
                    ForEach(recentProjects.prefix(4)) { project in
                        ProjectCard(project: project)
                    }
                }
            }
        }
    }

    private var emptyProjectsHint: some View {
        HStack {
            Spacer()
            VStack(spacing: 8) {
                Text("暂无数据".localized())
                    .font(AppFont.bodyMedium)
                    .foregroundStyle(AppColor.textTertiary)
                Button {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        appState.selectedSection = .voiceStudio
                    }
                } label: {
                    Text("新建项目".localized())
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(AppColor.accentPrimary.opacity(0.15))
                        .foregroundStyle(AppColor.accentPrimary)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
            }
            Spacer()
        }
        .padding(.vertical, 32)
        .gridCellColumns(2)
    }
}
