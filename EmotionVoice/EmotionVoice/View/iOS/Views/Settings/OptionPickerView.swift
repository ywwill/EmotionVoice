//
//  OptionPickerView.swift
//  iOSEmora
//
//  设置里的「默认格式」「采样率」选项面板 —— **就地 sheet，不再 push 二级页**。
//
//  macOS 上这两项是 220/280pt 宽的下拉菜单，iOS 换成半高 sheet 里的单勾选列表：
//  右侧恒留 17pt 勾位 + 副标题说明，选中即写入 UserDefaults（AppState 的 didSet
//  负责），与工作台里的值双向同步；右上角「完成」/ 左上角 ✕ 收起。
//
//  ⚠️ 不再走 `Route`，所以导航栈里没有它 —— 收起后直接看到设置行上的新值。
//

import SwiftUI

/// 选择种类
enum SettingsOptionKind: Identifiable {
    case defaultFormat
    case sampleRate

    var id: String {
        switch self {
        case .defaultFormat: return "defaultFormat"
        case .sampleRate:    return "sampleRate"
        }
    }

    /// 行数（sheet 高度按它算，避免固定 detent 在小列表下留一大片空白）
    var optionCount: Int {
        switch self {
        case .defaultFormat: return 2
        case .sampleRate:    return Constants.sampleRates.count
        }
    }

    var title: String {
        switch self {
        case .defaultFormat: return "默认格式".localized()
        case .sampleRate:    return "采样率".localized()
        }
    }

    var groupTitle: String {
        switch self {
        case .defaultFormat: return "音频格式".localized()
        case .sampleRate:    return "音频质量".localized()
        }
    }

    var footnote: String {
        switch self {
        case .defaultFormat: return "MP3 体积更小，WAV 保真度更高。".localized()
        case .sampleRate:    return "更高的采样率意味着更大的文件。WAV 每秒字节数 = 采样率 × 2。".localized()
        }
    }
}

struct OptionPickerSheet: View {
    @Environment(\.aurora) private var c
    @Environment(\.screenMetrics) private var metrics
    @Environment(\.dismiss) private var dismiss

    @EnvironmentObject private var appState: AppState

    let kind: SettingsOptionKind

    var body: some View {
        VStack(spacing: 0) {
            SheetNavBar(
                title: kind.title,
                leading: {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 19, weight: .medium))
                            .foregroundStyle(c.textTertiary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("关闭".localized())
                },
                trailing: {
                    Button { dismiss() } label: {
                        Text("完成".localized())
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(c.accent)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            )

            ScrollView {
                VStack(spacing: 0) {
                    GroupTitle(text: kind.groupTitle, topPadding: 6)

                    VStack(spacing: 0) {
                        ForEach(options.indices, id: \.self) { i in
                            optionRow(options[i])
                            if i != options.count - 1 {
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

                    Text(kind.footnote)
                        .font(.system(size: 12))
                        .foregroundStyle(c.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, metrics.pageMargin + 16)
                        .padding(.top, 8)

                    Spacer(minLength: 20)
                }
            }
        }
        .background(c.backgroundGrouped)
    }

    /// sheet 首选高度：导航栏 + 分组标题 + 行 + 脚注，按行数算出来再夹一下上下限
    static func preferredDetentHeight(for kind: SettingsOptionKind) -> CGFloat {
        let raw: CGFloat = 53 + 33 + CGFloat(kind.optionCount) * 48 + 44
        return max(240, min(raw, 520))
    }

    // MARK: 选项

    private struct Option {
        let title: String
        let subtitle: String
        let isSelected: Bool
        let select: () -> Void
    }

    private var options: [Option] {
        switch kind {
        case .defaultFormat:
            // 与工作台的格式分段控件同源：只有 mp3 / wav 两项
            return ["mp3", "wav"].map { fmt in
                Option(title: fmt.uppercased(),
                       subtitle: Self.formatSubtitle(fmt),
                       isSelected: appState.defaultFormat.lowercased() == fmt.lowercased()) {
                    appState.defaultFormat = fmt.uppercased()
                }
            }
        case .sampleRate:
            return Constants.sampleRates.map { item in
                Option(title: item.displayName,
                       subtitle: item.useCase,
                       isSelected: appState.defaultSampleRate == item.rate) {
                    appState.defaultSampleRate = item.rate
                }
            }
        }
    }

    private func optionRow(_ option: Option) -> some View {
        Button(action: option.select) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(option.title)
                        .font(.system(size: 16.5, design: .monospaced))
                        .foregroundStyle(c.textPrimary)
                    Text(option.subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(option.isSelected ? c.textSecondary : c.textTertiary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                // 恒留 17pt 勾位，避免勾选时文字横向跳动
                Group {
                    if option.isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(c.accent)
                    } else {
                        Color.clear
                    }
                }
                .frame(width: 17, height: 17)
            }
            .padding(.horizontal, 14)
            .frame(minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(option.isSelected ? c.accentSoft : Color.clear)
    }

    // MARK: 文案

    private static func formatSubtitle(_ fmt: String) -> String {
        switch fmt.lowercased() {
        case "mp3": return "压缩率高，体积小，适合分享".localized()
        case "wav": return "无损原始 PCM，适合二次编辑".localized()
        default:    return ""
        }
    }
}
