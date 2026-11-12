//
//  ProjectsView.swift
//  iOSEmora
//
//  历史记录

import SwiftUI

struct ProjectsView: View {
    @Environment(\.aurora) private var c
    @Environment(\.screenMetrics) private var metrics

    @EnvironmentObject private var uiState: IOSUIState
    @EnvironmentObject private var router: TabRouter

    @StateObject private var vm = HistoryListViewModel()
    @StateObject private var flags = AudioFlagStore.shared
    @StateObject private var nowPlaying = NowPlayingStore.shared
    
    @StateObject private var status = PlaybackStatus.shared

    // MARK: 多选 / 重命名 / 删除
    @State private var isSelecting = false
    @State private var selectedIDs: Set<Int64> = []
    @State private var renameTarget: AudioItem? = nil
    @State private var renameText: String = ""
    @State private var deleteTarget: AudioItem? = nil
    @State private var deleteMany = false

    // MARK: 分享 / 导出
    @State private var shareURLs: [URL] = []
    @State private var isSharing = false

    // MARK: 菜单 / 刷新节奏
    @State private var moreMenuPresented = false
    @State private var contentVisible = true
    @State private var scrollResetID = 0
    @State private var searchTask: Task<Void, Never>? = nil

    var body: some View {
        VStack(spacing: 0) {
            header
            searchField

            if vm.isSearching {
                HistoryScopeChips(selection: vm.searchScope) { scope in
                    animateRefresh { vm.searchScope = scope }
                }
                HistoryResultBar(count: vm.resultCount, sortOrder: vm.sortOrder)
            }

            HistoryStatBar(count: vm.totalCount, bytes: vm.totalBytes, monthly: vm.monthlyCount)

            HistoryFilterChips(allCount: vm.totalCount,
                               favoriteCount: vm.favoriteTotalCount,
                               selection: vm.filter) { filter in
                animateRefresh { vm.filter = filter }
            }

            listArea
        }
        .background(c.backgroundGrouped)
        // 多选态导航栏中间显示「已选 N 条」；平时留空（大标题在内容区）
        .navigationTitle(isSelecting ? "已选 %d 条".localized(selectedIDs.count) : "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .safeAreaInset(edge: .bottom) {
            if isSelecting { selectionBar }
        }
        .sheet(isPresented: $isSharing) { ShareSheet(items: shareURLs) }
        .overlay {
            if renameTarget != nil {
                RenameDialog(text: $renameText,
                             onCancel: { renameTarget = nil },
                             onSave: { commitRename() })
            }
        }
        .overlay {
            if moreMenuPresented { moreMenu }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: renameTarget?.id)
        .alert("移入最近删除？".localized(), isPresented: deletePresented) {
            Button("取消".localized(), role: .cancel) {
                deleteTarget = nil
                deleteMany = false
            }
            Button("移入最近删除".localized(), role: .destructive) { commitSoftDelete() }
        } message: {
            Text(deleteMessage)
        }
        .onAppear {
            vm.load()
            uiState.hideMiniPlayer = isSelecting
        }
        .onChange(of: vm.searchText) { _, _ in scheduleRefresh() }
        // 详情页 / 最近删除页撤销软删后，列表页早已 onAppear 过 → 靠信号重新拉全量
        .onChange(of: uiState.historyReloadSignal) { _, _ in vm.load() }
    }

    // MARK: - 顶部固定区

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("历史记录".localized())
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(c.textPrimary)
            Text(isSelecting ? "选择要操作的语音".localized() : "")
                .font(.system(size: 12.5))
                .foregroundStyle(c.textTertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, metrics.pageMargin)
        .padding(.top, 2)
    }

    private var searchField: some View {
        AuroraSearchField(text: $vm.searchText,
                          placeholder: "搜索名称、文案或音色".localized()) {
            commitSearch()
        }
        .padding(.horizontal, metrics.pageMargin)
        .padding(.vertical, 9)
    }

    // MARK: - 列表

    /// iPad 大屏走多列网格；其余设备（含 iPad 分屏，宽度不够）保持原 `.plain` List 逐字不变。
    @ViewBuilder
    private var listArea: some View {
        if metrics.isPadClass {
            gridArea
        } else {
            phoneListArea
        }
    }

    private var historyColumns: [GridItem] {
        let contentWidth = metrics.width - 2 * metrics.pageMargin
        return Array(repeating: GridItem(.flexible(), spacing: 10),
                     count: metrics.historyGridColumns(forContentWidth: contentWidth))
    }

    /// iPad 大屏：按自然日分组，每组内一个多列网格。
    /// 刷新过渡（`.id` / opacity / offset / 动画参数）与 `phoneListArea` 完全一致。
    private var gridArea: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                if vm.isLoading && vm.sections.isEmpty {
                    LazyVGrid(columns: historyColumns, spacing: 10) {
                        ForEach(0..<6, id: \.self) { _ in HistorySkeletonRow() }
                    }
                    .padding(.horizontal, metrics.pageMargin)
                    .padding(.top, 13)
                } else {
                    ForEach(vm.sections) { section in
                        Section {
                            LazyVGrid(columns: historyColumns, spacing: 10) {
                                ForEach(section.items) { audio in
                                    gridRow(audio)
                                        .id(audio.id)
                                }
                            }
                            .padding(.horizontal, metrics.pageMargin)
                            // 组头底部 7pt 由 HistorySectionHeader 自己给，这里不再叠
                        } header: {
                            HistorySectionHeader(section: section)
                        }
                    }

                    if showEmpty {
                        HistoryEmptyState(isSearching: vm.isSearching,
                                          onCreate: { router.selection = .studio },
                                          onClearSearch: { clearSearch() },
                                          onClearFilter: { clearFilter() })
                    }

                    if vm.hasMoreVisible && !vm.isSearching {
                        loadMoreRow
                    }
                }

                //    不给底部留占位，最后一行滚到底仍会被盖住。
                if miniPlayerVisible {
                    Color.clear.frame(height: MiniPlayerView.height + 28)
                }
            }
        }
        .scrollDismissesKeyboard(.immediately)
        .id(scrollResetID)
        .opacity(contentVisible ? 1 : 0)
        .offset(y: contentVisible ? 0 : 12)
        .animation(.easeOut(duration: 0.28), value: contentVisible)
        .animation(.spring(response: 0.34, dampingFraction: 0.9), value: vm.sections.count)
        .animation(RootTabView.dockAnimation, value: miniPlayerVisible)
    }

    /// 网格卡片：List 的 `.swipeActions` 在这里不可用，改成长按菜单保留四个操作。
    private func gridRow(_ audio: AudioItem) -> some View {
        row(audio)
            .contextMenu { swipeButtons(audio) }
    }

    @ViewBuilder
    private var phoneListArea: some View {
        List {
            if vm.isLoading && vm.sections.isEmpty {
                ForEach(0..<3, id: \.self) { _ in
                    HistorySkeletonRow()
                        .listRowInsets(EdgeInsets(top: 3.5, leading: 12, bottom: 3.5, trailing: 12))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            } else {
                ForEach(vm.sections) { section in
                    Section {
                        ForEach(section.items) { audio in
                            row(audio)
                                .id(audio.id)
                                .listRowInsets(EdgeInsets(top: 3.5, leading: 12, bottom: 3.5, trailing: 12))
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    swipeButtons(audio)
                                }
                        }
                    } header: {
                        HistorySectionHeader(section: section)
                            .listRowInsets(EdgeInsets())
                    }
                }

                if showEmpty {
                    Section {
                        HistoryEmptyState(isSearching: vm.isSearching,
                                          onCreate: { router.selection = .studio },
                                          onClearSearch: { clearSearch() },
                                          onClearFilter: { clearFilter() })
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                }

                if vm.hasMoreVisible && !vm.isSearching {
                    Section {
                        loadMoreRow
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                    }
                }
            }

            if miniPlayerVisible {
                Section {
                    Color.clear
                        .frame(height: MiniPlayerView.height + 28)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollDismissesKeyboard(.immediately)
        .listSectionSpacing(0)
        .environment(\.defaultMinListHeaderHeight, 0)
        .contentMargins(.top, 0, for: .scrollContent)
        .id(scrollResetID)
        .opacity(contentVisible ? 1 : 0)
        .offset(y: contentVisible ? 0 : 12)
        .animation(.easeOut(duration: 0.28), value: contentVisible)
        .animation(.spring(response: 0.34, dampingFraction: 0.9), value: vm.sections.count)
        .animation(RootTabView.dockAnimation, value: miniPlayerVisible)
    }

    private var showEmpty: Bool { vm.sections.isEmpty && !vm.isLoading }

    private var miniPlayerVisible: Bool {
        !uiState.hideMiniPlayer
        && router.activePath.isEmpty
        && nowPlaying.currentItem != nil
    }

    private var loadMoreRow: some View {
        HStack(spacing: 7) {
            if vm.isLoading { ProgressView().controlSize(.small) }
            Text("继续加载更早的记录…".localized())
                .font(.system(size: 11.5))
                .foregroundStyle(c.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .onAppear { vm.loadMoreVisible() }
    }

    private func row(_ audio: AudioItem) -> some View {
        HistoryRow(audio: audio,
                   voiceName: vm.voiceName(for: audio),
                   favorite: flags.isFavorite(audio.id),
                   isPlaying: isPlaying(audio),
                   isSelecting: isSelecting,
                   selected: selectedIDs.contains(audio.id),
                   query: vm.searchText,
                   onPreview: { preview(audio) },
                   onOpen: { tap(audio) },
                   onRetry: { retry(audio) })
    }

    private var moreMenu: some View {
        HistoryMoreMenu(deletedCount: flags.deletedCount,
                        sortOrder: vm.sortOrder,
                        onTrash: {
                            router.push(.recentlyDeleted)
                        },
                        onSortChange: { order in
                            animateRefresh { vm.sortOrder = order }
                        },
                        onDismiss: { setMoreMenu(false) })
            .transition(.opacity)
    }

    private func setMoreMenu(_ on: Bool) {
        withAnimation(.easeOut(duration: 0.2)) { moreMenuPresented = on }
    }

    // MARK: - 导航栏

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            if isSelecting {
                Button("取消".localized()) { setSelecting(false) }
                    .foregroundStyle(c.accent)
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            HStack(spacing: 10) {
                if isSelecting {
                    Button {
                        if selectedIDs.count == vm.sections.reduce(0, { $0 + $1.items.count }) {
                            selectedIDs = []
                        } else {
                            selectedIDs = Set(vm.sections.flatMap(\.items).map(\.id))
                        }
                    } label: {
                        Text(allSelected ? "取消全选".localized() : "全选".localized())
                            .font(.system(size: 14.5, weight: .semibold))
                            .foregroundStyle(c.accent)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button { setSelecting(true) } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "checklist")
                                .font(.system(size: 17, weight: .semibold))
                        }
                        .foregroundStyle(c.accent)
                        .padding(.horizontal, 11)
                        .frame(height: 32)
                        .background(
                            Capsule(style: .continuous)
                                .fill(c.accentSoft)
                                .overlay(
                                    Capsule(style: .continuous)
                                        .strokeBorder(c.accent.opacity(0.28), lineWidth: 0.5)
                                )
                        )
                        .contentShape(Capsule(style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("进入多选".localized())

                    Button { setMoreMenu(true) } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(c.accent)
                            .frame(width: 32, height: 32)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("更多".localized())
                }
            }
        }
    }

    private var allSelected: Bool {
        let total = vm.sections.reduce(0) { $0 + $1.items.count }
        return total > 0 && selectedIDs.count == total
    }

    // MARK: - 多选工具条（图标 + 文字）

    private var selectionBar: some View {
        HStack(spacing: 0) {
            Text("\(selectedIDs.count)")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Capsule(style: .continuous).fill(c.accent))
            Text("已选择".localized())
                .font(.system(size: 12))
                .foregroundStyle(c.textSecondary)
                .padding(.leading, 8)

            Spacer(minLength: 0)
            Rectangle().fill(c.line2).frame(width: 1, height: 26).padding(.horizontal, 4)

            toolAction("square.and.arrow.up", "分享".localized(), tint: c.accent) { shareSelected() }
            toolAction("square.on.square", "复制".localized(), tint: c.accent) { duplicateSelected() }
            // 所选条目全部已收藏时，同一个按钮翻转为「取消收藏」→ 支持批量取消
            toolAction(allSelectedFavorited ? "heart.slash.fill" : "heart.fill",
                       allSelectedFavorited ? "取消收藏".localized() : "收藏".localized(),
                       tint: AuroraDecor.rose) { toggleFavoriteSelected() }
            toolAction("trash.fill", "删除".localized(), tint: c.danger) { deleteMany = true }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(c.bar)
        .overlay(alignment: .top) { Hairline() }
    }

    private func toolAction(_ icon: String, _ title: String, tint: Color,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 17, weight: .semibold))
                Text(title)
                    .font(.system(size: 10))
            }
            .foregroundStyle(selectedIDs.isEmpty ? c.textTertiary : tint)
            .frame(minWidth: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(selectedIDs.isEmpty)
    }

    // MARK: - 刷新节奏
    private func scheduleRefresh() {
        searchTask?.cancel()
        searchTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 280_000_000)
            guard !Task.isCancelled else { return }
            vm.rebuild()
            scrollResetID += 1
        }
    }

    /// 回车：取消防抖，立即查全库。
    private func commitSearch() {
        searchTask?.cancel()
        searchTask = nil
        vm.rebuild()
        scrollResetID += 1
    }

    /// 筛选 / 排序：淡出 0.1s → 换数据 → 淡入 0.28s，滚动复位。
    private func animateRefresh(_ apply: @escaping () -> Void) {
        withAnimation(.easeOut(duration: 0.1)) { contentVisible = false }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 100_000_000)
            apply()
            vm.rebuild()
            scrollResetID += 1
            withAnimation(.easeOut(duration: 0.28)) { contentVisible = true }
        }
    }

    private func clearSearch() {
        vm.searchText = ""
        vm.searchScope = .all
        commitSearch()
    }

    private func clearFilter() {
        animateRefresh {
            vm.filter = .all
            vm.searchText = ""
            vm.searchScope = .all
        }
    }

    // MARK: - 行为
    private func setSelecting(_ on: Bool) {
        withAnimation(.easeOut(duration: 0.18)) {
            isSelecting = on
            if !on { selectedIDs = [] }
        }
        uiState.hideMiniPlayer = on
    }

    private func isPlaying(_ audio: AudioItem) -> Bool {
        status.playingKey == audio.fileName && status.isPlaying
    }

    /// 行内 32pt 试听：就地播/停，不 push。
    private func preview(_ audio: AudioItem) {
        guard audio.isOnDisk else {
            uiState.showToast(.failure("语音文件已丢失".localized()))
            return
        }
        nowPlaying.toggle(audio, voiceName: vm.voiceName(for: audio))
    }

    /// 点行：接管播放并 push 详情（播放跨页保留，详情页不再 stop）。
    private func tap(_ audio: AudioItem) {
        if isSelecting {
            if selectedIDs.contains(audio.id) { selectedIDs.remove(audio.id) }
            else { selectedIDs.insert(audio.id) }
            return
        }
        guard audio.isOnDisk else {
            uiState.showToast(.failure("语音文件已丢失".localized()))
            return
        }
        let voice = vm.voiceName(for: audio)
        router.push(.player(audio))
        if status.playingKey == audio.fileName {
            nowPlaying.attach(audio, voiceName: voice)
        } else {
            nowPlaying.start(audio, voiceName: voice)
        }
    }

    /// 失败记录「重新编辑」：把文案带回创作页。
    private func retry(_ audio: AudioItem) {
        VoiceStudioViewModel.shared.text = audio.text
        router.selection = .studio
        uiState.showToast(.info("已将文案带回创作页".localized()))
    }

    private func toggleFavorite(_ audio: AudioItem) {
        let on = flags.toggleFavorite(audio.id)
        vm.rebuild()
        uiState.showToast(.success(on ? "已加入收藏".localized() : "已取消收藏".localized(), duration: 1))
    }

    // MARK: 左滑四操作（数组从右到左：删除 / 复制 / 重命名 / 收藏）
    @ViewBuilder
    private func swipeButtons(_ audio: AudioItem) -> some View {
        Button(role: .destructive) { deleteTarget = audio } label: {
            Label("删除".localized(), systemImage: "trash.fill")
        }
        Button { duplicate(audio) } label: {
            Label("复制".localized(), systemImage: "square.on.square")
        }
        .tint(c.info)
        Button { beginRename(audio) } label: {
            Label("重命名".localized(), systemImage: "square.and.pencil")
        }
        .tint(c.success)
        Button { toggleFavorite(audio) } label: {
            Label(flags.isFavorite(audio.id) ? "取消收藏".localized() : "收藏".localized(),
                  systemImage: flags.isFavorite(audio.id) ? "heart.slash.fill" : "heart.fill")
        }
        .tint(AuroraDecor.rose)
    }

    // MARK: 复制
    private func duplicate(_ audio: AudioItem) {
        let sourceURL = audio.absoluteURL
        let ext = audio.fileExtension
        let sourceID = audio.id
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 260_000_000)
            let staged = await Task.detached(priority: .userInitiated) {
                ProjectService.stageDuplicatedFile(sourceURL: sourceURL, fileExtension: ext)
            }.value
            guard let name = staged,
                  let copy = ProjectService.shared.finishDuplicate(source: audio, newFileName: name) else {
                uiState.showToast(.failure("复制失败".localized()))
                return
            }
            withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) {
                vm.insertItem(copy, after: sourceID)
            }
            uiState.showToast(.success("已复制语音".localized()))
        }
    }

    private func duplicateSelected() {
        let targets = selectedAudios()
        guard !targets.isEmpty else { return }
        Task { @MainActor in
            var copies: [AudioItem] = []
            for item in targets {
                let url = item.absoluteURL
                let ext = item.fileExtension
                let staged = await Task.detached(priority: .userInitiated) {
                    ProjectService.stageDuplicatedFile(sourceURL: url, fileExtension: ext)
                }.value
                if let name = staged,
                   let copy = ProjectService.shared.finishDuplicate(source: item, newFileName: name) {
                    copies.append(copy)
                }
            }
            vm.load()
            uiState.showToast(.success("已复制 %d 条语音".localized(copies.count)))
        }
    }

    // MARK: 重命名
    private func beginRename(_ audio: AudioItem) {
        renameTarget = audio
        renameText = audio.shownName
    }

    private func commitRename() {
        guard let target = renameTarget else { return }
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        renameTarget = nil
        if !trimmed.isEmpty, trimmed != target.shownName {
            ProjectService.shared.renameAudio(id: target.id, displayName: trimmed)
            withAnimation(.spring(response: 0.34, dampingFraction: 0.9)) {
                vm.renameItem(target.id, name: trimmed)
            }
        }
    }

    // MARK: 软删 + 撤销
    private var deletePresented: Binding<Bool> {
        Binding(get: { deleteTarget != nil || deleteMany },
                set: { if !$0 { deleteTarget = nil; deleteMany = false } })
    }

    private var deleteMessage: String {
        if deleteMany {
            return "选中的 %d 条将保留 30 天，期间可随时恢复。".localized(selectedIDs.count)
        }
        if let target = deleteTarget {
            return "「%@」将保留 30 天，期间可随时恢复。".localized(target.shownName)
        }
        return ""
    }

    /// 确认后立即从数组移除并出 Toast；5 秒内不动磁盘文件，撤销 = 清标记 + 插回原位置。
    private func commitSoftDelete() {
        let ids: Set<Int64>
        if deleteMany {
            ids = selectedIDs
            deleteMany = false
            selectedIDs = []
            isSelecting = false
            uiState.hideMiniPlayer = false
        } else if let target = deleteTarget {
            ids = [target.id]
            deleteTarget = nil
        } else { return }

        let idArray = Array(ids)
        flags.markDeleted(idArray)
        nowPlaying.clearIfMatches(ids)
        withAnimation(.spring(response: 0.34, dampingFraction: 0.9)) {
            vm.removeItems(ids)
        }

        let store = flags
        let state = uiState
        let text = ids.count == 1
            ? "已移入最近删除 · 30 天内可恢复".localized()
            : "已移入 %d 条 · 30 天内可恢复".localized(ids.count)
        state.showUndoToast(text: text) {
            store.restore(idArray)
            state.requestHistoryReload()
            state.showToast(.success("已撤销删除".localized()))
        }
    }

    // MARK: 分享 / 收藏（多选）
    private func selectedAudios() -> [AudioItem] {
        vm.sections.flatMap(\.items).filter { selectedIDs.contains($0.id) }
    }

    private func shareSelected() {
        let urls = selectedAudios().compactMap { $0.isOnDisk ? $0.absoluteURL : nil }
        guard !urls.isEmpty else {
            uiState.showToast(.failure("所选语音文件不存在".localized()))
            return
        }
        shareURLs = urls
        isSharing = true
    }

    private var allSelectedFavorited: Bool {
        let ids = Array(selectedIDs)
        return !ids.isEmpty && ids.allSatisfy { flags.isFavorite($0) }
    }

    private func toggleFavoriteSelected() {
        let ids = Array(selectedIDs)
        guard !ids.isEmpty else { return }
        let target = !allSelectedFavorited
        flags.setFavorites(ids, to: target)
        if !target && vm.filter == .favorites { selectedIDs = [] }
        vm.rebuild()
        uiState.showToast(.success(target
            ? "已加入收藏".localized()
            : "已取消收藏".localized(), duration: 1))
    }
}
