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
        .frame(minWidth: 1024, minHeight: 700)
    }

    @ViewBuilder
    private var mainContent: some View {
        switch appState.selectedSection {
        case .home:        HomeView()
        case .voiceStudio: VoiceStudioView()
        case .voices:      VoicesLibraryView()
        case .projects:    ProjectsView()
        case .credits:     CreditsView()
        case .stats:       StatsView()
        case .settings:    SettingsView()
        }
    }
}