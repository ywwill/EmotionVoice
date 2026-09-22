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
    
    // 分页状态
    @State private var currentPage: Int = 1
    @State private var creditRecords: PagedResult<CreditRecord> = PagedResult(
        items: [],
        totalCount: 0,
        currentPage: 1,
        pageSize: 10,
        totalPages: 1
    )
    
    // 监听购买状态
    @State private var lastPurchaseState: PurchaseState = .idle

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
        .onChange(of: storeManager.purchaseState) { _, newState in
            // 购买成功后刷新积分记录
            if case .success = newState, case .success = lastPurchaseState {
                // 跳过连续相同的成功状态
            } else if case .success = newState {
                reload()
            }
            lastPurchaseState = newState
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
                Text("💰 当前余额".localized())
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
                        Text("积分永久有效".localized())
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
            HStack {
                Text("💎 推荐套餐".localized())
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
            }

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
        HStack(spacing: 12) {
            ForEach(storeManager.products, id: \.id) { product in
                ProductCardView(product: product, creditProduct: CreditProduct(rawValue: product.id)) {
                    Task {
                        await storeManager.purchase(product)
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
                Text("共 \(creditRecords.totalCount) 条".localized())
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textTertiary)
            }
            
            VStack(spacing: 0) {
                // 表头
                HStack {
                    Text("类型".localized())
                        .frame(width: 50, alignment: .leading)
                    Text("详情".localized())
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("积分".localized())
                        .frame(width: 70, alignment: .trailing)
                    Text("时间".localized())
                        .frame(width: 130, alignment: .trailing)
                }
                .font(AppFont.label)
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
            // 类型图标
            Circle()
                .fill(recordColor(for: record.type).opacity(0.15))
                .frame(width: 28, height: 28)
                .overlay(
                    Text(record.type.icon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(recordColor(for: record.type))
                )
                .frame(width: 50, alignment: .leading)
            
            // 详情（单行）
            Text(record.title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(AppColor.textPrimary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            // 积分
            Text(record.formattedAmount)
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundStyle(record.isPositive ? AppColor.statusSuccess : AppColor.textSecondary)
                .frame(width: 70, alignment: .trailing)
            
            // 时间（具体到秒）
            Text(record.createdAt.shortDateTimeString)
                .font(AppFont.monoSmall)
                .foregroundStyle(AppColor.textTertiary)
                .frame(width: 130, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
    }
    
    private func recordColor(for type: CreditRecordType) -> Color {
        switch type {
        case .consumption: return Color(hex: 0x6B8BC9)
        case .purchase: return AppColor.statusSuccess
        }
    }
    
    private var paginationControl: some View {
        HStack(spacing: 16) {
            Button {
                if currentPage > 1 {
                    currentPage -= 1
                    loadCreditRecords()
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                    Text("上一页".localized())
                }
                .font(AppFont.bodyMedium)
                .foregroundStyle(currentPage > 1 ? AppColor.accentPrimary : AppColor.textTertiary)
            }
            .disabled(currentPage <= 1)
            .buttonStyle(.plain)
            
            Spacer()
            
            Text("第 \(currentPage) / \(creditRecords.totalPages) 页".localized())
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
            
            Spacer()
            
            Button {
                if currentPage < creditRecords.totalPages {
                    currentPage += 1
                    loadCreditRecords()
                }
            } label: {
                HStack(spacing: 4) {
                    Text("下一页".localized())
                    Image(systemName: "chevron.right")
                }
                .font(AppFont.bodyMedium)
                .foregroundStyle(currentPage < creditRecords.totalPages ? AppColor.accentPrimary : AppColor.textTertiary)
            }
            .disabled(currentPage >= creditRecords.totalPages)
            .buttonStyle(.plain)
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
}

// MARK: - CreditRecord 扩展

extension CreditRecord {
    var formattedAmount: String {
        return (isPositive ? "+" : "−") + "\(amount)"
    }
}
