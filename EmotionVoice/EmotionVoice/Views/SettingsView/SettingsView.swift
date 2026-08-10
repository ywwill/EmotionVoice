//
//  SettingsView.swift
//  EmotionVoice
//
//  Created by young on 2026/8/8.
//

import SwiftUI

/// 设置
struct SettingsView: View {

    @EnvironmentObject var appState: AppState

    @State private var selectedCategory: SettingsCategory = .voice

    enum SettingsCategory: String, CaseIterable, Identifiable {
        case voice = "语音合成"
        case shortcut = "快捷键"
        case appearance = "外观"
        case file = "文件"
        case notification = "通知"
        case language = "语言"
        case about = "关于"

        var id: String { rawValue }
        var displayName: String { rawValue.localized() }

        var icon: String {
            switch self {
            case .voice: return "waveform"
            case .shortcut: return "keyboard"
            case .appearance: return "paintbrush.fill"
            case .file: return "folder"
            case .notification: return "bell.fill"
            case .language: return "globe"
            case .about: return "info.circle.fill"
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            // 左侧分类
            settingsNav
                .frame(width: 200)

            Divider().background(AppColor.borderSubtle)

            // 右侧内容
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    settingsHeader
                    content(for: selectedCategory)
                }
                .padding(32)
                .frame(maxWidth: 800, alignment: .leading)
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - 左侧导航

    private var settingsNav: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("设置分类".localized())
                .font(AppFont.label)
                .foregroundStyle(AppColor.textTertiary)
                .textCase(.uppercase)
                .tracking(0.06)
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

            ForEach(SettingsCategory.allCases) { cat in
                Button {
                    selectedCategory = cat
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: cat.icon)
                            .font(.system(size: 13))
                            .frame(width: 16)
                        Text(cat.displayName)
                            .font(.system(size: 13, weight: .medium))
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        selectedCategory == cat
                        ? AppColor.bgElevated
                        : Color.clear
                    )
                    .foregroundStyle(
                        selectedCategory == cat
                        ? AppColor.textPrimary
                        : AppColor.textSecondary
                    )
                    .clipShape(RoundedRectangle(cornerRadius: AppRadius.small))
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
                .padding(.horizontal, 12)
            }
            Spacer()
        }
        .padding(.vertical, 24)
        .background(AppColor.bgSidebar.opacity(0.5))
    }

    // MARK: - 头部

    private var settingsHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(selectedCategory.displayName)
                    .font(.system(size: 22, weight: .semibold))
                Text(headerSubtitle)
                    .font(AppFont.bodyMedium)
                    .foregroundStyle(AppColor.textTertiary)
            }
            Spacer()
            Button {} label: {
                Text("完成".localized())
                    .font(.system(size: 12, weight: .medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(AppColor.borderMedium, lineWidth: 1)
                    )
                    .foregroundStyle(AppColor.textPrimary)
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
        }
        .padding(.bottom, 8)
        .overlay(alignment: .bottom) {
            Divider().background(AppColor.borderSubtle)
        }
    }

    private var headerSubtitle: String {
        switch selectedCategory {
        case .voice: return "配置音色和音频输出选项".localized()
        case .shortcut: return "自定义快捷键以提升效率".localized()
        case .appearance: return "个性化应用外观".localized()
        case .file: return "管理文件存储与缓存".localized()
        case .notification: return "配置应用通知".localized()
        case .language: return "选择界面语言".localized()
        case .about: return "应用信息与协议".localized()
        }
    }

    // MARK: - 内容

    @ViewBuilder
    private func content(for cat: SettingsCategory) -> some View {
        switch cat {
        case .voice:      voiceContent
        case .shortcut:   shortcutContent
        case .appearance: appearanceContent
        case .file:       fileContent
        case .notification: notificationContent
        case .language:   languageContent
        case .about:      aboutContent
        }
    }

    // MARK: 语音合成

    private var voiceContent: some View {
        VStack(spacing: 20) {
            sectionCard(icon: "🎭", title: "默认音色".localized()) {
                settingRow(
                    label: "默认音色".localized(),
                    desc: "新项目自动使用".localized(),
                    control: {
                        Picker("", selection: Binding(
                            get: { appState.selectedVoice?.key ?? Constants.defaultVoice },
                            set: { key in
                                if let v = appState.voices.first(where: { $0.key == key }) {
                                    appState.selectedVoice = v
                                }
                            })) {
                            ForEach(appState.voices) { v in
                                Text("\(v.name) \(v.isPremium ? "(旗舰)".localized() : "")")
                                    .tag(v.key)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 220)
                    }
                )
            }

            sectionCard(icon: "🔊", title: "音频输出".localized()) {
                settingRow(
                    label: "默认格式".localized(),
                    desc: "导出音频文件格式".localized(),
                    control: {
                        Picker("", selection: .constant("MP3")) {
                            Text("MP3 (推荐)").tag("MP3")
                            Text("WAV").tag("WAV")
                            Text("OGG").tag("OGG")
                            Text("FLAC").tag("FLAC")
                        }
                        .labelsHidden()
                        .frame(width: 220)
                    }
                )

                divider()

                settingRowWithTrailing(
                    label: "采样率".localized(),
                    desc: "音频质量".localized(),
                    control: {
                        Picker("", selection: .constant(48)) {
                            Text("48 kHz (推荐)").tag(48)
                            Text("44.1 kHz").tag(44)
                            Text("24 kHz").tag(24)
                        }
                        .labelsHidden()
                        .frame(width: 220)
                    },
                    trailing: {
                        Text("24-bit")
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.textTertiary)
                    }
                )

                divider()

                settingRow(
                    label: "自动添加元数据".localized(),
                    desc: "嵌入标题、艺术家信息".localized(),
                    control: { Toggle("", isOn: .constant(true))
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .tint(AppColor.accentPrimary) }
                )
            }
        }
    }

    // MARK: 快捷键

    private var shortcutContent: some View {
        VStack(spacing: 20) {
            sectionCard(icon: "⌨️", title: "快捷键".localized()) {
                shortcutRow("生成语音".localized(), desc: "立即开始合成音频".localized(), keys: ["⌘", "↵"])
                divider()
                shortcutRow("预览播放".localized(), desc: "播放/暂停当前预览".localized(), keys: ["⌘", "P"])
                divider()
                shortcutRow("导出音频".localized(), desc: "导出当前音频文件".localized(), keys: ["⌘", "E"])
                divider()
                shortcutRow("保存草稿".localized(), desc: "保存当前编辑".localized(), keys: ["⌘", "S"])
                divider()
                shortcutRow("切换音色".localized(), desc: "打开音色选择器".localized(), keys: ["⌘", "K"])
            }
        }
    }

    private func shortcutRow(_ label: String, desc: String, keys: [String]) -> some View {
        settingRowWithTrailing(
            label: label,
            desc: desc,
            control: {
                HStack(spacing: 4) {
                    ForEach(keys, id: \.self) { key in
                        Text(key)
                            .font(.system(size: 11, design: .monospaced))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(AppColor.bgTertiary)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(AppColor.borderSubtle, lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                }
            },
            trailing: {
                Button {} label: {
                    Text("编辑".localized())
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textTertiary)
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
            }
        )
    }

    // MARK: 外观

    private var appearanceContent: some View {
        VStack(spacing: 20) {
            sectionCard(icon: "🎨", title: "外观".localized()) {
                settingRow(
                    label: "主题".localized(),
                    desc: "应用外观模式".localized(),
                    control: {
                        HStack(spacing: 16) {
                            radioOption("跟随系统".localized(), isSelected: false)
                            radioOption("浅色".localized(), isSelected: false)
                            radioOption("深色".localized(), isSelected: true)
                        }
                    }
                )

                divider()

                settingRow(
                    label: "情感标签样式".localized(),
                    desc: "在文本编辑器中的标签展示方式".localized(),
                    control: {
                        HStack(spacing: 16) {
                            radioOption("Emoji".localized(), isSelected: false)
                            radioOption("图标".localized(), isSelected: true)
                            radioOption("文字".localized(), isSelected: false)
                        }
                    }
                )
            }
        }
    }

    private func radioOption(_ label: String, isSelected: Bool) -> some View {
        HStack(spacing: 6) {
            ZStack {
                Circle()
                    .stroke(AppColor.borderStrong, lineWidth: 1)
                    .frame(width: 14, height: 14)
                if isSelected {
                    Circle()
                        .fill(AppColor.accentPrimary)
                        .frame(width: 8, height: 8)
                }
            }
            Text(label)
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textPrimary)
        }
    }

    // MARK: 文件

    private var fileContent: some View {
        VStack(spacing: 20) {
            sectionCard(icon: "📁", title: "文件".localized()) {
                settingRow(
                    label: "导出目录".localized(),
                    desc: "音频文件保存位置".localized(),
                    control: {
                        HStack(spacing: 6) {
                            Text("~/Documents/EmotionVoice/")
                                .font(AppFont.monoMedium)
                                .foregroundStyle(AppColor.textSecondary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(AppColor.bgTertiary)
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                            Button {} label: {
                                Text("更改...".localized())
                                    .font(AppFont.caption)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke(AppColor.borderMedium, lineWidth: 1)
                                    )
                                    .foregroundStyle(AppColor.textPrimary)
                            }
                            .buttonStyle(.plain)
                            .pointingHandCursor()
                        }
                    }
                )

                divider()

                settingRow(
                    label: "自动清理缓存".localized(),
                    desc: "定期清理临时文件".localized(),
                    control: {
                        Picker("", selection: .constant(30)) {
                            Text("7 天").tag(7)
                            Text("30 天").tag(30)
                            Text("60 天").tag(60)
                            Text("从不").tag(0)
                        }
                        .labelsHidden()
                        .frame(width: 140)
                    }
                )
            }
        }
    }

    // MARK: 通知

    private var notificationContent: some View {
        VStack(spacing: 20) {
            sectionCard(icon: "🔔", title: "通知".localized()) {
                settingRow(
                    label: "生成完成".localized(),
                    desc: "音频合成完成后通知".localized(),
                    control: { Toggle("", isOn: .constant(true)).labelsHidden().toggleStyle(.switch).tint(AppColor.accentPrimary) }
                )
                divider()
                settingRow(
                    label: "积分不足".localized(),
                    desc: "积分低于 100 时提醒".localized(),
                    control: { Toggle("", isOn: .constant(true)).labelsHidden().toggleStyle(.switch).tint(AppColor.accentPrimary) }
                )
                divider()
                settingRow(
                    label: "系统更新".localized(),
                    desc: "新版本发布时通知".localized(),
                    control: { Toggle("", isOn: .constant(false)).labelsHidden().toggleStyle(.switch).tint(AppColor.accentPrimary) }
                )
            }
        }
    }

    // MARK: 语言

    private var languageContent: some View {
        VStack(spacing: 20) {
            sectionCard(icon: "🌐", title: "语言".localized()) {
                settingRow(
                    label: "界面语言".localized(),
                    desc: "应用界面显示语言".localized(),
                    control: {
                        Picker("", selection: .constant("zh-Hans")) {
                            Text("简体中文").tag("zh-Hans")
                            Text("English").tag("en")
                        }
                        .labelsHidden()
                        .frame(width: 220)
                    }
                )
            }
        }
    }

    // MARK: 关于

    private var aboutContent: some View {
        VStack(spacing: 20) {
            VStack(spacing: 16) {
                Text("EmotionVoice")
                    .font(.system(size: 28, weight: .bold))
                Text("v1.0.0")
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundStyle(AppColor.textTertiary)
                Text("基于阿里云 Qwen-Audio-TTS".localized())
                    .font(AppFont.bodyMedium)
                    .foregroundStyle(AppColor.textSecondary)
                Text("© 2026 EmotionVoice Team")
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textTertiary)
            }
            .padding(40)
            .frame(maxWidth: .infinity)
            .background(AppColor.bgSecondary)
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.large)
                    .stroke(AppColor.borderSubtle, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.large))

            VStack(spacing: 12) {
                aboutButton("检查更新".localized())
                Divider().background(AppColor.borderSubtle)
                aboutButton("用户协议".localized())
                Divider().background(AppColor.borderSubtle)
                aboutButton("隐私政策".localized())
            }
            .background(AppColor.bgSecondary)
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.large)
                    .stroke(AppColor.borderSubtle, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.large))
        }
    }

    private func aboutButton(_ title: String) -> some View {
        Button {} label: {
            HStack {
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppColor.textPrimary)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11))
                    .foregroundStyle(AppColor.textTertiary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
    }

    // MARK: - 通用组件

    @ViewBuilder
    private func sectionCard<Content: View>(icon: String, title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Text(icon)
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColor.textPrimary)
            }
            VStack(spacing: 0) {
                content()
            }
            .background(AppColor.bgSecondary)
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.large)
                    .stroke(AppColor.borderSubtle, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.large))
        }
    }

    @ViewBuilder
    private func settingRow<Control: View>(
        label: String,
        desc: String,
        @ViewBuilder control: () -> Control
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppColor.textPrimary)
                Text(desc)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textTertiary)
            }
            Spacer()
            control()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private func settingRowWithTrailing<Control: View, Trailing: View>(
        label: String,
        desc: String,
        @ViewBuilder control: () -> Control,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppColor.textPrimary)
                Text(desc)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textTertiary)
            }
            Spacer()
            control()
            trailing()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private func divider() -> some View {
        Divider()
            .background(AppColor.borderSubtle)
            .padding(.horizontal, 20)
    }
}