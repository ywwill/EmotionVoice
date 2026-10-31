//
//  VoicePickerSheet.swift
//  iOSEmora
//
//  工作台里的「更换音色」。
//
//  结构完全对齐 `VoicesLibraryView`：搜索 + 分类 / 收藏筛选 + 卡片网格（上拉追加），
//  交互规则（分类单选互斥、分类与收藏互斥、搜索时忽略分类、计数恒为全量）同样沿用。
//
//  两点差异：
//   ① 点卡片（非按钮区）或卡片右下角箭头 = 选中并关闭，不再有「跳回创作页」；
//   ② 筛选状态是 Sheet 私有的 @State，不写回 AppState —— 免得选个音色把音色库的筛选改了。
//
//  分类列表**就地替换内容区**而不是再开一层 Sheet：两层 detent 同时存在时拖拽手势会打架。
//

import SwiftUI

struct VoicePickerSheet: View {
    @Environment(\.aurora) private var c
    @Environment(\.screenMetrics) private var metrics
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var uiState: IOSUIState

    @Binding var selectedKey: String

    @StateObject private var vm = VoicesLibraryViewModel(
        selectedCategory: nil, searchText: "", showFavoritesOnly: false, currentPage: 1
    )
    @StateObject private var player = AudioPreviewPlayer.shared

    // MARK: 筛选状态（Sheet 私有）

    @State private var selectedCategory: VoiceCategory? = nil
    @State private var searchText: String = ""
    @State private var showFavoritesOnly: Bool = false

    // MARK: 追加式加载

    @State private var page: Int = 1
    @State private var voices: [Voice] = []
    @State private var totalCount: Int = 0
    @State private var didLoad = false
    @State private var isAppending = false

    @State private var categoryPresented = false

    /// 搜索防抖用的 Task（每次键击都全表过滤会很卡）
    @State private var searchTask: Task<Void, Never>? = nil

    /// 列表滚动位置的「重置版本号」：作为 `ScrollView` 的 id，一自增就整体重建、偏移归零
    @State private var scrollResetID = 0

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 10),
              count: metrics.voiceGridColumns)
    }

    private var pageSize: Int { metrics.voiceGridColumns * 4 }

    private var hasMore: Bool { voices.count < totalCount }

    var body: some View {
        VStack(spacing: 0) {
            if categoryPresented {
                CategoryFilterSheet(
                    selectedCategory: $selectedCategory,
                    showFavoritesOnly: $showFavoritesOnly,
                    counts: vm.chipCounts,
                    totalAll: vm.totalAll,
                    favoriteCount: vm.favoriteCount,
                    onCommit: { reload() },
                    onDismiss: { categoryPresented = false }
                )
            } else {
                navBar
                searchBar
                filterBar
                resultBar
                grid
            }
        }
        .background(c.backgroundGrouped)
        .task { initialLoad() }
        .onChange(of: searchText) { _, _ in scheduleSearch() }
        .onDisappear { player.stop() }
    }

    // MARK: - 顶栏

    private var navBar: some View {
        SheetNavBar(
            title: "选择音色".localized(),
            leading: {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 19, weight: .medium))
                        .foregroundStyle(c.textTertiary)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            },
            trailing: {
                Button { dismiss() } label: {
                    Text("完成".localized())
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(c.accent)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        )
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
                categoryPresented = true
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

    // MARK: 结果行（右侧常驻「当前音色」）

    private var resultBar: some View {
        HStack(spacing: 8) {
            if let cat = selectedCategory {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                    Text("%@ · %d 个".localized(cat.displayName, totalCount))
                        .font(.system(size: 12))
                }
                .foregroundStyle(c.accent)
                Text("点 ✕ 取消筛选".localized())
                    .font(.system(size: 12))
                    .foregroundStyle(c.textTertiary)
            } else if showFavoritesOnly {
                Text("仅看收藏 · %d 个".localized(totalCount))
                    .font(.system(size: 12))
                    .foregroundStyle(AuroraDecor.rose)
            } else {
                Text("共 %d 个 · 旗舰优先，再按名称排序".localized(totalCount))
                    .font(.system(size: 12))
                    .foregroundStyle(c.textTertiary)
            }

            Spacer(minLength: 8)

            if let name = currentVoiceName {
                HStack(spacing: 4) {
                    Image(systemName: "waveform")
                        .font(.system(size: 10, weight: .semibold))
                    Text(name)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                }
                .foregroundStyle(c.accent)
                .layoutPriority(1)
            }
        }
        .padding(.horizontal, metrics.pageMargin)
        .padding(.bottom, 8)
    }

    /// 当前已选音色的展示名（取不到就说明该 key 已下架，右侧不显示）
    private var currentVoiceName: String? {
        guard !selectedKey.isEmpty else { return nil }
        if let hit = voices.first(where: { $0.key == selectedKey }) { return hit.localizedName }
        return VoiceService.shared.voice(forKey: selectedKey)?.localizedName
    }

    // MARK: 网格

    private var grid: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 10) {
                    if didLoad {
                        ForEach(voices) { voice in
                            VoiceCardGrid(
                                voice: voice,
                                isPreviewing: player.playingKey == voice.key && player.isPlaying,
                                onPreview: { togglePreview(voice) },
                                onFavorite: { toggleFavorite(voice) },
                                onUse: { pick(voice) }
                            )
                            // 当前选中项：强调描边（内侧 1.5pt，不盖住卡片内容）
                            .overlay(
                                RoundedRectangle(cornerRadius: AuroraRadius.md, style: .continuous)
                                    .strokeBorder(voice.key == selectedKey ? c.accent.opacity(0.65) : Color.clear,
                                                  lineWidth: 1.5)
                            )
                            .contentShape(Rectangle())
                            // 卡片空白处点击也等于选中；三个按钮在更内层，优先吃掉自己的点击
                            .onTapGesture { pick(voice) }
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
            .id(scrollResetID)
    }

    // MARK: 底部

    private var appendFooter: some View {
        HStack(spacing: 7) {
            ProgressView()
                .controlSize(.small)
            Text("上拉加载更多 · 已显示 %d / %d".localized(voices.count, totalCount))
                .font(.system(size: 12))
                .foregroundStyle(c.textTertiary)
        }
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity)
    }

    private var endFooter: some View {
        Text("已显示全部 %d 个音色".localized(totalCount))
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
        scrollResetID += 1   // 换掉 ScrollView 的 id → 滚动复位到顶部
    }

    /// 追加下一页
    private func loadMore() {
        guard didLoad, hasMore, !isAppending else { return }
        isAppending = true
        let next = page + 1
        // ⚠️ 先写 `page` 再 `syncToVM()`：syncToVM 会把 `page` 灌回 `vm.currentPage`，
        // 反过来的话新页码会被旧页码覆盖，取回来的还是当前页 → 追加恒为空。
        page = next
        syncToVM()
        vm.reloadCurrentPage()
        let known = Set(voices.map(\.key))
        let appended = vm.displayedVoices.filter { !known.contains($0.key) }
        voices.append(contentsOf: appended)
        totalCount = vm.totalCount
        if appended.isEmpty { page = max(1, next - 1) }
        isAppending = false
    }

    private func syncToVM() {
        vm.syncFromAppState(selectedCategory: selectedCategory,
                            searchText: searchText,
                            showFavoritesOnly: showFavoritesOnly,
                            currentPage: page)
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
        // ⚠️ 不能 `play(key:)`：基础音色的 key 带 `qwen-audio-3.0-tts-plus-` 前缀，
        // 而 Bundle 里的资源是 `longbaikehui.m4a` 这种短名，按 key 找永远找不到。
        player.toggle(voice: voice)
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

    private func pick(_ voice: Voice) {
        player.stop()
        selectedKey = voice.key
        uiState.showToast(.success("已切换到「%@」".localized(voice.localizedName)))
        dismiss()
    }
}
