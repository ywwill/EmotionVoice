//
//  StatItem.swift
//  EmotionVoice
//
//  Created: young on 2026/8/8.
//

import SwiftUI

// MARK: - 统计项

struct StatItem: View {

    let value: String
    var unit: String? = nil
    let label: String

    var body: some View {
        VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 24, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppColor.textPrimary)
                if let unit {
                    Text(unit)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppColor.accentPrimary)
                }
            }
            Text(label)
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }
}
