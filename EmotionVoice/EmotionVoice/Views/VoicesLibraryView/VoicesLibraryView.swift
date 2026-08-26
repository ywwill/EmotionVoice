//
//  VoicesLibraryView.swift
//  EmotionVoice
//
//  Created by young on 2026/8/8.
//
//  优化点：
//  - 派生数据缓存到 VoicesLibraryViewModel（debounce 120ms）
//  - 顶部 Chip 按"维度分组"展示所有分类；点击切换内容区
//  - VoiceCard 接受不可变 VO，闭包以弱引用触发 AppState 更新
//  - ScrollViewReader 仅首次 onAppear 滚动一次
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

    enum ViewMode {
        case grid
        case list
    }

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
                    LazyVStack(alignment: .leading, spacing: 20) {
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
                    .padding(20)
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

    /// 全部分类 Chip：多行展示，按维度顺序展示所有分类
    private var categoryChips: some View {
        FlowLayout(spacing: 8) {
            CategoryChip(
                title: "全部".localized(),
                isActive: vm.selectedCategory == nil
            ) {
                vm.selectedCategory = nil
            }

            ForEach(VoiceCategory.displayOrder, id: \.self) { dim in
                let cats = VoiceCategory.allCases.filter { $0.dimension == dim }
                if !cats.isEmpty {
                    ForEach(cats) { cat in
                        CategoryChip(
                            title: cat.displayName.localized(),
                            isActive: vm.selectedCategory == cat
                        ) {
                            vm.selectedCategory = (vm.selectedCategory == cat) ? nil : cat
                        }
                    }
                }
            }
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
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 160, maximum: 200), spacing: 12)],
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
        .pointingHandCursor()
    }
}
