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
    // ⚠️ 同 VoicesLibraryView：宿主不订阅 10Hz progress，播放态走低频代理。
    private let player = AudioPreviewPlayer.shared
    @StateObject private var status = PlaybackStatus.shared

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

    /// 一次拖拽只收一次键盘（DragGesture 的 onChanged 会刷几十次）
    @State private var didResignOnDrag = false

    /// 列表滚动位置的「重置版本号」：作为 `ScrollView` 的 id，一自增就整体重建、偏移归零
    @State private var scrollResetID = 0

    /// 「换数据」那一步排的 Task（见 `apply(_:total:)`）
    @State private var swapTask: Task<Void, Never>? = nil

    /// 内容区可见度：刷新 = 旧内容淡出 → 换数据 → 新内容淡入 + 上浮。
    /// ⚠️ 不用容器级 `.transition`（`.id` 重建触发的 transition 不保证触发，肉眼看是硬切），
    ///    直接改 `opacity` / `offset` 这种可动画属性必然出效果。
    @State private var contentVisible = true

    /// ⚠️ 列数按**实测的 sheet 宽度**再封顶：Sheet 的环境值继承的是全屏
    ///    `ScreenMetrics`，而 iPad 上的 sheet 可能比屏幕窄，直接套 `voiceGridColumns`
    ///    会把 4~5 列硬塞进细卡片（见 `ScreenMetrics.voiceGridColumns(forContentWidth:)`）。
    private func columns(forAvailableWidth availableWidth: CGFloat) -> [GridItem] {
        let capped = min(availableWidth, metrics.voiceGridMaxWidth ?? .infinity)
        let contentWidth = capped - 2 * metrics.pageMargin
        return Array(repeating: GridItem(.flexible(), spacing: 10),
                     count: metrics.voiceGridColumns(forContentWidth: contentWidth))
    }

    private var pageSize: Int { metrics.voiceGridColumns * 4 }

    private var hasMore: Bool { voices.count < totalCount }

    /// 新内容淡入 + 上浮 / 旧内容淡出（与 `VoicesLibraryView` 同一套节奏）
    private static let swapAnimation = Animation.easeOut(duration: 0.28)
    private static let fadeOutAnimation = Animation.easeOut(duration: 0.1)
    private static let fadeOutNanos: UInt64 = 100_000_000

    /// 分类列表就地替换内容区的进出场（出现：从下方滑入 + 淡入；消失：滑下去 + 淡出）
    private static let panelAnimation = Animation.easeOut(duration: 0.26)
    private static let panelTransition: AnyTransition = .asymmetric(
        insertion: .move(edge: .bottom).combined(with: .opacity),
        removal: .move(edge: .bottom).combined(with: .opacity)
    )

    var body: some View {
        VStack(spacing: 0) {
            if categoryPresented {
                CategoryFilterSheet(
                    selectedCategory: $selectedCategory,
                    showFavoritesOnly: $showFavoritesOnly,
                    counts: vm.chipCounts,
                    totalAll: vm.totalAll,
                    favoriteCount: vm.favoriteCount,
                    onCommit: { _ in reload() },
                    onDismiss: { dismissCategoryList() }
                )
                .transition(Self.panelTransition)
            } else {
                // ⚠️ 必须包一层：`navBar`/`grid` 是多个视图，逐个挂 transition 会各自为政
                VStack(spacing: 0) {
                    navBar
                    searchBar
                    filterBar
                    resultBar
                    // ⚠️ GeometryReader 在 VStack 里正好吃掉剩余高度（ScrollView 本来也要占满），
                    //    顺带把 sheet 的真实宽度交给列数计算 —— iPad 的 sheet 未必是全屏宽。
                    GeometryReader { geo in
                        grid(availableWidth: geo.size.width)
                    }
                }
                .transition(.opacity)
            }
        }
        // ⚠️ 分支切换的过渡由这个 `value` 驱动（配合下面的 withAnimation）
        .animation(Self.panelAnimation, value: categoryPresented)
        .background(c.backgroundGrouped)
        .simultaneousGesture(dragToDismissKeyboard)
        .task { initialLoad() }
        .onChange(of: searchText) { _, _ in scheduleSearch() }
        .onDisappear {
            stopPreviewIfNeeded()
            swapTask?.cancel()
            contentVisible = true   // 别让半途取消的淡出把列表留在透明状态
        }
    }

    /// Sheet 关闭只停「这里的试听」；mini player 正在收听的生成音频不能跟着断
    /// （identifier 不同：试听 = `voice.key`，生成音频 = `fileName`）。
    private func stopPreviewIfNeeded() {
        guard let key = player.playingKey else { return }
        if key == NowPlayingStore.shared.currentItem?.fileName { return }
        player.stop()
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
                          placeholder: "搜索音色名 / 特质 / 场景".localized(),
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

    /// 分类按钮：整块胶囊都是热区，点哪儿都切到分类列表。
    ///
    /// ⚠️ 早年只有中间那截 `Button` 的 label 能点（右侧 chevron 区、左侧留白都点不动）。
    ///    改成「外层容器 + `contentShape(Rectangle())` + `onTapGesture`」，视觉不变、整条都能点。
    ///
    /// ⚠️ 选完分类**不再出现 ×**：清除筛选在分类列表里点「全部音色 / 重置」，
    ///    按钮上挂 × 既挤掉类名，又容易被看成「删掉这个分类」。
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
        .contentShape(Rectangle())
        // 选完分类，胶囊的底色/描边/计数跟着过渡一下，别硬切
        .animation(.easeOut(duration: 0.22), value: selectedCategory)
        .onTapGesture { openCategoryList() }
        .accessibilityAddTraits(.isButton)
        .accessibilityLabel("选择分类".localized())
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

    private func grid(availableWidth: CGFloat) -> some View {
        ScrollView {
            LazyVGrid(columns: columns(forAvailableWidth: availableWidth), spacing: 10) {
                    if didLoad {
                        ForEach(voices) { voice in
                            VoiceCardGrid(
                                voice: voice,
                                isPreviewing: status.playingKey == voice.key && status.isPlaying,
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
                        // 骨架数量跟着列数走：iPad 4/5 列只放 8 张会先矮两行、换数据再跳高
                        ForEach(0..<max(8, pageSize), id: \.self) { _ in VoiceCardSkeleton() }
                    }
                }
                .voiceGridPadding()
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
            // 换 id 是瞬间替换，所以配套「淡出 → 换 → 淡入上浮」（见 `apply(_:total:)`）
            .opacity(contentVisible ? 1 : 0)
            .offset(y: contentVisible ? 0 : 12)
            .animation(Self.swapAnimation, value: contentVisible)
            // 滑动列表即收键盘（原生滚动拦截）
            .scrollDismissesKeyboard(.immediately)
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

    // MARK: - 分类列表进出场

    /// 分类按钮 → 列表从下方滑入（列表是就地替换内容区，不套第二层 Sheet）
    private func openCategoryList() {
        withAnimation(Self.panelAnimation) { categoryPresented = true }
    }

    /// 列表滑下去退回网格；网格那边的淡入由 `reload()` 自己接上
    private func dismissCategoryList() {
        withAnimation(Self.panelAnimation) { categoryPresented = false }
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
        apply(vm.displayedVoices, vm.totalCount)
    }

    /// 落地一页新数据：淡出 → 换 → 淡入（换的瞬间内容已经是透明的，硬替换看不见）
    ///
    /// ⚠️ 与 `VoicesLibraryView` 同口径：被取消只代表不做动画，数据必须照样落地，
    ///    否则 `onDisappear` 一取消就留下「didLoad = true + voices 为空」的空态。
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

    private func commit(_ fresh: [Voice], _ total: Int) {
        voices = fresh
        totalCount = total
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

    /// 回车提交：取消还在等待的防抖任务，立刻出结果
    private func commitSearch() {
        searchTask?.cancel()
        reload()
    }

    // MARK: - 键盘

    /// 拖拽收键盘：`.scrollDismissesKeyboard` 依赖内容可滚动，
    /// 搜索无结果 / 不满一屏时滑不动，靠这层手势兜底
    private var dragToDismissKeyboard: some Gesture {
        DragGesture(minimumDistance: 12)
            .onChanged { _ in
                guard !didResignOnDrag else { return }
                didResignOnDrag = true
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                                to: nil, from: nil, for: nil)
            }
            .onEnded { _ in didResignOnDrag = false }
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
        stopPreviewIfNeeded()
        selectedKey = voice.key
        uiState.showToast(.success("已切换到「%@」".localized(voice.localizedName)))
        dismiss()
    }
}
