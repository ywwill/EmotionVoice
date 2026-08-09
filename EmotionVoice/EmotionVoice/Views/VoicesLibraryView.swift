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

    @State private var selectedCategory: VoiceCategory? = nil
    @State private var searchText: String = ""
    @State private var viewMode: ViewMode = .grid

    enum ViewMode {
        case grid
        case list
    }

    var filteredVoices: [Voice] {
        appState.voices.filter { v in
            let matchesCategory = selectedCategory == nil || v.category == selectedCategory
            let matchesSearch = searchText.isEmpty
                || v.name.localizedCaseInsensitiveContains(searchText)
                || v.desc.localizedCaseInsensitiveContains(searchText)
            return matchesCategory && matchesSearch
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            toolbar
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    if let cat = selectedCategory {
                        categorySection(cat)
                    } else {
                        // 显示所有分类
                        ForEach(VoiceCategory.allCases) { cat in
                            let voices = appState.voices.filter { $0.category == cat }
                            if !voices.isEmpty {
                                categorySection(cat, voices: voices)
                            }
                        }
                    }
                }
                .padding(24)
                .padding(.bottom, 24)
            }
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
                }
                .background(AppColor.bgTertiary)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.small))
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
        }
        .buttonStyle(.plain)
    }

    // MARK: - 分类区块

    @ViewBuilder
    private func categorySection(_ category: VoiceCategory, voices: [Voice]? = nil) -> some View {
        let list = voices ?? appState.voices.filter { $0.category == category }
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
                columns: [GridItem(.adaptive(minimum: 200, maximum: 280), spacing: 12)],
                spacing: 12
            ) {
                ForEach(list) { voice in
                    VoiceCard(voice: voice,
                              isSelected: appState.selectedVoice?.key == voice.key) {
                        appState.selectedVoice = voice
                        let newFav = VoiceService.shared.toggleFavorite(key: voice.key)
                        var copy = voice
                        copy.isFavorite = newFav
                        appState.refreshVoices()
                    }
                }
            }
        }
    }
}

// MARK: - 音色卡片

private struct VoiceCard: View {

    let voice: Voice
    let isSelected: Bool
    let onFavorite: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                AvatarView(text: voice.avatar, size: 40)
                Spacer()
                if voice.isPremium {
                    Text("⭐ 旗舰".localized())
                        .font(AppFont.monoSmall)
                        .foregroundStyle(AppColor.accentGlow)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(AppColor.accentPrimary.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(voice.name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppColor.textPrimary)
                Text(voice.desc)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
            }

            // 简易波形
            HStack(spacing: 2) {
                ForEach(0..<12, id: \.self) { i in
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [AppColor.accentPrimary.opacity(0.5), AppColor.accentGlow.opacity(0.7)],
                                startPoint: .bottom, endPoint: .top
                            )
                        )
                        .frame(width: 3, height: CGFloat(8 + (i % 5) * 4))
                }
            }
            .frame(height: 28)

            HStack(spacing: 6) {
                Button {
                    // 试听
                } label: {
                    Label("试听".localized(), systemImage: "play.fill")
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(AppColor.bgTertiary)
                        .foregroundStyle(AppColor.textSecondary)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)

                Button(action: onFavorite) {
                    Image(systemName: voice.isFavorite ? "heart.fill" : "heart")
                        .font(.system(size: 12))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            voice.isFavorite
                            ? AppColor.accentPrimary.opacity(0.2)
                            : AppColor.bgTertiary
                        )
                        .foregroundStyle(
                            voice.isFavorite ? AppColor.accentPrimary : AppColor.textSecondary
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(AppColor.accentPrimary)
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColor.bgSecondary)
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.medium)
                .stroke(
                    isSelected ? AppColor.accentPrimary.opacity(0.5) : AppColor.borderSubtle,
                    lineWidth: 1
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium))
    }
}
