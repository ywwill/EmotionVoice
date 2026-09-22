//
//  SummaryCard.swift
//  EmotionVoice
//
//  Created: young on 2026/8/8.
//

import SwiftUI

// MARK: - 概览卡

struct SummaryCard: View {
    let label: String
    let value: String
    let trend: String
    let trendUp: Bool
    var accent: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textTertiary)
            Text(value)
                .font(.system(size: 24, weight: .bold, design: .monospaced))
                .foregroundStyle(accent ? AppColor.accentPrimary : AppColor.textPrimary)
            HStack(spacing: 4) {
                Text(trendUp ? "↑" : "·")
                    .foregroundStyle(trendUp ? AppColor.statusSuccess : AppColor.textTertiary)
                Text(trend)
                    .font(AppFont.monoSmall)
                    .foregroundStyle(trendUp ? AppColor.statusSuccess : AppColor.textTertiary)
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColor.bgSecondary)
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.large)
                .stroke(AppColor.borderSubtle, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.large))
    }
}
