//
//  VoicesLibraryViewModel.swift
//  EmotionVoice
//
//  Created by young on 2026/8/15.
//
//  音色库视图模型：
//  - 仅持有选中的分类与搜索文本
//  - 缓存按当前分类过滤后的音色列表（debounce 120ms）
//  - 提供每个分类的命中数量，用于 chip 上显示计数
//

import Foundation
import SwiftUI
import Combine

@MainActor
final class VoicesLibraryViewModel: ObservableObject {

    // MARK: - 状态

    /// 当前选中的分类（nil 表示"全部"）
    @Published var selectedCategory: VoiceCategory? = nil
    /// 搜索文本
    @Published var searchText: String = ""

    // MARK: - 派生缓存

    /// 当前分类（或全部）下，命中筛选条件的音色
    @Published private(set) var displayedVoices: [Voice] = []
    /// "全部"模式下按分类分组的桶（用于分组视图）
    @Published private(set) var groupedByCategory: [CategoryBucket] = []
    /// 当前分类下是否为空
    @Published private(set) var isEmpty: Bool = true
    /// 搜索命中（在当前 selectedCategory 下）的所有音色总数
    @Published private(set) var totalMatched: Int = 0
    /// 全部音色总数（忽略筛选）
    @Published private(set) var totalAll: Int = 0

    /// 分类分组视图项
    struct CategoryBucket: Identifiable {
        let category: VoiceCategory
        let voices: [Voice]
        var id: VoiceCategory { category }
    }

    // MARK: - 输入

    private var allVoices: [Voice] = []
    private var cancellables: Set<AnyCancellable> = []

    init() {
        // 分类与搜索变化时做 debounce
        $selectedCategory.map { _ in () }
            .merge(with: $searchText.map { _ in () })
            .receive(on: RunLoop.main)
            .debounce(for: .milliseconds(120), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.recompute() }
            .store(in: &cancellables)
    }

    // MARK: - 数据注入

    func setVoices(_ voices: [Voice]) {
        self.allVoices = voices
        recompute()
    }

    /// 原地切换收藏状态（避免全量 re-fetch / recompute）
    func toggleFavorite(key: String) {
        guard let idx = allVoices.firstIndex(where: { $0.key == key }) else { return }
        let old = allVoices[idx]
        let updated = Voice(
            key: old.key,
            name: old.name,
            desc: old.desc,
            avatar: old.avatar,
            category: old.category,
            isFavorite: !old.isFavorite,
            scene: old.scene,
            age: old.age,
            gender: old.gender,
            audio: old.audio,
            lang: old.lang
        )
        allVoices[idx] = updated
        recompute()
    }

    // MARK: - 计算

    /// 全部命中某个分类的音色数（不考虑 selectedCategory，只考虑搜索）
    func countForCategory(_ cat: VoiceCategory) -> Int {
        let needle = searchText.trimmingCharacters(in: .whitespaces)
        let pool: [Voice]
        if needle.isEmpty {
            pool = allVoices
        } else {
            pool = allVoices.filter { v in
                v.name.localizedCaseInsensitiveContains(needle)
                || v.desc.localizedCaseInsensitiveContains(needle)
                || v.scene.localizedCaseInsensitiveContains(needle)
                || v.lang.localizedCaseInsensitiveContains(needle)
            }
        }
        return pool.filter { cat.matches($0) }.count
    }

    /// 收藏数量（用于"我的收藏"chip 计数）
    var favoriteCount: Int {
        allVoices.filter { $0.isFavorite }.count
    }

    private func recompute() {
        let voices = allVoices
        let needle = searchText.trimmingCharacters(in: .whitespaces)
        let selected = selectedCategory

        // 搜索过滤
        let searched: [Voice]
        if needle.isEmpty {
            searched = voices
        } else {
            searched = voices.filter { v in
                v.name.localizedCaseInsensitiveContains(needle)
                || v.desc.localizedCaseInsensitiveContains(needle)
                || v.scene.localizedCaseInsensitiveContains(needle)
                || v.lang.localizedCaseInsensitiveContains(needle)
            }
        }

        // 分类过滤
        if let selected {
            displayedVoices = searched.filter { selected.matches($0) }
            groupedByCategory = [CategoryBucket(category: selected, voices: displayedVoices)]
        } else {
            // 全部模式：按分类分桶
            var groups: [VoiceCategory: [Voice]] = [:]
            for v in searched {
                for cat in VoiceCategory.allCases where cat.matches(v) {
                    groups[cat, default: []].append(v)
                }
            }
            groupedByCategory = VoiceCategory.allCases.compactMap { cat in
                guard let bucket = groups[cat], !bucket.isEmpty else { return nil }
                return CategoryBucket(category: cat, voices: bucket)
            }
            displayedVoices = searched
        }

        totalAll = voices.count
        totalMatched = searched.count
        isEmpty = displayedVoices.isEmpty
    }
}