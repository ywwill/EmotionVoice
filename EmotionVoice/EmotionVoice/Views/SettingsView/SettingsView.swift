//
//  SettingsView.swift
//  EmotionVoice
//
//  Created by young on 2026/8/8.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// 设置
struct SettingsView: View {

    @EnvironmentObject var appState: AppState

    @State private var selectedCategory: SettingsCategory = .voice

    @State private var showingDirectoryPicker: Bool = false

    enum SettingsCategory: String, CaseIterable, Identifiable {
        case voice = "语音合成"
        case file = "文件"

        var id: String { rawValue }
        var displayName: String { rawValue.localized() }

        var icon: String {
            switch self {
            case .voice: return "waveform"
            case .file: return "folder"
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
        case .file: return "管理文件存储与缓存".localized()
        }
    }

    // MARK: - 内容

    @ViewBuilder
    private func content(for cat: SettingsCategory) -> some View {
        switch cat {
        case .voice:      voiceContent
        case .file:       fileContent
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
                        Picker("", selection: $appState.defaultFormat) {
                            Text("MP3 (推荐)").tag("MP3")
                            Text("WAV").tag("WAV")
                            Text("PCM").tag("PCM")
                            Text("Opus").tag("Opus")
                        }
                        .labelsHidden()
                        .frame(width: 220)
                    }
                )

                divider()

                settingRow(
                    label: "采样率".localized(),
                    desc: "音频质量".localized(),
                    control: {
                        Picker("", selection: Binding(
                            get: { appState.defaultSampleRate },
                            set: { appState.defaultSampleRate = $0 }
                        )) {
                            ForEach(Constants.sampleRates) { item in
                                Text("\(item.displayName) - \(item.useCase)").tag(item.rate)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 280)
                    }
                )
            }
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
                        HStack() {
                            if let exportDir = appState.exportDirectory {
                                Text(exportDir.path)
                                    .font(AppFont.monoMedium)
                                    .foregroundStyle(AppColor.textSecondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .frame(maxWidth: 240)
                                    .help(exportDir.path)
                            } else {
                                Text("未设置".localized())
                                    .font(AppFont.monoMedium)
                                    .foregroundStyle(AppColor.textTertiary)
                            }
                            Button {
                                selectExportDirectory()
                            } label: {
                                Text(appState.exportDirectory == nil ? "打开...".localized() : "更改".localized())
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
        .fileImporter(
            isPresented: $showingDirectoryPicker,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    // 获取安全访问的 bookmark 数据
                    if url.startAccessingSecurityScopedResource() {
                        appState.exportDirectory = url
                        url.stopAccessingSecurityScopedResource()
                    } else {
                        // 如果无法访问安全范围资源，直接使用路径
                        appState.exportDirectory = url
                    }
                }
            case .failure:
                break
            }
        }
    }

    private func selectExportDirectory() {
        showingDirectoryPicker = true
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

    private func divider() -> some View {
        Divider()
            .background(AppColor.borderSubtle)
            .padding(.horizontal, 20)
    }
}
