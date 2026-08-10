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
    let usageCount: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack {
                VStack(spacing: 2) {
                    Text(emotion.emoji)
                        .font(.system(size: 18))
                    Text(emotion.label)
                        .font(.system(size: 10))
                        .foregroundStyle(AppColor.textSecondary)
                }
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity)

                // 使用次数显示
                if usageCount > 0 {
                    Text("\(usageCount)")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(AppColor.accentPrimary)
                        .clipShape(Capsule())
                        .offset(x: 12, y: -12)
                }
            }
            .background(AppColor.bgTertiary)
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.small)
                    .stroke(AppColor.borderSubtle, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.small))
            .contentShape(RoundedRectangle(cornerRadius: AppRadius.small))
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
    }
}
