//
//  VoicesLibraryView.swift
//  EmotionVoice
//
//  Created by young on 2026/8/8.
//
//  优化点：
//  - 派生数据缓存到 VoicesLibraryViewModel（debounce 120ms）
//  - 外层容器 VStack → LazyVStack，让分类区块按需渲染
//  - VoiceCard 改为接受不可变 VO，闭包以弱引用触发 AppState 更新，避免 voice 数组整体替换引起所有卡片失效
//  - ScrollViewReader 只在首次 onAppear 滚动一次；后续不重复触发
//  - 收窄 AudioPreviewPlayer 观察范围：本视图不再订阅 playingKey，仅在卡片层观察
//

import SwiftUI

/// 音色库
struct VoicesLibraryView: View {

    @EnvironmentObject var appState: AppState
    @Environment(\.voiceLibraryUseHandler) private var useHandler
    @Environment(\.voiceLibraryDismiss) private var sheetDismiss

    @StateObject private var vm = VoicesLibraryViewModel()

    @State private var showFilters: Bool = false

    // 滚动定位
    @State private var didInitialScroll: Bool = false

    enum ViewMode {
        case grid
        case list
    }

    // MARK: - 视图入口

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            toolbar
            if showFilters { filterPanel }

            content
        }
        .onAppear {
            vm.setVoices(appState.voices)
        }
        .onChange(of: appState.voices) { _, new in
            vm.setVoices(new)
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
                emptyState
                    .padding(24)
            }
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 24) {
                        if let cat = vm.selectedCategory {
                            CategorySectionView(
                                category: cat,
                                voices: vm.voicesForSelectedCategory,
                                selectedKey: appState.selectedVoice?.key,
                                playingKey: AudioPreviewPlayer.shared.playingKey,
                                onFavorite: toggleFavorite(key:),
                                onPreview: preview(key:),
                                onUse: use(voice:)
                            )
                        } else {
                            ForEach(VoiceCategory.allCases) { cat in
                                let voices = vm.filteredVoicesByCategory[cat] ?? []
                                if !voices.isEmpty {
                                    CategorySectionView(
                                        category: cat,
                                        voices: voices,
                                        selectedKey: appState.selectedVoice?.key,
                                        playingKey: AudioPreviewPlayer.shared.playingKey,
                                        onFavorite: toggleFavorite(key:),
                                        onPreview: preview(key:),
                                        onUse: use(voice:)
                                    )
                                }
                            }
                        }
                    }
                    .padding(24)
                    .padding(.bottom, 24)
                }
                .onAppear {
                    // 仅在首次出现时滚动到选中音色（不带动画）
                    guard !didInitialScroll else { return }
                    didInitialScroll = true
                    if let key = appState.selectedVoice?.key {
                        DispatchQueue.main.async {
                            proxy.scrollTo("voice-\(key)", anchor: .center)
                        }
                    }
                }
            }
        }
    }

    // MARK: - 行为（通过 viewModel 间接修改状态）

    private func toggleFavorite(key: String) {
        _ = VoiceService.shared.toggleFavorite(key: key)
        // 局部刷新而非全局重建：通过 viewModel 重新注入最新数据
        vm.setVoices(VoiceService.shared.fetchAll())
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

    // MARK: - 工具栏

    private var toolbar: some View {
        VStack(spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("音色库".localized())
                        .font(.system(size: 16, weight: .semibold))
                    Text("共 %d 个精选音色 · 支持方言和角色".localized(appState.voices.count))
                        .font(AppFont.bodySmall)
                        .foregroundStyle(AppColor.textTertiary)
                }
                Spacer()

                searchField

                filterToggleButton

                favoritesButton

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
                .frame(width: 200)
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

    private var filterToggleButton: some View {
        let active = filterIsActive
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                showFilters.toggle()
            }
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "line.3.horizontal.decrease.circle\(active ? ".fill" : "")")
                Text("筛选".localized())
                    .font(.system(size: 12, weight: .medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(active ? AppColor.accentPrimary.opacity(0.18) : AppColor.bgTertiary)
            .foregroundStyle(active ? AppColor.accentPrimary : AppColor.textSecondary)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.small))
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
    }

    private var favoritesButton: some View {
        Button {
            vm.favoritesOnly.toggle()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: vm.favoritesOnly ? "heart.fill" : "heart")
                    .font(.system(size: 12, weight: .medium))
                Text("收藏".localized())
                    .font(.system(size: 12, weight: .medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(vm.favoritesOnly ? AppColor.accentPrimary.opacity(0.2) : AppColor.bgTertiary)
            .foregroundStyle(vm.favoritesOnly ? AppColor.accentPrimary : AppColor.textSecondary)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.small))
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
    }

    private var categoryChips: some View {
        HStack(spacing: 6) {
            CategoryChip(
                title: "全部".localized(),
                isActive: vm.selectedCategory == nil
            ) {
                vm.selectedCategory = nil
            }
            ForEach(VoiceCategory.allCases) { cat in
                CategoryChip(
                    title: cat.displayName.localized(),
                    isActive: vm.selectedCategory == cat
                ) {
                    vm.selectedCategory = cat
                }
            }
        }
    }

    private var filterIsActive: Bool {
        vm.selectedScene != nil || vm.selectedAgeBucket != .any || vm.useAgeRange || vm.favoritesOnly
    }

    /// 年龄桶：.unknown 数量为 0 时自动隐藏
    var visibleAgeBuckets: [AgeBucket] {
        let unknownCount = appState.voices.count { $0.age == nil }
        return AgeBucket.allCases.filter { bucket in
            if bucket == .unknown { return unknownCount > 0 }
            return true
        }
    }

    // MARK: - 筛选面板

    private var filterPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            // 适用场景
            VStack(alignment: .leading, spacing: 8) {
                sectionLabel("适用场景".localized())
                FlowLayout(spacing: 6) {
                    SceneChip(
                        title: "全部".localized(),
                        isActive: vm.selectedScene == nil
                    ) {
                        vm.selectedScene = nil
                    }
                    ForEach(vm.availableScenes, id: \.self) { scene in
                        SceneChip(
                            title: scene,
                            isActive: vm.selectedScene == scene
                        ) {
                            vm.selectedScene = scene
                        }
                    }
                }
            }

            // 年龄范围
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    sectionLabel("年龄范围".localized())
                    Toggle(isOn: $vm.useAgeRange) {
                        Text("自定义滑块".localized())
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.textSecondary)
                    }
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .tint(AppColor.accentPrimary)
                    .pointingHandCursor()

                    Spacer()

                    if vm.useAgeRange {
                        Text("\(Int(min(vm.ageLower, vm.ageUpper))) – \(Int(max(vm.ageLower, vm.ageUpper))) 岁")
                            .font(AppFont.monoSmall)
                            .foregroundStyle(AppColor.textSecondary)
                    }
                }

                if vm.useAgeRange {
                    let lo = Double(vm.availableAgeRange.lowerBound)
                    let hi = Double(vm.availableAgeRange.upperBound)
                    HStack(spacing: 8) {
                        Text("\(Int(lo))")
                            .font(AppFont.monoSmall)
                            .foregroundStyle(AppColor.textTertiary)
                            .frame(width: 28, alignment: .trailing)
                        RangeSlider(lowerValue: $vm.ageLower,
                                     upperValue: $vm.ageUpper,
                                     range: lo...hi,
                                     step: 1)
                        Text("\(Int(hi))")
                            .font(AppFont.monoSmall)
                            .foregroundStyle(AppColor.textTertiary)
                            .frame(width: 28, alignment: .leading)
                    }
                } else {
                    HStack(spacing: 6) {
                        ForEach(visibleAgeBuckets) { bucket in
                            AgeBucketChip(
                                title: bucket.displayName.localized(),
                                range: bucket.rangeDescription,
                                isActive: vm.selectedAgeBucket == bucket
                            ) {
                                vm.selectedAgeBucket = bucket
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 14)
        .background(Color(hex: 0x0E0F12).opacity(0.25))
        .overlay(alignment: .bottom) {
            Divider().background(AppColor.borderSubtle)
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(AppFont.label)
            .foregroundStyle(AppColor.textTertiary)
            .textCase(.uppercase)
            .tracking(0.06)
    }

    // MARK: - 空态

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("没有匹配的音色".localized())
                .font(AppFont.bodyMedium)
                .foregroundStyle(AppColor.textTertiary)
            Button {
                vm.clearFilters()
            } label: {
                Text("重置筛选".localized())
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
}

// MARK: - 拆出的局部子视图（让卡片网格与 chip 各自持有稳定 identity）

/// 分类区块：独立子视图，避免父视图状态变化导致整片网格重渲染
private struct CategorySectionView: View {
    let category: VoiceCategory
    let voices: [Voice]
    let selectedKey: String?
    let playingKey: String?
    let onFavorite: (String) -> Void
    let onPreview: (String) -> Void
    let onUse: (Voice) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(category.displayName.localized())
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                Text("\(voices.count) 个".localized())
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textTertiary)
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 190, maximum: 210), spacing: 12)],
                spacing: 12
            ) {
                ForEach(voices) { voice in
                    VoiceCard(
                        item: VoiceCardItem(voice: voice),
                        isSelected: selectedKey == voice.key,
                        isPlaying: playingKey == voice.key
                    ) {
                        onFavorite(voice.key)
                    } onPreview: {
                        onPreview(voice.key)
                    } onUse: {
                        onUse(voice)
                    }
                    .id("voice-\(voice.key)")
                }
            }
        }
    }
}

// MARK: - Chip 视图（无依赖，稳定 identity）

private struct CategoryChip: View {
    let title: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(isActive ? AppColor.accentPrimary.opacity(0.2) : AppColor.bgTertiary)
                .foregroundStyle(isActive ? AppColor.accentPrimary : AppColor.textSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.pill)
                        .stroke(
                            isActive ? AppColor.accentPrimary.opacity(0.5) : AppColor.borderSubtle,
                            lineWidth: 1
                        )
                )
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.pill))
                .contentShape(RoundedRectangle(cornerRadius: AppRadius.pill))
                .transaction { $0.animation = nil }
        }
        .buttonStyle(StaticButtonStyle())
        .fixedSize()
        .pointingHandCursor()
    }
}

private struct SceneChip: View {
    let title: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(isActive ? AppColor.accentPrimary.opacity(0.2) : AppColor.bgTertiary)
                .foregroundStyle(isActive ? AppColor.accentPrimary : AppColor.textSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.pill)
                        .stroke(
                            isActive ? AppColor.accentPrimary.opacity(0.5) : AppColor.borderSubtle,
                            lineWidth: 1
                        )
                )
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.pill))
                .contentShape(RoundedRectangle(cornerRadius: AppRadius.pill))
                .transaction { $0.animation = nil }
        }
        .buttonStyle(StaticButtonStyle())
        .fixedSize()
        .pointingHandCursor()
    }
}

private struct AgeBucketChip: View {
    let title: String
    let range: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                Text(range)
                    .font(AppFont.monoSmall)
                    .foregroundStyle(isActive ? AppColor.accentPrimary.opacity(0.7) : AppColor.textTertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(isActive ? AppColor.accentPrimary.opacity(0.2) : AppColor.bgTertiary)
            .foregroundStyle(isActive ? AppColor.accentPrimary : AppColor.textSecondary)
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.pill)
                    .stroke(
                        isActive ? AppColor.accentPrimary.opacity(0.5) : AppColor.borderSubtle,
                        lineWidth: 1
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.pill))
            .contentShape(RoundedRectangle(cornerRadius: AppRadius.pill))
            .transaction { $0.animation = nil }
        }
        .buttonStyle(StaticButtonStyle())
        .fixedSize()
        .pointingHandCursor()
    }
}
