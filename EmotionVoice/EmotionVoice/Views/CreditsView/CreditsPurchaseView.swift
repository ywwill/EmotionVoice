//
//  CreditsPurchaseView.swift
//  EmotionVoice
//
//  简洁的积分购买界面 - 用于积分不足时弹出
//  Design: Dark-tech Premium, VARIANCE: 7, MOTION: 6, DENSITY: 3
//

import SwiftUI
import StoreKit

/// 积分购买界面（简洁版）
struct CreditsPurchaseView: View {

    @EnvironmentObject var appState: AppState
    @StateObject private var storeManager = StoreKitManager.shared
    @Environment(\.dismiss) private var dismiss
    
    @State private var appearAnimation = false

    var body: some View {
        VStack(spacing: 0) {
            // 头部 - 简洁设计
            headerSection
            
            Divider().background(AppColor.borderSubtle)

            ScrollView {
                VStack(spacing: 20) {
                    // 当前余额提示
                    insufficientCreditsBanner
                    
                    // 套餐选择
                    packagesSection
                }
                .padding(15)
            }
        }
        .background(AppColor.bgPrimary)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.xlarge))
        .shadow(color: .black.opacity(0.3), radius: 40, x: 0, y: 20)
        .scaleEffect(appearAnimation ? 1 : 0.95)
        .opacity(appearAnimation ? 1 : 0)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                appearAnimation = true
            }
            Task {
                await storeManager.loadProducts()
            }
        }
        .onChange(of: storeManager.purchaseState) { _, newState in
            if case .success = newState {
                withAnimation(.easeOut(duration: 0.2)) {
                    dismiss()
                }
            }
        }
    }

    // MARK: - 头部

    private var headerSection: some View {
        HStack {
            Button {
                withAnimation(.easeOut(duration: 0.15)) {
                    dismiss()
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppColor.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(AppColor.bgSecondary)
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            Spacer()

            Text("购买积分")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppColor.textPrimary)

            Spacer()

            Color.clear.frame(width: 28, height: 28)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: - 积分不足提示

    private var insufficientCreditsBanner: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                // 警告图标 - 更大更突出
                ZStack {
                    Circle()
                        .fill(Color.orange.opacity(0.15))
                        .frame(width: 44, height: 44)
                    
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.orange)
                }
                
                VStack(alignment: .leading, spacing: 6) {
                    Text("积分不足")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(AppColor.textPrimary)
                    
                    HStack(spacing: 8) {
                        Text("当前余额")
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.textSecondary)
                        
                        Text("\(appState.creditsBalance)")
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundStyle(Color.orange)
                        
                        Text("积分")
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.textSecondary)
                    }
                }
                
                Spacer()
            }
            .padding(20)
        }
        .background(
            RoundedRectangle(cornerRadius: AppRadius.large)
                .fill(AppColor.bgSecondary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.large)
                .stroke(Color.orange.opacity(0.2), lineWidth: 1)
        )
    }

    // MARK: - 套餐选择

    private var packagesSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 简洁标题
            Text("选择套餐")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppColor.textTertiary)
                .textCase(.uppercase)
                .tracking(0.1)

            if storeManager.isLoading {
                skeletonProductCards
            } else if storeManager.products.isEmpty {
                emptyProductsView
            } else {
                productCards
            }
        }
    }

    private var productCards: some View {
        VStack(spacing: 10) {
            ForEach(Array(storeManager.products.enumerated()), id: \.element.id) { index, product in
                PurchaseProductRow(
                    product: product,
                    creditProduct: CreditProduct(rawValue: product.id),
                    isHighlighted: CreditProduct(rawValue: product.id)?.isRecommended == true,
                    isPurchasing: storeManager.purchasingProductId == product.id
                ) {
                    Task {
                        await storeManager.purchase(product)
                    }
                }
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .move(edge: .bottom)),
                    removal: .opacity
                ))
            }
        }
    }

    private var skeletonProductCards: some View {
        VStack(spacing: 10) {
            ForEach(0..<4, id: \.self) { _ in
                SkeletonProductRow()
            }
        }
    }

    private var emptyProductsView: some View {
        VStack(spacing: 10) {
            ForEach(CreditProduct.allCases, id: \.rawValue) { creditProduct in
                PurchaseProductRow(
                    product: nil,
                    creditProduct: creditProduct,
                    isHighlighted: creditProduct.isRecommended,
                    isPurchasing: false
                ) {
                    Task {
                        await storeManager.loadProducts()
                    }
                }
            }
        }
    }
}

// MARK: - 购买套餐行

struct PurchaseProductRow: View {
    let product: Product?
    let creditProduct: CreditProduct?
    let isHighlighted: Bool
    let isPurchasing: Bool
    let onPurchase: () -> Void
    
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 16) {
            // 积分图标 - 纯色背景
            ZStack {
                Circle()
                    .fill(iconColor)
                    .frame(width: 44, height: 44)

                Text(emoji)
                    .font(.system(size: 18))
            }

            // 信息
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    if isHighlighted {
                        Text("推荐")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(AppColor.accentPrimary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(AppColor.accentPrimary.opacity(0.15))
                            .clipShape(Capsule())
                    }
                }

                HStack(spacing: 6) {
                    Text("\(creditProduct?.creditsAmount ?? 0) 积分")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AppColor.accentGlow)
                    
                    Text("·")
                        .foregroundStyle(AppColor.textTertiary)
                    
                    Text(productDescription)
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                }
                
                // 价格放在这里
                Text(product?.displayPrice ?? "...")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(AppColor.textPrimary)
                    .padding(.top, 2)
            }

            Spacer()

            // 购买按钮
            Button {
                onPurchase()
            } label: {
                Group {
                    if isPurchasing {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(0.7)
                    } else {
                        Text("购买")
                            .font(.system(size: 12, weight: .semibold))
                    }
                }
                .frame(width: 72)
                .padding(.vertical, 8)
                .background(isHighlighted ? AppColor.accentPrimary : AppColor.bgTertiary)
                .foregroundStyle(isHighlighted ? .white : AppColor.textPrimary)
                .clipShape(Capsule())
            }
            .buttonStyle(PurchaseButtonStyle())
            .disabled(product == nil || isPurchasing)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.large)
                .fill(isHighlighted ? AppColor.accentPrimary.opacity(0.08) : AppColor.bgSecondary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.large)
                .stroke(
                    isHighlighted ? AppColor.accentPrimary.opacity(0.3) : AppColor.borderSubtle,
                    lineWidth: isHovered ? (isHighlighted ? 1.5 : 1) : 1
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.large))
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var productName: String {
        if let product = product {
            return product.displayName
        }
        return creditProduct?.name ?? "加载中..."
    }

    private var productDescription: String {
        switch creditProduct {
        case .credits6: return "适合尝鲜".localized()
        case .credits30: return "个人创作首选".localized()
        case .credits60: return "进阶用户".localized()
        case .credits98: return "高频使用".localized()
        case .none: return ""
        }
    }

    private var emoji: String {
        creditProduct?.icon ?? "💎"
    }

    private var iconColor: Color {
        switch creditProduct {
        case .credits6: return .orange
        case .credits30: return .purple
        case .credits60: return .red
        case .credits98: return AppColor.accentPrimary
        case .none: return AppColor.accentPrimary
        }
    }

    private var gradientColors: [Color] {
        switch creditProduct {
        case .credits6: return [Color.orange.opacity(0.9), Color.yellow.opacity(0.8)]
        case .credits30: return [Color.purple.opacity(0.9), Color.pink.opacity(0.8)]
        case .credits60: return [Color.red.opacity(0.9), Color.orange.opacity(0.8)]
        case .credits98: return [AppColor.accentPrimary, AppColor.accentGlow]
        case .none: return [AppColor.accentPrimary, AppColor.accentGlow]
        }
    }
}

// MARK: - 购买按钮样式

struct PurchaseButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - 骨架屏

struct SkeletonProductRow: View {
    @State private var isAnimating = false

    var body: some View {
        HStack(spacing: 16) {
            // 圆圈骨架
            Circle()
                .fill(AppColor.bgTertiary)
                .frame(width: 44, height: 44)

            // 文字骨架
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(skeletonColor)
                    .frame(width: 100, height: 14)

                RoundedRectangle(cornerRadius: 4)
                    .fill(skeletonColor)
                    .frame(width: 60, height: 11)
            }

            Spacer()

            // 价格骨架
            VStack(alignment: .trailing, spacing: 10) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(skeletonColor)
                    .frame(width: 45, height: 16)

                RoundedRectangle(cornerRadius: 14)
                    .fill(skeletonColor)
                    .frame(width: 72, height: 30)
            }
        }
        .padding(16)
        .background(AppColor.bgSecondary)
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.large)
                .stroke(AppColor.borderSubtle, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.large))
        .opacity(appearOpacity)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
        }
    }
    
    private var skeletonColor: Color {
        isAnimating ? AppColor.bgTertiary.opacity(0.5) : AppColor.bgTertiary
    }
    
    private var appearOpacity: Double {
        isAnimating ? 0.6 : 1.0
    }
}

// MARK: - 预览

#Preview {
    CreditsPurchaseView()
        .frame(width: 480, height: 620)
        .environmentObject(AppState())
        .preferredColorScheme(.dark)
}
