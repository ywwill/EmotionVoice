//
//  ProgressBar.swift
//  EmotionVoice
//
//  Created: young on 2026/8/8.
//

import SwiftUI

// MARK: - 进度条

struct ProgressBar: View {

    let progress: Double

    var body: some View {
        HStack(spacing: 8) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(AppColor.bgElevated)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(
                            LinearGradient(
                                colors: [AppColor.accentPrimary, AppColor.accentGlow],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * progress)
                }
            }
            .frame(height: 3)

            Text(progress >= 0.99 ? "已完成".localized() : "\(Int(progress * 100))%")
                .font(AppFont.monoSmall)
                .foregroundStyle(progress >= 0.99 ? AppColor.statusSuccess : AppColor.textSecondary)
                .frame(width: 50, alignment: .trailing)
        }
    }
}
