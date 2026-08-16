//
//  ContentView.swift
//  EmotionVoice
//
//  Created by young on 2026/8/8.
//

import SwiftUI

struct ContentView: View {

    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(spacing: 0) {
            Sidebar()
            Divider()
                .background(AppColor.borderSubtle)
            mainContent
        }
        .background(AppColor.bgPrimary)
        .frame(minWidth: 1500, minHeight: 900)
    }

    @ViewBuilder
    private var mainContent: some View {
        Group {
            switch appState.selectedSection {
            case .home:
                // 已移除侧边栏入口；保留以保证 switch 穷尽。
                // 程序不会进入此分支（默认 section = .voiceStudio，且无 UI 可触发）。
                VoiceStudioView()
            case .voiceStudio: VoiceStudioView()
            case .voices:      VoicesLibraryView()
            case .projects:    ProjectsView()
            case .credits:     CreditsView()
            case .stats:       StatsView()
            case .settings:    SettingsView()
            }
        }
        .id(appState.selectedSection)
        .transition(.opacity.animation(.easeInOut(duration: 0.1)))
    }
}
