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
    @Published var selectedSection: SidebarSection = .home

    /// 积分余额（联动 CreditsService）
    @Published var creditsBalance: Int

    /// 本月已用积分
    @Published var monthlyUsed: Int

    /// 所有音色（首页加载时拉取）
    @Published var voices: [Voice] = []

    /// 当前选中的音色（在 voice studio 中切换）
    @Published var selectedVoice: Voice?

    /// 触发动画效果（生成完成/开始时）
    @Published var isGenerating: Bool = false

    init() {
        self.creditsBalance = CreditsService.shared.balance
        self.monthlyUsed = CreditsService.shared.monthlyUsed
        self.voices = VoiceService.shared.fetchAll()
        if self.selectedVoice == nil {
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
        if let selected = selectedVoice,
           let updated = voices.first(where: { $0.key == selected.key }) {
            selectedVoice = updated
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
        case .projects:    return "所有项目".localized()
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
