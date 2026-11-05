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

    @ObservedObject private var store = StoreKitManager.shared

    /// 购买结果反馈。⚠️ 全局 Toast 挂在根视图上，会被本 Sheet 整块盖住 ——
    /// 失败 / 取消 / 待确认必须在本页内提示，否则用户什么提示都看不到。
    /// 购买成功不弹提示：余额卡的滚动动画已经表达到账，再加横幅是重复反馈。
    @State private var feedback: PurchaseFeedback?
    @State private var feedbackHideTask: Task<Void, Never>?
    /// 已成功到账后不再展示「积分不足」横幅（钱到了还挂缺口提示自相矛盾）
    @State private var purchaseSucceeded = false

    /// 余额不足提示：由外部传入（工作台按缺口算），为 nil 时不显示
    var shortfallHint: String? = nil

    /// 当前选中的套餐。默认落在推荐档上，省掉用户一次点选。
    @State private var selected: CreditProduct = .credits400

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

                    if let hint = shortfallHint, !purchaseSucceeded {
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
                    // 处理中锁住套餐选择：避免系统确认弹窗期间还能切档，导致按钮状态闪回
                    .allowsHitTesting(!isPurchasing)
                    .opacity(isPurchasing ? 0.5 : 1)
                    .animation(.easeOut(duration: 0.16), value: isPurchasing)

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
        // 页内结果浮层：不占布局高度，压在内容之上（与 macOS 积分中心同语义）
        .overlay(alignment: .top) {
            if let feedback {
                feedbackToast(feedback)
                    // 让开 SheetNavBar（抓手 5 + 标题行 42 + 上下留白）
                    .padding(.top, 58)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(10)
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.8), value: feedback?.id)
        .onDisappear { feedbackHideTask?.cancel() }
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
                // 到账/扣费都走 AppState.creditsBalance：值一变就逐位滚动到新余额
                AnimatedCreditText(value: appState.creditsBalance,
                                   font: AuroraFont.balance,
                                   weight: .bold,
                                   color: .white)
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
                Text("购买后积分永久有效。".localized())
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
            HStack(spacing: 10) {
                PrimaryButton(title: ctaTitle, systemImage: "diamond.fill", height: 50,
                              isEnabled: canBuy, isLoading: isPurchasing) {
                    Task { await buy(selected) }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 10)
        }
        .background(c.bar)
    }

    private var ctaTitle: String {
        isPurchasing ? "购买中…".localized() : "立即购买".localized()
    }

    /// 任意一笔购买在进行中都算「处理中」——不能只看 selected：
    /// 用户在系统确认弹窗期间点了别的套餐时 selected 会变，绑死 selected 会让 CTA 瞬间恢复可点。
    private var isPurchasing: Bool {
        store.purchasingProductId != nil
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
        guard !isPurchasing else { return }
        withAnimation(.easeOut(duration: 0.16)) { selected = product }
    }

    private func buy(_ product: CreditProduct) async {
        // PurchaseAction 必须来自视图环境：iPhone 上没窗口会被报成「用户取消」
        await store.purchase(product, confirmWith: purchaseAction)
    }

    private func handle(_ state: PurchaseState) {
        switch state {
        case .success(_):
            // StoreKitManager 已把积分写进 CreditManager，这里补一次展示值刷新，
            // AnimatedCreditText 从旧余额滚到新余额 —— 这就是唯一的成功反馈。
            appState.refreshCredits()
            purchaseSucceeded = true
            clearFeedback()
            store.resetPurchaseState()
            // ⚠️ 不 dismiss：留在购买页看余额滚动，关闭只由 X / 下拉触发。
        case .failed(let message):
            let kind: PurchaseFeedback.Kind
            let text: String
            if message == StoreError.userCancelled.localizedDescription {
                kind = .info
                text = "已取消购买".localized()
            } else if message == StoreError.pending.localizedDescription {
                kind = .info
                text = "等待确认，到账后自动发放".localized()
            } else {
                kind = .failure
                text = "购买失败".localized() + "：\(message)"
            }
            showFeedback(PurchaseFeedback(kind: kind, text: text))
            store.resetPurchaseState()
        case .purchasing:
            clearFeedback()
        case .idle, .loading:
            // resetPurchaseState() 会再发一次 .idle，这里刻意不清提示，
            // 否则刚显示的失败/取消提示会被状态重置抹掉。
            break
        }
    }

    // MARK: 购买结果页内反馈

    private func showFeedback(_ item: PurchaseFeedback) {
        feedbackHideTask?.cancel()
        withAnimation(.easeOut(duration: 0.18)) { feedback = item }
        // 失败留久一点看清原因，取消 / 待确认 4s
        let delay: UInt64 = item.kind == .failure ? 8 : 4
        feedbackHideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: delay * 1_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) { feedback = nil }
        }
    }

    private func clearFeedback() {
        feedbackHideTask?.cancel()
        feedbackHideTask = nil
        feedback = nil
    }

    private func feedbackToast(_ item: PurchaseFeedback) -> some View {
        let tint: Color = {
            switch item.kind {
            case .failure: return c.danger
            case .info:    return c.warning
            }
        }()
        return HStack(spacing: 9) {
            Image(systemName: item.icon)
                .font(.system(size: 16, weight: .semibold))
            Text(item.text)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: AuroraRadius.md, style: .continuous)
                .fill(c.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: AuroraRadius.md, style: .continuous)
                        .strokeBorder(tint.opacity(0.35), lineWidth: 1)
                )
        )
        .padding(.horizontal, 16)
        .shadow(color: c.shadow.opacity(0.6), radius: 16, x: 0, y: 6)
    }

    // MARK: 展示

    private func priceText(for product: CreditProduct) -> String {
        let live = store.displayPrice(for: product)
        return live == "--" ? priceFallback(for: product) : live
    }

    private func emoji(for product: CreditProduct) -> String {
        switch product {
        case .credits60:   return "🌱"
        case .credits400:  return "⭐"
        case .credits900:  return "🔥"
        case .credits1500: return "💎"
        }
    }

    private func subtitle(for product: CreditProduct) -> String {
        switch product {
        case .credits60:   return "适合尝鲜体验".localized()
        case .credits400:  return "个人创作首选".localized()
        case .credits900:  return "高频使用推荐".localized()
        case .credits1500: return "专业创作者".localized()
        }
    }

    /// 商品还没拉回来时的兜底价（与 App Store Connect 配置保持一致）
    private func priceFallback(for product: CreditProduct) -> String {
        switch product {
        case .credits60:   return "¥6"
        case .credits400:  return "¥30"
        case .credits900:  return "¥60"
        case .credits1500: return "¥98"
        }
    }

    private func packageTint(_ product: CreditProduct) -> Color {
        switch product {
        case .credits60:   return Color(hex: 0x57C08A)
        case .credits400:  return Color(hex: 0xF2A03D)
        case .credits900:  return Color(hex: 0xFF7A6B)
        case .credits1500: return Color(hex: 0x918DF5)
        }
    }
}

/// 购买结果反馈模型（id 用于驱动浮层的插入 / 移除动画）
/// 仅承载失败 / 取消 / 待确认；成功由余额滚动动画表达，不产生反馈。
private struct PurchaseFeedback: Identifiable {
    enum Kind { case failure, info }
    let id = UUID()
    let kind: Kind
    let text: String

    var icon: String {
        switch kind {
        case .failure: return "exclamationmark.triangle.fill"
        case .info:    return "info.circle.fill"
        }
    }
}
