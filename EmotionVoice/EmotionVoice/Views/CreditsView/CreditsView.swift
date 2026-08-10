//
//  CreditsView.swift
//  EmotionVoice
//
//  Created by young on 2026/8/8.
//

import SwiftUI

/// 积分中心
struct CreditsView: View {

    @EnvironmentObject var appState: AppState
    @State private var transactions: [TransactionRecord] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            toolbar
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    balanceHero
                    twoColumnStats
                    packagesSection
                    costReferenceSection
                    historySection
                }
                .padding(24)
            }
        }
        .onAppear { reload() }
    }

    private func reload() {
        transactions = CreditsService.shared.fetchTransactions()
    }

    // MARK: - 工具栏

    private var toolbar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("积分中心".localized())
                    .font(.system(size: 16, weight: .semibold))
                Text("充值积分，管理你的订阅与消费".localized())
                    .font(AppFont.bodySmall)
                    .foregroundStyle(AppColor.textTertiary)
            }
            Spacer()
            ToolbarButton(title: "消费明细".localized(), icon: "📋") {}
            ToolbarButton(title: "充值".localized(), icon: "+", isPrimary: true) {
                // 演示：跳到套餐
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 16)
        .background(
            Color(hex: 0x0E0F12).opacity(0.4)
                .background(.ultraThinMaterial)
        )
        .overlay(alignment: .bottom) {
            Divider().background(AppColor.borderSubtle)
        }
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
                        Text("有效期至 2027-08-08".localized())
                    }
                    Text("本月已使用 \(appState.monthlyUsed) 积分".localized())
                }
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
            }
            Spacer()
            VStack(spacing: 8) {
                PrimaryButton(title: "⚡ 立即充值".localized(), icon: nil) {}
                SecondaryButton(title: "📋 消费明细".localized(), icon: nil) {}
            }
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

    // MARK: - 两栏统计

    private var twoColumnStats: some View {
        HStack(spacing: 20) {
            usageCard
            trendCard
        }
    }

    private var usageCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("📊 本月使用情况".localized())
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button {} label: {
                    Text("详细报告 →".localized())
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.accentPrimary)
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("已使用".localized())
                    Spacer()
                    Text("\(appState.monthlyUsed) / 10,000")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(AppColor.textSecondary)
                }
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(AppColor.bgElevated)
                        RoundedRectangle(cornerRadius: 4)
                            .fill(
                                LinearGradient(
                                    colors: [AppColor.accentPrimary, AppColor.accentGlow],
                                    startPoint: .leading, endPoint: .trailing
                                )
                            )
                            .frame(width: geo.size.width * min(1.0, Double(appState.monthlyUsed) / 10000.0))
                    }
                }
                .frame(height: 8)
            }

            Divider().background(AppColor.borderSubtle)

            HStack(spacing: 0) {
                usageStat("152", "日均积分".localized())
                Divider().background(AppColor.borderSubtle).frame(height: 30)
                usageStat("28", "音频数量".localized())
                Divider().background(AppColor.borderSubtle).frame(height: 30)
                usageStat("\(appState.monthlyUsed)", "预计消耗".localized())
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColor.bgSecondary)
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.large)
                .stroke(AppColor.borderSubtle, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.large))
    }

    private func usageStat(_ value: String, _ label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 18, weight: .bold, design: .monospaced))
                .foregroundStyle(AppColor.textPrimary)
            Text(label)
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }

    private var trendCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("📈 消费趋势".localized())
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Text("最近 30 天".localized())
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textTertiary)
            }

            // 简易柱状图
            let heights: [Double] = [0.3, 0.45, 0.35, 0.6, 0.75, 0.5, 0.85, 0.95, 0.7, 0.55, 0.8, 0.65, 0.9, 0.75, 0.95]
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(0..<heights.count, id: \.self) { i in
                    let h = heights[i]
                    let isLast = i == heights.count - 1
                    VStack {
                        Spacer()
                        RoundedRectangle(cornerRadius: 2)
                            .fill(
                                isLast
                                ? AppColor.accentGlow
                                : AppColor.accentPrimary
                            )
                            .frame(height: 100 * h)
                            .opacity(isLast ? 1.0 : (0.4 + h * 0.4))
                            .shadow(
                                color: isLast ? AppColor.accentPrimary.opacity(0.4) : .clear,
                                radius: 8
                            )
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 110)

            HStack {
                Text("7月25日")
                Spacer()
                Text("8月1日")
                Spacer()
                Text("8月8日")
            }
            .font(AppFont.monoSmall)
            .foregroundStyle(AppColor.textTertiary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColor.bgSecondary)
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.large)
                .stroke(AppColor.borderSubtle, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.large))
    }

    // MARK: - 套餐

    private var packagesSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("💎 推荐套餐".localized())
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button {} label: {
                    Text("查看完整定价 →".localized())
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.accentPrimary)
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
            }

            HStack(spacing: 12) {
                ForEach(Constants.creditsPackages) { pkg in
                    PackageCardView(package: pkg) {
                        // 购买演示
                        CreditsService.shared.purchase(pkg.points)
                        CreditsService.shared.addTransaction(TransactionRecord(
                            id: 0,
                            type: .purchase,
                            title: "购买\(pkg.name)".localized(),
                            amount: pkg.points,
                            meta: "微信支付",
                            createdAt: Date()
                        ))
                        appState.refreshCredits()
                        reload()
                    }
                }
            }
        }
    }

    // MARK: - 消耗参考

    private var costReferenceSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("💡 积分消耗参考".localized())
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button {} label: {
                    Text("计费规则 →".localized())
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.accentPrimary)
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
            }

            VStack(spacing: 0) {
                HStack {
                    Text("内容类型".localized())
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("字数范围".localized())
                        .frame(width: 140, alignment: .leading)
                    Text("预估积分".localized())
                        .frame(width: 100, alignment: .trailing)
                    Text("场景示例".localized())
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .font(AppFont.label)
                .foregroundStyle(AppColor.textTertiary)
                .textCase(.uppercase)
                .tracking(0.05)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)

                Divider().background(AppColor.borderSubtle)

                ForEach(Constants.costReference) { item in
                    HStack {
                        Text(item.type)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .foregroundStyle(AppColor.textSecondary)
                        Text(item.range)
                            .font(.system(size: 13, design: .monospaced))
                            .foregroundStyle(AppColor.textTertiary)
                            .frame(width: 140, alignment: .leading)
                        Text(item.points)
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                            .foregroundStyle(AppColor.accentGlow)
                            .frame(width: 100, alignment: .trailing)
                        Text(item.scene)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .foregroundStyle(AppColor.textSecondary)
                    }
                    .font(AppFont.bodyMedium)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)

                    if item.id != Constants.costReference.last?.id {
                        Divider()
                            .background(AppColor.borderSubtle)
                            .padding(.horizontal, 12)
                    }
                }
            }
            .background(AppColor.bgSecondary)
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.large)
                    .stroke(AppColor.borderSubtle, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.large))
        }
    }

    // MARK: - 交易记录

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("📋 交易记录".localized())
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
                Button {} label: {
                    Text("查看全部 →".localized())
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.accentPrimary)
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
            }

            VStack(spacing: 0) {
                if transactions.isEmpty {
                        Text("暂无数据".localized())
                            .font(AppFont.bodyMedium)
                            .foregroundStyle(AppColor.textTertiary)
                            .padding(40)
                            .frame(maxWidth: .infinity)
                } else {
                    ForEach(transactions.prefix(6)) { tx in
                        historyRow(tx)
                        if tx.id != transactions.prefix(6).last?.id {
                            Divider()
                                .background(AppColor.borderSubtle)
                                .padding(.horizontal, 16)
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
        }
    }

    private func historyRow(_ tx: TransactionRecord) -> some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(historyColor(for: tx.type).opacity(0.15))
                    .frame(width: 32, height: 32)
                Text(tx.type.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(historyColor(for: tx.type))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(tx.title)
                    .font(.system(size: 13, weight: .medium))
                Text("\(tx.createdAt.shortDateString) · \(tx.meta ?? "")")
                    .font(AppFont.monoSmall)
                    .foregroundStyle(AppColor.textTertiary)
            }

            Spacer()

            Text((tx.type.isPositive ? "+" : "−") + "\(tx.amount)")
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundStyle(
                    tx.type.isPositive ? AppColor.statusSuccess : AppColor.textSecondary
                )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func historyColor(for type: TransactionType) -> Color {
        switch type {
        case .purchase: return AppColor.statusSuccess
        case .consume:  return Color(hex: 0x6B8BC9)
        case .refund:   return AppColor.accentPrimary
        }
    }
}
