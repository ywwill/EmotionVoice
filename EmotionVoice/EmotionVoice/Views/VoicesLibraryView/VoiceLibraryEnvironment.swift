//
//  VoiceLibraryEnvironment.swift
//  EmotionVoice
//
//  Created by young on 2026/8/8.
//

import SwiftUI

// MARK: - VoiceLibraryUseHandler / VoiceLibraryDismissKey / DismissActionWrapper Environment

/// 用于在 sheet 上下文（如 VoiceStudioView 中弹出的 VoicesLibraryView）中
/// 重定向 "使用" 按钮的回调。注入 handler 时，点击 "使用" 仅触发 handler，
/// 未注入时保留原有跳转 `.voiceStudio` 的默认行为。
struct VoiceLibraryUseHandler {
    let handler: (Voice) -> Void
}

struct VoiceLibraryUseHandlerKey: EnvironmentKey {
    static let defaultValue: VoiceLibraryUseHandler? = nil
}

extension EnvironmentValues {
    var voiceLibraryUseHandler: VoiceLibraryUseHandler? {
        get { self[VoiceLibraryUseHandlerKey.self] }
        set { self[VoiceLibraryUseHandlerKey.self] = newValue }
    }
}

/// 包装 SwiftUI DismissAction，使其可以通过 EnvironmentValues 传递
struct DismissActionWrapper {
    let action: DismissAction
    init(_ action: DismissAction) {
        self.action = action
    }
    func callAsFunction() {
        action()
    }
}

struct VoiceLibraryDismissKey: EnvironmentKey {
    static let defaultValue: DismissActionWrapper? = nil
}

extension EnvironmentValues {
    var voiceLibraryDismiss: DismissActionWrapper? {
        get { self[VoiceLibraryDismissKey.self] }
        set { self[VoiceLibraryDismissKey.self] = newValue }
    }
}
