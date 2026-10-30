//
//  PurchaseSheet.swift
//  iOSEmora
//
//  购买积分 Sheet（large detent）
//
//  两个入口共用同一张 Sheet：
//  ① 设置页顶部账户卡的「购买积分」按钮；② 工作台生成时积分不足直接弹出。
//  原 macOS「我的」页那排横向套餐卡（4 张 196pt）取消，套餐统一收在这里。
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

    var body: some View {
        VStack(spacing: 0) {
            SheetNavBar(
                title: "购买积分".localized(),
                leading: {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(c.textTertiary)
                    }
                    .buttonStyle(.plain)
                },
                trailing: { Color.clear.frame(width: 19) }
            )

            ScrollView {
                VStack(spacing: 0) {
                    if let hint = shortfallHint {
                        warningBanner(hint)
                    }

                    Text("选择套餐".localized())
                        .font(.system(size: 12, weight: .semibold))
                        .tracking(0.8)
                        .foregroundStyle(c.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.top, 10)
                        .padding(.bottom, 8)

                    VStack(spacing: 10) {
                        ForEach(CreditProduct.allCases, id: \.rawValue) { product in
                            packageRow(product)
                        }
                    }
                    .padding(.horizontal, 16)

                    Text("购买后积分永久有效，到账可能延迟；未到账时 App 会在下次启动自动补发。".localized())
                        .font(.system(size: 11.5))
                        .foregroundStyle(c.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.top, 14)

                    Spacer(minLength: 20)
                }
            }
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

    // MARK: 余额不足横幅

    private func warningBanner(_ hint: String) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(c.warning.opacity(0.2))
                    .frame(width: 42, height: 42)
                Image(systemName: "info.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(c.warning)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("积分不足".localized())
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(c.warning)
                Text(hint)
                    .font(.system(size: 12.5))
                    .foregroundStyle(c.textSecondary)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: AuroraRadius.lg, style: .continuous)
                .fill(c.warning.opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: AuroraRadius.lg, style: .continuous)
                        .strokeBorder(c.warning.opacity(0.3), lineWidth: 1)
                )
        )
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 16)
    }

    // MARK: 套餐行

    private func packageRow(_ product: CreditProduct) -> some View {
        let isRecommended = product.isRecommended
        let isPurchasing = store.purchasingProductId == product.rawValue
        let storeProduct = store.products.first { $0.id == product.rawValue }

        return HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(packageTint(product).opacity(0.2))
                    .frame(width: 44, height: 44)
                Text(emoji(for: product))
                    .font(.system(size: 22))
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 0) {
                    Text("\(product.creditsAmount) 积分".localized())
                        .font(.system(size: 14.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(c.accent)
                    Text(" · \(subtitle(for: product))")
                        .font(.system(size: 13.5))
                        .foregroundStyle(isRecommended ? c.textSecondary : c.textTertiary)
                        .lineLimit(1)
                }
                Text(storeProduct?.displayPrice ?? priceFallback(for: product))
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(c.textPrimary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                Task { await buy(product) }
            } label: {
                ZStack {
                    if isPurchasing {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("购买".localized())
                            .font(.system(size: 13.5, weight: .semibold))
                    }
                }
                .foregroundStyle(isRecommended ? c.ctaForeground : c.textPrimary)
                .padding(.horizontal, 16)
                .frame(height: 34)
                .background(
                    Capsule(style: .continuous)
                        .fill(isRecommended ? AnyShapeStyle(c.ctaGradient) : AnyShapeStyle(c.surface3))
                )
            }
            .buttonStyle(.plain)
            .disabled(isPurchasing || storeProduct == nil)
            .opacity(storeProduct == nil ? 0.5 : 1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: AuroraRadius.md, style: .continuous)
                .fill(isRecommended ? c.accentSoft : c.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: AuroraRadius.md, style: .continuous)
                        .strokeBorder(isRecommended ? c.accent.opacity(0.32) : c.line,
                                      lineWidth: isRecommended ? 1 : 0.5)
                )
        )
    }

    // MARK: 行为

    private func buy(_ product: CreditProduct) async {
        // PurchaseAction 必须来自视图环境：iPhone 上没窗口会被报成「用户取消」
        await store.purchase(product, confirmWith: purchaseAction)
    }

    private func handle(_ state: PurchaseState) {
        switch state {
        case .success(let credits):
            appState.refreshCredits()
            uiState.showToast(.success(String(format: "购买成功，+%@ 积分已到账".localized(),
                                              formatCredits(Double(credits)))))
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
