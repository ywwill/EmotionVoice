//
//  VoicesLibraryViewModel.swift
//  EmotionVoice
//
//  Created by young on 2026/8/15.
//
//  音色库视图模型：
//  - 选中分类 + 搜索文本变化时重置分页并加载
//  - 分页（pageSize = N 行 × 实际列数）从数据库按需查询，避免一次性加载全表
//  - chip 数量缓存于 chipCounts，按 searchText 防抖刷新
//

import Foundation
import SwiftUI
import Combine

@MainActor
final class VoicesLibraryViewModel: ObservableObject {

    // MARK: - 用户输入

    /// 当前选中的分类（nil 表示"全部"）
    @Published var selectedCategory: VoiceCategory? = nil
    /// 搜索文本
    @Published var searchText: String = ""
    /// 是否仅显示收藏
    @Published var showFavoritesOnly: Bool = false

    // MARK: - 分页状态

    /// 当前页码（1-based）
    @Published private(set) var currentPage: Int = 1
    /// 每页显示数量（默认 16 = 4 行 × 4 列；视图按实际列数动态调整）
    @Published private(set) var pageSize: Int = 16
    /// 命中总数（按当前 selectedCategory + searchText 过滤）
    @Published private(set) var totalCount: Int = 0
    /// 总页数（>=1）
    @Published private(set) var totalPages: Int = 1
    /// 当前页的音色列表
    @Published private(set) var displayedVoices: [Voice] = []
    /// 当前结果是否为空（不区分页码）
    @Published private(set) var isEmpty: Bool = true

    // MARK: - Chip 计数（按 searchText 缓存）

    /// 全部命中数（用于"全部"chip）
    @Published private(set) var totalMatched: Int = 0
    /// 全部音色数（忽略搜索和分类）
    @Published private(set) var totalAll: Int = 0
    /// 收藏数
    @Published private(set) var favoriteCount: Int = 0
    /// 每个分类命中数缓存（key: VoiceCategory.rawValue）
    @Published private(set) var chipCounts: [String: Int] = [:]

    // MARK: - 内部

    private var cancellables: Set<AnyCancellable> = []
    /// 上次查询的签名（用于判断是否需要重新计算 totalCount）
    private var lastQueryKey: String = ""

    /// "全部"chip 的特殊 key
    private static let allKey = "__all__"

    // MARK: - 初始化

    init() {
        // 分类 / 搜索 / 收藏筛选变化 → 重置到第 1 页并重新加载
        Publishers.CombineLatest3($selectedCategory, $searchText, $showFavoritesOnly)
            .dropFirst()
            .debounce(for: .milliseconds(180), scheduler: RunLoop.main)
            .sink { [weak self] _, _, _ in
                guard let self else { return }
                self.currentPage = 1
                self.reloadCurrentPage()
            }
            .store(in: &cancellables)

        // 首次加载（无需防抖）
        reloadCurrentPage()
    }

    // MARK: - 分页操作

    /// 跳转到指定页（自动 clamp）
    func goToPage(_ page: Int) {
        let target = max(1, min(page, totalPages))
        guard target != currentPage else { return }
        currentPage = target
        reloadCurrentPage()
    }

    func nextPage() { goToPage(currentPage + 1) }
    func prevPage() { goToPage(currentPage - 1) }

    /// 设置每页大小（视图在测得列数后调用）
    /// 若发生变化，会重新计算 totalPages 并加载当前页
    func setPageSize(_ size: Int) {
        let new = max(1, size)
        guard new != pageSize else { return }
        pageSize = new
        totalPages = max(1, Int(ceil(Double(totalCount) / Double(pageSize))))
        if currentPage > totalPages { currentPage = totalPages }
        reloadCurrentPage()
    }

    // MARK: - 数据加载

    /// 重新加载当前页：刷新总数（如签名变化）+ 重新拉取当前页数据
    func reloadCurrentPage() {
        let needle = searchText.trimmingCharacters(in: .whitespaces)
        let category = selectedCategory
        let showingFavorites = showFavoritesOnly
        let key = "\(showingFavorites ? "__fav__" : (category?.rawValue ?? Self.allKey))|\(needle)"

        // 查询签名变化 → 重新查询总数与 chip 计数
        if key != lastQueryKey {
            if showingFavorites {
                totalCount = VoiceService.shared.countFavorites(searchText: needle)
            } else {
                totalCount = VoiceService.shared.count(category: category, searchText: needle)
            }
            totalPages = max(1, Int(ceil(Double(totalCount) / Double(pageSize))))
            if currentPage > totalPages { currentPage = totalPages }
            reloadChipCounts(searchText: needle)
            lastQueryKey = key
        }

        // 拉取当前页数据（limit + offset）
        let offset = (currentPage - 1) * pageSize
        let limit = pageSize

        let voices: [Voice]
        if showingFavorites {
            voices = VoiceService.shared.fetchFavorites(searchText: needle, limit: limit, offset: offset)
        } else {
            // "全部"分类：旗舰音色始终排在最前面
            voices = VoiceService.shared.fetch(
                category: category,
                searchText: needle,
                limit: limit,
                offset: offset,
                orderByPremiumFirst: (category == nil)
            )
        }

        displayedVoices = voices
        isEmpty = (totalCount == 0)
    }

    /// 刷新所有 chip 上的命中数量（仅依赖 searchText）
    private func reloadChipCounts(searchText: String) {
        let needle = searchText.trimmingCharacters(in: .whitespaces)

        var newCounts: [String: Int] = [:]

        // "全部"
        let allCount = VoiceService.shared.count(category: nil, searchText: needle)
        newCounts[Self.allKey] = allCount
        totalMatched = allCount

        // 每个分类
        for cat in VoiceCategory.allCases {
            newCounts[cat.rawValue] = VoiceService.shared.count(category: cat, searchText: needle)
        }

        chipCounts = newCounts

        // 全部音色总数与收藏总数（不受搜索影响）
        totalAll = VoiceService.shared.count(category: nil, searchText: "")
        favoriteCount = VoiceService.shared.countFavorites()
    }

    /// 查询某个分类的命中数量（chip 显示）
    func countForCategory(_ cat: VoiceCategory) -> Int {
        chipCounts[cat.rawValue] ?? 0
    }

    // MARK: - 收藏

    /// 切换收藏：更新数据库，刷新当前页，更新收藏数
    func toggleFavorite(key: String) {
        _ = VoiceService.shared.toggleFavorite(key: key)
        // 当前页需要重取以反映 isFavorite 变化
        reloadCurrentPage()
        // 收藏数同步刷新（搜索状态无关）
        favoriteCount = VoiceService.shared.countFavorites()
    }

    // MARK: - Chip 互斥选择

    /// 选择某个分类：清空收藏筛选
    func selectCategory(_ cat: VoiceCategory) {
        selectedCategory = (selectedCategory == cat) ? nil : cat
        showFavoritesOnly = false
    }

    /// 切换收藏筛选：清空分类选择
    func toggleFavoritesFilter() {
        showFavoritesOnly.toggle()
        if showFavoritesOnly {
            selectedCategory = nil
        }
    }
}
