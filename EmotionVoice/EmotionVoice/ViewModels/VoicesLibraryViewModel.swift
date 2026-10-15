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

    // MARK: - 用户输入（引用外部状态）

    /// 当前选中的分类（nil 表示"全部"）
    var selectedCategory: VoiceCategory?
    /// 搜索文本
    var searchText: String
    /// 是否仅显示收藏
    var showFavoritesOnly: Bool
    /// 当前页码
    var currentPage: Int

    // MARK: - 分页状态
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
    /// 首屏是否仍在加载：用于驱动骨架屏。初始为 true，
    /// 视图 onAppear 后再异步发起 load()，确保骨架先上屏、避免一次性同步查询阻塞首帧。
    @Published private(set) var isLoading: Bool = true
    /// sheet 进入并成功定位到选中音色后，发出待滚动到的音色 key（视图据此 scrollTo）
    @Published private(set) var scrollTargetVoiceKey: String? = nil

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
    /// 缓存：当前查询签名下「过滤 + 排序」后的完整**有序 key 列表**（仅 [String]，几十 KB）。
    /// 仅在签名变化（切分类 / 搜索 / 切收藏）时重算；纯翻页只对其切片，再按 key 取当前这一窗的 Voice 对象。
    /// 这样上一页的 Voice 对象不保留，内存稳定，也不会连点翻页时反复全表重查 + 全量排序。
    private var cachedOrderedKeys: [String] = []

    /// 待定位音色 key（sheet 进入时，需翻到「当前选中音色」所在页）。
    /// 实际翻页要等视图测出最终 pageSize 后再执行（见 commitPageSize / finalizePendingJump）。
    private var pendingJumpToVoiceKey: String?
    /// pageSize 是否已由视图几何确定（只有确定后才能正确计算目标页码）
    private var pageSizeFinalized: Bool = false

    /// "全部"chip 的特殊 key
    private static let allKey = "__all__"

    // MARK: - 初始化

    init(
        selectedCategory: VoiceCategory?,
        searchText: String,
        showFavoritesOnly: Bool,
        currentPage: Int
    ) {
        self.selectedCategory = selectedCategory
        self.searchText = searchText
        self.showFavoritesOnly = showFavoritesOnly
        self.currentPage = currentPage

        // 不在 init 里同步加载：全表过滤 + 排序 + 逐分类 count（约 17 次查询）
        // 会阻塞主线程导致首屏卡顿。改为由视图 onAppear 后的 load() 异步触发，
        // 期间 isLoading 为 true，视图先绘制骨架屏。
        isLoading = true
    }

    /// 从 AppState 同步最新状态（当视图重新出现时调用）
    func syncFromAppState(
        selectedCategory: VoiceCategory?,
        searchText: String,
        showFavoritesOnly: Bool,
        currentPage: Int
    ) {
        self.selectedCategory = selectedCategory
        self.searchText = searchText
        self.showFavoritesOnly = showFavoritesOnly
        self.currentPage = currentPage
        // 仅设置参数，不在此加载；实际加载统一交给 load()
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
        // 首屏骨架阶段（isLoading）只确定列数，不做实际查询；
        // 真正的取数统一在 load() 里完成，避免骨架期间被提前/重复触发。
        if !isLoading {
            reloadCurrentPage()
        }
    }

    /// 由视图在测得**最终** pageSize 后调用：设定 pageSize，并在有待定位音色时翻到对应页。
    /// （几何 onAppear / 宽度变化都会触发，保证定位只发生在 pageSize 确定之后）
    func commitPageSize(_ size: Int) {
        setPageSize(size)
        pageSizeFinalized = true
        // 骨架阶段尚未取数，跳过定位；load() 完成后再做 finalizePendingJump
        if !isLoading {
            finalizePendingJump()
        }
    }

    /// sheet 进入：重置筛选为「全部」（保证选中音色一定在结果集内），
    /// 先填充有序列表，再等 pageSize 确定后翻到该音色所在页。
    func jumpToVoice(key: String?) {
        pendingJumpToVoiceKey = key
        selectedCategory = nil
        searchText = ""
        showFavoritesOnly = false
        currentPage = 1
        lastQueryKey = ""   // 强制重算有序列表（全部、无筛选）
        // 不在此加载；填充 cachedOrderedKeys 与定位交由 load() 完成
    }

    /// 在有序列表中定位待定位音色并翻页（仅当 pageSize 已确定且存在待定位项时生效）
    private func finalizePendingJump() {
        guard pageSizeFinalized else { return }
        guard let key = pendingJumpToVoiceKey, !key.isEmpty else {
            pendingJumpToVoiceKey = nil
            return
        }
        if let index = cachedOrderedKeys.firstIndex(of: key) {
            currentPage = index / pageSize + 1
            pendingJumpToVoiceKey = nil
            reloadCurrentPage()
            scrollTargetVoiceKey = key // 通知视图滚动到该卡片
        } else {
            // 理论上重置为「全部」后该音色必然在集内；若不在则停留在第一页
            pendingJumpToVoiceKey = nil
        }
    }

    // MARK: - 数据加载

    /// 首屏加载入口：在视图 onAppear 后**异步**调用（通过 Task 让骨架屏先绘制）。
    /// 统一完成「填充有序 key 列表 + chip 计数 + 取当前页」，
    /// 随后置 isLoading = false 由视图切到真实网格，避免重复加载与首帧阻塞。
    func load() {
        reloadCurrentPage()
        finalizePendingJump()
        isLoading = false
    }

    /// 重新加载当前页：
    /// - 查询签名（分类 / 搜索 / 收藏）变化时才重查「完整有序结果 + 总数 + chip 计数」并缓存
    /// - 纯翻页（签名不变）直接对缓存结果切片，不再全表重查 + 全量排序（避免连点翻页 CPU / 内存飙升）
    /// 注意：搜索时忽略分类，在全部数据中搜索
    func reloadCurrentPage() {
        let needle = searchText.trimmingCharacters(in: .whitespaces)
        // 搜索时忽略分类，在全部数据中搜索
        let isSearching = !needle.isEmpty
        let category = isSearching ? nil : selectedCategory
        let showingFavorites = showFavoritesOnly
        let key = "\(showingFavorites ? "__fav__" : (category?.rawValue ?? Self.allKey))|\(needle)"

        // 查询签名变化 → 重新计算有序 key 列表、总数与 chip 计数
        if key != lastQueryKey {
            // 只取「过滤 + 排序」后的有序 key 列表（轻量），Voice 对象按需按页取
            cachedOrderedKeys = VoiceService.shared.orderedVoices(
                showingFavorites: showingFavorites,
                category: category,
                searchText: needle
            ).map(\.key)
            totalCount = cachedOrderedKeys.count
            totalPages = max(1, Int(ceil(Double(totalCount) / Double(pageSize))))
            if currentPage > totalPages { currentPage = totalPages }
            reloadChipCounts(searchText: needle)
            lastQueryKey = key
        }

        // 翻页：对有序 key 列表按 offset 切片，再只取当前这一窗的 Voice 对象
        // （上一页的 Voice 对象随 displayedVoices 被替换而释放，不保留）
        let start = min(max(0, (currentPage - 1) * pageSize), cachedOrderedKeys.count)
        let end = min(start + pageSize, cachedOrderedKeys.count)
        let windowKeys = Array(cachedOrderedKeys[start..<end])
        displayedVoices = VoiceService.shared.fetchByKeys(windowKeys)
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

    /// 切换收藏：更新数据库，刷新当前页与收藏数。
    /// 缓存只存 key：非收藏视图下该项仍属原分类，无需改缓存；
    /// 「仅收藏」视图下取消收藏时，从有序 key 列表移除该项并重算总数 / 页数。
    func toggleFavorite(key: String) {
        let newState = VoiceService.shared.toggleFavorite(key: key)
        if showFavoritesOnly, newState == false {
            // 「仅收藏」视图下取消收藏：该项不再满足过滤条件
            cachedOrderedKeys.removeAll { $0 == key }
            totalCount = cachedOrderedKeys.count
            totalPages = max(1, Int(ceil(Double(totalCount) / Double(pageSize))))
            if currentPage > totalPages { currentPage = totalPages }
        }
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
