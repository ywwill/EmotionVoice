//
//  HistoryListViewModel.swift
//  iOSEmora
//
//  iOS 历史记录页专用列表模型。
//
//  与 macOS 共用的 `HistoryViewModel` 保持原样（那边是「分页 + 已加载数据里过滤」）：
//  - 本 VM 一次拉全量（`fetchAllAudios`），**全库检索**覆盖 名称 / 文案 / 音色；
//  - 搜索态不分页（命中即全显），默认列表按 50 条一批上拉追加；
//  - 时间分组（今天 / 昨天 / 本周 / 更早）+ 统计条，统计恒为全量；
//  - 收藏 / 软删交给 `AudioFlagStore`，本 VM 只负责把标记排除出数据源。
//
//  ⚠️ 刷新节奏（淡出 0.1s → 换数据 → 淡入 0.28s / 滚动复位）由 `ProjectsView` 驱动，
//     所以这里 `@Published` 属性都**不挂 didSet**：`rebuild()` 是唯一数据出口。
//

import Foundation
import SwiftUI
import Combine

// MARK: - 筛选 / 搜索 / 排序

enum HistoryFilter: String, CaseIterable {
    case all
    case favorites
}

enum HistorySearchScope: String, CaseIterable, Identifiable {
    case all
    case name
    case text
    case voice

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "全部字段".localized()
        case .name: return "名称".localized()
        case .text: return "文案".localized()
        case .voice: return "音色".localized()
        }
    }
}

enum HistorySortOrder: String, CaseIterable {
    case newest
    case oldest

    var title: String {
        self == .newest ? "最新优先".localized() : "最早优先".localized()
    }
}

struct HistorySection: Identifiable {
    let id: String
    let title: String
    /// 组头右侧的补充说明（更早组带日期）
    var detail: String? = nil
    let count: Int
    var items: [AudioItem]
}

// MARK: - ViewModel

@MainActor
final class HistoryListViewModel: ObservableObject {

    @Published var sections: [HistorySection] = []
    @Published var searchText: String = ""
    @Published var searchScope: HistorySearchScope = .all
    @Published var filter: HistoryFilter = .all
    @Published var sortOrder: HistorySortOrder = .newest

    @Published var isLoading: Bool = false
    @Published var totalCount: Int = 0
    @Published var totalBytes: Int = 0
    @Published var monthlyCount: Int = 0
    @Published var favoriteTotalCount: Int = 0
    @Published var resultCount: Int = 0
    @Published var hasMoreVisible: Bool = false

    private static let pageStep = 50
    private var visibleCount: Int = 50
    private var allAudios: [AudioItem] = []
    private var voiceNames: [String: String] = [:]
    private let flags = AudioFlagStore.shared

    var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 供行卡片取本地化音色名（body 里不许查库）。
    func voiceName(for audio: AudioItem) -> String {
        voiceNames[audio.voice] ?? audio.voice
    }

    // MARK: 载入

    /// 重新拉全量。软删 / 恢复 / 到期清理之后统一走这里。
    func load() {
        isLoading = true
        // 到期清理：磁盘删除在事务之外做，不夹动画。
        let expired = flags.purgeExpired()
        if !expired.isEmpty {
            for id in expired { ProjectService.shared.deleteAudio(id: id) }
        }
        allAudios = ProjectService.shared.fetchAllAudios()
        var map: [String: String] = [:]
        for voice in VoiceService.shared.fetchAll() { map[voice.key] = voice.localizedName }
        voiceNames = map
        visibleCount = Self.pageStep
        isLoading = false
        rebuild()
    }

    func loadMoreVisible() {
        guard hasMoreVisible else { return }
        visibleCount += Self.pageStep
        rebuild()
    }

    // MARK: 就地增删（纯内存，磁盘 IO 由调用方放在动画事务之外）

    /// 左滑「复制」：副本插在被操作行的下面，不整表 reload（会把刚操作的行顶出视野）。
    func insertItem(_ item: AudioItem, after afterID: Int64) {
        let at = allAudios.firstIndex(where: { $0.id == afterID })
            .map { min($0 + 1, allAudios.count) } ?? 0
        allAudios.insert(item, at: at)
        rebuild()
    }

    /// 软删：立刻从数据源移除，统计同步 −1。
    func removeItems(_ ids: Set<Int64>) {
        allAudios.removeAll { ids.contains($0.id) }
        rebuild()
    }

    func renameItem(_ id: Int64, name: String) {
        if let idx = allAudios.firstIndex(where: { $0.id == id }) {
            allAudios[idx].displayName = name
        }
        rebuild()
    }

    /// 唯一的重算出口：搜索 → 筛选 → 排序 → 可见条数 → 分组 → 统计。
    func rebuild() {
        let cal = Calendar.current
        let now = Date()
        let active = allAudios.filter { !flags.isDeleted($0.id) }

        // ① 统计恒为全量（不受搜索 / 筛选影响）
        totalCount = active.count
        totalBytes = active.reduce(0) { $0 + $1.fileSize }
        monthlyCount = active.filter {
            cal.isDate($0.createdAt, equalTo: now, toGranularity: .month)
        }.count
        favoriteTotalCount = flags.favoriteCount(in: active.map(\.id))

        // ② 全库检索
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        var matched = active
        if !query.isEmpty {
            matched = matched.filter { matches($0, query: query) }
        }
        resultCount = matched.count

        // ③ 收藏筛选（与「全部」单选互斥）
        if filter == .favorites {
            matched = matched.filter { flags.isFavorite($0.id) }
        }

        // ④ 排序
        matched.sort { lhs, rhs in
            sortOrder == .newest ? lhs.createdAt > rhs.createdAt : lhs.createdAt < rhs.createdAt
        }

        // ⑤ 分页：搜索态一次给全，默认列表 50 条一批
        let total = matched.count
        let shown: [AudioItem]
        if query.isEmpty {
            let cap = min(visibleCount, total)
            shown = Array(matched.prefix(cap))
            hasMoreVisible = total > cap
        } else {
            shown = matched
            hasMoreVisible = false
        }

        sections = makeSections(shown)
    }

    // MARK: 匹配

    private func matches(_ audio: AudioItem, query: String) -> Bool {
        let name = audio.shownName
        let voice = voiceName(for: audio)
        switch searchScope {
        case .all:
            return name.localizedCaseInsensitiveContains(query)
                || audio.text.localizedCaseInsensitiveContains(query)
                || voice.localizedCaseInsensitiveContains(query)
                || audio.voice.localizedCaseInsensitiveContains(query)
        case .name:
            return name.localizedCaseInsensitiveContains(query)
        case .text:
            return audio.text.localizedCaseInsensitiveContains(query)
        case .voice:
            return voice.localizedCaseInsensitiveContains(query)
                || audio.voice.localizedCaseInsensitiveContains(query)
        }
    }

    // MARK: 分组

    private func makeSections(_ items: [AudioItem]) -> [HistorySection] {
        let cal = Calendar.current
        let now = Date()
        let startToday = cal.startOfDay(for: now)
        let startYesterday = cal.date(byAdding: .day, value: -1, to: startToday) ?? startToday
        let startWeek = cal.date(from: cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: now)) ?? startToday

        var today: [AudioItem] = []
        var yesterday: [AudioItem] = []
        var week: [AudioItem] = []
        var older: [AudioItem] = []
        for item in items {
            if item.createdAt >= startToday { today.append(item) }
            else if item.createdAt >= startYesterday { yesterday.append(item) }
            else if item.createdAt >= startWeek { week.append(item) }
            else { older.append(item) }
        }

        let ascending = sortOrder == .oldest
        func arrange(_ list: [AudioItem]) -> [AudioItem] {
            ascending ? list.sorted { $0.createdAt < $1.createdAt }
                      : list.sorted { $0.createdAt > $1.createdAt }
        }

        var groups: [(String, String?, [AudioItem])] = [
            ("今天".localized(), nil, arrange(today)),
            ("昨天".localized(), nil, arrange(yesterday)),
            ("本周".localized(), nil, arrange(week)),
            ("更早".localized(), older.first.map { Self.monthDay($0.createdAt) }, arrange(older))
        ]
        if ascending { groups.reverse() }

        return groups.compactMap { title, detail, list in
            guard !list.isEmpty else { return nil }
            return HistorySection(id: title, title: title, detail: detail,
                                  count: list.count, items: list)
        }
    }

    // MARK: 时间文案

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f
    }()

    private static let monthDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM-dd"
        return f
    }()

    private static let fullDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "M月d日 HH:mm"
        return f
    }()

    /// 行内右上的时间锚点：今天=时分 / 昨天=「昨天」/ 更早=MM-dd
    static func rowTime(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return timeFormatter.string(from: date) }
        if cal.isDateInYesterday(date) { return "昨天".localized() }
        return monthDayFormatter.string(from: date)
    }

    static func monthDay(_ date: Date) -> String {
        monthDayFormatter.string(from: date)
    }

    /// 最近删除页：「今天 14:32 移入」/「10月24日 移入」
    static func deletedTime(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) {
            return "今天 %@ 移入".localized(timeFormatter.string(from: date))
        }
        if cal.isDateInYesterday(date) {
            return "昨天 %@ 移入".localized(timeFormatter.string(from: date))
        }
        return "%@ 移入".localized(fullDateFormatter.string(from: date))
    }
}
