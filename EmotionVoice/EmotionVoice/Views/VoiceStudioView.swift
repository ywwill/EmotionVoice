//
//  VoiceStudioView.swift
//  EmotionVoice
//
//  Created by young on 2026/8/8.
//

import SwiftUI

/// 语音合成工作台
struct VoiceStudioView: View {

    @EnvironmentObject var appState: AppState
    @StateObject private var vm = VoiceStudioViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 工具栏
            toolbar

            // 内容：左右分栏
            HStack(alignment: .top, spacing: 16) {
                editorColumn
                rightPanel
            }
            .padding(20)
            .padding(.bottom, 16)
        }
        .onAppear {
            if let v = appState.selectedVoice {
                vm.selectedVoiceKey = v.key
            }
        }
    }

    // MARK: - 工具栏

    private var toolbar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("文字转语音".localized())
                    .font(.system(size: 16, weight: .semibold))
                Text("将文字转化为带有情感的语音内容".localized())
                    .font(AppFont.bodySmall)
                    .foregroundStyle(AppColor.textTertiary)
            }
            Spacer()
            ToolbarButton(title: "清空".localized(), icon: "🗑") {
                vm.clearText()
            }
            ToolbarButton(title: "格式化".localized(), icon: "✎") {
                // 演示：不做实际格式化
            }
            ToolbarButton(title: "高级设置".localized(), icon: "⚙") {
                // 演示
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

    // MARK: - 编辑器列

    private var editorColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            // 模型/音色配置条
            configBar

            // 文本编辑区
            textEditorCard

            // 情感面板
            emotionCard
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 配置条

    private var configBar: some View {
        HStack(spacing: 12) {
            // 模型
            HStack(spacing: 6) {
                Text("模型".localized())
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textTertiary)
                Picker("", selection: $vm.model) {
                    ForEach(vm.availableModels, id: \.self) { m in
                        Text(m == Constants.modelPlus ? "Plus (高质量)".localized()
                             : "Flash (快速)".localized())
                            .tag(m)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 200)
            }

            Rectangle().fill(AppColor.borderSubtle).frame(width: 1, height: 20)

            // 音色
            HStack(spacing: 6) {
                Text("音色".localized())
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textTertiary)
                Picker("", selection: $vm.selectedVoiceKey) {
                    ForEach(appState.voices) { voice in
                        Text(voice.name).tag(voice.key)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(width: 160)
            }

            Spacer()

            if vm.model == Constants.modelPlus {
                Text("⭐ 推荐".localized())
                    .font(AppFont.label)
                    .foregroundStyle(AppColor.accentGlow)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(AppColor.accentPrimary.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
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

    // MARK: - 文本编辑器

    private var textEditorCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("文本输入区".localized())
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                HStack(spacing: 12) {
                    Text("\(vm.charCount) 字".localized())
                    Text("·")
                    Text("约 \(vm.estimatedPoints) 积分".localized())
                }
                .font(AppFont.monoSmall)
                .foregroundStyle(AppColor.textTertiary)
            }
            .padding(.bottom, 12)
            .overlay(alignment: .bottom) {
                Divider().background(AppColor.borderSubtle)
            }

            // 编辑区
            ZStack(alignment: .topLeading) {
                if vm.text.isEmpty {
                    Text("插入文本或粘贴内容".localized())
                        .font(AppFont.bodyLarge)
                        .foregroundStyle(AppColor.textTertiary)
                        .padding(.top, 4)
                        .allowsHitTesting(false)
                }

                EmotionHighlightedTextEditor(
                    text: $vm.text,
                    emotions: Constants.emotions + Constants.richLanguageTags
                )
                .font(AppFont.bodyLarge)
                .foregroundStyle(AppColor.textPrimary)
            }
            .frame(minHeight: 220)
            .scrollContentBackground(.hidden)

            HStack(spacing: 16) {
                Text("输入 [[]] 可快速插入情感标签".localized())
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textTertiary)
                Spacer()
                Button {
                    vm.appendEmotion(tag: "excited")
                } label: {
                    Label("[excited]", systemImage: "plus.circle.fill")
                        .font(AppFont.monoSmall)
                        .foregroundStyle(AppColor.accentPrimary)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 12)
            .overlay(alignment: .top) {
                Divider().background(AppColor.borderSubtle)
            }
        }
        .padding(20)
        .background(AppColor.bgSecondary)
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.large)
                .stroke(AppColor.borderSubtle, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.large))
    }

    // MARK: - 情感卡片

    private var emotionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("情感控制面板".localized())
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("已选 \(vm.selectedEmotions.count) 个".localized())
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textTertiary)
            }

            // 情感网格
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 10),
                spacing: 6
            ) {
                ForEach(Constants.emotions) { emotion in
                    EmotionButton(
                        emotion: emotion,
                        isSelected: vm.selectedEmotions.contains(emotion.tag)
                    ) {
                        if vm.selectedEmotions.contains(emotion.tag) {
                            vm.selectedEmotions.remove(emotion.tag)
                        } else {
                            vm.selectedEmotions.insert(emotion.tag)
                            vm.appendEmotion(tag: emotion.tag)
                        }
                    }
                }
            }

            Divider().background(AppColor.borderSubtle).padding(.vertical, 6)

            // 富语言
            VStack(alignment: .leading, spacing: 8) {
                Text("富语言效果".localized())
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textTertiary)

                HStack(spacing: 6) {
                    ForEach(Constants.richLanguageTags) { tag in
                        Button {
                            vm.appendEmotion(tag: tag.tag)
                        } label: {
                            HStack(spacing: 4) {
                                Text(tag.emoji)
                                Text("[\(tag.tag)]")
                                    .font(AppFont.monoSmall)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(AppColor.bgTertiary)
                            .overlay(
                                RoundedRectangle(cornerRadius: AppRadius.small)
                                    .stroke(AppColor.borderSubtle, lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: AppRadius.small))
                            .foregroundStyle(AppColor.textSecondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Divider().background(AppColor.borderSubtle).padding(.vertical, 6)

            // 语速/音量
            HStack(alignment: .top, spacing: 16) {
                LabeledSlider(
                    label: "语速".localized(),
                    value: $vm.rate,
                    range: 0.5...2.0,
                    step: 0.1,
                    unit: "x",
                    displayValue: String(format: "%.1fx", vm.rate)
                )

                LabeledSlider(
                    label: "音量".localized(),
                    value: $vm.volume,
                    range: 0...100,
                    step: 5,
                    unit: "%",
                    displayValue: "\(Int(vm.volume))%"
                )
            }
        }
        .padding(18)
        .background(AppColor.bgSecondary)
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.large)
                .stroke(AppColor.borderSubtle, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.large))
    }

    // MARK: - 右侧面板

    private var rightPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            languageCard
            voiceCard
            nlCard
            generateBar
        }
        .frame(width: 320)
    }

    private var languageCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("🌐 语言与采样率".localized())
                .font(.system(size: 13, weight: .semibold))

            HStack(spacing: 4) {
                ForEach(Constants.languages) { lang in
                    let selected = vm.language == lang
                    Button {
                        vm.language = lang
                    } label: {
                        Text(lang.name)
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(
                                selected ? AppColor.bgElevated : AppColor.bgTertiary
                            )
                            .foregroundStyle(
                                selected ? AppColor.textPrimary : AppColor.textSecondary
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }
            }

            HStack {
                Text("采样率".localized())
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textTertiary)
                Spacer()
                HStack(spacing: 4) {
                    ForEach(Constants.sampleRates, id: \.self) { rate in
                        let selected = vm.sampleRate == rate
                        Button {
                            vm.sampleRate = rate
                        } label: {
                            Text("\(rate / 1000) kHz")
                                .font(AppFont.monoSmall)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(
                                    selected ? AppColor.accentPrimary.opacity(0.2) : AppColor.bgTertiary
                                )
                                .foregroundStyle(
                                    selected ? AppColor.accentPrimary : AppColor.textSecondary
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColor.bgSecondary)
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.large)
                .stroke(AppColor.borderSubtle, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.large))
    }

    private var voiceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("🎭 音色切换".localized())
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("旗舰 2 + 基础 500+".localized())
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textTertiary)
            }

            // 当前音色
            if let voice = vm.voice {
                HStack(spacing: 10) {
                    AvatarView(text: voice.avatar, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(voice.name)
                            .font(.system(size: 13, weight: .semibold))
                        HStack(spacing: 4) {
                            if voice.isPremium {
                                Text("⭐ 旗舰".localized())
                                    .font(AppFont.monoSmall)
                                    .foregroundStyle(AppColor.accentGlow)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 1)
                                    .background(AppColor.accentPrimary.opacity(0.15))
                                    .clipShape(RoundedRectangle(cornerRadius: 3))
                            }
                            Text(voice.desc)
                                .font(AppFont.caption)
                                .foregroundStyle(AppColor.textSecondary)
                        }
                    }
                    Spacer()
                    Button {
                        // 演示：切换到下一个
                        if let idx = appState.voices.firstIndex(where: { $0.key == vm.selectedVoiceKey }),
                           idx + 1 < appState.voices.count {
                            vm.selectedVoiceKey = appState.voices[idx + 1].key
                        }
                    } label: {
                        Text("🔄 切换")
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.textSecondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(AppColor.bgTertiary)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }

                // 简易播放进度条
                HStack(spacing: 8) {
                    Text("▶")
                        .font(.system(size: 12))
                        .foregroundStyle(AppColor.accentPrimary)
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(AppColor.bgTertiary)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(AppColor.accentPrimary)
                                .frame(width: geo.size.width * 0.3)
                        }
                    }
                    .frame(height: 3)
                    Text("0:08")
                        .font(AppFont.monoSmall)
                        .foregroundStyle(AppColor.textTertiary)
                }
            }

            Divider().background(AppColor.borderSubtle)

            // 备选音色列表
            VStack(spacing: 4) {
                ForEach(appState.voices.prefix(4)) { v in
                    VoiceRow(voice: v, isSelected: vm.selectedVoiceKey == v.key) {
                        vm.selectedVoiceKey = v.key
                        appState.selectedVoice = v
                    }
                }
            }
        }
        .padding(16)
        .background(AppColor.bgSecondary)
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.large)
                .stroke(AppColor.borderSubtle, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.large))
    }

    private var nlCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("📋 语音指令".localized())
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("自然语言".localized())
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textTertiary)
            }

            // 预设芯片
            FlowLayout(spacing: 6) {
                ForEach(vm.nlPresets, id: \.self) { preset in
                    Button {
                        vm.applyPreset(preset)
                    } label: {
                        Text(preset)
                            .font(AppFont.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(AppColor.bgTertiary)
                            .foregroundStyle(AppColor.textSecondary)
                            .clipShape(Capsule())
                            .overlay(
                                Capsule().stroke(AppColor.borderSubtle, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }

            // 输入框
            VStack(alignment: .leading, spacing: 4) {
                if vm.nlInstruction.isEmpty {
                    Text("或自定义描述你想听到的声音...".localized())
                        .font(AppFont.bodyMedium)
                        .foregroundStyle(AppColor.textTertiary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 8)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $vm.nlInstruction)
                    .font(AppFont.bodyMedium)
                    .foregroundStyle(AppColor.textPrimary)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 4)
            }
            .background(AppColor.bgTertiary)
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.small)
                    .stroke(AppColor.borderSubtle, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.small))
            .frame(height: 80)

            HStack {
                Text("💡 详细描述 = 更好的效果".localized())
                    .font(AppFont.monoSmall)
                    .foregroundStyle(AppColor.textTertiary)
                Spacer()
                Text("\(vm.nlInstruction.count) / 200")
                    .font(AppFont.monoSmall)
                    .foregroundStyle(AppColor.textTertiary)
            }
        }
        .padding(16)
        .background(AppColor.bgSecondary)
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.large)
                .stroke(AppColor.borderSubtle, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.large))
    }

    private var generateBar: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("💎 本次消耗".localized())
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textTertiary)
                Spacer()
                Text("约 \(vm.estimatedPoints) 积分".localized())
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppColor.accentPrimary)
            }

            HStack(spacing: 8) {
                SecondaryButton(title: "预览".localized(), icon: "play.fill") {
                    // 演示
                }
                PrimaryButton(title: "生成音频".localized(), icon: "waveform") {
                    vm.generate { success in
                        if success {
                            appState.refreshCredits()
                        }
                    }
                }
            }

            if vm.isGenerating {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.7)
                        .tint(AppColor.accentPrimary)
                    Text("正在生成...".localized())
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textTertiary)
                }
            }

            if let err = vm.lastError {
                Text(err)
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.statusError)
            }
        }
        .padding(16)
        .background(AppColor.bgSecondary)
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.large)
                .stroke(AppColor.borderSubtle, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.large))
    }
}

// MARK: - 情感按钮

private struct EmotionButton: View {
    let emotion: EmotionItem
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(emotion.emoji)
                    .font(.system(size: 18))
                Text(emotion.label)
                    .font(.system(size: 10))
                    .foregroundStyle(
                        isSelected ? AppColor.accentPrimary : AppColor.textSecondary
                    )
            }
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity)
            .background(
                isSelected
                ? AppColor.accentPrimary.opacity(0.15)
                : AppColor.bgTertiary
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.small)
                    .stroke(
                        isSelected ? AppColor.accentPrimary.opacity(0.5) : AppColor.borderSubtle,
                        lineWidth: 1
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.small))
            .contentShape(RoundedRectangle(cornerRadius: AppRadius.small))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 音色行

private struct VoiceRow: View {
    let voice: Voice
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                AvatarView(text: voice.avatar, size: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(voice.name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(AppColor.textPrimary)
                    Text(voice.desc)
                        .font(AppFont.monoSmall)
                        .foregroundStyle(AppColor.textTertiary)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(AppColor.accentPrimary)
                } else {
                    Image(systemName: "play")
                        .foregroundStyle(AppColor.textTertiary)
                        .font(.system(size: 11))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                isSelected ? AppColor.bgTertiary : Color.clear
            )
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.small))
        }
        .buttonStyle(.plain)
    }
}