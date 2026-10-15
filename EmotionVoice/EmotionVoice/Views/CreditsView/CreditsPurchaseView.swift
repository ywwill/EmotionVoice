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
    /// StoreKit 购买动作，自带 UI 上下文，确认弹窗会贴着当前视图显示
    @Environment(\.purchase) private var purchaseAction
    
    @State private var appearAnimation = false

    /// 是否有任意一笔购买正在进行中（用于锁住其他套餐）
    private var isPurchaseInProgress: Bool {
        storeManager.purchasingProductId != nil
    }

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

            Text("购买")
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
            HStack(spacing: 8) {
                Text("选择套餐")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppColor.textTertiary)
                    .textCase(.uppercase)
                    .tracking(0.1)

                Spacer()

                if isPurchaseInProgress {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text("处理中…")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(AppColor.textTertiary)
                    }
                    .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.15), value: isPurchaseInProgress)

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
            ForEach(storeManager.products, id: \.id) { product in
                PurchaseProductRow(
                    product: product,
                    creditProduct: CreditProduct(rawValue: product.id),
                    isHighlighted: CreditProduct(rawValue: product.id)?.isRecommended == true,
                    isPurchasing: storeManager.purchasingProductId == product.id,
                    isBlocked: isPurchaseInProgress
                ) {
                    Task {
                        await storeManager.purchase(product, confirmWith: purchaseAction)
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
    /// 有别的套餐正在购买中 —— 本行需被蒙版锁住
    var isBlocked: Bool = false
    let onPurchase: () -> Void
    
    @State private var isHovered = false

    /// 本行是否被蒙版遮住（别的套餐在买）
    private var isMasked: Bool { isBlocked && !isPurchasing }

    /// 按钮是否不可点：商品未加载 / 本行在买 / 别的行在买
    private var isButtonDisabled: Bool { product == nil || isPurchasing || isMasked }

    var body: some View {
        HStack(spacing: 16) {
            // 积分图标 - 低饱和柔光底 + 细描边，避免大面积高亮刺眼
            ZStack {
                Circle()
                    .fill(iconTint.opacity(0.14))
                    .frame(width: 44, height: 44)
                    .overlay(
                        Circle()
                            .strokeBorder(iconTint.opacity(0.24), lineWidth: 1)
                    )

                Text(emoji)
                    .font(.system(size: 18))
                    .opacity(0.92)
            }

            // 信息
            // 「推荐」徽章与积分同一行：若单独占一行，非推荐行虽为空但仍吃 VStack spacing，
            // 会导致各行高度不一致
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if isHighlighted {
                        Text("推荐")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(AppColor.accentPrimary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AppColor.accentPrimary.opacity(0.15))
                            .clipShape(Capsule())
                            .fixedSize()
                    }

                    Text("\(creditProduct?.creditsAmount ?? 0) " + "积分".localized())
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AppColor.accentGlow)
                        .fixedSize()
                    
                    Text("·")
                        .foregroundStyle(AppColor.textTertiary)
                    
                    Text(productDescription)
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)
                        .lineLimit(1)
                }
                .frame(height: 20)
                
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
                // 内容尺寸恒定：spinner 与文字固有高度不同，不钉死会在点击瞬间撑高按钮
                .frame(width: 72, height: 18)
                // 按钮整体高度恒定（原来靠 padding 撑，文字换成 spinner 后会变）
                .frame(height: 34)
                .background(isHighlighted ? AppColor.accentPrimary : AppColor.bgTertiary)
                .foregroundStyle(isHighlighted ? .white : AppColor.textPrimary)
                .clipShape(Capsule())
            }
            .buttonStyle(PurchaseButtonStyle())
            .disabled(isButtonDisabled)
        }
        .padding(16)
        // 等高兜底：所有套餐行保持同一高度，不受有无「推荐」徽章、文案长短影响
        .frame(minHeight: 76)
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
        // 购买中：给其余套餐盖一层蒙版，既Dim 视觉也吃掉点击
        .overlay {
            if isMasked {
                RoundedRectangle(cornerRadius: AppRadius.large)
                    .fill(AppColor.bgPrimary.opacity(0.55))
                    .contentShape(Rectangle())
                    .allowsHitTesting(true)
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.18), value: isMasked)
        .onHover { hovering in
            isHovered = isBlocked ? false : hovering
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
        case .credits6: return "适合尝鲜体验".localized()
        case .credits30: return "个人创作首选".localized()
        case .credits60: return "高频使用推荐".localized()
        case .credits98: return "专业创作者".localized()
        case .none: return ""
        }
    }

    private var emoji: String {
        creditProduct?.icon ?? "💎"
    }

    /// 低饱和图标色调：只用于 14% 柔光底 + 24% 细描边，
    /// 替代原来的满饱和纯色实心圆（大面积高亮刺眼）
    private var iconTint: Color {
        switch creditProduct {
        case .credits6:  return Color(hex: 0x7C9A80)   // 🌱 哑光苔绿
        case .credits30: return Color(hex: 0xB98A55)   // ⭐ 哑光琥珀
        case .credits60: return Color(hex: 0xC4735A)   // 🔥 哑光赭红
        case .credits98: return Color(hex: 0x7C86B8)   // 💎 哑光蓝紫
        case .none:      return AppColor.textTertiary
        }
    }
}

// MARK: - 购买按钮样式

struct PurchaseButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            // 刻意不做 scaleEffect：按下时缩放会让按钮看起来尺寸在变，这里只用透明度反馈
            .opacity(configuration.isPressed ? 0.85 : 1.0)
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

            // 文字骨架（与真实行同构：积分行 + 价格行）
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(skeletonColor)
                    .frame(width: 100, height: 11)

                RoundedRectangle(cornerRadius: 4)
                    .fill(skeletonColor)
                    .frame(width: 60, height: 14)
            }

            Spacer()

            // 按钮骨架
            RoundedRectangle(cornerRadius: 14)
                .fill(skeletonColor)
                .frame(width: 72, height: 30)
        }
        .padding(16)
        .frame(minHeight: 76)
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
