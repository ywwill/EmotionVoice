//
//  ProjectsView.swift
//  iOSEmora
//
//  历史记录（项目标签页）。
//
//  按 UI/iOS/history-redesign.html v2 重做：
//  - 大标题「历史记录」+ 副标题；标签栏仍叫「项目」（D1 默认不改标签名）
//  - 全库检索（名称 / 文案 / 音色）+ 范围 chip + 命中高亮 + 结果计数
//  - 统计条 / 全部·收藏筛选 / 时间分组（今天·昨天·本周·更早，组头吸顶）
//  - 行内 32pt 就地试听 ≠ 点行进详情；mini player 全局常驻
//  - 删除 = 移入最近删除（30 天）+ 5 秒撤销 Toast，不再是永久删除
//  - 左滑四操作 / 多选工具条图标+文字 / 空态引导 / 骨架屏
//
//  ⚠️ 约定：磁盘 IO 一律在动画事务之外；列表刷新用 opacity+offset 可动画属性，
//     `.id(scrollResetID)` 只负责滚动复位；同一层只挂一个 `.alert`。
//

import SwiftUI

struct ProjectsView: View {
    @Environment(\.aurora) private var c
    @Environment(\.screenMetrics) private var metrics

    @EnvironmentObject private var uiState: IOSUIState
    @EnvironmentObject private var router: TabRouter

    @StateObject private var vm = HistoryListViewModel()
    @StateObject private var flags = AudioFlagStore.shared
    @StateObject private var nowPlaying = NowPlayingStore.shared
    // ⚠️ 列表宿主不订阅播放器：progress 10Hz 会让 ForEach 里所有行一起重算。
    //    播放态走低频代理，行内进度条由「正在播放那一行」自己订阅。
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
            Text(isSelecting ? "选择要操作的音频".localized() : "全部生成音频 · 按时间排列".localized())
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
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }

    // MARK: - 列表

    @ViewBuilder
    private var listArea: some View {
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

            // ⚠️ mini player 是 RootTabView 的全局浮层，不参与 List 的 safe area。
            //    不给底部留占位，最后一行滚到底也仍被盖住。
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
        // ⚠️ `.id` 只负责滚动复位；过渡靠可动画属性，不用容器 .transition
        .id(scrollResetID)
        .opacity(contentVisible ? 1 : 0)
        .offset(y: contentVisible ? 0 : 12)
        .animation(.easeOut(duration: 0.28), value: contentVisible)
        .animation(.spring(response: 0.34, dampingFraction: 0.9), value: vm.sections.count)
        // 占位 Section 的插入 / 移除跟 mini player 的进出场同一节奏，
        // 否则浮层是滑上来的、列表却先一步瞬跳 84pt。
        .animation(RootTabView.dockAnimation, value: miniPlayerVisible)
    }

    private var showEmpty: Bool { vm.sections.isEmpty && !vm.isLoading }

    /// 与 `RootTabView.bottomDock` 的 mini player 显示条件对齐（键盘态除外：
    /// 键盘弹起浮层会隐藏，此时多留一段底部空白没有副作用）。
    /// ⚠️ 不要加 `status.playingKey != nil`：浮层只随 `currentItem` 存亡（用户点 ✕ 才收），
    ///    否则播到结尾 / 试听顶掉 key 时浮层还在、这里的占位却先没了，最后一行会被盖住。
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

    // MARK: - ⋯ 菜单

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
            // 退场淡出（进场由菜单内部 appeared 驱动缩放 + 淡入）
            .transition(.opacity)
    }

    /// ⚠️ 翻转必须落在动画事务里，overlay 的插入 / 移除才有过渡，否则瞬切。
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

    /// 打字：280ms 防抖，只重算不淡出（每敲一个字都闪一下太晃）。
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
            uiState.showToast(.failure("音频文件已丢失".localized()))
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
            uiState.showToast(.failure("音频文件已丢失".localized()))
            return
        }
        let voice = vm.voiceName(for: audio)
        // ⚠️ 顺序不能反：**先 push，再接管播放**。
        //    `attach` 会立刻把 `NowPlayingStore.currentItem` 写成这条，而此刻导航栈还是空的
        //    → `RootTabView.bottomDock` 判定「该显示 mini player」，于是底部先滑出一个小条，
        //    下一帧 path 变非空又把它收走 —— 观感就是「进详情页前底部弹了一下」。
        //    path 先更新，同一帧里 `currentItem` 再怎么变都不满足 `activePath.isEmpty`。
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
        uiState.showToast(.success(on ? "已加入收藏".localized() : "已取消收藏".localized()))
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

    /// ⚠️ 等左滑回弹走完 + 磁盘复制脱离主线程 + 纯插入，三步缺一就会复现「该行先消失」。
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
            uiState.showToast(.success("已复制音频".localized()))
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
            uiState.showToast(.success("已复制 %d 条音频".localized(copies.count)))
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
            uiState.showToast(.failure("所选音频文件不存在".localized()))
            return
        }
        shareURLs = urls
        isSharing = true
    }

    /// 所选条目全部已收藏 → 按钮变「取消收藏」；否则是批量加入收藏。
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
            : "已取消收藏".localized()))
    }
}
