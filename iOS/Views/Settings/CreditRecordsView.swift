//
//  CreditRecordsView.swift
//  iOSEmora
//
//  积分记录（设置页的二级列表）
//
//  macOS 的 5 列表格（类型 / 详情 / 时长 / 积分 / 时间）拆成 iOS 两行行：
//  左侧色圆 = 类型（绿 ↑ 充值 / 红 ↓ 消费），主标题 = 详情，副标题 = 时长 · 时间
//  （仅消费记录有音频时长），右侧等宽数字（绿 + / 红 −，保留两位小数）。
//
//  顶部一行「共 N 条」+ 累计充值 / 累计消耗，替代 macOS 右下角那组分页按钮；
//  滚动到底自动追加下一页（沿用 `CreditsService.fetchCreditRecords(page:)`）。
//

import SwiftUI

struct CreditRecordsView: View {
    @Environment(\.aurora) private var c
    @Environment(\.screenMetrics) private var metrics

    @State private var records: [CreditRecord] = []
    @State private var totalCount: Int = 0
    @State private var page: Int = 0
    @State private var isLoading = false

    private var hasMore: Bool { records.count < totalCount }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: []) {
                summaryLine
                    .padding(.horizontal, 20)
                    .padding(.top, 6)
                    .padding(.bottom, 8)

                VStack(spacing: 0) {
                    ForEach(records) { record in
                        recordRow(record)
                        if record.id != records.last?.id {
                            Rectangle()
                                .fill(c.line)
                                .frame(height: 0.5)
                                .padding(.leading, 14)
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: AuroraRadius.md, style: .continuous)
                        .fill(c.surface)
                        .overlay(
                            RoundedRectangle(cornerRadius: AuroraRadius.md, style: .continuous)
                                .strokeBorder(c.line, lineWidth: 0.5)
                        )
                )
                .clipShape(RoundedRectangle(cornerRadius: AuroraRadius.md, style: .continuous))
                .padding(.horizontal, metrics.pageMargin)

                if isLoading || hasMore {
                    appendFooter
                        .onAppear { loadNextPage() }
                } else if records.isEmpty && !isLoading {
                    emptyState
                }
            }
        }
        .background(c.backgroundGrouped)
        .navigationTitle("积分记录".localized())
        .navigationBarTitleDisplayMode(.inline)
        .task { loadNextPage() }
    }

    // MARK: 汇总行

    private var summaryLine: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(String(format: "共 %d 条".localized(), totalCount))
                .font(.system(size: 12.5, design: .monospaced))
                .foregroundStyle(c.textTertiary)
            Spacer(minLength: 0)
            HStack(spacing: 5) {
                Text("+\(formatCredits(totalIncome))")
                    .font(.system(size: 12.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(c.success)
                Text("/")
                    .font(.system(size: 12.5))
                    .foregroundStyle(c.line2)
                Text("−\(formatCredits(totalExpense))")
                    .font(.system(size: 12.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(c.danger)
            }
        }
    }

    // MARK: 行

    private func recordRow(_ record: CreditRecord) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(record.isPositive ? c.success.opacity(0.16) : c.danger.opacity(0.16))
                    .frame(width: 28, height: 28)
                Image(systemName: record.isPositive ? "arrow.up" : "arrow.down")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(record.isPositive ? c.success : c.danger)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(record.title)
                    .font(.system(size: 15))
                    .foregroundStyle(c.textPrimary)
                    .lineLimit(1)
                Text(subtitle(for: record))
                    .font(.system(size: 12))
                    .foregroundStyle(c.textTertiary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(record.formattedAmount)
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .foregroundStyle(record.isPositive ? c.success : c.danger)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private func subtitle(for record: CreditRecord) -> String {
        // 设计稿格式：2026/10/26 11:08
        let date = record.createdAt.shortDateTimeString
        // 购买记录的 subtitle 是占位符 "/"，只显示日期
        if record.subtitle.isEmpty || record.subtitle == "/" { return date }
        return "\(record.subtitle) · \(date)"
    }

    // MARK: 底部

    private var appendFooter: some View {
        HStack(spacing: 7) {
            ProgressView().controlSize(.small)
            Text(String(format: "上拉加载更多 · 已显示 %d / %d".localized(), records.count, totalCount))
                .font(.system(size: 12))
                .foregroundStyle(c.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 18)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "diamond")
                .font(.system(size: 28))
                .foregroundStyle(c.textTertiary.opacity(0.6))
            Text("还没有积分记录".localized())
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(c.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    // MARK: - 数据

    private var totalIncome: Double {
        records.filter(\.isPositive).reduce(0) { $0 + $1.amount }
    }

    private var totalExpense: Double {
        records.filter { !$0.isPositive }.reduce(0) { $0 + $1.amount }
    }

    private func loadNextPage() {
        guard !isLoading else { return }
        isLoading = true
        let next = page + 1
        let result = CreditsService.shared.fetchCreditRecords(page: next)
        totalCount = result.totalCount
        let known = Set(records.map(\.id))
        records.append(contentsOf: result.items.filter { !known.contains($0.id) })
        page = next
        isLoading = false
    }
}
