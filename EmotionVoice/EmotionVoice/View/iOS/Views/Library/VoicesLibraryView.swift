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
//  ⚠️ 筛选状态的生命周期：只在**当前进程内**保留（`VoiceLibraryFilterStore`，纯内存），
//     切标签 / 页面跳转 / View 被重建都不丢；App 重启回到「全部音色」。
//     不读写 `AppState.voiceLibrary*` —— 那组字段会落 UserDefaults，是 macOS 用的。
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
    // ⚠️ 音色库是 LazyVGrid（卡片多）：订阅播放器的 10Hz progress 会让整格重算。
    //    宿主用非观察的 let 调方法，播放态走低频代理。
    private let player = AudioPreviewPlayer.shared
    @StateObject private var status = PlaybackStatus.shared

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
    /// 是否已经出现过一次：切回标签时的空态自愈不能打断首屏骨架淡入
    @State private var didAppearOnce = false

    @State private var sheetPresented = false

    /// 列表滚动位置的「重置版本号」：作为 `ScrollView` 的 id，
    /// 一自增就整体重建 ScrollView，contentOffset 随之归零
    @State private var scrollResetID = 0

    /// 搜索防抖用的 Task（每次键击都全表过滤会很卡）
    @State private var searchTask: Task<Void, Never>? = nil

    /// 分类 Sheet 提交后排的延迟刷新（见 `reloadAfterSheetDismiss`）
    @State private var deferredReloadTask: Task<Void, Never>? = nil

    /// 这次延迟刷新还没落地：离屏前要就地同步做完，否则回来会「按钮是分类 A、列表还是全部音色」
    @State private var pendingSheetReload = false

    /// 「换数据」那一步排的 Task（见 `apply(_:total:)`）
    @State private var swapTask: Task<Void, Never>? = nil

    /// 内容区可见度：刷新 = 旧内容淡出 → 换数据 → 新内容淡入 + 上浮。
    ///
    /// ⚠️ 不用容器级 `.transition`：`.id` 整体重建触发的 transition 在
    ///    「Sheet 正在收起」「骨架屏替换」这些场景下不保证触发，肉眼看就是硬切。
    ///    直接改 `opacity` / `offset` 这种可动画属性，必然出效果。
    @State private var contentVisible = true

    /// 一次拖拽只收一次键盘（DragGesture 的 onChanged 会刷几十次）
    @State private var didResignOnDrag = false

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 10),
              count: metrics.voiceGridColumns)
    }

    private var pageSize: Int { metrics.voiceGridColumns * 4 }

    private var hasMore: Bool { voices.count < totalCount }

    /// 新内容淡入 + 上浮（0.28s）
    private static let swapAnimation = Animation.easeOut(duration: 0.28)

    /// 旧内容淡出（短一点，换数据的等待时间都算在这里）
    private static let fadeOutAnimation = Animation.easeOut(duration: 0.1)

    /// 淡出走完后换数据的等待
    private static let fadeOutNanos: UInt64 = 100_000_000

    /// 分类 Sheet 收起动画约 0.25s：刷新排在这个点之后，过渡才看得见
    /// （同步刷新的话淡入全程发生在下落中的 Sheet 背后，用户只看到硬切）
    private static let sheetDismissDelayNanos: UInt64 = 250_000_000

    var body: some View {
        VStack(spacing: 0) {
            searchBar
            filterBar

            ScrollView {
                LazyVGrid(columns: columns, spacing: 10) {
                        if didLoad {
                            ForEach(voices) { voice in
                                VoiceCardGrid(
                                    voice: voice,
                                    isPreviewing: status.playingKey == voice.key && status.isPlaying,
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
                // 滑动列表即收键盘（原生滚动拦截；⚠️ 必须挂在 ScrollView 上，挂容器不生效）
                .scrollDismissesKeyboard(.immediately)
                // ⚠️ 筛选一变就换 id → ScrollView 整体重建 → 滚动偏移归零。
                // 早先试过 `scrollTo(顶部锚点)`：它在布局前按**旧 contentSize** 算偏移，
                // 行数变少时算出的偏移仍超出新范围，于是「滚不动」——
                // 表现就是「滚动过再点收藏 → 列表一片空白，而数据其实早就换好了」。
                .id(scrollResetID)
                // ⚠️ 换 id 等于「整块内容被瞬间替换」，所以配套两层动画：
                //    ① 换之前 `contentVisible = false` → 旧内容淡出；
                //    ② 换的同一帧置回 true → 新内容淡入并从下方 12pt 浮上来。
                //    （`scrollResetID` 只在 reload 里自增，loadMore 追加不触发，
                //     所以上拉加载不会整屏闪一下。）
                .opacity(contentVisible ? 1 : 0)
                .offset(y: contentVisible ? 0 : 12)
                .animation(Self.swapAnimation, value: contentVisible)
            }
        .background(c.backgroundGrouped)
        // ⚠️ 兜底：`.scrollDismissesKeyboard` 依赖**内容能否滚动**——
        //    搜索无结果 / 结果不满一屏时 ScrollView 滑不动，键盘就永远收不掉，
        //    而这恰恰是「输完关键词等结果」最常见的状态。
        //    `minimumDistance: 12` 避免误吞卡片点击（`simultaneous` 不挡 tap）。
        .simultaneousGesture(dragToDismissKeyboard)
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
                onCommit: { dismissing in
                    dismissing ? reloadAfterSheetDismiss() : reload()
                },
                onDismiss: { sheetPresented = false }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .task { initialLoad() }
        .onAppear {
            defer { didAppearOnce = true }
            // 切回标签时的空态自愈：旧版本 / 其它取消路径可能留下
            // 「didLoad = true 但 voices 为空」。VM 的 totalCount 是同步查库得到的，
            // 不受 swapTask 影响，可据此区分「没落地」和「搜索确实无结果」。
            // 首次出现不干预，避免把骨架 → 卡片的淡入动画吃掉。
            guard didAppearOnce, didLoad, voices.isEmpty, vm.totalCount > 0 else { return }
            reload(animated: false)
        }
        // ⚠️ 筛选一变就写进程内 store，不等 reload：Sheet 的刷新排在 0.25s 之后，
        //   用户完全可能在这之前切标签 / 跳走，那时状态必须已经安全落地。
        .onChange(of: searchText) { _, _ in
            persist()
            scheduleSearch()
        }
        .onChange(of: selectedCategory) { _, _ in persist() }
        .onChange(of: showFavoritesOnly) { _, _ in persist() }
        .onDisappear {
            stopPreviewIfNeeded()
            if pendingSheetReload {
                // 延迟刷新还没跑就离屏：取消它，改成无动画同步落地。
                // 否则回来时分类名是新的、列表数据还是旧的。
                pendingSheetReload = false
                deferredReloadTask?.cancel()
                deferredReloadTask = nil
                swapTask?.cancel()
                reload(animated: false)
            } else {
                deferredReloadTask?.cancel()
                swapTask?.cancel()
            }
            contentVisible = true   // 别让半途取消的淡出把列表留在透明状态
        }
    }

    /// 离开本页只停「音色库自己的试听」。
    /// ⚠️ 生成音频的播放归 `NowPlayingStore` 管，要跨标签常驻 ——
    ///    早先在这里无条件 `player.stop()`，用户一切标签音频就断、mini player 跟着没了。
    ///    两个 identifier 不同（试听 = `voice.key`，生成音频 = `fileName`），据此区分。
    private func stopPreviewIfNeeded() {
        guard let key = player.playingKey else { return }
        if key == NowPlayingStore.shared.currentItem?.fileName { return }
        player.stop()
    }

    // MARK: 搜索框

    private var searchBar: some View {
        AuroraSearchField(text: $searchText,
                          placeholder: "搜索音色名 / 特质 / 场景 / 语种".localized(),
                          onSubmit: { commitSearch() })
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

    /// 分类按钮：整块胶囊都是热区，点哪儿都弹分类 Sheet。
    ///
    /// ⚠️ 早年只有中间那个 `Button` 的 label 能点（右边一小截 chevron 区、左侧留白都点不动），
    ///    命中率很低。改成「外层容器 + `contentShape(Rectangle())` + `onTapGesture`」：
    ///    视觉一点没变（背景 / 圆角 / 描边都在外层），但整条胶囊都响应。
    ///
    /// ⚠️ 分类选完后**不再出现 ×**：分类是「选一个就走」的单选操作，
    ///    清除筛选在 Sheet 里点「全部音色 / 重置」即可；按钮上再挂一个 ×
    ///    既挤掉类名，又容易被看成「删掉这个分类」。
    private var filterButton: some View {
        HStack(spacing: 0) {
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
        // ⚠️ `Rectangle` 而不是 `Capsule`：连圆角外的四个方角也算进热区（多出几 pt 无所谓，
        //    漏掉一角就会「明明点在按钮上却没反应」）
        .contentShape(Rectangle())
        // 选完分类，胶囊的底色/描边/计数跟着过渡一下，别硬切
        .animation(.easeOut(duration: 0.22), value: selectedCategory)
        .onTapGesture { sheetPresented = true }
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("选择分类".localized())
    }

    private var favoriteButton: some View {
        Button {
            deferredReloadTask?.cancel()   // 别让 Sheet 排的延迟刷新晚一步把列表再切一次
            pendingSheetReload = false
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
                    Text("%@ · %d 个".localized(cat.displayName, totalCount))
                        .font(.system(size: 12))
                }
                .foregroundStyle(c.accent)
                // ⚠️ 分类选完后按钮上不再有 ×（见 `filterButton`），提示语跟着改，
                //    否则会指引用户去找一个不存在的按钮。
                Text("点上方按钮可重新选择".localized())
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
        // 只从进程内 store 恢复：View 重建 / 切标签回来时保留筛选；
        // App 重启时 store 是全新的，自然回到「全部音色」。
        let store = VoiceLibraryFilterStore.shared
        selectedCategory = store.selectedCategory
        searchText = store.searchText
        showFavoritesOnly = store.showFavoritesOnly
        reload()
        // 骨架屏 → 真实卡片也算一次「内容切换」，走同一条淡入过渡
        withAnimation(Self.swapAnimation) { didLoad = true }
    }

    /// 分类 Sheet 提交（点行即收起）后的刷新
    ///
    /// ⚠️ 不能同步 `reload()`：Sheet 收起动画与列表淡入同时开始，
    /// 0.28s 的过渡全程发生在 Sheet 背后，用户体感就是「数据硬切了一下」。
    /// 排到收起之后，按钮上的分类名（Binding）已经先变，列表随后淡入换数据。
    private func reloadAfterSheetDismiss() {
        deferredReloadTask?.cancel()
        pendingSheetReload = true
        deferredReloadTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: Self.sheetDismissDelayNanos)
            guard !Task.isCancelled else { return }
            pendingSheetReload = false
            reload()
        }
    }

    /// 重新按当前筛选取首页并整体替换
    ///
    /// ⚠️ 查库**必须留在动画事务之外**：`vm.reloadCurrentPage()` 是同步的全表过滤，
    /// 放进 `withAnimation` 会卡住动画的第一帧（与 `ProjectsView.duplicate` 同一个坑）。
    /// 这里只把最后那几次 `@State` 写入包进动画。
    private func reload(animated: Bool = true) {
        page = 1
        vm.setPageSize(pageSize)
        syncToVM()
        vm.reloadCurrentPage()
        apply(vm.displayedVoices, vm.totalCount, animated: animated)
        persist()
    }

    /// 落地一页新数据：淡出 → 换 → 淡入
    ///
    /// ⚠️ 换数据的瞬间 `contentVisible` 已经是 0，所以 `.id` 那一次硬替换看不见；
    ///    紧接着把它置回 1，用户看到的就是「旧列表淡出 → 新列表浮上来」。
    ///
    /// ⚠️ **取消只代表「不做动画」，绝不代表「数据不要了」**：
    ///    `onDisappear` 会取消 `swapTask`，早先这里 `guard !Task.isCancelled { return }`
    ///    直接把这批数据丢掉，`didLoad` 却已是 true、`.task` 又不会重跑 ——
    ///    切回标签就是「分类是全部、一个音色都没有」的永久空态。
    private func apply(_ fresh: [Voice], _ total: Int, animated: Bool = true) {
        guard animated else {
            commit(fresh, total)
            return
        }
        withAnimation(Self.fadeOutAnimation) { contentVisible = false }
        swapTask?.cancel()
        swapTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: Self.fadeOutNanos)
            guard !Task.isCancelled else {
                // 离屏期间被取消：无动画同步落地，回来时列表必须已经有数据、且不透明
                commit(fresh, total)
                contentVisible = true
                return
            }
            withAnimation(Self.swapAnimation) {
                commit(fresh, total)
                contentVisible = true
            }
        }
    }

    /// 数据落地与动画解耦：任何路径（正常淡入 / 被取消 / 无动画）都走这里
    private func commit(_ fresh: [Voice], _ total: Int) {
        voices = fresh
        totalCount = total
        scrollResetID += 1   // 换掉 ScrollView 的 id → 滚动复位到顶部
    }

    /// 追加下一页
    ///
    /// ⚠️ **先写 `page` 再 `syncToVM()`**。早年先 `vm.currentPage = next` 再 sync，
    /// 而 `syncToVM()` 会把本地的 `page` 灌回 `vm.currentPage` —— 下一行就把新页码
    /// 覆盖成了旧页码，`reloadCurrentPage()` 于是又把当前页取了一遍，
    /// `fresh` 全是已经显示过的音色，追加恒为空：这就是「上拉加载无效」。
    private func loadMore() {
        guard didLoad, hasMore, !isAppending else { return }
        isAppending = true
        let next = page + 1
        page = next
        syncToVM()
        vm.reloadCurrentPage()
        let known = Set(voices.map(\.key))
        let appended = vm.displayedVoices.filter { !known.contains($0.key) }
        voices.append(contentsOf: appended)
        totalCount = vm.totalCount
        // 空页（页码越界）回退，否则页码会一直空转
        if appended.isEmpty { page = max(1, next - 1) }
        isAppending = false
    }

    private func syncToVM() {
        vm.syncFromAppState(selectedCategory: selectedCategory,
                            searchText: searchText,
                            showFavoritesOnly: showFavoritesOnly,
                            currentPage: page)
    }

    /// 筛选状态即时写进进程内 store（不落盘）。
    /// ⚠️ 不依赖 `reload()` 完成：分类 Sheet 的刷新是延迟的，用户可能在 0.25s 内就切走；
    ///    页码不入 store —— View 重建 / 重启后一律从第一页重新加载。
    private func persist() {
        VoiceLibraryFilterStore.shared.update(
            selectedCategory: selectedCategory,
            searchText: searchText,
            showFavoritesOnly: showFavoritesOnly
        )
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

    /// 回车提交：取消还在等待的防抖任务，立刻出结果
    private func commitSearch() {
        searchTask?.cancel()
        reload()
    }

    // MARK: - 键盘

    /// 列表区拖拽收键盘：`ScrollView` 内容不够高时滑不动，只能靠这层手势兜底
    private var dragToDismissKeyboard: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { _ in
                guard !didResignOnDrag else { return }
                didResignOnDrag = true
                resignKeyboard()
            }
            .onEnded { _ in didResignOnDrag = false }
    }

    private func resignKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
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

    private func useVoice(_ voice: Voice) {
        appState.selectedVoice = voice
        VoiceStudioViewModel.shared.selectedVoiceKey = voice.key
        stopPreviewIfNeeded()   // 只停试听；mini player 正在收听的生成音频不受影响
        router.selection = .studio
        uiState.showToast(.success("已切换到「%@」".localized(voice.localizedName)))
    }
}
