//
//  AppState.swift
//  EmotionVoice
//
//  Created by young on 2026/8/8.
//

import Foundation
import SwiftUI
import Combine

/// 全局应用状态
@MainActor
final class AppState: ObservableObject {

    /// 当前选中的侧边栏项
    @Published var selectedSection: SidebarSection = .voiceStudio

    /// 积分余额（联动 CreditsService）
    @Published var creditsBalance: Int

    /// 本月已用积分
    @Published var monthlyUsed: Int

    /// 所有音色（首页加载时拉取）
    @Published var voices: [Voice] = []

    /// 当前选中的音色（在 voice studio 中切换）
    @Published var selectedVoice: Voice? {
        didSet {
            if let voice = selectedVoice {
                UserDefaults.standard.set(voice.key, forKey: "selectedVoiceKey")
            }
        }
    }

    /// 触发动画效果（生成完成/开始时）
    @Published var isGenerating: Bool = false

    /// 默认音频格式（用于导出和生成）
    @Published var defaultFormat: String {
        didSet {
            UserDefaults.standard.set(defaultFormat, forKey: "defaultFormat")
        }
    }

    /// 默认采样率（Hz）
    @Published var defaultSampleRate: Int {
        didSet {
            UserDefaults.standard.set(defaultSampleRate, forKey: "defaultSampleRate")
        }
    }

    // MARK: - 音色库筛选状态（跨视图持久化）

    /// 音色库当前选中的分类（nil 表示"全部"）
    @Published var voiceLibrarySelectedCategory: VoiceCategory? = nil {
        didSet { UserDefaults.standard.set(voiceLibrarySelectedCategory?.rawValue, forKey: "voiceLibrarySelectedCategory") }
    }

    /// 音色库搜索文本
    @Published var voiceLibrarySearchText: String = "" {
        didSet { UserDefaults.standard.set(voiceLibrarySearchText, forKey: "voiceLibrarySearchText") }
    }

    /// 音色库是否仅显示收藏
    @Published var voiceLibraryShowFavoritesOnly: Bool = false {
        didSet { UserDefaults.standard.set(voiceLibraryShowFavoritesOnly, forKey: "voiceLibraryShowFavoritesOnly") }
    }

    /// 音色库当前页码
    @Published var voiceLibraryCurrentPage: Int = 1 {
        didSet { UserDefaults.standard.set(voiceLibraryCurrentPage, forKey: "voiceLibraryCurrentPage") }
    }

    init() {
        self.creditsBalance = CreditsService.shared.balance
        self.monthlyUsed = CreditsService.shared.monthlyUsed
        self.voices = VoiceService.shared.fetchAll()

        // 加载保存的设置，没有则使用默认值
        let savedFormat = UserDefaults.standard.string(forKey: "defaultFormat") ?? Constants.defaultFormat.uppercased()
        let savedSampleRate = UserDefaults.standard.integer(forKey: "defaultSampleRate")
        self.defaultFormat = savedFormat.isEmpty ? Constants.defaultFormat.uppercased() : savedFormat.uppercased()
        self.defaultSampleRate = savedSampleRate > 0 ? savedSampleRate : Constants.defaultSampleRate

        // 加载音色库筛选状态
        if let categoryRaw = UserDefaults.standard.string(forKey: "voiceLibrarySelectedCategory") {
            self.voiceLibrarySelectedCategory = VoiceCategory(rawValue: categoryRaw)
        }
        self.voiceLibrarySearchText = UserDefaults.standard.string(forKey: "voiceLibrarySearchText") ?? ""
        self.voiceLibraryShowFavoritesOnly = UserDefaults.standard.bool(forKey: "voiceLibraryShowFavoritesOnly")
        let savedPage = UserDefaults.standard.integer(forKey: "voiceLibraryCurrentPage")
        self.voiceLibraryCurrentPage = savedPage > 0 ? savedPage : 1

        // 恢复上次选中的音色，如果没有则使用默认音色
        if let savedVoiceKey = UserDefaults.standard.string(forKey: "selectedVoiceKey"),
           let savedVoice = voices.first(where: { $0.key == savedVoiceKey }) {
            self.selectedVoice = savedVoice
        } else {
            self.selectedVoice = voices.first(where: { $0.key == Constants.defaultVoice }) ?? voices.first
        }
    }

    /// 刷新积分数据
    func refreshCredits() {
        creditsBalance = CreditsService.shared.balance
        monthlyUsed = CreditsService.shared.monthlyUsed
    }

    /// 刷新音色数据
    func refreshVoices() {
        voices = VoiceService.shared.fetchAll()
        // 尝试从新的音色列表中找到之前选中的音色（可能因数据更新而变化）
        if let selected = selectedVoice,
           let updated = voices.first(where: { $0.key == selected.key }) {
            selectedVoice = updated
        } else if selectedVoice == nil {
            // 如果没有选中音色，使用默认音色
            selectedVoice = voices.first(where: { $0.key == Constants.defaultVoice }) ?? voices.first
        }
    }
}

/// 侧边栏导航项
enum SidebarSection: Hashable, Identifiable {
    case home
    case voiceStudio
    case voices
    case projects
    case credits
    case stats
    case settings

    var id: Self { self }

    var title: String {
        switch self {
        case .home:        return "首页".localized()
        case .voiceStudio: return "语音合成".localized()
        case .voices:      return "音色库".localized()
        case .projects:    return "历史记录".localized()
        case .credits:     return "积分中心".localized()
        case .stats:       return "使用统计".localized()
        case .settings:    return "设置".localized()
        }
    }

    var icon: String {
        switch self {
        case .home:        return "house.fill"
        case .voiceStudio: return "waveform"
        case .voices:      return "person.wave.2.fill"
        case .projects:    return "folder.fill"
        case .credits:     return "diamond.fill"
        case .stats:       return "chart.bar.fill"
        case .settings:    return "gearshape.fill"
        }
    }
}
