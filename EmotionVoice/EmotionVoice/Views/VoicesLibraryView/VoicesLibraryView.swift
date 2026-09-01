//
//  VoicesLibraryView.swift
//  EmotionVoice
//
//  Created by young on 2026/8/8.
//
//  优化点（参考 voices.html）：
//  - 顶部工具栏采用「面包屑标题 + 搜索 + 筛选」的精简样式
//  - 分类 chip 增加命中数量徽标
//  - 分类区块头部带「图标 + 标题 + 数量」与「查看全部」动作
//  - 旗舰音色采用渐变高亮（featured）样式，区别于基础音色
//  - 卡片支持 4 列网格，hover/选中时变化边框与背景
//  - 播放中展示波形动画
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

    // MARK: - 视图入口

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            toolbar
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
                emptyState.padding(20)
            }
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 28) {
                        // 切换分类时滚动到此处
                        Color.clear
                            .frame(width: 1, height: 1)
                            .id("library-top")

                        ForEach(vm.groupedByCategory) { bucket in
                            CategorySectionView(
                                category: bucket.category,
                                voices: bucket.voices,
                                selectedKey: appState.selectedVoice?.key,
                                playingKey: previewPlayer.playingKey,
                                onFavorite: toggleFavorite(key:),
                                onPreview: preview(key:),
                                onUse: use(voice:)
                            )
                        }
                    }
                    .padding(.horizontal, 32)
                    .padding(.vertical, 24)
                    .padding(.bottom, 20)
                }
                .onChange(of: vm.selectedCategory) { _, _ in
                    withAnimation(.easeInOut(duration: 0.2)) {
                        proxy.scrollTo("library-top", anchor: .top)
                    }
                }
                .onAppear {
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

    // MARK: - 行为

    private func toggleFavorite(key: String) {
        _ = VoiceService.shared.toggleFavorite(key: key)
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

    // MARK: - 工具栏

    private var toolbar: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                // 左侧：标题 + 副标题
                VStack(alignment: .leading, spacing: 2) {
                    Text("音色库".localized())
                        .font(.system(size: 16, weight: .semibold))
                    Text("共 %d 个精选音色 · 支持方言和角色".localized(appState.voices.count))
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

            categoryChips
                .frame(maxWidth: .infinity, alignment: .leading)
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

    /// 分类 Chip：单行横向展示（不再换行），按维度分组全部展示
    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                CountChip(
                    title: "全部".localized(),
                    count: vm.totalMatched,
                    isActive: vm.selectedCategory == nil
                ) {
                    vm.selectedCategory = nil
                }

                ForEach(VoiceCategory.displayOrder, id: \.self) { dim in
                    let cats = VoiceCategory.allCases.filter { $0.dimension == dim }
                    if !cats.isEmpty {
                        ForEach(cats) { cat in
                            CountChip(
                                title: cat.displayName.localized(),
                                count: vm.countForCategory(cat),
                                isActive: vm.selectedCategory == cat,
                                accent: cat.dimension == .premium
                            ) {
                                vm.selectedCategory = (vm.selectedCategory == cat) ? nil : cat
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 2)
        }
    }

    // MARK: - 空态

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("没有匹配的音色".localized())
                .font(AppFont.bodyMedium)
                .foregroundStyle(AppColor.textTertiary)
            Button {
                vm.searchText = ""
                vm.selectedCategory = nil
            } label: {
                Text("重置".localized())
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

// MARK: - 分类区块视图

private struct CategorySectionView: View {
    let category: VoiceCategory
    let voices: [Voice]
    let selectedKey: String?
    let playingKey: String?
    let onFavorite: (String) -> Void
    let onPreview: (String) -> Void
    let onUse: (Voice) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // 区块头：图标 + 标题 + 数量
            HStack(alignment: .center, spacing: 10) {
                Text(category.icon)
                    .font(.system(size: 16))
                Text(category.displayName.localized())
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(AppColor.textPrimary)
                if category == .premium {
                    Text("PLUS")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(AppColor.accentGlow)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(AppColor.accentPrimary.opacity(0.15))
                        .clipShape(Capsule())
                }
                Text("\(voices.count) 个".localized())
                    .font(AppFont.monoSmall)
                    .foregroundStyle(AppColor.textTertiary)
                Spacer()
            }

            // 卡片网格（4 列）
            LazyVGrid(
                columns: [
                    GridItem(.adaptive(minimum: 180, maximum: 240), spacing: 12)
                ],
                spacing: 12
            ) {
                ForEach(voices) { voice in
                    VoiceCard(
                        item: VoiceCardItem(voice: voice),
                        isSelected: selectedKey == voice.key,
                        isPlaying: playingKey == voice.key,
                        isFeatured: voice.isPremium
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

// MARK: - 带数量徽标的 Chip

private struct CountChip: View {
    let title: String
    let count: Int
    let isActive: Bool
    var accent: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(title)
                    .font(.system(size: 12, weight: .medium))
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