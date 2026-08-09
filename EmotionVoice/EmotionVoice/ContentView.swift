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
        .frame(minWidth: 1200, minHeight: 900)
    }

    @ViewBuilder
    private var mainContent: some View {
        Group {
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
        .id(appState.selectedSection)
        .transition(.asymmetric(
            insertion: .opacity.combined(with: .move(edge: .trailing)),
            removal:   .opacity.combined(with: .move(edge: .leading))
        ))
    }
}
