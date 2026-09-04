//
//  VoicesLibraryView.swift
//  EmotionVoice
//
//  Created by young on 2026/8/8.
//
//  优化点（参考 voices.html）：
//  - 顶部工具栏采用「面包屑标题 + 搜索 + 筛选」的精简样式
//  - 分类 chip 增加命中数量徽标
//  - 卡片支持自适应列网格，hover/选中时变化边框与背景
//  - 播放中展示波形动画
//  - 顶部 chip 使用瀑布流布局（FlowLayout）
//  - 卡片列表使用 SQL 分页：每页 3 行，按列数动态计算 pageSize
//  - 底部带分页栏：上一页 / 页码输入 / 下一页 / 总数，仅 1 页时输入框不可编辑
//

import SwiftUI

/// 音色库
struct VoicesLibraryView: View {

    @EnvironmentObject var appState: AppState
    @Environment(\.voiceLibraryUseHandler) private var useHandler
    @Environment(\.voiceLibraryDismiss) private var sheetDismiss

    @StateObject private var vm = VoicesLibraryViewModel()
    @ObservedObject private var previewPlayer = AudioPreviewPlayer.shared

    // 滚动定位
    @State private var didInitialScroll: Bool = false

    // 网格实际可用宽度（用于计算列数 → pageSize）
    @State private var gridAvailableWidth: CGFloat = 0
    // 页码输入框本地状态
    @State private var pageInputText: String = "1"

    // 每行 3 个音色的目标行数
    private static let rowsPerPage: Int = 4
    // 卡片最小宽度 + 间距（与下方 GridItem 保持一致）
    private static let cardMinWidth: CGFloat = 220
    private static let gridSpacing: CGFloat = 14

    // MARK: - 视图入口

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            toolbar
            content
        }
        .onChange(of: appState.voices) { _, _ in
            // 收藏等操作触发 appState.voices 变化时，仅刷新当前页
            vm.reloadCurrentPage()
        }
        .onDisappear {
            AudioPreviewPlayer.shared.stop()
        }
    }

    // MARK: - 内容区

    @ViewBuilder
    private var content: some View {
        if vm.isEmpty {
            ScrollView {
                emptyState.padding(20)
            }
        } else {
            VStack(spacing: 0) {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            // 切换分类 / 翻页时滚动到此处
                            Color.clear
                                .frame(width: 1, height: 1)
                                .id("library-top")

                            // 单分类卡片列表（分页由 vm 管理）
                            singleCategoryCardList
                        }
                    }
                    .onChange(of: vm.selectedCategory) { _, _ in
                        syncPageInput()
                        withAnimation(.easeInOut(duration: 0.2)) {
                            proxy.scrollTo("library-top", anchor: .top)
                        }
                    }
                    .onChange(of: vm.showFavoritesOnly) { _, _ in
                        syncPageInput()
                        withAnimation(.easeInOut(duration: 0.2)) {
                            proxy.scrollTo("library-top", anchor: .top)
                        }
                    }
                    .onChange(of: vm.currentPage) { _, _ in
                        syncPageInput()
                        withAnimation(.easeInOut(duration: 0.2)) {
                            proxy.scrollTo("library-top", anchor: .top)
                        }
                    }
                    .onAppear {
                        syncPageInput()
                        guard !didInitialScroll else { return }
                        didInitialScroll = true
                        if let key = appState.selectedVoice?.key {
                            DispatchQueue.main.async {
                                proxy.scrollTo("voice-\(key)", anchor: .center)
                            }
                        }
                    }
                }

                // 分页栏（仅在有数据时显示）
                paginationBar
            }
        }
    }

    /// 单分类卡片列表：标题 + 卡片网格
    private var singleCategoryCardList: some View {
        let voices = vm.displayedVoices

        return VStack(alignment: .leading, spacing: 16) {
            // 卡片网格
            LazyVGrid(
                columns: [
                    GridItem(.adaptive(minimum: Self.cardMinWidth, maximum: 320), spacing: Self.gridSpacing)
                ],
                spacing: Self.gridSpacing
            ) {
                ForEach(Array(voices.enumerated()), id: \.element.key) { index, voice in
                    VoiceCard(
                        item: VoiceCardItem(voice: voice),
                        isSelected: appState.selectedVoice?.key == voice.key,
                        isPlaying: previewPlayer.playingKey == voice.key,
                        isFeatured: voice.isPremium
                    ) {
                        toggleFavorite(key: voice.key)
                    } onPreview: {
                        preview(key: voice.key)
                    } onUse: {
                        use(voice: voice)
                    }
                    .id("voice-\(voice.key)")
                    .transition(
                        .asymmetric(
                            insertion: .opacity
                                .combined(with: .offset(y: 14))
                                .combined(with: .scale(scale: 0.98)),
                            removal: .opacity
                        )
                    )
                    // 交错上滑：按当前页内的列优先顺序递增延迟
                    .animation(
                        .easeOut(duration: 0.35)
                            .delay(Double(index) * 0.03),
                        value: voice.key
                    )
                }
            }
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear { updatePageSize(availableWidth: geo.size.width) }
                        .onChange(of: geo.size.width) { _, newWidth in
                            updatePageSize(availableWidth: newWidth)
                        }
                }
            )
            // 整组淡入淡出作为兜底，确保 key 变化时所有 transition 都生效
            .animation(.easeOut(duration: 0.35), value: voices.map(\.key))
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 20)
    }

    // MARK: - 分页栏

    private var paginationBar: some View {
        HStack(spacing: 12) {
            // 上一页
            Button {
                vm.prevPage()
                syncPageInput()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text("上一页".localized())
                }
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(AppColor.bgTertiary)
                .foregroundStyle(vm.currentPage > 1 ? AppColor.textPrimary : AppColor.textTertiary)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
            .disabled(vm.currentPage <= 1)

            // 页码输入（仅 1 页时不可编辑）
            HStack(spacing: 6) {
                TextField("", text: $pageInputText)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.center)
                    .frame(width: 40)
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(AppColor.textPrimary)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 6)
                    .background(AppColor.bgTertiary)
                    .overlay(
                        RoundedRectangle(cornerRadius: AppRadius.small)
                            .stroke(AppColor.borderSubtle, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.small))
                    .disabled(vm.totalPages <= 1)
                    .onSubmit { commitPageInput() }
                    .onChange(of: pageInputText) { _, new in
                        // 仅允许数字，并 clamp 到 [1, totalPages]
                        let filtered = new.filter { $0.isNumber }
                        let clamped = clampPage(Int(filtered) ?? 1)
                        pageInputText = clamped > 0 ? "\(clamped)" : ""
                    }
                Text("/ \(vm.totalPages)")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(AppColor.textTertiary)
            }

            // 下一页
            Button {
                vm.nextPage()
                syncPageInput()
            } label: {
                HStack(spacing: 4) {
                    Text("下一页".localized())
                    Image(systemName: "chevron.right")
                }
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(AppColor.bgTertiary)
                .foregroundStyle(vm.currentPage < vm.totalPages ? AppColor.textPrimary : AppColor.textTertiary)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
            .disabled(vm.currentPage >= vm.totalPages)

            Spacer()

            // 总数与范围
            Text(rangeDescription)
                .font(AppFont.monoSmall)
                .foregroundStyle(AppColor.textTertiary)
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 12)
        .background(
            Color(hex: 0x0E0F12).opacity(0.4)
                .background(.ultraThinMaterial)
        )
        .overlay(alignment: .top) {
            Divider().background(AppColor.borderSubtle)
        }
    }

    /// 形如 "1 - 12 / 共 891 个"
    private var rangeDescription: String {
        if vm.totalCount == 0 { return "共 0 个".localized() }
        let start = (vm.currentPage - 1) * vm.pageSize + 1
        let end = min(vm.currentPage * vm.pageSize, vm.totalCount)
        return "\(start) - \(end) · 共 \(vm.totalCount) 个".localized()
    }

    /// 同步输入框显示
    private func syncPageInput() {
        pageInputText = "\(vm.currentPage)"
    }

    /// 提交输入的页码（回车时）
    private func commitPageInput() {
        let trimmed = pageInputText.trimmingCharacters(in: .whitespaces)
        guard let page = Int(trimmed), page >= 1 else {
            syncPageInput()
            return
        }
        let clamped = clampPage(page)
        vm.goToPage(clamped)
        syncPageInput()
    }

    /// 页码 clamp 到 [1, totalPages]
    private func clampPage(_ page: Int) -> Int {
        max(1, min(page, max(1, vm.totalPages)))
    }

    /// 根据实际可用宽度计算列数，更新 pageSize = columns × rows
    private func updatePageSize(availableWidth: CGFloat) {
        guard availableWidth > 0 else { return }
        gridAvailableWidth = availableWidth
        // columns = floor((width + spacing) / (cardMinWidth + spacing))
        let columns = max(1, Int((availableWidth + Self.gridSpacing) / (Self.cardMinWidth + Self.gridSpacing)))
        vm.setPageSize(columns * Self.rowsPerPage)
    }

    // MARK: - 工具栏

    private var toolbar: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                // 左侧：标题 + 副标题
                VStack(alignment: .leading, spacing: 2) {
                    Text("音色库".localized())
                        .font(.system(size: 16, weight: .semibold))
                    Text(vm.showFavoritesOnly
                         ? "收藏的音色".localized()
                         : "共 %d 个精选音色 · 支持方言和角色".localized(vm.totalAll))
                        .font(AppFont.bodySmall)
                        .foregroundStyle(AppColor.textTertiary)
                }

                Spacer()

                searchField

                if let dismissWrapper = sheetDismiss {
                    Button {
                        dismissWrapper()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(AppColor.textTertiary)
                            .frame(width: 30, height: 30)
                            .background(AppColor.bgTertiary)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .pointingHandCursor()
                }
            }

            // 分类 Chip：瀑布流布局，一行显示满后自动换行
            categoryChips
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

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(AppColor.textTertiary)
            TextField("搜索".localized(), text: $vm.searchText)
                .textFieldStyle(.plain)
                .foregroundStyle(AppColor.textPrimary)
                .frame(width: 220)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(AppColor.bgTertiary)
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.small)
                .stroke(AppColor.borderSubtle, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.small))
        .pointingHandCursor()
    }

    /// 分类 Chip：两行布局
    /// 第一行（固定）：收藏、全部、旗舰、中文、英文
    /// 第二行（其余）：按 displayOrder 渲染剩余分类，行满自动换行
    private var categoryChips: some View {
        VStack(alignment: .leading, spacing: 6) {
            // 第一行：收藏 / 全部 / 旗舰 / 中文 / 英文
            HStack(spacing: 6) {
                CountChip(
                    title: "收藏".localized(),
                    count: vm.favoriteCount,
                    isActive: vm.showFavoritesOnly,
                    accent: true,
                    showHeart: true
                ) {
                    vm.toggleFavoritesFilter()
                }

                CountChip(
                    title: "全部".localized(),
                    count: vm.totalMatched,
                    isActive: vm.selectedCategory == nil && !vm.showFavoritesOnly
                ) {
                    vm.selectedCategory = nil
                    vm.showFavoritesOnly = false
                }

                primaryRowChip(for: .premium)
                primaryRowChip(for: .chinese)
                primaryRowChip(for: .english)
            }

            // 第二行：其余分类（按 displayOrder，自动换行）
            FlowLayout(spacing: 6, lineSpacing: 6) {
                ForEach(VoiceCategory.secondaryDisplayOrder, id: \.self) { cat in
                    CountChip(
                        title: cat.displayName.localized(),
                        count: vm.countForCategory(cat),
                        isActive: vm.selectedCategory == cat,
                        accent: cat.dimension == .premium
                    ) {
                        vm.selectCategory(cat)
                    }
                }
            }
        }
    }

    /// 第一行 chip 工厂：自动应用 selectCategory 互斥逻辑
    private func primaryRowChip(for cat: VoiceCategory) -> some View {
        CountChip(
            title: cat.displayName.localized(),
            count: vm.countForCategory(cat),
            isActive: vm.selectedCategory == cat,
            accent: cat.dimension == .premium
        ) {
            vm.selectCategory(cat)
        }
    }

    // MARK: - 空态

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text(vm.showFavoritesOnly ? "还没有收藏的音色".localized() : "没有匹配的音色".localized())
                .font(AppFont.bodyMedium)
                .foregroundStyle(AppColor.textTertiary)
            Button {
                vm.searchText = ""
                vm.selectedCategory = nil
                vm.showFavoritesOnly = false
            } label: {
                Text(vm.showFavoritesOnly ? "查看全部".localized() : "重置".localized())
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(AppColor.accentPrimary.opacity(0.15))
                    .foregroundStyle(AppColor.accentPrimary)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }

    // MARK: - 行为

    private func toggleFavorite(key: String) {
        vm.toggleFavorite(key: key)
    }

    private func preview(key: String) {
        if AudioPreviewPlayer.shared.isPlaying(key: key) {
            AudioPreviewPlayer.shared.stop()
        } else {
            AudioPreviewPlayer.shared.play(key: key)
        }
    }

    private func use(voice: Voice) {
        appState.selectedVoice = voice
        if let handler = useHandler {
            handler.handler(voice)
        } else {
            appState.selectedSection = .voiceStudio
        }
    }
}

// MARK: - 带数量徽标的 Chip

private struct CountChip: View {
    let title: String
    let count: Int
    let isActive: Bool
    var accent: Bool = false
    var showHeart: Bool = false  // 收藏图标
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if showHeart {
                    Image(systemName: isActive ? "heart.fill" : "heart")
                        .font(.system(size: 10))
                        .foregroundStyle(isActive ? AppColor.accentGlow : AppColor.textTertiary)
                }

                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)

                Text("\(count)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(isActive
                                     ? AppColor.accentGlow
                                     : AppColor.textTertiary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(
                        isActive
                        ? AppColor.accentPrimary.opacity(0.35)
                        : AppColor.bgElevated.opacity(0.6)
                    )
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(
                isActive
                ? (accent ? AppColor.accentPrimary.opacity(0.25)
                           : AppColor.accentPrimary.opacity(0.20))
                : AppColor.bgTertiary
            )
            .foregroundStyle(isActive ? AppColor.accentGlow : AppColor.textSecondary)
            .overlay(
                Capsule()
                    .stroke(
                        isActive
                        ? AppColor.accentPrimary.opacity(0.5)
                        : AppColor.borderSubtle,
                        lineWidth: 1
                    )
            )
            .clipShape(Capsule())
            .contentShape(Capsule())
            .transaction { $0.animation = nil }
        }
        .buttonStyle(StaticButtonStyle())
        .pointingHandCursor()
    }
}
