//
//  PurchaseSheet.swift
//  iOSEmora
//
//  购买积分 Sheet（large detent）
//
//  两个入口共用同一张 Sheet：
//  ① 设置页顶部账户卡的「购买积分」按钮；② 工作台生成时积分不足直接弹出。
//
//  ⚠️ 不照搬 macOS 那版「一行一个套餐行 + 行内购买按钮」的表格布局。
//  iOS 的购买页是**先选后买**：顶部余额卡 → 2 列套餐卡（点卡选中）→ 底部固定 CTA。
//  行内塞按钮会让每张卡都变成一个「确认购买」的热区，误触成本高，也不符合
//  App Store 内购页的肌肉记忆（选中态 + 单一主按钮）。
//
//  ⚠️ StoreKit 2 的 `PurchaseAction`（`@Environment(\.purchase)`）**必须带 UI 上下文**：
//  在 iPhone 上如果拿不到窗口，系统确认弹窗挂不上，会被报成 `.userCancelled`。
//  所以这里在视图内取 `purchase` 环境值再传给 `StoreKitManager.purchase(_:confirmWith:)`。
//

import SwiftUI
import StoreKit

struct PurchaseSheet: View {
    @Environment(\.aurora) private var c
    @Environment(\.purchase) private var purchaseAction
    @Environment(\.dismiss) private var dismiss

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var uiState: IOSUIState

    @ObservedObject private var store = StoreKitManager.shared

    /// 余额不足提示：由外部传入（工作台按缺口算），为 nil 时不显示
    var shortfallHint: String? = nil

    /// 当前选中的套餐。默认落在推荐档上，省掉用户一次点选。
    @State private var selected: CreditProduct = .credits30

    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 12), count: 2)
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetNavBar(
                title: "购买积分".localized(),
                leading: {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(c.textSecondary)
                            .frame(width: 30, height: 30)
                            .background(Circle().fill(c.surface3))
                    }
                    .buttonStyle(.plain)
                },
                trailing: { Color.clear.frame(width: 30) }
            )

            ScrollView {
                VStack(spacing: 0) {
                    balanceHero
                        .padding(.horizontal, 16)
                        .padding(.top, 6)

                    if let hint = shortfallHint {
                        shortfallBanner(hint)
                            .padding(.horizontal, 16)
                            .padding(.top, 12)
                    }

                    sectionTitle("选择套餐".localized())

                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(CreditProduct.allCases, id: \.rawValue) { product in
                            PackageCard(product: product,
                                        isSelected: selected == product,
                                        priceText: priceText(for: product),
                                        emoji: emoji(for: product),
                                        subtitle: subtitle(for: product),
                                        tint: packageTint(product))
                                .onTapGesture { select(product) }
                        }
                    }
                    .padding(.horizontal, 16)

                    footnote

                    Spacer(minLength: 12)
                }
            }

            footBar
        }
        .background(c.backgroundGrouped)
        .task {
            if store.products.isEmpty {
                await store.loadProducts()
            }
        }
        .onChange(of: store.purchaseState) { _, state in
            handle(state)
        }
    }

    // MARK: 顶部余额卡

    private var balanceHero: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.22))
                    .frame(width: 46, height: 46)
                Image(systemName: "diamond.fill")
                    .font(.system(size: 21))
                    .foregroundStyle(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("当前余额".localized())
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                Text(formatCredits(appState.creditsBalance))
                    .font(AuroraFont.balance)
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: AuroraRadius.xl, style: .continuous)
                .fill(AuroraDecor.creditGradient)
        )
        .overlay(alignment: .topTrailing) {
            Image(systemName: "sparkles")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.55))
                .padding(.top, 14)
                .padding(.trailing, 16)
        }
    }

    // MARK: 余额不足横幅

    private func shortfallBanner(_ hint: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(c.warning)
            Text(hint)
                .font(.system(size: 12.5))
                .foregroundStyle(c.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: AuroraRadius.md, style: .continuous)
                .fill(c.warning.opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: AuroraRadius.md, style: .continuous)
                        .strokeBorder(c.warning.opacity(0.32), lineWidth: 1)
                )
        )
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(c.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 10)
    }

    private var footnote: some View {
        VStack(alignment: .leading, spacing: 4) {
            // ⚠️ 商品拉不回来时一定要说清楚为什么按钮点不了：
            // 否则用户只看到一个灰着的「立即购买」，既不知道在加载也不知道失败了。
            if productsLoaded {
                Text("购买后积分永久有效，到账可能延迟；未到账时 App 会在下次启动自动补发。".localized())
                Text("确认购买后将从您的 App Store 账户扣款。".localized())
            } else {
                Text("正在获取商品信息…".localized())
            }
        }
        .font(.system(size: 11.5))
        .foregroundStyle(c.textTertiary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    // MARK: 底部固定 CTA

    private var footBar: some View {
        VStack(spacing: 0) {
            Hairline()
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("%d 积分".localized(selected.creditsAmount))
                        .font(.system(size: 12))
                        .foregroundStyle(c.textTertiary)
                    Text(priceText(for: selected))
                        .font(AuroraFont.mono17)
                        .foregroundStyle(c.textPrimary)
                }
                .fixedSize()

                PrimaryButton(title: ctaTitle, systemImage: "diamond.fill", height: 48,
                              isEnabled: canBuy) {
                    Task { await buy(selected) }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 10)
            .disabled(isPurchasing)
            .opacity(isPurchasing ? 0.6 : 1)
        }
        .background(c.bar)
    }

    private var ctaTitle: String {
        isPurchasing ? "购买中…".localized() : "立即购买".localized()
    }

    private var isPurchasing: Bool {
        store.purchasingProductId == selected.rawValue
    }

    /// 商品还没拉回来时不能点（点了只会拿到「商品未找到」）。
    /// 卡片选中则不做这个限制 —— 先让用户看清价格结构，商品回来即亮起。
    private var canBuy: Bool {
        !isPurchasing && store.product(for: selected) != nil
    }

    private var productsLoaded: Bool {
        !store.products.isEmpty
    }

    // MARK: 行为

    private func select(_ product: CreditProduct) {
        withAnimation(.easeOut(duration: 0.16)) { selected = product }
    }

    private func buy(_ product: CreditProduct) async {
        // PurchaseAction 必须来自视图环境：iPhone 上没窗口会被报成「用户取消」
        await store.purchase(product, confirmWith: purchaseAction)
    }

    private func handle(_ state: PurchaseState) {
        switch state {
        case .success(let credits):
            appState.refreshCredits()
            uiState.showToast(.success("购买成功，+%@ 积分已到账".localized(formatCredits(Double(credits)))))
            store.resetPurchaseState()
            dismiss()
        case .failed(let message):
            uiState.showToast(.failure(message))
            store.resetPurchaseState()
        case .idle, .loading, .purchasing:
            break
        }
    }

    // MARK: 展示

    private func priceText(for product: CreditProduct) -> String {
        let live = store.displayPrice(for: product)
        return live == "--" ? priceFallback(for: product) : live
    }

    private func emoji(for product: CreditProduct) -> String {
        switch product {
        case .credits6:  return "🌱"
        case .credits30: return "⭐"
        case .credits60: return "🔥"
        case .credits98: return "💎"
        }
    }

    private func subtitle(for product: CreditProduct) -> String {
        switch product {
        case .credits6:  return "适合尝鲜体验".localized()
        case .credits30: return "个人创作首选".localized()
        case .credits60: return "高频使用推荐".localized()
        case .credits98: return "专业创作者".localized()
        }
    }

    /// 商品还没拉回来时的兜底价（与 App Store Connect 配置保持一致）
    private func priceFallback(for product: CreditProduct) -> String {
        switch product {
        case .credits6:  return "¥6"
        case .credits30: return "¥30"
        case .credits60: return "¥60"
        case .credits98: return "¥98"
        }
    }

    private func packageTint(_ product: CreditProduct) -> Color {
        switch product {
        case .credits6:  return Color(hex: 0x57C08A)
        case .credits30: return Color(hex: 0xF2A03D)
        case .credits60: return Color(hex: 0xFF7A6B)
        case .credits98: return Color(hex: 0x918DF5)
        }
    }
}

// MARK: - 套餐卡

/// 2 列网格里的一张套餐卡：点选 → 底部 CTA 购买。
///
/// 卡片本身只负责「选中」这一种状态，购买动作统一交给底部按钮 ——
/// 卡片里再塞一个购买按钮，等于每张卡都是热区，误触一次就真的扣款了。
private struct PackageCard: View {
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
                Text("\(product.creditsAmount)")
                    .font(.system(size: 25, weight: .bold, design: .monospaced))
                    .foregroundStyle(c.textPrimary)
                Text("积分".localized())
                    .font(.system(size: 12))
                    .foregroundStyle(c.textTertiary)
            }

            Text(subtitle)
                .font(.system(size: 12))
                .foregroundStyle(c.textSecondary)
                .lineLimit(1)
                .padding(.top, 3)

            Text(priceText)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(c.accent)
                .padding(.top, 8)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
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
