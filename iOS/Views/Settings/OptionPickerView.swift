//
//  OptionPickerView.swift
//  iOSEmora
//
//  二级选择页（macOS 下拉菜单的 iOS 化）
//
//  macOS 设置里的「默认格式」「采样率」是 220/280pt 宽的下拉菜单，
//  iOS 换成 push 的**单勾选列表**：右侧恒留 17pt 勾位 + 副标题说明。
//  外观 / 语言两个 Picker 已被删除，所以这里只有这两处二级页。
//
//  改动即写入 UserDefaults（AppState 的 didSet 负责），并与工作台里的值双向同步。
//

import SwiftUI

/// 选择种类
enum SettingsOptionKind {
    case defaultFormat
    case sampleRate

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

struct OptionPickerView: View {
    @Environment(\.aurora) private var c
    @Environment(\.screenMetrics) private var metrics

    @EnvironmentObject private var appState: AppState

    let kind: SettingsOptionKind

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                GroupTitle(text: kind.groupTitle, topPadding: 16)

                VStack(spacing: 0) {
                    ForEach(options.indices, id: \.self) { i in
                        optionRow(options[i], isLast: i == options.count - 1)
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

                Spacer(minLength: 24)
            }
        }
        .background(c.backgroundGrouped)
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.inline)
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

    private func optionRow(_ option: Option, isLast: Bool) -> some View {
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
