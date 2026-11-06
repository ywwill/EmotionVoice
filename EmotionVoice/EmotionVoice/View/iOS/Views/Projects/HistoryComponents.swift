//
//  HistoryComponents.swift
//  iOSEmora
//
//  历史记录页的展示组件（对应 UI/iOS/history-redesign.html 第 04 章规格）。
//  色板 / 圆角 / 字体全部沿用 AuroraPalette.swift，不引入新颜色；
//  玫红强调统一用 `AuroraDecor.rose`，与音色库 heart.fill 同一套视觉语言。
//

import SwiftUI
import Combine

// MARK: - 统计条

/// 总条数 / 占用空间 / 本月新增，三等分。数值恒为全量（不含已软删条目）。
struct HistoryStatBar: View {
    @Environment(\.aurora) private var c
    @Environment(\.screenMetrics) private var metrics
    let count: Int
    let bytes: Int
    let monthly: Int

    var body: some View {
        HStack(spacing: 0) {
            stat("%d 条音频".localized(count))
            divider
            stat(sizeText)
            divider
            stat("%d 条本月".localized(monthly))
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(c.surface2)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(c.line, lineWidth: 0.5)
                )
        )
        .padding(.horizontal, metrics.pageMargin)
        .padding(.bottom, 9)
    }

    private func stat(_ text: String) -> some View {
        HStack(spacing: 5) {
            // 数值段用等宽粗体，单位段用常规小字
            let parts = text.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
            if let first = parts.first {
                Text(first)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundStyle(c.textPrimary)
            }
            if parts.count > 1 {
                Text(parts[1])
                    .font(.system(size: 11.5))
                    .foregroundStyle(c.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var divider: some View {
        Rectangle().fill(c.line2).frame(width: 0.5, height: 16)
            .padding(.horizontal, 10)
    }

    private var sizeText: String {
        let u = autoByteUnit(Double(bytes))
        return "\(u.value) \(u.unit)"
    }
}

// MARK: - 筛选胶囊

/// 全部 / 收藏，单选互斥；计数恒为全量。
/// ⚠️ 整条胶囊都是热区：外层 contentShape + onTapGesture，不用内部 Button；
///    选完分类不再出现 ×，清除走「全部」。
struct HistoryFilterChips: View {
    @Environment(\.aurora) private var c
    @Environment(\.screenMetrics) private var metrics
    let allCount: Int
    let favoriteCount: Int
    let selection: HistoryFilter
    let onSelect: (HistoryFilter) -> Void

    var body: some View {
        HStack(spacing: 7) {
            chip(title: "全部".localized(), count: allCount,
                 systemImage: nil, on: selection == .all) { onSelect(.all) }
            chip(title: "收藏".localized(), count: favoriteCount,
                 systemImage: "heart", on: selection == .favorites) { onSelect(.favorites) }
        }
        // ⚠️ VStack 默认 .center：不显式撑满，两个胶囊会整体居中而不是左对齐
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, metrics.pageMargin)
        // 设计稿 .chips{padding:0 16px 10px}：下方留白由这 10pt 和分组头的
        // 13pt 上内边距共同构成；List 的系统 section 间距已在 listArea 清零，别再叠加。
        .padding(.bottom, 10)
    }

    private func chip(title: String, count: Int, systemImage: String?,
                      on: Bool, action: @escaping () -> Void) -> some View {
        HStack(spacing: 5) {
            if let systemImage {
                Image(systemName: on ? "heart.fill" : systemImage)
                    .font(.system(size: 12))
            }
            Text(title)
                .font(.system(size: 12.5, weight: on ? .semibold : .regular))
            Text("\(count)")
                .font(.system(size: 11, design: .monospaced))
                .opacity(0.75)
        }
        .foregroundStyle(on ? c.accent : c.textSecondary)
        .padding(.horizontal, 11)
        .frame(height: 29)
        .background(
            Capsule(style: .continuous)
                .fill(on ? c.accentSoft : c.surface)
                .overlay(
                    Capsule(style: .continuous)
                        .strokeBorder(on ? c.accent.opacity(0.42) : c.line, lineWidth: 0.5)
                )
        )
        .contentShape(Capsule(style: .continuous))
        .onTapGesture(perform: action)
        .accessibilityAddTraits(on ? [.isSelected] : [])
    }
}

// MARK: - 搜索范围 / 结果条

struct HistoryScopeChips: View {
    @Environment(\.aurora) private var c
    @Environment(\.screenMetrics) private var metrics
    let selection: HistorySearchScope
    let onSelect: (HistorySearchScope) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(HistorySearchScope.allCases) { scope in
                let on = scope == selection
                Text(scope.title)
                    .font(.system(size: 11.5, weight: on ? .semibold : .regular))
                    .foregroundStyle(on ? c.accent : c.textSecondary)
                    .padding(.horizontal, 10)
                    .frame(height: 26)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(on ? c.accentSoft : c.surface2)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(on ? c.accent.opacity(0.42) : c.line, lineWidth: 0.5)
                            )
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { onSelect(scope) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, metrics.pageMargin)
        .padding(.bottom, 8)
    }
}

struct HistoryResultBar: View {
    @Environment(\.aurora) private var c
    @Environment(\.screenMetrics) private var metrics
    let count: Int
    let sortOrder: HistorySortOrder

    var body: some View {
        HStack {
            Text("全库命中 %d 条".localized(count))
                .font(.system(size: 11.5))
                .foregroundStyle(c.textSecondary)
            Spacer(minLength: 0)
            Text(sortOrder.title)
                .font(.system(size: 11.5))
                .foregroundStyle(c.textTertiary)
        }
        .padding(.horizontal, metrics.pageMargin)
        .padding(.bottom, 9)
    }
}

// MARK: - 分组头

struct HistorySectionHeader: View {
    @Environment(\.aurora) private var c
    @Environment(\.screenMetrics) private var metrics
    let section: HistorySection

    var body: some View {
        HStack(spacing: 8) {
            Text(section.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(c.textTertiary)
            if let detail = section.detail {
                Text(detail)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(c.textTertiary.opacity(0.8))
            }
            Text("%d 条".localized(section.count))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(c.textTertiary.opacity(0.8))
            Rectangle().fill(c.line).frame(height: 0.5)
        }
        .padding(.horizontal, metrics.pageMargin)
        // 设计稿 .group{padding:13px 16px 7px}：顶部 13pt 是分组之间的呼吸，
        // 底部 7pt 贴合首行卡片；不用 .vertical 对称值，否则组头离上一组太近。
        .padding(.top, 13)
        .padding(.bottom, 7)
        .background(c.backgroundGrouped)
    }
}

// MARK: - 空态

struct HistoryEmptyState: View {
    @Environment(\.aurora) private var c
    @Environment(\.screenMetrics) private var metrics
    let isSearching: Bool
    let onCreate: () -> Void
    let onClearSearch: () -> Void
    let onClearFilter: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(c.surface2)
                    .overlay(
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .strokeBorder(c.line, lineWidth: 0.5)
                    )
                    .frame(width: 92, height: 92)
                Image(systemName: isSearching ? "magnifyingglass" : "waveform")
                    .font(.system(size: 36, weight: .medium))
                    .foregroundStyle(c.accent)
                Circle()
                    .strokeBorder(c.line2, style: StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .frame(width: 120, height: 120)
            }

            Text(isSearching ? "没有匹配的音频".localized() : "还没有生成过音频".localized())
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(c.textPrimary)

            if isSearching {
                Text("换个关键词，或清除筛选条件再试试。".localized())
                    .font(.system(size: 12.5))
                    .foregroundStyle(c.textTertiary)
                    .multilineTextAlignment(.center)
                HStack(spacing: 10) {
                    SecondaryButton(title: "换个关键词".localized(), isFullWidth: false, action: onClearSearch)
                    SecondaryButton(title: "清除筛选".localized(), isFullWidth: false, action: onClearFilter)
                }
            } else {
                Text("写一段文字、挑一个音色，第一条作品就会出现在这里。".localized())
                    .font(.system(size: 12.5))
                    .foregroundStyle(c.textTertiary)
                    .multilineTextAlignment(.center)
                Button(action: onCreate) {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 14, weight: .semibold))
                        Text("去创作".localized())
                            .font(.system(size: 13.5, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .frame(height: 38)
                    .background(Capsule(style: .continuous).fill(c.ctaGradient))
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 44)
    }
}
