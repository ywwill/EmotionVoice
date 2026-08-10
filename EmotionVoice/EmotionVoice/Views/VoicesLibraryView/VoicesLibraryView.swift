//
//  VoicesLibraryView.swift
//  EmotionVoice
//
//  Created by young on 2026/8/8.
//

import SwiftUI

/// 音色库
struct VoicesLibraryView: View {

    @EnvironmentObject var appState: AppState
    @Environment(\.voiceLibraryUseHandler) private var useHandler
    @Environment(\.voiceLibraryDismiss) private var sheetDismiss
    @ObservedObject private var player = AudioPreviewPlayer.shared

    @State private var selectedCategory: VoiceCategory? = nil
    @State private var searchText: String = ""
    @State private var viewMode: ViewMode = .grid

    // MARK: - 筛选状态
    @State private var selectedScene: String? = nil           // nil = 全部
    @State private var selectedAgeBucket: AgeBucket = .any    // 年龄段
    @State private var ageLower: Double = 0                   // 手动滑块下限
    @State private var ageUpper: Double = 99                  // 手动滑块上限
    @State private var useAgeRange: Bool = false              // 是否启用自定义范围
    @State private var showFilters: Bool = false              // 折叠/展开筛选区
    @State private var favoritesOnly: Bool = false            // 只看收藏

    // MARK: - 滚动定位
    /// 需要滚动到的音色 key（每次 onAppear 时读取）
    @State private var pendingScrollKey: String? = nil

    enum ViewMode {
        case grid
        case list
    }

    // MARK: - 数据

    /// 当前可用的场景列表（按使用频次排序，含 "全部" 占位）
    private var availableScenes: [String] {
        let counts = appState.voices.reduce(into: [String: Int]()) { dict, v in
            let s = v.scene.trimmingCharacters(in: .whitespaces)
            guard !s.isEmpty else { return }
            dict[s, default: 0] += 1
        }
        // 稳定排序：先按频次降序，频次相同时按字典序升序，保证每次顺序一致
        return counts.keys.sorted { lhs, rhs in
            let lc = counts[lhs] ?? 0
            let rc = counts[rhs] ?? 0
            if lc != rc { return lc > rc }
            return lhs < rhs
        }
    }

    /// 当前分类下的所有可用年龄范围
    private var availableAgeRange: ClosedRange<Int> {
        let ages = appState.voices.compactMap { $0.age }
        if ages.isEmpty { return 0...99 }
        return ages.min()!...ages.max()!
    }

    var filteredVoices: [Voice] {
        appState.voices.filter { v in
            let matchesCategory = selectedCategory == nil || v.category == selectedCategory
            let matchesSearch = searchText.isEmpty
                || v.name.localizedCaseInsensitiveContains(searchText)
                || v.desc.localizedCaseInsensitiveContains(searchText)
                || v.scene.localizedCaseInsensitiveContains(searchText)
            let matchesScene = selectedScene == nil || v.scene == selectedScene
            let matchesAge = ageMatches(v.age)
            let matchesFavorite = !favoritesOnly || v.isFavorite
            return matchesCategory && matchesSearch && matchesScene && matchesAge && matchesFavorite
        }
    }

    private func ageMatches(_ age: Int?) -> Bool {
        if useAgeRange {
            // 自定义滑块模式：忽略 bucket
            guard let age else { return false }
            let lo = Int(min(ageLower, ageUpper))
            let hi = Int(max(ageLower, ageUpper))
            return age >= lo && age <= hi
        }
        // 桶模式
        if selectedAgeBucket == .any { return true }
        guard let age else { return selectedAgeBucket == .unknown }
        switch selectedAgeBucket {
        case .any:     return true
        case .child:   return age < 13
        case .teen:    return age >= 13 && age < 18
        case .young:   return age >= 18 && age < 36
        case .middle:  return age >= 36 && age < 60
        case .senior:  return age >= 60
        case .unknown: return false
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            toolbar
            if showFilters { filterPanel }
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        if filteredVoices.isEmpty {
                            emptyState
                        } else if let cat = selectedCategory {
                            // 只显示选中分类
                            categorySection(cat, voices: filteredVoices.filter { $0.category == cat })
                        } else {
                            // 全部：按分类分组
                            ForEach(VoiceCategory.allCases) { cat in
                                let voices = filteredVoices.filter { $0.category == cat }
                                if !voices.isEmpty {
                                    categorySection(cat, voices: voices)
                                }
                            }
                        }
                    }
                    .padding(24)
                    .padding(.bottom, 24)
                }
                .onChange(of: pendingScrollKey) { _, key in
                    guard let key else { return }
                    // 等一帧让布局稳定再滚动
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            proxy.scrollTo("voice-\(key)", anchor: .center)
                        }
                    }
                }
            }
        }
        .onAppear {
            // 记录需要滚动到的选中音色 key
            pendingScrollKey = appState.selectedVoice?.key
        }
        .onDisappear {
            // 离开时停止试听
            AudioPreviewPlayer.shared.stop()
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

                // 搜索框
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(AppColor.textTertiary)
                    TextField("搜索".localized(), text: $searchText)
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

                // 筛选切换
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showFilters.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "line.3.horizontal.decrease.circle\(filterIsActive ? ".fill" : "")")
                        Text("筛选".localized())
                            .font(.system(size: 12, weight: .medium))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(filterIsActive ? AppColor.accentPrimary.opacity(0.18) : AppColor.bgTertiary)
                    .foregroundStyle(filterIsActive ? AppColor.accentPrimary : AppColor.textSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.small))
                }
                .buttonStyle(.plain)
                .pointingHandCursor()

                // 视图切换
                HStack(spacing: 0) {
                    Button {
                        viewMode = .grid
                    } label: {
                        Image(systemName: "square.grid.2x2")
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(viewMode == .grid ? AppColor.bgElevated : Color.clear)
                            .foregroundStyle(viewMode == .grid ? AppColor.accentPrimary : AppColor.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .pointingHandCursor()

                    Button {
                        viewMode = .list
                    } label: {
                        Image(systemName: "list.bullet")
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(viewMode == .list ? AppColor.bgElevated : Color.clear)
                            .foregroundStyle(viewMode == .list ? AppColor.accentPrimary : AppColor.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .pointingHandCursor()
                }
                .background(AppColor.bgTertiary)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.small))

                // 仅看收藏
                Button {
                    favoritesOnly.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: favoritesOnly ? "heart.fill" : "heart")
                            .font(.system(size: 12, weight: .medium))
                        Text("收藏".localized())
                            .font(.system(size: 12, weight: .medium))
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(favoritesOnly ? AppColor.accentPrimary.opacity(0.2) : AppColor.bgTertiary)
                    .foregroundStyle(favoritesOnly ? AppColor.accentPrimary : AppColor.textSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.small))
                }
                .buttonStyle(.plain)
                .pointingHandCursor()

                // 关闭按钮（仅 sheet 模式下显示）
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

            // 分类筛选
            HStack(spacing: 6) {
                categoryChip(nil, title: "全部".localized())
                ForEach(VoiceCategory.allCases) { cat in
                    categoryChip(cat, title: cat.displayName.localized())
                }
            }
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

    private var filterIsActive: Bool {
        selectedScene != nil || selectedAgeBucket != .any || useAgeRange || favoritesOnly
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
                    sceneChip(nil, title: "全部".localized())
                    ForEach(availableScenes, id: \.self) { scene in
                        sceneChip(scene, title: scene)
                    }
                }
            }

            // 年龄范围
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 12) {
                    sectionLabel("年龄范围".localized())
                    Toggle(isOn: $useAgeRange) {
                        Text("自定义滑块".localized())
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.textSecondary)
                    }
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .tint(AppColor.accentPrimary)
                    .pointingHandCursor()

                    Spacer()

                    if useAgeRange {
                        Text("\(Int(min(ageLower, ageUpper))) – \(Int(max(ageLower, ageUpper))) 岁")
                            .font(AppFont.monoSmall)
                            .foregroundStyle(AppColor.textSecondary)
                    }
                }

                if useAgeRange {
                    let lo = Double(availableAgeRange.lowerBound)
                    let hi = Double(availableAgeRange.upperBound)
                    HStack(spacing: 8) {
                        Text("\(Int(lo))")
                            .font(AppFont.monoSmall)
                            .foregroundStyle(AppColor.textTertiary)
                            .frame(width: 28, alignment: .trailing)
                        RangeSlider(lowerValue: $ageLower,
                                     upperValue: $ageUpper,
                                     range: lo...hi,
                                     step: 1)
                        Text("\(Int(hi))")
                            .font(AppFont.monoSmall)
                            .foregroundStyle(AppColor.textTertiary)
                            .frame(width: 28, alignment: .leading)
                    }
                } else {
                    // 桶模式
                    HStack(spacing: 6) {
                        ForEach(visibleAgeBuckets) { bucket in
                            ageBucketChip(bucket)
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

    private func sceneChip(_ scene: String?, title: String) -> some View {
        let isActive = selectedScene == scene
        return Button {
            selectedScene = scene
        } label: {
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

    private func ageBucketChip(_ bucket: AgeBucket) -> some View {
        let isActive = selectedAgeBucket == bucket
        return Button {
            selectedAgeBucket = bucket
        } label: {
            HStack(spacing: 4) {
                Text(bucket.displayName.localized())
                    .font(.system(size: 12, weight: .medium))
                Text(bucket.rangeDescription)
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

    private func categoryChip(_ cat: VoiceCategory?, title: String) -> some View {
        let isActive = selectedCategory == cat
        return Button {
            selectedCategory = cat
        } label: {
            Text(title)
                .font(.system(size: 12, weight: .medium))
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .background(
                    isActive ? AppColor.accentPrimary.opacity(0.2) : AppColor.bgTertiary
                )
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

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("没有匹配的音色".localized())
                .font(AppFont.bodyMedium)
                .foregroundStyle(AppColor.textTertiary)
            Button {
                clearFilters()
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

    private func clearFilters() {
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedScene = nil
            selectedAgeBucket = .any
            useAgeRange = false
            ageLower = 0
            ageUpper = 99
            searchText = ""
            favoritesOnly = false
        }
    }

    // MARK: - 分类区块

    @ViewBuilder
    private func categorySection(_ category: VoiceCategory, voices: [Voice]? = nil) -> some View {
        let list = voices ?? filteredVoices.filter { $0.category == category }
        let title = category.displayName.localized()
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                Text("\(list.count) 个".localized())
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textTertiary)
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 190, maximum: 210), spacing: 12)],
                spacing: 12
            ) {
                ForEach(list) { voice in
                    VoiceCard(voice: voice,
                              isSelected: appState.selectedVoice?.key == voice.key,
                              isPlaying: player.isPlaying(key: voice.key)) {
                        // 仅切换收藏状态，不改变当前选中音色
                        _ = VoiceService.shared.toggleFavorite(key: voice.key)
                        appState.refreshVoices()
                    } onPreview: {
                        // 试听 / 再次点击则停止
                        if player.isPlaying(key: voice.key) {
                            AudioPreviewPlayer.shared.stop()
                        } else {
                            AudioPreviewPlayer.shared.play(key: voice.key)
                        }
                    } onUse: {
                        // sheet 上下文：仅选中并关闭；页面上下文：跳转工作台
                        appState.selectedVoice = voice
                        if let handler = useHandler {
                            handler.handler(voice)
                        } else {
                            appState.selectedSection = .voiceStudio
                        }
                    }
                    .id("voice-\(voice.key)")
                }
            }
        }
    }
}
