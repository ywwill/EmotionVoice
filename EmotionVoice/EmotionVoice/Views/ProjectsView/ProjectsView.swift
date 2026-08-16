//
//  ProjectsView.swift
//  EmotionVoice
//
//  Created by young on 2026/8/8.
//
//  历史记录页面：扁平展示所有音频条目。
//  文件名保留为 ProjectsView 以避免破坏 Xcode 工程的文件引用；
//  类型重命名为 HistoryView，对外语义是"历史记录"。
//

import SwiftUI

/// 历史记录：所有音频条目的扁平列表
struct HistoryView: View {

    @State private var audios: [AudioItem] = []
    @State private var filter: HistoryFilter = .all
    @State private var searchText: String = ""

    enum HistoryFilter: String, CaseIterable, Identifiable {
        case all = "全部"
        case last7 = "最近 7 天"
        case last30 = "最近 30 天"
        case completed = "已完成"

        var id: String { rawValue }

        var displayName: String { rawValue.localized() }
    }

    var filteredAudios: [AudioItem] {
        let now = Date()
        var list = audios
        switch filter {
        case .all: break
        case .last7:
            list = list.filter { $0.createdAt.timeIntervalSince(now) > -7 * 86400 }
        case .last30:
            list = list.filter { $0.createdAt.timeIntervalSince(now) > -30 * 86400 }
        case .completed:
            // 演示：仅展示已完成
            list = list.filter { $0.status == .completed }
        }
        if !searchText.isEmpty {
            list = list.filter { $0.shownName.localizedCaseInsensitiveContains(searchText) }
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

                    if filteredAudios.isEmpty {
                        emptyHint
                    } else {
                        audioList
                    }
                }
                .padding(24)
            }
        }
        .onAppear { reload() }
    }

    private func reload() {
        audios = ProjectService.shared.fetchAllAudios()
    }

    // MARK: - 工具栏

    private var toolbar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("历史记录".localized())
                    .font(.system(size: 16, weight: .semibold))
                Text("查看你生成过的所有音频".localized())
                    .font(AppFont.bodySmall)
                    .foregroundStyle(AppColor.textTertiary)
            }
            Spacer()
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
        let totalDuration = audios.reduce(0.0) { $0 + $1.duration }
        let totalPoints = audios.reduce(0) { $0 + $1.pointsCost }
        return HStack(spacing: 12) {
            SummaryCard(label: "音频总数".localized(),
                        value: "\(audios.count)",
                        trend: "本机".localized(),
                        trendUp: true)
            SummaryCard(label: "总时长".localized(),
                        value: totalDuration.durationString,
                        trend: "已生成".localized(),
                        trendUp: true)
            SummaryCard(label: "已消耗积分".localized(),
                        value: "\(totalPoints)",
                        trend: "累计".localized(),
                        trendUp: false,
                        accent: true)
        }
    }

    // MARK: - 筛选条

    private var filterBar: some View {
        HStack {
            HStack(spacing: 6) {
                ForEach(HistoryFilter.allCases) { f in
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
                TextField("搜索音频...".localized(), text: $searchText)
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

    // MARK: - 列表

    private var audioList: some View {
        let columns = [
            GridItem(.adaptive(minimum: 320, maximum: 480), spacing: 16)
        ]
        return LazyVGrid(columns: columns, spacing: 16) {
            ForEach(filteredAudios) { audio in
                AudioListCard(
                    audio: audio,
                    onPlay: {
                        // 播放逻辑由卡片内部处理；此处保留钩子以便后续扩展
                    },
                    onDelete: {
                        ProjectService.shared.deleteAudio(id: audio.id)
                        reload()
                    },
                    onRename: { newName in
                        ProjectService.shared.renameAudio(id: audio.id, displayName: newName)
                        reload()
                    }
                )
            }
        }
    }

    // MARK: - 空提示

    private var emptyHint: some View {
        VStack(spacing: 12) {
            Text("🎧")
                .font(.system(size: 36))
            Text("暂无音频".localized())
                .font(.system(size: 16, weight: .semibold))
            Text("前往「语音合成」生成你的第一条音频".localized())
                .font(AppFont.bodyMedium)
                .foregroundStyle(AppColor.textTertiary)
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

/// 类型别名：保留 ProjectsView 名称，便于 Xcode 工程引用与未来扩展。
typealias ProjectsView = HistoryView