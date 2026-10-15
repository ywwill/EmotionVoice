//
//  CreditsView.swift
//  EmotionVoice
//
//  Created by young on 2026/8/8.
//

import SwiftUI
import StoreKit

/// 积分中心
struct CreditsView: View {

    @EnvironmentObject var appState: AppState
    @StateObject private var storeManager = StoreKitManager.shared
    /// StoreKit 购买动作，自带 UI 上下文，确认弹窗会贴着当前视图显示
    @Environment(\.purchase) private var purchaseAction
    
    // 分页状态
    @State private var currentPage: Int = 1
    @State private var creditRecords: PagedResult<CreditRecord> = PagedResult(
        items: [],
        totalCount: 0,
        currentPage: 1,
        pageSize: 10,
        totalPages: 1
    )
    
    // 购买结果提示（成功 / 失败 / 取消）
    @State private var purchaseFeedback: PurchaseFeedback?
    @State private var feedbackHideTask: Task<Void, Never>?

    // 计费规则弹窗
    @State private var showCreditRulePopover = false

    /// 是否有任意一笔购买正在进行中（用于锁住其余套餐）
    private var isPurchaseInProgress: Bool {
        storeManager.purchasingProductId != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    packagesSection
                    balanceHero
                    creditRecordsSection
                }
                .padding(24)
            }
        }
        .onAppear { reload() }
        .onDisappear { feedbackHideTask?.cancel() }
        .onChange(of: storeManager.purchaseState) { _, newState in
            handlePurchaseState(newState)
        }
        // 购买结果用浮层 toast 提示，从顶部往下弹出，不占据内容区布局
        .overlay(alignment: .top) {
            if let feedback = purchaseFeedback {
                purchaseToast(feedback)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(10)
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.8), value: purchaseFeedback?.text)
    }

    // MARK: - 购买状态

    /// 购买状态 → 视觉反馈：按钮转圈 + 其余卡片蒙版由 isPurchasing/isBlocked 驱动，
    /// 这里只负责结果提示条与数据刷新
    private func handlePurchaseState(_ state: PurchaseState) {
        switch state {
        case .idle, .loading:
            clearFeedback()

        case .purchasing:
            // 新一轮开始，立刻清掉上一条提示
            clearFeedback()

        case .success(let credits):
            reload()
            showFeedback(
                credits > 0
                    ? PurchaseFeedback(kind: .success, text: "已到账 %d 积分".localized(credits))
                    : PurchaseFeedback(kind: .success, text: "购买已完成".localized())
            )

        case .failed(let message):
            if message == StoreError.userCancelled.localizedDescription {
                showFeedback(PurchaseFeedback(kind: .info, text: "已取消购买".localized()))
            } else if message == StoreError.pending.localizedDescription {
                showFeedback(PurchaseFeedback(kind: .info, text: "等待确认，到账后自动发放".localized()))
            } else {
                showFeedback(PurchaseFeedback(kind: .error, text: "购买失败".localized() + "：\(message)"))
            }
        }
    }

    private func showFeedback(_ feedback: PurchaseFeedback) {
        feedbackHideTask?.cancel()
        withAnimation(.easeOut(duration: 0.18)) {
            purchaseFeedback = feedback
        }
        // 成功/提示 4 秒后自动消失，失败留久一点给用户看清原因
        let delay: UInt64 = feedback.kind == .error ? 8 : 4
        feedbackHideTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: delay * 1_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.25)) {
                self.purchaseFeedback = nil
            }
        }
    }

    private func clearFeedback() {
        feedbackHideTask?.cancel()
        feedbackHideTask = nil
        purchaseFeedback = nil
    }

    /// 购买结果提示模型
    private struct PurchaseFeedback: Equatable {
        enum Kind { case success, error, info }
        let kind: Kind
        let text: String

        var tint: Color {
            switch kind {
            case .success: return AppColor.statusSuccess
            case .error:   return AppColor.statusError
            case .info:    return AppColor.textSecondary
            }
        }

        var iconName: String {
            switch kind {
            case .success: return "checkmark.circle.fill"
            case .error:   return "exclamationmark.triangle.fill"
            case .info:    return "info.circle.fill"
            }
        }
    }

    private func reload() {
        loadCreditRecords()
    }
    
    private func loadCreditRecords() {
        creditRecords = CreditsService.shared.fetchCreditRecords(page: currentPage)
    }

    // MARK: - 余额 Hero

    private var balanceHero: some View {
        HStack {
            VStack(alignment: .leading, spacing: 8) {
                Text("当前余额".localized())
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppColor.textTertiary)
                    .textCase(.uppercase)
                    .tracking(0.08)

                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(appState.creditsBalance)")
                        .font(.system(size: 56, weight: .bold, design: .monospaced))
                        .foregroundStyle(AppColor.accentGlow)
                        .tracking(-0.03)
                    Text("积分".localized())
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(AppColor.textSecondary)
                }

                HStack(spacing: 16) {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(AppColor.statusSuccess)
                            .frame(width: 6, height: 6)
                        Text("永久有效".localized())
                    }
                    
                    Divider()
                        .frame(height: 12)
                        .background(AppColor.borderSubtle)
                    
                    // 积分计算规则
                    Button {
                        showCreditRulePopover.toggle()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "info.circle")
                                .font(.system(size: 11))
                            Text("计费规则".localized())
                                .font(AppFont.caption)
                        }
                        .foregroundStyle(AppColor.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .pointingHandCursor()
                    .popover(isPresented: $showCreditRulePopover) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("积分计算规则".localized())
                                .font(.system(size: 13, weight: .semibold))
                                .padding(.bottom, 4)
                            
                            Group {
                                HStack(alignment: .top, spacing: 8) {
                                    Circle()
                                        .fill(AppColor.accentPrimary)
                                        .frame(width: 5, height: 5)
                                        .padding(.top, 6)
                                    Text("2 积分 / 100 字符".localized())
                                        .font(AppFont.caption)
                                }
                                
                                HStack(alignment: .top, spacing: 8) {
                                    Circle()
                                        .fill(AppColor.accentPrimary)
                                        .frame(width: 5, height: 5)
                                        .padding(.top, 6)
                                    Text("中日韩文字按 2 字符计算".localized())
                                        .font(AppFont.caption)
                                }
                                
                                HStack(alignment: .top, spacing: 8) {
                                    Circle()
                                        .fill(AppColor.accentPrimary)
                                        .frame(width: 5, height: 5)
                                        .padding(.top, 6)
                                    Text("英文、数字、标点按 1 字符计算".localized())
                                        .font(AppFont.caption)
                                }
                            }
                            .foregroundStyle(AppColor.textSecondary)
                        }
                        .padding(16)
                        .presentationCompactAdaptation(.popover)
                    }
                }
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
            }
            Spacer()
        }
        .padding(32)
        .background(AppColor.bgSecondary)
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.xlarge)
                .stroke(AppColor.borderSubtle, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.xlarge))
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [AppColor.accentPrimary.opacity(0.2), Color.clear],
                        center: .center, startRadius: 10, endRadius: 120
                    )
                )
                .frame(width: 240, height: 240)
                .offset(x: 80, y: -80)
                .allowsHitTesting(false)
        }
    }

    // MARK: - 套餐

    private var packagesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            if storeManager.isLoading {
                skeletonProductCards
            } else if storeManager.products.isEmpty {
                emptyProductsView
            } else {
                productCards
            }
        }
    }

    /// 顶部浮层 toast：从顶部往下弹出，悬浮在内容之上，不参与布局计算，出现/消失都不会顶动套餐区
    private func purchaseToast(_ feedback: PurchaseFeedback) -> some View {
        HStack(spacing: 8) {
            Image(systemName: feedback.iconName)
                .font(.system(size: 13))
            Text(feedback.text)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .foregroundStyle(feedback.tint)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.large)
                .fill(AppColor.bgElevated)
                .shadow(color: .black.opacity(0.35), radius: 16, x: 0, y: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.large)
                .stroke(feedback.tint.opacity(0.3), lineWidth: 1)
        )
        .padding(.top, 24)
        .allowsHitTesting(false)
    }

    private var productCards: some View {
        HStack(spacing: 12) {
            ForEach(storeManager.products, id: \.id) { product in
                ProductCardView(
                    product: product,
                    creditProduct: CreditProduct(rawValue: product.id),
                    isPurchasing: storeManager.purchasingProductId == product.id,
                    isBlocked: isPurchaseInProgress
                ) {
                    Task {
                        await storeManager.purchase(product, confirmWith: purchaseAction)
                    }
                }
            }
        }
    }

    private var skeletonProductCards: some View {
        HStack(spacing: 12) {
            ForEach(0..<4, id: \.self) { _ in
                SkeletonProductCard()
            }
        }
    }

    private var emptyProductsView: some View {
        HStack(spacing: 12) {
            ForEach(CreditProduct.allCases, id: \.rawValue) { creditProduct in
                ProductCardView(product: nil, creditProduct: creditProduct) {
                    Task {
                        await storeManager.loadProducts()
                    }
                }
            }
        }
    }
    
    // MARK: - 积分记录
    
    private var creditRecordsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("📋 积分记录".localized())
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Text("共 %d 条".localized(creditRecords.totalCount))
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textTertiary)
            }
            
            VStack(spacing: 0) {
                // 表头
                HStack {
                    Text("类型".localized())
                        .frame(width: 100, alignment: .leading)
                    Text("详情".localized())
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("时长".localized())
                        .frame(width: 100, alignment: .center)
                    Text("积分".localized())
                        .frame(width: 100, alignment: .trailing)
                    Text("时间".localized())
                        .frame(width: 150, alignment: .trailing)
                }
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AppColor.textTertiary)
                .textCase(.uppercase)
                .tracking(0.05)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

                Divider().background(AppColor.borderSubtle)
                
                if creditRecords.items.isEmpty {
                    // 空状态
                    VStack(spacing: 8) {
                        Image(systemName: "tray")
                            .font(.system(size: 32))
                            .foregroundStyle(AppColor.textTertiary)
                        Text("暂无积分记录".localized())
                            .font(AppFont.bodyMedium)
                            .foregroundStyle(AppColor.textTertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                } else {
                    // 记录列表
                    ForEach(creditRecords.items) { record in
                        creditRecordRow(record)
                        if record.id != creditRecords.items.last?.id {
                            Divider()
                                .background(AppColor.borderSubtle)
                                .padding(.horizontal, 12)
                        }
                    }
                }
            }
            .background(AppColor.bgSecondary)
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.large)
                    .stroke(AppColor.borderSubtle, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.large))
            
            // 分页控制
            if creditRecords.totalPages > 1 {
                paginationControl
            }
        }
    }
    
    private func creditRecordRow(_ record: CreditRecord) -> some View {
        HStack {
            // 类型图标（只显示图标，不显示文字，节省空间）
            Circle()
                .fill(recordColor(for: record.type).opacity(0.15))
                .frame(width: 28, height: 28)
                .overlay(
                    Text(record.type.icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(recordColor(for: record.type))
                )
                .frame(width: 100, alignment: .leading)
            
            // 详情（单行）
            Text(record.title)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(AppColor.textPrimary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            // 时长（消耗记录显示，购买记录为空）
            Text(record.subtitle)
                .font(.system(size: 13))
                .foregroundStyle(AppColor.textSecondary)
                .frame(width: 100, alignment: .center)
            
            // 积分
            Text(record.formattedAmount)
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundStyle(record.isPositive ? AppColor.statusSuccess : .red)
                .frame(width: 100, alignment: .trailing)
            
            // 时间
            Text(record.createdAt.shortDateTimeString)
                .font(AppFont.monoSmall)
                .foregroundStyle(AppColor.textTertiary)
                .frame(width: 150, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
    }
    
    private func recordColor(for type: CreditRecordType) -> Color {
        switch type {
        case .consumption: return Color.red
        case .purchase: return AppColor.statusSuccess
        }
    }
    
    private var paginationControl: some View {
        HStack(spacing: 0) {
            Spacer()

            // 左侧导航按钮组（聚合在一起）
            HStack(spacing: 4) {
                Button {
                    currentPage = 1
                    loadCreditRecords()
                } label: {
                    Image(systemName: "chevron.left.2")
                        .font(.system(size: 11, weight: .medium))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(currentPage > 1 ? AppColor.accentPrimary : AppColor.textTertiary)
                .disabled(currentPage <= 1)

                Button {
                    if currentPage > 1 {
                        currentPage -= 1
                        loadCreditRecords()
                    }
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(currentPage > 1 ? AppColor.accentPrimary : AppColor.textTertiary)
                .disabled(currentPage <= 1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(AppColor.bgTertiary)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.small))

            // 中间页码区
            pageNumberButtons

            // 右侧导航按钮组（聚合在一起）
            HStack(spacing: 4) {
                Button {
                    if currentPage < creditRecords.totalPages {
                        currentPage += 1
                        loadCreditRecords()
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .medium))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(currentPage < creditRecords.totalPages ? AppColor.accentPrimary : AppColor.textTertiary)
                .disabled(currentPage >= creditRecords.totalPages)

                Button {
                    currentPage = creditRecords.totalPages
                    loadCreditRecords()
                } label: {
                    Image(systemName: "chevron.right.2")
                        .font(.system(size: 11, weight: .medium))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(currentPage < creditRecords.totalPages ? AppColor.accentPrimary : AppColor.textTertiary)
                .disabled(currentPage >= creditRecords.totalPages)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(AppColor.bgTertiary)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.small))

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(AppColor.bgSecondary)
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.medium)
                .stroke(AppColor.borderSubtle, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium))
    }

    /// 页码数字按钮组件
    @ViewBuilder
    private var pageNumberButtons: some View {
        let totalPages = creditRecords.totalPages
        let current = currentPage

        HStack(spacing: 8) {
            // 当前页码 / 总页数
            Text("\(current)")
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .foregroundStyle(AppColor.accentPrimary)

            Text("/")
                .font(.system(size: 13))
                .foregroundStyle(AppColor.textTertiary)

            Text("\(totalPages)")
                .font(.system(size: 15, weight: .medium, design: .monospaced))
                .foregroundStyle(AppColor.textSecondary)
        }
        .padding(.horizontal, 12)
    }

    /// 单个页码按钮
    private func pageNumberButton(_ page: Int) -> some View {
        Button {
            currentPage = page
            loadCreditRecords()
        } label: {
            Text("\(page)")
                .font(.system(size: 13, weight: currentPage == page ? .semibold : .regular, design: .monospaced))
                .foregroundStyle(currentPage == page ? AppColor.accentPrimary : AppColor.textSecondary)
                .frame(minWidth: 32, minHeight: 32)
                .background(
                    currentPage == page
                        ? AppColor.accentPrimary.opacity(0.15)
                        : Color.clear
                )
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.small))
        }
        .buttonStyle(.plain)
    }
}
