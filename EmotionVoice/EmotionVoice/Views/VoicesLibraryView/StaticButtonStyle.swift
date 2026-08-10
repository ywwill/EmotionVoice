//
//  StaticButtonStyle.swift
//  EmotionVoice
//
//  Created by young on 2026/8/8.
//

import SwiftUI

// MARK: - StaticButtonStyle（按压时大小/外观不发生变化）

struct StaticButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.7 : 1.0)
    }
}
