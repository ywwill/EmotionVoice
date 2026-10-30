//
//  VoicesLibraryView.swift
//  iOSEmora
//
//  音色库标签页
//
//  与 macOS 的结构差异：**取消横向 chip 模块**。iPhone 只有 371pt 可用宽，
//  31 项 chip 横滚两行既看不全也不好点，改成一个「分类按钮 + 收藏按钮」的行，
//  点按钮弹全部分类 Sheet。
//
//  七条交互规则全部沿用源码语义，iOS 不改：
//  ① 分类单选互斥 ② 分类与收藏互斥 ③ 每行数字恒为**全量统计**（不随搜索变化）
//  ④ 搜索时忽略当前分类，在全库匹配 ⑤ 搜索只命中 4 个字段
//  ⑥ 排序固定「旗舰优先 → 展示名字典序」，没有排序控件
//  ⑦ macOS pageSize = 列数 × 4 的分页在 iOS 改成上拉追加。
//

import SwiftUI

struct VoicesLibraryView: View {
    @Environment(\.aurora) private var c
    @Environment(\.screenMetrics) private var metrics

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var uiState: IOSUIState
    @EnvironmentObject private var router: TabRouter

    @StateObject private var vm = VoicesLibraryViewModel(
        selectedCategory: nil, searchText: "", showFavoritesOnly: false, currentPage: 1
    )
    @StateObject private var player = AudioPreviewPlayer.shared

    // MARK: 筛选状态（镜像 AppState，切标签回来不丢）

    @State private var selectedCategory: VoiceCategory? = nil
    @State private var searchText: String = ""
    @State private var showFavoritesOnly: Bool = false

    // MARK: 追加式加载

    @State private var page: Int = 1
    @State private var voices: [Voice] = []
    @State private var totalCount: Int = 0
    @State private var didLoad = false
    @State private var isAppending = false

    @State private var sheetPresented = false

    /// 搜索防抖用的 Task（每次键击都全表过滤会很卡）
    @State private var searchTask: Task<Void, Never>? = nil

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 10),
              count: metrics.voiceGridColumns)
    }

    private var pageSize: Int { metrics.voiceGridColumns * 4 }

    private var hasMore: Bool { voices.count < totalCount }

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            filterBar
            resultBar

            ScrollView {
                LazyVGrid(columns: columns, spacing: 10) {
                    if didLoad {
                        ForEach(voices) { voice in
                            VoiceCardGrid(
                                voice: voice,
                                isPreviewing: player.playingKey == voice.key && player.isPlaying,
                                onPreview: { togglePreview(voice) },
                                onFavorite: { toggleFavorite(voice) },
                                onUse: { useVoice(voice) }
                            )
                            .onAppear {
                                // 触底追加：最后一张卡出现时拉下一页
                                if voice.key == voices.last?.key { loadMore() }
                            }
                        }
                    } else {
                        ForEach(0..<8, id: \.self) { _ in VoiceCardSkeleton() }
                    }
                }
                .pagePadding()
                .padding(.bottom, 4)

                if didLoad && hasMore {
                    appendFooter
                } else if didLoad && voices.isEmpty {
                    emptyState
                } else if didLoad {
                    endFooter
                }
            }
        }
        .background(c.backgroundGrouped)
        .navigationTitle("音色库".localized())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { router.openSettings() } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(c.accent)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .sheet(isPresented: $sheetPresented) {
            CategoryFilterSheet(
                selectedCategory: $selectedCategory,
                showFavoritesOnly: $showFavoritesOnly,
                counts: vm.chipCounts,
                totalAll: vm.totalAll,
                favoriteCount: vm.favoriteCount,
                onCommit: { reload() },
                onDismiss: { sheetPresented = false }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .task { initialLoad() }
        .onChange(of: searchText) { _, _ in scheduleSearch() }
        .onDisappear { player.stop() }
    }

    // MARK: 搜索框

    private var searchBar: some View {
        AuroraSearchField(text: $searchText,
                          placeholder: "搜索音色名 / 特质 / 场景 / 语种".localized())
        .padding(.horizontal, metrics.pageMargin)
        .padding(.top, 2)
        .padding(.bottom, 10)
    }

    // MARK: 分类按钮 + 收藏按钮

    private var filterBar: some View {
        HStack(spacing: 8) {
            filterButton
            favoriteButton
        }
        .padding(.horizontal, metrics.pageMargin)
        .padding(.bottom, 8)
    }

    private var filterButton: some View {
        HStack(spacing: 0) {
            Button {
                sheetPresented = true
            } label: {
                HStack(spacing: 7) {
                    if let cat = selectedCategory {
                        Text(cat.icon)
                            .font(.system(size: 15))
                        Text(cat.displayName)
                            .font(.system(size: 14, weight: .medium))
                            .lineLimit(1)
                        Text("\(vm.countForCategory(cat))")
                            .font(.system(size: 12.5, design: .monospaced))
                            .foregroundStyle(c.accent.opacity(0.75))
                    } else {
                        Image(systemName: "list.bullet")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(c.textSecondary)
                        Text("全部分类".localized())
                            .font(.system(size: 14, weight: .medium))
                            .lineLimit(1)
                        Text("\(vm.totalAll)")
                            .font(.system(size: 12.5, design: .monospaced))
                            .foregroundStyle(c.textTertiary)
                    }
                }
                .foregroundStyle(c.textPrimary)
                .padding(.leading, 12)
                .padding(.trailing, 6)
                .frame(height: 36)
            }
            .buttonStyle(.plain)

            if selectedCategory != nil {
                Button {
                    selectedCategory = nil
                    reload()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(c.accent.opacity(0.8))
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(c.accent.opacity(0.18)))
                }
                .buttonStyle(.plain)
                .padding(.trailing, 4)
            }

            Image(systemName: "chevron.down")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(c.textTertiary)
                .padding(.trailing, 12)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Capsule(style: .continuous)
                .fill(selectedCategory == nil ? c.surface : c.accentSoft)
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(selectedCategory == nil ? c.line : c.accent.opacity(0.35),
                                      lineWidth: 0.5)
                )
        )
        .contentShape(Capsule(style: .continuous))
    }

    private var favoriteButton: some View {
        Button {
            showFavoritesOnly.toggle()
            if showFavoritesOnly { selectedCategory = nil }
            reload()
        } label: {
            HStack(spacing: 5) {
                Image(systemName: showFavoritesOnly ? "heart.fill" : "heart")
                    .font(.system(size: 13, weight: .semibold))
                Text("\(vm.favoriteCount)")
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
            }
            .foregroundStyle(showFavoritesOnly ? AuroraDecor.rose : c.textSecondary)
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(
                Capsule(style: .continuous)
                    .fill(showFavoritesOnly ? AuroraDecor.rose.opacity(0.14) : c.surface)
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(showFavoritesOnly ? AuroraDecor.rose.opacity(0.4) : c.line,
                                          lineWidth: 0.5)
                    )
            )
        }
        .buttonStyle(.plain)
        // 分类按钮是 maxWidth:.infinity，固定尺寸才能让收藏按钮不被挤扁
        .fixedSize(horizontal: true, vertical: false)
    }

    // MARK: 结果行

    private var resultBar: some View {
        HStack(spacing: 8) {
            if let cat = selectedCategory {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                    Text(String(format: "%@ · %d 个".localized(), cat.displayName, totalCount))
                        .font(.system(size: 12))
                }
                .foregroundStyle(c.accent)
                Text("点 ✕ 取消筛选".localized())
                    .font(.system(size: 12))
                    .foregroundStyle(c.textTertiary)
            } else if showFavoritesOnly {
                Text(String(format: "仅看收藏 · %d 个".localized(), totalCount))
                    .font(.system(size: 12))
                    .foregroundStyle(AuroraDecor.rose)
            } else {
                Text(String(format: "共 %d 个 · 旗舰优先，再按名称排序".localized(), totalCount))
                    .font(.system(size: 12))
                    .foregroundStyle(c.textTertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, metrics.pageMargin)
        .padding(.bottom, 8)
    }

    // MARK: 底部

    private var appendFooter: some View {
        HStack(spacing: 7) {
            ProgressView()
                .controlSize(.small)
            Text(String(format: "上拉加载更多 · 已显示 %d / %d".localized(), voices.count, totalCount))
                .font(.system(size: 12))
                .foregroundStyle(c.textTertiary)
        }
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity)
    }

    private var endFooter: some View {
        Text(String(format: "已显示全部 %d 个音色".localized(), totalCount))
            .font(.system(size: 12))
            .foregroundStyle(c.textTertiary)
            .padding(.vertical, 18)
            .frame(maxWidth: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 30))
                .foregroundStyle(c.textTertiary.opacity(0.6))
            Text("没有匹配的音色".localized())
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(c.textSecondary)
            Text("试试换个关键词，或清除筛选条件".localized())
                .font(.system(size: 12))
                .foregroundStyle(c.textTertiary)
        }
        .padding(.top, 70)
        .frame(maxWidth: .infinity)
    }

    // MARK: - 数据

    private func initialLoad() {
        guard !didLoad else { return }
        // 恢复上次的筛选状态
        selectedCategory = appState.voiceLibrarySelectedCategory
        searchText = appState.voiceLibrarySearchText
        showFavoritesOnly = appState.voiceLibraryShowFavoritesOnly
        reload()
        didLoad = true
    }

    /// 重新按当前筛选取首页并整体替换
    private func reload() {
        page = 1
        vm.setPageSize(pageSize)
        syncToVM()
        vm.reloadCurrentPage()
        voices = vm.displayedVoices
        totalCount = vm.totalCount
        persist()
    }

    /// 追加下一页
    private func loadMore() {
        guard didLoad, hasMore, !isAppending else { return }
        isAppending = true
        let next = page + 1
        vm.currentPage = next
        syncToVM()
        vm.reloadCurrentPage()
        let fresh = vm.displayedVoices
        if fresh.isEmpty {
            isAppending = false
            return
        }
        let known = Set(voices.map(\.key))
        voices.append(contentsOf: fresh.filter { !known.contains($0.key) })
        totalCount = vm.totalCount
        page = next
        isAppending = false
    }

    private func syncToVM() {
        vm.syncFromAppState(selectedCategory: selectedCategory,
                            searchText: searchText,
                            showFavoritesOnly: showFavoritesOnly,
                            currentPage: page)
    }

    private func persist() {
        appState.voiceLibrarySelectedCategory = selectedCategory
        appState.voiceLibrarySearchText = searchText
        appState.voiceLibraryShowFavoritesOnly = showFavoritesOnly
        appState.voiceLibraryCurrentPage = page
    }

    /// 搜索防抖：每次键击都全表过滤会很卡
    private func scheduleSearch() {
        searchTask?.cancel()
        let needle = searchText
        searchTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 280_000_000)
            guard !Task.isCancelled, needle == searchText else { return }
            reload()
        }
    }

    // MARK: - 行为

    private func togglePreview(_ voice: Voice) {
        if player.playingKey == voice.key && player.isPlaying {
            player.stop()
        } else {
            _ = player.play(key: voice.key)
        }
    }

    private func toggleFavorite(_ voice: Voice) {
        // 翻转是确定的，先记下目标态；DB 写入 / 缓存维护 / 计数刷新交给 VM
        let newState = !voice.isFavorite
        vm.toggleFavorite(key: voice.key)
        guard let idx = voices.firstIndex(where: { $0.key == voice.key }) else { return }
        if showFavoritesOnly && !newState {
            // 「仅收藏」视图下取消收藏：该项不再满足过滤条件
            voices.remove(at: idx)
        } else {
            var updated = voices[idx]
            updated.isFavorite = newState
            voices[idx] = updated
        }
        totalCount = vm.totalCount
    }

    private func useVoice(_ voice: Voice) {
        appState.selectedVoice = voice
        VoiceStudioViewModel.shared.selectedVoiceKey = voice.key
        player.stop()
        router.selection = .studio
        uiState.showToast(.success(String(format: "已切换到「%@」".localized(), voice.localizedName)))
    }
}
