//
//  PackageCard.swift
//  iOSEmora
//
//  积分套餐卡片（先选后买，卡片本身只负责选中态）。
//  从 PurchaseSheet.swift 拆出：代码逐字搬移，未改动任何逻辑（原 private 类型按需放开为 internal）。
//

import SwiftUI

// MARK: - 套餐卡

/// 2 列网格里的一张套餐卡：点选 → 底部 CTA 购买。
///
/// 卡片本身只负责「选中」这一种状态，购买动作统一交给底部按钮 ——
/// 卡片里再塞一个购买按钮，等于每张卡都是热区，误触一次就真的扣款了。
struct PackageCard: View {
    @Environment(\.aurora) private var c

    let product: CreditProduct
    let isSelected: Bool
    let priceText: String
    let emoji: String
    let subtitle: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                ZStack {
                    Circle()
                        .fill(tint.opacity(0.18))
                        .frame(width: 34, height: 34)
                    Text(emoji)
                        .font(.system(size: 17))
                }
                Spacer(minLength: 0)
                if product.isRecommended {
                    Text("推荐".localized())
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(c.ctaForeground)
                        .padding(.horizontal, 7)
                        .frame(height: 18)
                        .background(Capsule(style: .continuous).fill(c.ctaGradient))
                }
            }
            .padding(.bottom, 10)

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(formatCredits(product.creditsAmount))
                    .font(.system(size: 25, weight: .bold, design: .monospaced))
                    .foregroundStyle(c.textPrimary)
                Text("积分".localized())
                    .font(.system(size: 12))
                    .foregroundStyle(c.textTertiary)
            }

            Text(subtitle)
                .font(.system(size: 12))
                .foregroundStyle(c.textSecondary)
                // ⚠️ 别写死 lineLimit(1)：英文译文最长 ≈179pt，而 2 列卡片在 320pt 屏
                //    的内容区只有 110pt，会被截成 "…"。允许 2 行完整显示，配下面的
                //    Spacer + maxHeight:.infinity 让同排卡片等高、价格行仍贴底对齐。
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 3)

            Spacer(minLength: 0)

            Text(priceText)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(c.accent)
                .padding(.top, 8)
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: AuroraRadius.lg, style: .continuous)
                .fill(isSelected ? c.accentSoft : c.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: AuroraRadius.lg, style: .continuous)
                        .strokeBorder(isSelected ? c.accent : c.line,
                                      lineWidth: isSelected ? 2 : 0.5)
                )
        )
        .overlay(alignment: .topTrailing) {
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(c.accent)
                    .background(Circle().fill(c.surface).padding(2))
                    .offset(x: 6, y: -6)
            }
        }
        .contentShape(Rectangle())
        .animation(.easeOut(duration: 0.16), value: isSelected)
    }
}
