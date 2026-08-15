//
//  VoicesLibraryViewModel.swift
//  EmotionVoice
//
//  Created by young on 2026/8/15.
//
//  音色库专用视图模型：
//  - 持有筛选条件（与视图 @State 等价）
//  - 用 Combine 把 filter 计算 debounce 到一次 idle
//  - 缓存 filteredVoicesByCategory、availableScenes、availableAgeRange，避免每次 body 重算
//  - 把"切换收藏 → refreshVoices → 全表重建"的影响面收敛到这里
//

import Foundation
import SwiftUI
import Combine

@MainActor
final class VoicesLibraryViewModel: ObservableObject {

    // MARK: - 筛选条件（@Published 仅用于触发自身更新）

    @Published var selectedCategory: VoiceCategory? = nil
    @Published var searchText: String = ""
    @Published var selectedScene: String? = nil
    @Published var selectedAgeBucket: AgeBucket = .any
    @Published var ageLower: Double = 0
    @Published var ageUpper: Double = 99
    @Published var useAgeRange: Bool = false
    @Published var favoritesOnly: Bool = false

    // MARK: - 派生缓存（onChange 触发更新）

    /// 按分类分组后的已筛选音色（懒渲染时按需读取）
    @Published private(set) var filteredVoicesByCategory: [VoiceCategory: [Voice]] = [:]
    /// 单分类视图（selectedCategory != nil 时使用）
    @Published private(set) var voicesForSelectedCategory: [Voice] = []
    /// "全部" 模式下的扁平列表
    @Published private(set) var filteredVoices: [Voice] = []
    /// 场景列表（按频次排序）
    @Published private(set) var availableScenes: [String] = []
    /// 当前分类下年龄范围
    @Published private(set) var availableAgeRange: ClosedRange<Int> = 0...99
    /// 是否需要展示空态
    @Published private(set) var isEmpty: Bool = true

    // MARK: - 输入

    /// 原始音色数据（外部刷新后调用 setVoices）
    private var allVoices: [Voice] = []
    private var cancellables: Set<AnyCancellable> = []
    /// debounce 句柄
    private var pendingRecompute: AnyCancellable?

    init() {
        // 关键：把所有筛选条件组合后做 debounce（200ms），避免每个字符都重算
        let publishers: AnyPublisher<Void, Never> = Publishers
            .CombineLatest4(
                $selectedCategory.map { _ in () },
                $searchText.map { _ in () },
                $selectedScene.map { _ in () },
                $selectedAgeBucket.map { _ in () }
            )
            .map { _ in () }
            .eraseToAnyPublisher()

        let publishers2: AnyPublisher<Void, Never> = Publishers
            .CombineLatest3(
                $ageLower.map { _ in () },
                $ageUpper.map { _ in () },
                $useAgeRange.map { _ in () }
            )
            .map { _ in () }
            .eraseToAnyPublisher()

        let favoritesPub: AnyPublisher<Void, Never> = $favoritesOnly.map { _ in () }.eraseToAnyPublisher()

        publishers.merge(with: publishers2, favoritesPub)
            .receive(on: RunLoop.main)
            .debounce(for: .milliseconds(120), scheduler: RunLoop.main)
            .sink { [weak self] in self?.recompute() }
            .store(in: &cancellables)
    }

    // MARK: - 数据注入

    /// 由视图在 onAppear / refreshVoices 时调用
    func setVoices(_ voices: [Voice]) {
        self.allVoices = voices
        // 数据源变化时立即重算一次（不走 debounce）
        recomputeNow()
    }

    // MARK: - 重置

    func clearFilters() {
        selectedCategory = nil
        selectedScene = nil
        selectedAgeBucket = .any
        useAgeRange = false
        ageLower = 0
        ageUpper = 99
        searchText = ""
        favoritesOnly = false
        // 立刻同步一次，不等 debounce
        recomputeNow()
    }

    // MARK: - 计算

    private func recomputeNow() {
        recompute()
    }

    private func recompute() {
        let voices = allVoices

        // 1) 按场景分桶 + 频次
        var sceneCounts: [String: Int] = [:]
        for v in voices {
            let s = v.scene.trimmingCharacters(in: .whitespaces)
            guard !s.isEmpty else { continue }
            sceneCounts[s, default: 0] += 1
        }
        availableScenes = sceneCounts.keys.sorted { lhs, rhs in
            let lc = sceneCounts[lhs] ?? 0
            let rc = sceneCounts[rhs] ?? 0
            if lc != rc { return lc > rc }
            return lhs < rhs
        }

        // 2) 年龄范围
        let ages = voices.compactMap { $0.age }
        if let lo = ages.min(), let hi = ages.max() {
            availableAgeRange = lo...hi
        } else {
            availableAgeRange = 0...99
        }

        // 3) 单次过滤
        let bucket = selectedAgeBucket
        let useRange = useAgeRange
        let lo = Int(min(ageLower, ageUpper))
        let hi = Int(max(ageLower, ageUpper))
        let scene = selectedScene
        let category = selectedCategory
        let needle = searchText
        let favOnly = favoritesOnly

        let filtered = voices.filter { v in
            if let category, v.category != category { return false }
            if let scene, v.scene != scene { return false }
            if favOnly && !v.isFavorite { return false }
            if !needle.isEmpty {
                if !v.name.localizedCaseInsensitiveContains(needle)
                    && !v.desc.localizedCaseInsensitiveContains(needle)
                    && !v.scene.localizedCaseInsensitiveContains(needle) {
                    return false
                }
            }
            // 年龄匹配
            if useRange {
                guard let age = v.age else { return false }
                return age >= lo && age <= hi
            } else {
                switch bucket {
                case .any: return true
                case .unknown:
                    return v.age == nil
                case .child:
                    if let a = v.age { return a < 13 } else { return false }
                case .teen:
                    if let a = v.age { return a >= 13 && a < 18 } else { return false }
                case .young:
                    if let a = v.age { return a >= 18 && a < 36 } else { return false }
                case .middle:
                    if let a = v.age { return a >= 36 && a < 60 } else { return false }
                case .senior:
                    if let a = v.age { return a >= 60 } else { return false }
                }
            }
        }

        filteredVoices = filtered
        isEmpty = filtered.isEmpty

        if let category {
            voicesForSelectedCategory = filtered
            // 仅构建所选分类的桶
            filteredVoicesByCategory = [category: filtered]
        } else {
            // 按分类分组（一次循环搞定，避免对每个 category 重复 filter）
            var grouped: [VoiceCategory: [Voice]] = [:]
            grouped.reserveCapacity(VoiceCategory.allCases.count)
            for v in filtered {
                grouped[v.category, default: []].append(v)
            }
            // 清理空桶
            for cat in VoiceCategory.allCases where grouped[cat] == nil {
                grouped[cat] = []
            }
            voicesForSelectedCategory = []
            filteredVoicesByCategory = grouped
        }
    }
}
