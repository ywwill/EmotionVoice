//
//  SettingsView.swift
//  iOSEmora
//
//  设置页（齿轮 push 进当前标签的导航栈）
//
//  macOS 的「我的 / 积分中心」整块并进这里，且按需求**删掉五组桌面专属项**：
//  主题 / 语言 / 导出目录 / 自动清理缓存 / 设备标识
//  —— iOS 的外观与语言由系统设置接管，导出走分享面板没有常驻目录，
//  缓存交给系统，设备标识随 Keychain 走。
//
//  只留三组：账户（购买 + 记录）· 语音合成（默认格式 / 采样率）· 关于（版本）。
//

import SwiftUI

struct SettingsView: View {
    @Environment(\.aurora) private var c
    @Environment(\.screenMetrics) private var metrics

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var uiState: IOSUIState
    @EnvironmentObject private var router: TabRouter

    /// 积分记录总条数（首屏取一次，进入二级页后再由二级页自己翻页）
    @State private var recordCount: Int = 0

    /// 语音合成两项**就地弹 sheet**（`defaultFormat` / `sampleRate`），不再 push 二级页
    @State private var optionSheet: SettingsOptionKind?

    private var versionText: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        return "\(short)"
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                accountCard
                    .padding(.horizontal, metrics.pageMargin)
                    .padding(.top, 14)
                    .padding(.bottom, 18)

                recordsBlock

                GroupTitle(text: "语音合成".localized(), topPadding: 22)
                synthBlock
                footnote("与工作台里的值双向同步，改动即写入 UserDefaults。".localized())

                GroupTitle(text: "关于".localized(), topPadding: 20)
                aboutBlock

                Spacer(minLength: 24)
            }
        }
        .background(c.backgroundGrouped)
        .navigationTitle("设置".localized())
        .navigationBarTitleDisplayMode(.inline)
        .task {
            recordCount = CreditsService.shared.fetchCreditRecords(page: 1).totalCount
        }
        .sheet(item: $optionSheet) { kind in
            OptionPickerSheet(kind: kind)
                .presentationDetents([.height(OptionPickerSheet.preferredDetentHeight(for: kind)),
                                      .large])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: 账户卡（购买入口）

    private var accountCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("当前余额".localized())
                    .font(.system(size: 11.5, weight: .semibold))
                    .tracking(0.9)
                    .foregroundStyle(c.textTertiary)
                HStack(spacing: 4) {
                    Circle()
                        .fill(c.success)
                        .frame(width: 5, height: 5)
                    Text("永久有效".localized())
                        .font(.system(size: 11.5))
                        .foregroundStyle(c.textSecondary)
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(formatCredits(appState.creditsBalance))
                    .font(AuroraFont.balance)
                    .foregroundStyle(c.accent)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text("积分".localized())
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(c.textSecondary)
            }
            .padding(.top, 6)

            HStack(spacing: 5) {
                Image(systemName: "info.circle")
                    .font(.system(size: 12))
                Text("2 积分 / 100 字符 · 中日韩按 2 字符计".localized())
                    .font(.system(size: 12))
            }
            .foregroundStyle(c.textTertiary)
            .padding(.top, 8)

            PrimaryButton(title: "购买积分".localized(), systemImage: "diamond.fill", height: 42) {
                uiState.purchaseSheetPresented = true
            }
            .padding(.top, 14)
        }
        .padding(.horizontal, 18)
        .padding(.top, 20)
        .padding(.bottom, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AuroraRadius.xl, style: .continuous)
                .fill(c.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: AuroraRadius.xl, style: .continuous)
                        .strokeBorder(c.line, lineWidth: 0.5)
                )
        )
        .overlay(alignment: .topTrailing) {
            // 右上角的柔光：设计稿里的 radial-gradient 装饰
            Circle()
                .fill(
                    RadialGradient(colors: [c.accent.opacity(0.18), .clear],
                                   center: .center,
                                   startRadius: 0,
                                   endRadius: 108)
                )
                .frame(width: 216, height: 216)
                .offset(x: 76, y: -76)
                .allowsHitTesting(false)
        }
        // 柔光要裁在卡片圆角内，否则会溢出到分组背景上
        .clipShape(RoundedRectangle(cornerRadius: AuroraRadius.xl, style: .continuous))
    }

    // MARK: 积分记录

    private var recordsBlock: some View {
        Button { router.push(.creditRecords) } label: {
            NavigationRow(title: "积分记录".localized(),
                          iconSystemName: "clock",
                          iconGradient: [Color(hex: 0xFFB457), Color(hex: 0xF2703A)],
                          value: "%d 条".localized(recordCount))
        }
        .buttonStyle(.plain)
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
    }

    // MARK: 语音合成

    private var synthBlock: some View {
        VStack(spacing: 0) {
            Button { optionSheet = .defaultFormat } label: {
                NavigationRow(title: "默认格式".localized(),
                              iconSystemName: "doc.fill",
                              iconGradient: [Color(hex: 0xFFB457), Color(hex: 0xF2703A)],
                              value: appState.defaultFormat.uppercased())
            }
            .buttonStyle(.plain)

            Button { optionSheet = .sampleRate } label: {
                NavigationRow(title: "采样率".localized(),
                              iconSystemName: "waveform",
                              iconGradient: [Color(hex: 0x74B9FF), Color(hex: 0x3B74D9)],
                              value: sampleRateText,
                              showsSeparator: false)
            }
            .buttonStyle(.plain)
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
    }

    private var sampleRateText: String {
        let v = Double(appState.defaultSampleRate) / 1000.0
        if v == v.rounded() { return String(format: "%.0f kHz", v) }
        return String(format: "%.2f kHz", v)
    }

    // MARK: 关于

    private var aboutBlock: some View {
        NavigationRow(title: "版本".localized(),
                      value: versionText,
                      accessory: .none,
                      showsSeparator: false)
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
    }

    private func footnote(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(c.textTertiary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, metrics.pageMargin + 16)
            .padding(.top, 6)
    }
}
