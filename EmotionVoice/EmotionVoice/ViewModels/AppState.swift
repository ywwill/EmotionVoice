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

    /// UserDefaults 键：上次使用的音色 key
    private static let selectedVoiceKeyUDKey = "selectedVoiceKey"

    /// 当前选中的侧边栏项
    @Published var selectedSection: SidebarSection = .voiceStudio

    /// 积分余额（联动 CreditsService，最多 2 位小数）
    @Published var creditsBalance: Double

    /// 本月已用积分（最多 2 位小数）
    @Published var monthlyUsed: Double

    /// 所有音色（首页加载时拉取）
    @Published var voices: [Voice] = []

    /// 当前选中的音色（在 voice studio 中切换）
    @Published var selectedVoice: Voice? {
        didSet {
            if let voice = selectedVoice {
                UserDefaults.standard.set(voice.key, forKey: Self.selectedVoiceKeyUDKey)
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

    /// 导出目录（用户选择的文件保存位置）
    @Published var exportDirectory: URL? {
        didSet {
            if let url = exportDirectory {
                UserDefaults.standard.set(url.path, forKey: "exportDirectory")
            } else {
                UserDefaults.standard.removeObject(forKey: "exportDirectory")
            }
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

    /// Combine 订阅管理
    private var cancellables = Set<AnyCancellable>()

    init() {
        self.creditsBalance = CreditsService.shared.balance
        self.monthlyUsed = CreditsService.shared.monthlyUsed
        // 旗舰音色的默认收藏由 DatabaseManager 在音色同步时统一处理
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

        // 加载保存的导出目录
        if let savedPath = UserDefaults.standard.string(forKey: "exportDirectory") {
            self.exportDirectory = URL(fileURLWithPath: savedPath)
        } else {
            self.exportDirectory = nil
        }

        // 恢复上次选中的音色，如果没有则使用默认音色
        self.selectedVoice = nil
        resolveSelectedVoice()

        // 从云端同步积分（应用启动时调用）
        syncCreditsFromCloud()

        // 监听 CreditManager 的 balance 变化
        CreditManager.shared.$balance
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newBalance in
                self?.creditsBalance = newBalance
            }
            .store(in: &cancellables)
    }

    /// 从云端同步积分
    private func syncCreditsFromCloud() {
        Task {
            // 先更新本地余额
            self.creditsBalance = CreditManager.shared.balance
            // 再从云端同步
            CreditManager.shared.syncFromCloud()
        }
    }

    /// 刷新积分数据
    func refreshCredits() {
        creditsBalance = CreditManager.shared.balance
        monthlyUsed = CreditsService.shared.monthlyUsed
    }

    /// 刷新音色数据
    func refreshVoices() {
        voices = VoiceService.shared.fetchAll()
        resolveSelectedVoice()
    }

    // MARK: - 选中音色解析

    /// 默认音色 key：旗舰音色（idx 1，Constants.defaultVoice）。
    /// 该音色不存在时退化为任一旗舰音色，最后退化为首个可用音色。
    var defaultVoiceKey: String {
        if voices.contains(where: { $0.key == Constants.defaultVoice }) {
            return Constants.defaultVoice
        }
        return voices.first(where: { $0.isPremium })?.key
            ?? voices.first?.key
            ?? Constants.defaultVoice
    }

    /// 默认音色（旗舰音色 idx 1）
    var defaultVoice: Voice? {
        voices.first(where: { $0.key == defaultVoiceKey })
    }

    /// 上次使用的音色（UserDefaults 持久化）
    private var lastUsedVoice: Voice? {
        guard let key = UserDefaults.standard.string(forKey: Self.selectedVoiceKeyUDKey) else { return nil }
        return voices.first(where: { $0.key == key })
    }

    /// 确保当前有一个可用音色：
    /// 1. 已选中的音色仍然有效 → 保持不变
    /// 2. 否则取「上次使用的音色」
    /// 3. 再没有 → 回落到旗舰默认音色（idx 1）
    func resolveSelectedVoice() {
        if let current = selectedVoice,
           voices.contains(where: { $0.key == current.key }) {
            return
        }
        selectedVoice = lastUsedVoice ?? defaultVoice
    }
}

/// 侧边栏导航项
enum SidebarSection: Hashable, Identifiable {
    case home
    case voiceStudio
    case voices
    case projects
    case credits
    case settings

    var id: Self { self }

    var title: String {
        switch self {
        case .home:        return "首页".localized()
        case .voiceStudio: return "语音合成".localized()
        case .voices:      return "音色库".localized()
        case .projects:    return "我的项目".localized()
        case .credits:     return "积分中心".localized()
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
        case .settings:    return "gearshape.fill"
        }
    }
}
