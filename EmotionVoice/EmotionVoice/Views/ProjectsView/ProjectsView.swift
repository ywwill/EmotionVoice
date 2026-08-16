//
//  ProjectsView.swift
//  EmotionVoice
//
//  Created by young on 2026/8/8.
//

import SwiftUI

/// 项目管理
struct ProjectsView: View {

    @State private var projects: [Project] = []
    @State private var filter: ProjectFilter = .all
    @State private var searchText: String = ""

    enum ProjectFilter: String, CaseIterable, Identifiable {
        case all = "全部"
        case last7 = "最近 7 天"
        case last30 = "最近 30 天"
        case completed = "已完成"

        var id: String { rawValue }

        var displayName: String { rawValue.localized() }
    }

    var filteredProjects: [Project] {
        let now = Date()
        var list = projects
        switch filter {
        case .all: break
        case .last7:
            list = list.filter { $0.updatedAt.timeIntervalSince(now) > -7 * 86400 }
        case .last30:
            list = list.filter { $0.updatedAt.timeIntervalSince(now) > -30 * 86400 }
        case .completed:
            // 演示：所有项目视为已完成
            break
        }
        if !searchText.isEmpty {
            list = list.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
        }
        return list
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            toolbar
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    summaryCards

                    filterBar

                    if filteredProjects.isEmpty {
                        emptyHint
                    } else {
                        projectList
                    }
                }
                .padding(24)
            }
        }
        .onAppear { reload() }
    }

    private func reload() {
        projects = ProjectService.shared.fetchAllProjects()
    }

    // MARK: - 工具栏

    private var toolbar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("所有项目".localized())
                    .font(.system(size: 16, weight: .semibold))
                Text("管理和追踪你所有的音频创作".localized())
                    .font(AppFont.bodySmall)
                    .foregroundStyle(AppColor.textTertiary)
            }
            Spacer()
            ToolbarButton(title: "导入".localized(), icon: "📥") {}
            ToolbarButton(title: "新建项目".localized(), icon: "+", isPrimary: true) {
                let name = "未命名项目".localized() + " " + Date().timestampString
                _ = ProjectService.shared.createProject(name: name, folder: nil)
                reload()
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 16)
        .background(
            Color(hex: 0x0E0F12).opacity(0.4)
                .background(.ultraThinMaterial)
        )
        .overlay(alignment: .bottom) {
            Divider().background(AppColor.borderSubtle)
        }
    }

    // MARK: - 概览卡

    private var summaryCards: some View {
        HStack(spacing: 12) {
            SummaryCard(label: "项目总数".localized(),
                        value: "\(projects.count)",
                        trend: "本月 +3".localized(),
                        trendUp: true)
            SummaryCard(label: "总音频时长".localized(),
                        value: "2.8h".localized(),
                        trend: "28 个音频".localized(),
                        trendUp: true)
            SummaryCard(label: "已消耗积分".localized(),
                        value: "4,560".localized(),
                        trend: "本月".localized(),
                        trendUp: false,
                        accent: true)
            SummaryCard(label: "进行中项目".localized(),
                        value: "2".localized(),
                        trend: "需要关注".localized(),
                        trendUp: false)
        }
    }

    // MARK: - 筛选条

    private var filterBar: some View {
        HStack {
            HStack(spacing: 6) {
                ForEach(ProjectFilter.allCases) { f in
                    Button {
                        filter = f
                    } label: {
                        Text(f.displayName)
                            .font(.system(size: 12, weight: .medium))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 5)
                            .background(
                                filter == f ? AppColor.bgElevated : AppColor.bgTertiary
                            )
                            .foregroundStyle(
                                filter == f ? AppColor.textPrimary : AppColor.textSecondary
                            )
                            .clipShape(RoundedRectangle(cornerRadius: AppRadius.pill))
                    }
                    .buttonStyle(.plain)
                    .pointingHandCursor()
                }
            }

            Spacer()

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(AppColor.textTertiary)
                TextField("搜索项目...".localized(), text: $searchText)
                    .textFieldStyle(.plain)
                    .foregroundStyle(AppColor.textPrimary)
                    .frame(width: 180)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(AppColor.bgTertiary)
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.small)
                    .stroke(AppColor.borderSubtle, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.small))
        }
    }

    // MARK: - 项目列表

    private var projectList: some View {
        let columns = [
            GridItem(.adaptive(minimum: 320, maximum: 480), spacing: 16)
        ]
        return LazyVGrid(columns: columns, spacing: 16) {
            ForEach(filteredProjects) { project in
                ProjectListCard(
                    project: project,
                    onPlay: {
                        // 播放逻辑由卡片内部处理；此处保留钩子以便后续扩展
                    },
                    onDelete: {
                        ProjectService.shared.deleteProject(id: project.id)
                        reload()
                    }
                )
            }
        }
    }

    // MARK: - 空提示

    private var emptyHint: some View {
        VStack(spacing: 12) {
            Text("📁")
                .font(.system(size: 36))
            Text("暂无项目".localized())
                .font(.system(size: 16, weight: .semibold))
            Text("点击「新建项目」开始你的第一次创作".localized())
                .font(AppFont.bodyMedium)
                .foregroundStyle(AppColor.textTertiary)
            PrimaryButton(title: "新建项目".localized(), icon: "plus") {
                let name = "未命名项目".localized() + " " + Date().timestampString
                _ = ProjectService.shared.createProject(name: name, folder: nil)
                reload()
            }
        }
        .padding(60)
        .frame(maxWidth: .infinity)
        .background(AppColor.bgSecondary)
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.large)
                .stroke(AppColor.borderSubtle, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.large))
    }
}
