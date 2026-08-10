//
//  QuickActionCard.swift
//  EmotionVoice
//
//  Created: young on 2026/8/8.
//

import SwiftUI

// MARK: - 快速操作卡

struct QuickActionCard: View {

    let icon: String
    let title: String
    let desc: String
    let cta: String
    let gradient: [Color]
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: AppRadius.small)
                        .fill(
                            LinearGradient(
                                colors: gradient,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Text(icon)
                        .font(.system(size: 16))
                }
                .frame(width: 36, height: 36)

                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppColor.textPrimary)

                Text(desc)
                    .font(AppFont.bodySmall)
                    .foregroundStyle(AppColor.textSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Text(cta + " →")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppColor.accentPrimary)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColor.bgSecondary)
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.medium)
                    .stroke(AppColor.borderSubtle, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium))
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
    }
}
