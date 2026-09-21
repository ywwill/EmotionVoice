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
    // 使用 shared 单例，保证页面切换时数据不丢失（文本/情感/语速音量等）
    @StateObject private var vm = VoiceStudioViewModel.shared
    @ObservedObject private var player = AudioPreviewPlayer.shared
    @State private var showVoiceLibrarySheet: Bool = false
    @State private var showGenerationModal: Bool = false
    
    /// 弹窗高度：生成中状态较短，完成状态较长
    private var modalHeight: CGFloat {
        if vm.isGenerating {
            return 400  // 生成中状态：较矮
        } else {
            return 600  // 完成状态：较高
        }
    }

    var body: some View {
        
        HStack(spacing: 16) {
            // 左侧：输入框和情感面板
            VStack(alignment: .leading, spacing: 12) {
                textEditorCard
                emotionCard
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            // 右侧：生成栏 + 右侧面板
            VStack(alignment: .leading, spacing: 12) {
                generateBar
                editPanel
            }
            .frame(width: 360)
        }
        .padding(20)
        .padding(.bottom, 16)
        .sheet(isPresented: $showVoiceLibrarySheet) {
            VoiceLibrarySheet()
                .frame(width: 1400, height: 880)
        }
        .sheet(isPresented: $showGenerationModal) {
            AudioGenerationModal(vm: vm, isPresented: $showGenerationModal)
                .frame(width: 520, height: modalHeight)
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
            // EmotionTokenEditor 在 NSTextView 内部管理光标位置，
            // 通过 insertTokenTrigger 触发插入（emotion 按钮调用 vm.insertEmotion）。
            EmotionTokenEditor(
                items: $vm.ttsItems,
                insertTrigger: vm.insertTokenTrigger,
                insertLabel: vm.insertTokenLabel,
                insertEmoji: vm.insertTokenEmoji,
                insertTokenEnglishTag: vm.insertTokenEnglishTag,
                clearTrigger: vm.clearTokensTrigger,
                textBinding: $vm.text
            )
            .font(AppFont.bodyLarge)
            .foregroundStyle(AppColor.textPrimary)
            .frame(minHeight: 220)
            .scrollContentBackground(.hidden)
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
                Text("语气控制".localized())
                    .font(.system(size: 14, weight: .semibold))
                Spacer()
            }

            // 控制类情感网格（23 个）
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 10),
                spacing: 6
            ) {
                ForEach(Constants.emotions) { emotion in
                    EmotionButton(emotion: emotion) {
                        vm.insertEmotion(tag: emotion.tag)
                    }
                }
            }

            Divider().background(AppColor.borderSubtle).padding(.vertical, 6)

            // 富语言效果（7 个拟声标签）
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text("拟声效果".localized())
                        .font(.system(size: 14, weight: .semibold))
                }

                HStack(spacing: 6) {
                    ForEach(Constants.richLanguageTags) { tag in
                        Button {
                            vm.insertEmotion(tag: tag.tag)
                        } label: {
                            HStack(spacing: 4) {
                                Text(tag.emoji)
                                    .font(.system(size: 18))
                                Text("\(tag.label)")
                                    .font(.system(size: 10))
                                    .foregroundStyle(AppColor.textSecondary)
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

    private var editPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                voiceCard
                audioControlCard
                languageCard
                nlCard
            }
        }
        .frame(width: 350)
    }

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
                                .foregroundStyle(.white)
                            if voice.isPremium {
                                Text("⭐ 旗舰".localized())
                                    .font(AppFont.monoSmall)
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 1)
                                    .background(AppColor.accentPrimary.opacity(0.15))
                                    .clipShape(RoundedRectangle(cornerRadius: 3))
                            }
                        }
                        if !voice.desc.isEmpty {
                            Text(voice.desc)
                                .font(AppFont.caption)
                                .foregroundStyle(.white)
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                    Button {
                        showVoiceLibrarySheet = true
                    } label: {
                        Text("更换".localized())
                            .font(AppFont.caption)
                            .foregroundStyle(.white)
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
                .padding(12)
                .background(AppColor.accentPrimary.opacity(0.15))
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.medium)
                        .stroke(AppColor.accentPrimary.opacity(0.3), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium))
            }

            Divider().background(AppColor.borderSubtle)

            // 收藏的音色（最多显示 6 个）
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

    /// 备选音色：只显示用户收藏的音色，最多显示 6 个（按 dimension 排序，旗舰优先）
    private var alternateVoices: [Voice] {
        let all = appState.voices

        // 只取收藏的音色，按 dimension 排序（旗舰 > 语言 > 场景 > 角色 > 年龄）
        let favorites = all.filter { $0.isFavorite }

        return favorites
            .sorted { a, b in
                let da = dimensionRank(a.category.dimension)
                let db_ = dimensionRank(b.category.dimension)
                if da != db_ { return da < db_ }
                let aIsPremium = a.category == .premium
                let bIsPremium = b.category == .premium
                if aIsPremium != bIsPremium { return aIsPremium }
                return a.name < b.name
            }
            .prefix(6)
            .map { $0 }
    }

    /// 分类维度排序权重
    private func dimensionRank(_ dim: VoiceCategoryDimension) -> Int {
        switch dim {
        case .premium:  return 0
        case .language: return 1
        case .scene:    return 2
        case .role:     return 3
        case .age:      return 4
        }
    }

    // MARK: - 音频控制卡片（语速/音量）

    /// 语速/音量卡片。移出 emotionCard，统一在右侧面板集中展示音频输出参数。
    /// 横向空间受限，slider 在该卡片内采用上下纵向排列。
    private var audioControlCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("🎚️ 音频控制".localized())
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
            }

            VStack(alignment: .leading, spacing: 14) {
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
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppColor.bgSecondary)
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.large)
                .stroke(AppColor.borderSubtle, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.large))
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

    /// 生成栏：生成按钮 + 积分信息
    /// - 生成音频按钮（主操作）
    /// - 总积分余额 / 本月已用 / 预计消耗
    /// - 跳转积分中心入口
    private var generateBar: some View {
        let state = appState
        
        return HStack(spacing: 10) {
            // 左侧：生成音频按钮
            PrimaryButton(title: "生成音频".localized(), icon: "waveform") {
                if !validateInputs() { return }
                showGenerationModal = true
                vm.generate { success in
                    if success {
                        state.refreshCredits()
                    }
                }
            }
            
            Spacer()
            
            // 右侧：积分信息
            HStack(spacing: 5) {
                
                VStack(alignment: .leading) {
                    // 剩余积分
                    HStack {
                        Text("剩余积分")
                            .font(AppFont.monoSmall)
                            .foregroundStyle(AppColor.textTertiary)
                        Text("\(state.creditsBalance)")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(AppColor.accentPrimary)
                    }
                    
                    Rectangle()
                        .fill(AppColor.borderSubtle)
                        .frame(height: 1)
                    
                    // 预计消耗
                    HStack {
                        Text("预计消耗")
                            .font(AppFont.monoSmall)
                            .foregroundStyle(AppColor.textTertiary)
                        Text("≈ \(vm.estimatedPoints)")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(vm.estimatedPoints > state.creditsBalance ? Color.red : AppColor.textPrimary)
                    }
                }
                
                // 充值按钮
                Button {
                    state.selectedSection = .credits
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 14))
                        Text("充值".localized())
                            .font(AppFont.monoSmall)
                    }
                    .foregroundStyle(AppColor.accentPrimary)
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
            }
        }
        .padding(16)
        .background(AppColor.bgSecondary)
        .overlay(
                RoundedRectangle(cornerRadius: AppRadius.medium)
                    .stroke(AppColor.borderSubtle, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium))
    }
    
    /// 验证输入是否正确
    private func validateInputs() -> Bool {
        // 检查文本是否为空
        if vm.text.trimmingCharacters(in: .whitespaces).isEmpty {
            vm.alertItem = AlertItem(title: "无法生成".localized(),
                                     message: "请先输入要合成的文本".localized())
            return false
        }
        // 检查是否选择了音色
        guard vm.voice != nil else {
            vm.alertItem = AlertItem(title: "无法生成".localized(),
                                     message: "请先选择一个音色".localized())
            return false
        }
        // 检查积分是否足够
        let points = vm.estimatedPoints
        guard CreditsService.shared.canConsume(points) else {
            vm.alertItem = AlertItem(title: "积分不足".localized(),
                                     message: "本次合成需要约 %d 积分，请先充值".localized(points))
            return false
        }
        return true
    }
}
