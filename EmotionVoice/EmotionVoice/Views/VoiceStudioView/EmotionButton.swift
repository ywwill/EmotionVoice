//
//  EmotionButton.swift
//  EmotionVoice
//
//  Created by young on 2026/8/8.
//

import SwiftUI

// MARK: - 情感按钮

struct EmotionButton: View {
    let emotion: EmotionItem
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(emotion.emoji)
                    .font(.system(size: 18))
                Text(emotion.label)
                    .font(.system(size: 10))
                    .foregroundStyle(AppColor.textSecondary)
            }
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(AppColor.bgTertiary)
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.small)
                    .stroke(AppColor.borderSubtle, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.small))
            .contentShape(RoundedRectangle(cornerRadius: AppRadius.small))
        }
        .buttonStyle(.plain)
        .help(emotion.description)
        .pointingHandCursor()
    }
}