//
//  VoiceLibrarySheet.swift
//  EmotionVoice
//
//  Created by young on 2026/8/8.
//

import SwiftUI

// MARK: - 音色库 sheet（在 VoiceStudioView 中弹出）

/// 在 VoiceStudioView 中以 sheet 弹出 VoicesLibraryView。
/// 点击卡片上的"使用"按钮：仅选中音色并关闭 sheet，不跳页面。
struct VoiceLibrarySheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var appState: AppState

    var body: some View {
        VoicesLibraryView()
            .environment(\.voiceLibraryUseHandler, VoiceLibraryUseHandler { voice in
                appState.selectedVoice = voice
                dismiss()
            })
            .environment(\.voiceLibraryDismiss, DismissActionWrapper(dismiss))
    }
}
