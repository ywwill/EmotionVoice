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
    @ObservedObject private var player = AudioPreviewPlayer.shared
    @State private var showVoiceLibrarySheet: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 工具栏
            toolbar

            // 内容：左 / 右 两列分栏（音色回到 rightPanel）
            HStack(alignment: .top, spacing: 16) {
                editorColumn
                rightPanel
            }
            .padding(20)
            .padding(.bottom, 16)
        }
        .sheet(isPresented: $showVoiceLibrarySheet) {
            VoiceLibrarySheet()
                .frame(width: 1400, height: 880)
        }
        .alert(item: $vm.alertItem) { item in
            Alert(
                title: Text(item.title),
                message: Text(item.message),
                dismissButton: .default(Text("好".localized()))
            )
        }
        .onAppear {
            if let v = appState.selectedVoice {
                vm.selectedVoiceKey = v.key
            }
            // 从设置中读取默认采样率和格式
            vm.sampleRate = appState.defaultSampleRate
            vm.selectedFormat = appState.defaultFormat
        }
        .onChange(of: appState.selectedVoice?.key) { _, newKey in
            // 从音色库跳转过来时同步选中音色
            if let newKey, !newKey.isEmpty {
                vm.selectedVoiceKey = newKey
            }
        }
    }

    // MARK: - 工具栏

    private var toolbar: some View {
        HStack(spacing: 16) {
            // 左侧标题
            VStack(alignment: .leading, spacing: 2) {
                Text("文字转语音".localized())
                    .font(.system(size: 16, weight: .semibold))
                Text("将文字转化为带有情感的语音内容".localized())
                    .font(AppFont.bodySmall)
                    .foregroundStyle(AppColor.textTertiary)
            }

            Spacer(minLength: 16)

            // 右侧：消耗积分 + 操作按钮（generateBar 内联）
            generateBar
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
            // 文本编辑区
            textEditorCard

            // 情感面板
            emotionCard
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                .pointingHandCursor()
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
            }

            // 情感网格
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 10),
                spacing: 6
            ) {
                ForEach(Constants.emotions) { emotion in
                    EmotionButton(
                        emotion: emotion,
                        usageCount: vm.usageCount(for: emotion.tag)
                    ) {
                        vm.appendEmotion(tag: emotion.tag)
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
                        .pointingHandCursor()
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
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                voiceCard
                languageCard
                nlCard
            }
        }
        .frame(width: 320)
    }

    // MARK: - 音色卡片（在 rightPanel 中）

    private var voiceCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("🎭 音色切换".localized())
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("\(appState.voices.count) 个可用".localized())
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textTertiary)
            }

            // 当前音色
            if let voice = vm.voice {
                HStack(spacing: 10) {
                    AvatarView(text: voice.avatar, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(voice.name)
                                .font(.system(size: 13, weight: .semibold))
                            if voice.isPremium {
                                Text("⭐ 旗舰".localized())
                                    .font(AppFont.monoSmall)
                                    .foregroundStyle(AppColor.accentGlow)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 1)
                                    .background(AppColor.accentPrimary.opacity(0.15))
                                    .clipShape(RoundedRectangle(cornerRadius: 3))
                            }
                        }
                        if !voice.desc.isEmpty {
                            Text(voice.desc)
                                .font(AppFont.caption)
                                .foregroundStyle(AppColor.textSecondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                    Button {
                        showVoiceLibrarySheet = true
                    } label: {
                        Text("更换".localized())
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.textSecondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(AppColor.bgTertiary)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(AppColor.borderSubtle, lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .pointingHandCursor()
                }
            }

            Divider().background(AppColor.borderSubtle)

            // 备选音色（精选 4 条）
            VStack(spacing: 4) {
                ForEach(alternateVoices) { v in
                    VoiceRow(
                        voice: v,
                        isSelected: vm.selectedVoiceKey == v.key,
                        isPlaying: player.isPlaying(key: v.key)
                    ) {
                        vm.selectedVoiceKey = v.key
                        appState.selectedVoice = v
                    } onPreview: {
                        if player.isPlaying(key: v.key) {
                            AudioPreviewPlayer.shared.stop()
                        } else {
                            AudioPreviewPlayer.shared.play(key: v.key)
                        }
                    }
                }
            }

            Button {
                showVoiceLibrarySheet = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 10))
                    Text("查看全部音色库".localized())
                        .font(AppFont.caption)
                }
                .foregroundStyle(AppColor.accentPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .background(AppColor.accentPrimary.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.small)
                        .stroke(AppColor.accentPrimary.opacity(0.3), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.small))
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
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

    /// 6 个备选音色：固定 2 旗舰 + 2 中文 + 2 英文（按数据顺序；选中态由 UI 标识）
    private var alternateVoices: [Voice] {
        let all = appState.voices
        let premiumCat = VoiceCategory.premium

        // 旗舰：最多 2 个（不剔除当前选中，保留选中态标识）
        let premium = all.filter { $0.category == premiumCat }
            .prefix(2)

        // 候选：非旗舰的基础音色
        let nonPremium = all.filter { $0.category != premiumCat }

        var zh: [Voice] = []
        var en: [Voice] = []
        for v in nonPremium {
            if v.lang.contains("中文") && zh.count < 2 {
                zh.append(v)
            } else if v.lang.contains("英文") && en.count < 2 {
                en.append(v)
            }
            if zh.count >= 2 && en.count >= 2 { break }
        }

        return Array(premium) + zh + en
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
                                selected ? AppColor.accentPrimary.opacity(0.2) : AppColor.bgTertiary
                            )
                            .foregroundStyle(
                                selected ? AppColor.accentPrimary : AppColor.textSecondary
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    .pointingHandCursor()
                }
            }

            HStack {
                Text("格式".localized())
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textTertiary)
                
                HStack(spacing: 4) {
                    ForEach(["mp3", "wav"], id: \.self) { format in
                        let selected = vm.selectedFormat.lowercased() == format.lowercased()
                        Button {
                            vm.selectedFormat = format.uppercased()
                            appState.defaultFormat = format.uppercased()
                        } label: {
                            Text(format.uppercased())
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
                        .pointingHandCursor()
                    }
                }
            }
            
            HStack {
                Text("采样率".localized())
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textTertiary)
                Spacer()
            }

            // 采样率选项网格（2列）
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 2),
                spacing: 6
            ) {
                ForEach(Constants.sampleRates) { item in
                    let selected = vm.sampleRate == item.rate
                    Button {
                        vm.sampleRate = item.rate
                        appState.defaultSampleRate = item.rate
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.displayName)
                                    .font(AppFont.monoSmall)
                                Text(item.useCase)
                                    .font(.system(size: 9))
                                    .foregroundStyle(AppColor.textTertiary)
                            }
                            Spacer()
                            if selected {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 12))
                                    .foregroundStyle(AppColor.accentPrimary)
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            selected ? AppColor.accentPrimary.opacity(0.15) : AppColor.bgTertiary
                        )
                        .foregroundStyle(
                            selected ? AppColor.accentPrimary : AppColor.textSecondary
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(
                                    selected ? AppColor.accentPrimary.opacity(0.5) : AppColor.borderSubtle,
                                    lineWidth: 1
                                )
                        )
                    }
                    .buttonStyle(.plain)
                    .pointingHandCursor()
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
                    .pointingHandCursor()
                }
            }

            // 输入框
            ZStack(alignment: .topLeading) {
                if vm.nlInstruction.isEmpty {
                    Text("或自定义描述你想听到的声音...".localized())
                        .font(AppFont.bodyMedium)
                        .foregroundStyle(AppColor.textTertiary)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 7)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $vm.nlInstruction)
                    .font(AppFont.bodyMedium)
                    .foregroundStyle(AppColor.textPrimary)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
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

    /// 顶部工具栏内的操作区：预览 / 生成按钮 + 下方积分消耗与进度
    /// 原为右侧面板底部卡片，迁移至顶部 toolbar 后改为按钮在上、积分与进度在下的紧凑布局。
    private var generateBar: some View {
        VStack(alignment: .trailing, spacing: 6) {
            // 按钮行
            HStack(spacing: 8) {
                SecondaryButton(
                    title: player.isPlaying(key: vm.selectedVoiceKey) ? "停止".localized() : "预览".localized(),
                    icon: player.isPlaying(key: vm.selectedVoiceKey) ? "stop.fill" : "play.fill"
                ) {
                    if player.isPlaying(key: vm.selectedVoiceKey) {
                        AudioPreviewPlayer.shared.stop()
                    } else {
                        AudioPreviewPlayer.shared.play(key: vm.selectedVoiceKey)
                    }
                }

                PrimaryButton(title: "生成音频".localized(), icon: "waveform") {
                    vm.generate { success in
                        if success {
                            appState.refreshCredits()
                        }
                    }
                }
            }

            // 下方信息行：消耗积分（生成中显示具体进度）
            HStack(spacing: 8) {
                Spacer()

                // 生成中：显示具体进度（0~100%）
                if vm.isGenerating {
                    HStack(spacing: 8) {
                        ProgressView(value: vm.generationProgress, total: 1.0)
                            .progressViewStyle(.linear)
                            .tint(AppColor.accentPrimary)
                            .frame(width: 140)
                        Text("\(Int(vm.generationProgress * 100))%")
                            .font(AppFont.monoSmall)
                            .foregroundStyle(AppColor.accentPrimary)
                            .monospacedDigit()
                    }
                }

                Text("本次消耗".localized() + " ")
                    .font(AppFont.label)
                    .foregroundStyle(AppColor.textTertiary)
                + Text("约 %d 积分".localized(vm.estimatedPoints))
                    .font(AppFont.label)
                    .foregroundStyle(AppColor.accentPrimary)
            }
        }
    }
}
