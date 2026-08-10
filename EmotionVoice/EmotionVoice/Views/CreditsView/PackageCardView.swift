//
//  PackageCardView.swift
//  EmotionVoice
//
//  Created: young on 2026/8/8.
//

import SwiftUI

// MARK: - 套餐卡

struct PackageCardView: View {

    let package: CreditsPackage
    let onPurchase: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if package.isRecommended {
                Text("⭐ 推荐".localized())
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(AppColor.bgPrimary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(AppColor.accentPrimary)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .offset(y: -8)
            }

            Text(package.icon)
                .font(.system(size: 28))

            Text(package.name)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppColor.textTertiary)

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text("¥")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(AppColor.textSecondary)
                Text(String(format: "%.1f", package.price))
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(AppColor.textPrimary)
            }

            Text("\(package.points) 积分".localized())
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(AppColor.accentGlow)

            let unitPriceText = String(format: "%.3f", package.unitPrice)
            Text("≈ ¥\(unitPriceText) / 积分".localized())
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textTertiary)
                .padding(.bottom, 12)
                .overlay(alignment: .bottom) {
                    Divider().background(AppColor.borderSubtle)
                }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(package.features, id: \.self) { f in
                    HStack(spacing: 6) {
                        Text("✓")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(AppColor.statusSuccess)
                        Text(f)
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.textSecondary)
                    }
                }
            }

            Button(action: onPurchase) {
                Text("购买".localized())
                    .font(.system(size: 12, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(recommendedButtonBackground(isRecommended: package.isRecommended))
                    .foregroundStyle(
                        package.isRecommended ? AppColor.bgPrimary : AppColor.textPrimary
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: AppRadius.small)
                            .stroke(AppColor.borderSubtle, lineWidth: package.isRecommended ? 0 : 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.small))
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(recommendedCardBackground(isRecommended: package.isRecommended))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.large)
                .stroke(
                    package.isRecommended ? AppColor.accentPrimary : AppColor.borderSubtle,
                    lineWidth: package.isRecommended ? 1.5 : 1
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.large))
    }

    private func recommendedButtonBackground(isRecommended: Bool) -> AnyShapeStyle {
        if isRecommended {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [AppColor.accentPrimary, AppColor.accentSecondary],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            )
        } else {
            return AnyShapeStyle(AppColor.bgTertiary)
        }
    }

    private func recommendedCardBackground(isRecommended: Bool) -> AnyShapeStyle {
        if isRecommended {
            return AnyShapeStyle(
                LinearGradient(
                    colors: [AppColor.bgSecondary, AppColor.accentPrimary.opacity(0.05)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                )
            )
        } else {
            return AnyShapeStyle(AppColor.bgSecondary)
        }
    }
}
