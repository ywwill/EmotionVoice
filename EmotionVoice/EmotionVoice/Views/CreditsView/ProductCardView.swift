//
//  ProductCardView.swift
//  EmotionVoice
//
//  内购产品卡视图
//

import SwiftUI
import StoreKit

// MARK: - 内购产品卡

struct ProductCardView: View {
    let product: Product?
    let creditProduct: CreditProduct?
    let onPurchase: () -> Void

    @State private var isHovered = false

    private var isRecommended: Bool {
        creditProduct?.isRecommended ?? false
    }

    private var icon: String {
        creditProduct?.icon ?? "💎"
    }

    private var name: String {
        creditProduct?.name ?? "套餐"
    }

    private var points: Int {
        creditProduct?.creditsAmount ?? 0
    }

    private var displayPrice: String {
        product?.displayPrice ?? "¥--"
    }

    private var unitPriceText: String {
        guard let product = product, let creditProduct = creditProduct else {
            return "--"
        }
        let unitPrice = product.price / Decimal(creditProduct.creditsAmount)
        let doubleValue = NSDecimalNumber(decimal: unitPrice).doubleValue
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = product.priceFormatStyle.currencyCode
        formatter.maximumFractionDigits = 4
        formatter.minimumFractionDigits = 2
        return formatter.string(from: NSNumber(value: doubleValue)) ?? String(format: "%.4f", doubleValue)
    }

    private var isLoading: Bool {
        product == nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 图标
            HStack {
                Text(icon)
                    .font(.system(size: 28))
                Spacer()
                if isRecommended {
                    Text("⭐ 推荐".localized())
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(AppColor.bgPrimary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(AppColor.accentPrimary)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                        .padding(.top, 4)
                        .padding(.trailing, 4)
                }
            }

            // 名称
            Text(name)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppColor.textTertiary)

            // 价格
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text("¥")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(AppColor.textSecondary)
                Text(displayPrice.replacingOccurrences(of: "¥", with: ""))
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(AppColor.textPrimary)
            }

            // 积分
            Text("\(points) 积分".localized())
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(AppColor.accentGlow)

            // 单位价格
            Text("≈ \(unitPriceText) / 积分".localized())
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textTertiary)

            Divider()
                .background(AppColor.borderSubtle)

            Spacer()

            // 特性列表
            VStack(alignment: .leading, spacing: 6) {
                ForEach(features, id: \.self) { f in
                    Text("✓ \(f)".localized())
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                }
            }

            // 购买按钮
            Button(action: onPurchase) {
                HStack(spacing: 6) {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: packageTextColor))
                            .scaleEffect(0.8)
                    } else {
                        Text("购买".localized())
                            .font(.system(size: 12, weight: .semibold))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(recommendedButtonBackground)
                .foregroundStyle(packageTextColor)
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.small))
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
            .disabled(isLoading)
        }
        .padding(20)
        .frame(minWidth: 160, minHeight: 360)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(cardBackground)
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.large)
                .stroke(
                    isRecommended ? AppColor.accentPrimary : (isHovered ? AppColor.accentPrimary : AppColor.borderSubtle),
                    lineWidth: isRecommended ? 1 : (isHovered ? 1 : 1)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.large))
        .offset(y: isHovered ? -2 : 0)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
    }

    private var features: [String] {
        switch creditProduct {
        case .credits6:
            return ["适合尝鲜体验", "积分永久有效"]
        case .credits30:
            return ["个人创作首选", "积分永久有效"]
        case .credits60:
            return ["个人创作首选", "积分永久有效"]
        case .credits98:
            return ["高频使用推荐", "积分永久有效", "优先客服支持"]
        case .none:
            return ["积分永久有效"]
        }
    }


    private var cardBackground: Color {
        if isRecommended {
            return Color(
                red: 0.08 + (0.02 * (232.0 / 255.0)),
                green: 0.09 + (0.02 * (169.0 / 255.0)),
                blue: 0.11 + (0.02 * (104.0 / 255.0))
            )
        }
        return AppColor.bgSecondary
    }

    private var recommendedButtonBackground: Color {
        if isRecommended {
            return Color(
                red: 232.0 / 255.0,
                green: 169.0 / 255.0,
                blue: 104.0 / 255.0
            )
        }
        return AppColor.bgTertiary
    }

    private var packageTextColor: Color {
        isRecommended ? AppColor.bgPrimary : AppColor.textPrimary
    }
}

// MARK: - 骨架产品卡

struct SkeletonProductCard: View {
    @State private var isAnimating = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 图标占位
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(skeletonColor)
                    .frame(width: 28, height: 28)
            }
            .frame(height: 32, alignment: .topLeading)

            // 名称占位
            RoundedRectangle(cornerRadius: 4)
                .fill(skeletonColor)
                .frame(width: 60, height: 13)

            // 价格占位
            RoundedRectangle(cornerRadius: 4)
                .fill(skeletonColor)
                .frame(width: 80, height: 28)

            // 积分占位
            RoundedRectangle(cornerRadius: 4)
                .fill(skeletonColor)
                .frame(width: 100, height: 18)

            // 单位价格占位
            RoundedRectangle(cornerRadius: 4)
                .fill(skeletonColor)
                .frame(width: 120, height: 12)

            Spacer()

            // 特性占位
            VStack(alignment: .leading, spacing: 6) {
                ForEach(0..<2, id: \.self) { _ in
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(skeletonColor)
                            .frame(width: 12, height: 12)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(skeletonColor)
                            .frame(width: 80, height: 12)
                    }
                }
            }

            // 按钮占位
            RoundedRectangle(cornerRadius: AppRadius.small)
                .fill(skeletonColor)
                .frame(height: 32)
        }
        .padding(20)
        .frame(minWidth: 160, minHeight: 340)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColor.bgSecondary)
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.large)
                .stroke(AppColor.borderSubtle, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.large))
        .onAppear {
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
        }
    }

    private var skeletonColor: Color {
        isAnimating ? AppColor.bgTertiary.opacity(0.5) : AppColor.bgTertiary
    }
}

// MARK: - CreditProduct 扩展

extension CreditProduct {
    var icon: String {
        switch self {
        case .credits6: return "🌱"
        case .credits30: return "⭐"
        case .credits60: return "🔥"
        case .credits98: return "💎"
        }
    }

    var name: String {
        switch self {
        case .credits6: return "体验包".localized()
        case .credits30: return "基础包".localized()
        case .credits60: return "进阶包".localized()
        case .credits98: return "专业包".localized()
        }
    }
}
