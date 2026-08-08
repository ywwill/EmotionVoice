//
//  StatsView.swift
//  EmotionVoice
//
//  Created by young on 2026/8/8.
//

import SwiftUI

/// 使用统计（简化版）
struct StatsView: View {

    @EnvironmentObject var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            toolbar
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    summaryCards
                    trendSection
                    voiceUsageSection
                }
                .padding(24)
            }
        }
    }

    private var toolbar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("使用统计".localized())
                    .font(.system(size: 16, weight: .semibold))
                Text("追踪你的创作轨迹".localized())
                    .font(AppFont.bodySmall)
                    .foregroundStyle(AppColor.textTertiary)
            }
            Spacer()
            ToolbarButton(title: "导出报告".localized(), icon: "📊", isPrimary: true) {}
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

    private var summaryCards: some View {
        HStack(spacing: 12) {
            statCard(value: "\(appState.monthlyUsed)", label: "积分消耗".localized(), icon: "💎")
            statCard(value: "28", label: "音频生成".localized(), icon: "🎵")
            statCard(value: "12.4h", label: "总时长".localized(), icon: "⏱")
            statCard(value: "18", label: "音色使用".localized(), icon: "🎭")
        }
    }

    private func statCard(value: String, label: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(icon)
                .font(.system(size: 22))
            Text(value)
                .font(.system(size: 24, weight: .bold, design: .monospaced))
                .foregroundStyle(AppColor.textPrimary)
            Text(label)
                .font(AppFont.caption)
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

    private var trendSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("📈 30 天趋势".localized())
                .font(.system(size: 14, weight: .semibold))

            HStack(alignment: .bottom, spacing: 6) {
                ForEach(0..<30, id: \.self) { i in
                    let h = 0.3 + Double((i * 7) % 60) / 100.0
                    VStack {
                        Spacer()
                        RoundedRectangle(cornerRadius: 2)
                            .fill(AppColor.accentPrimary)
                            .frame(height: 120 * h)
                            .opacity(0.4 + h * 0.5)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 140)
            .padding(20)
            .background(AppColor.bgSecondary)
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.large)
                    .stroke(AppColor.borderSubtle, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.large))
        }
    }

    private var voiceUsageSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("🎭 音色使用分布".localized())
                .font(.system(size: 14, weight: .semibold))

            VStack(spacing: 12) {
                voiceUsageRow("龙安灵心", "10 次", 0.35, AppColor.accentPrimary)
                voiceUsageRow("龙安鲁风", "8 次", 0.28, Color(hex: 0x6B8BC9))
                voiceUsageRow("龙安欢", "5 次", 0.18, Color(hex: 0x8AA5A0))
                voiceUsageRow("龙安风悦", "3 次", 0.10, Color(hex: 0xD49B5B))
                voiceUsageRow("其他", "2 次", 0.07, Color(hex: 0x6B6E76))
            }
            .padding(20)
            .background(AppColor.bgSecondary)
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.large)
                    .stroke(AppColor.borderSubtle, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.large))
        }
    }

    private func voiceUsageRow(_ name: String, _ count: String, _ ratio: Double, _ color: Color) -> some View {
        HStack(spacing: 12) {
            Text(name)
                .font(.system(size: 13, weight: .medium))
                .frame(width: 100, alignment: .leading)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(AppColor.bgElevated)
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color)
                        .frame(width: geo.size.width * ratio)
                }
            }
            .frame(height: 8)
            Text(count)
                .font(AppFont.monoSmall)
                .foregroundStyle(AppColor.textTertiary)
                .frame(width: 60, alignment: .trailing)
        }
    }
}