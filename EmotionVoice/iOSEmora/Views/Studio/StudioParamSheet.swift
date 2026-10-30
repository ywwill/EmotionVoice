//
//  StudioParamSheet.swift
//  iOSEmora
//
//  参数 Sheet：macOS 右侧三张卡（音色切换 / 音频控制 / 语音指令）在 iPhone 上合成一张，
//  medium detent 起步、可上拉到 large。
//

import SwiftUI

struct StudioParamSheet: View {
    @Environment(\.aurora) private var c
    @Environment(\.screenMetrics) private var metrics
    @Environment(\.dismiss) private var dismiss

    @ObservedObject var vm: VoiceStudioViewModel
    @Binding var voicePickerPresented: Bool

    @State private var languagesExpanded = false
    @State private var showInstructionGuide = false

    private static let instructionLimit = 1000

    var body: some View {
        VStack(spacing: 0) {
            SheetNavBar(
                title: "创作参数".localized(),
                leading: {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 19, weight: .medium))
                            .foregroundStyle(c.textTertiary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
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
                    voiceSection
                    GroupTitle(text: "音频控制".localized(), topPadding: 20)
                    audioControlCard
                    sampleRateSection
                    instructionSection
                    Spacer(minLength: 20)
                }
            }
        }
        .background(c.backgroundGrouped)
        .sheet(isPresented: $showInstructionGuide) {
            InstructionGuideSheet()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: 音色

    private var voiceSection: some View {
        VStack(spacing: 0) {
            GroupTitle(text: "音色".localized(), topPadding: 6)
            Button { voicePickerPresented = true } label: {
                HStack(spacing: 12) {
                    VoiceAvatar(text: voice?.localizedAvatar ?? "声",
                                seed: voice?.key ?? "default",
                                size: 44)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 6) {
                            Text(voice?.localizedName ?? "未选择音色".localized())
                                .font(.system(size: 16.5, weight: .semibold))
                                .foregroundStyle(c.textPrimary)
                                .lineLimit(1)
                            if voice?.isPremium == true {
                                Text("⭐ 旗舰".localized())
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(Color(hex: 0xFFB457))
                            }
                        }
                        Text(voiceSubtitle)
                            .font(.system(size: 12.5))
                            .foregroundStyle(c.textSecondary)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(c.textTertiary)
                }
                .padding(.horizontal, 14)
                .frame(minHeight: 60)
                .background(cardBackground(radius: AuroraRadius.md))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, metrics.pageMargin)
        }
    }

    private var voiceSubtitle: String {
        guard let v = voice else { return "" }
        var parts: [String] = []
        if !v.localizedDesc.isEmpty { parts.append(v.localizedDesc) }
        if !v.localizedScene.isEmpty { parts.append(v.localizedScene) }
        if let age = v.age, age > 0 { parts.append("%d 岁".localized(age)) }
        return parts.joined(separator: " · ")
    }

    // MARK: 音频控制

    private var audioControlCard: some View {
        VStack(spacing: 0) {
            sliderRow(title: "语速".localized(),
                      valueText: String(format: "%.1fx", vm.rate),
                      minLabel: "0.5x", maxLabel: "2.0x",
                      value: $vm.rate, range: 0.5...2.0)

            Hairline().padding(.vertical, 12)

            sliderRow(title: "音量".localized(),
                      valueText: String(format: "%d%%", Int(vm.volume.rounded())),
                      minLabel: "0%", maxLabel: "100%",
                      value: $vm.volume, range: 0...100)

            Hairline().padding(.vertical, 12)

            HStack(alignment: .center, spacing: 12) {
                Text("格式".localized())
                    .font(.system(size: 15.5))
                    .foregroundStyle(c.textPrimary)
                    .frame(width: 52, alignment: .leading)
                AuroraSegmented(options: ["MP3", "WAV"], selection: formatBinding)
            }
        }
        .padding(14)
        .background(cardBackground(radius: AuroraRadius.md))
        .padding(.horizontal, metrics.pageMargin)
    }

    private var formatBinding: Binding<String> {
        Binding(
            get: { vm.selectedFormat.uppercased() },
            set: { vm.selectedFormat = $0.lowercased() }
        )
    }

    private func sliderRow(title: String,
                           valueText: String,
                           minLabel: String,
                           maxLabel: String,
                           value: Binding<Double>,
                           range: ClosedRange<Double>) -> some View {
        VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 15.5))
                    .foregroundStyle(c.textPrimary)
                Spacer(minLength: 0)
                Text(valueText)
                    .font(AuroraFont.mono13)
                    .foregroundStyle(c.textSecondary)
            }
            HStack(spacing: 8) {
                Text(minLabel)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(c.textTertiary)
                Slider(value: value, in: range)
                    .tint(c.accent)
                Text(maxLabel)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(c.textTertiary)
            }
        }
    }

    // MARK: 采样率

    private var sampleRateSection: some View {
        VStack(spacing: 0) {
            HStack {
                Text("采样率".localized())
                    .font(AuroraFont.sectionTitle)
                    .foregroundStyle(c.textPrimary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18)
            .padding(.top, 16)

            let columns = Array(repeating: GridItem(.flexible(), spacing: 8),
                                count: metrics.sampleRateColumns)
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(Constants.sampleRates) { item in
                    Button { vm.sampleRate = item.rate } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.displayName)
                                    .font(.system(size: 13.5, design: .monospaced))
                                    .foregroundStyle(vm.sampleRate == item.rate ? c.textPrimary : c.textPrimary)
                                Text(item.useCase)
                                    .font(.system(size: 11))
                                    .foregroundStyle(vm.sampleRate == item.rate ? c.textSecondary : c.textTertiary)
                            }
                            Spacer(minLength: 0)
                            if vm.sampleRate == item.rate {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 14))
                                    .foregroundStyle(c.accent)
                            }
                        }
                        .padding(.horizontal, 11)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(vm.sampleRate == item.rate ? c.accentSoft : c.surface3)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                                        .strokeBorder(vm.sampleRate == item.rate
                                                      ? c.accent.opacity(0.5)
                                                      : c.line, lineWidth: vm.sampleRate == item.rate ? 1 : 0.5)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, metrics.pageMargin)
            .padding(.top, 8)
        }
    }

    // MARK: 语音指令

    private var instructionSection: some View {
        VStack(spacing: 0) {
            HStack {
                Text("语音指令".localized())
                    .font(AuroraFont.sectionTitle)
                    .foregroundStyle(c.textPrimary)
                Spacer(minLength: 0)
                Button { showInstructionGuide = true } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 17))
                        .foregroundStyle(c.accent)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)

            VStack(alignment: .leading, spacing: 0) {
                // 语言
                HStack(spacing: 6) {
                    Image(systemName: "globe")
                        .font(.system(size: 12, weight: .semibold))
                    Text("语言".localized())
                        .font(.system(size: 12.5, weight: .semibold))
                }
                .foregroundStyle(c.textSecondary)

                FlowLayout(spacing: 6, lineSpacing: 6) {
                    ForEach(visibleLanguages) { item in
                        AuroraChip(title: item.name.localized(),
                                   isSelected: vm.selectedLanguage == item.name) {
                            vm.toggleLanguage(item.name)
                        }
                    }
                    if !languagesExpanded {
                        Button {
                            withAnimation(.easeOut(duration: 0.18)) { languagesExpanded = true }
                        } label: {
                            HStack(spacing: 3) {
                                Text(String(format: "展开全部 %d".localized(), Constants.nlLanguages.count))
                                    .font(.system(size: 12.5))
                                Image(systemName: "chevron.down")
                                    .font(.system(size: 9, weight: .bold))
                            }
                            .foregroundStyle(c.textTertiary)
                            .padding(.horizontal, 11)
                            .frame(height: 30)
                            .background(Capsule(style: .continuous).fill(c.surface3))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.top, 8)

                Hairline().padding(.vertical, 12)

                // 描述预设
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12, weight: .semibold))
                    Text("描述预设".localized())
                        .font(.system(size: 12.5, weight: .semibold))
                }
                .foregroundStyle(c.textSecondary)

                FlowLayout(spacing: 6, lineSpacing: 6) {
                    ForEach(vm.nlPresets, id: \.self) { preset in
                        AuroraChip(title: preset.localized(),
                                   isSelected: vm.selectedPreset == preset) {
                            vm.applyPreset(preset)
                        }
                    }
                }
                .padding(.top, 8)

                Hairline().padding(.vertical, 12)

                // 指令输入
                ZStack(alignment: .topLeading) {
                    if vm.nlInstruction.isEmpty {
                        Text("用一句话描述你想要的声音".localized())
                            .font(.system(size: 15))
                            .foregroundStyle(c.textTertiary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                    }
                    TextEditor(text: $vm.nlInstruction)
                        .font(.system(size: 15))
                        .foregroundStyle(c.textPrimary)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 96)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .onChange(of: vm.nlInstruction) { _, newValue in
                            if newValue.count > Self.instructionLimit {
                                vm.nlInstruction = String(newValue.prefix(Self.instructionLimit))
                            }
                        }
                }
                .background(
                    RoundedRectangle(cornerRadius: AuroraRadius.sm, style: .continuous)
                        .fill(c.surface3)
                        .overlay(
                            RoundedRectangle(cornerRadius: AuroraRadius.sm, style: .continuous)
                                .strokeBorder(c.line, lineWidth: 0.5)
                        )
                )

                HStack {
                    Text("💡 详细描述 = 更好的效果".localized())
                        .font(.system(size: 11.5))
                        .foregroundStyle(c.textTertiary)
                    Spacer(minLength: 0)
                    Text("\(vm.nlInstruction.count) / \(Self.instructionLimit)")
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(vm.nlInstruction.count >= Self.instructionLimit
                                         ? c.accent : c.textTertiary)
                }
                .padding(.top, 8)

                HStack(spacing: 5) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 11))
                    Text("仅支持中文和英文输入".localized())
                        .font(.system(size: 11))
                }
                .foregroundStyle(c.warning)
                .padding(.top, 6)
            }
            .padding(14)
            .background(cardBackground(radius: AuroraRadius.md))
            .padding(.horizontal, metrics.pageMargin)
        }
    }

    private var visibleLanguages: [NLLanguageItem] {
        languagesExpanded ? Constants.nlLanguages : Array(Constants.nlLanguages.prefix(5))
    }

    private var voice: Voice? { vm.voice }

    private func cardBackground(radius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(c.surface)
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(c.line, lineWidth: 0.5)
            )
    }
}

// MARK: - 指令指南

private struct InstructionGuideSheet: View {
    @Environment(\.aurora) private var c
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            SheetNavBar(
                title: "如何编写高质量的声音描述".localized(),
                leading: {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 19, weight: .medium))
                            .foregroundStyle(c.textTertiary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                },
                trailing: { EmptyView() }
            )
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    guideItem("1. 先说语种与方言".localized(), "中文，粤语，四川话……".localized())
                    guideItem("2. 再说性别与年龄".localized(), "年轻男性，中年女性，童声……".localized())
                    guideItem("3. 然后描述音色与节奏".localized(), "温柔柔和，语速偏快，语调积极……".localized())
                    guideItem("4. 最后补充场景".localized(), "适合新闻播报 / 有声书 / 广告配音……".localized())
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
            }
        }
        .background(c.backgroundGrouped)
    }

    private func guideItem(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 14.5, weight: .semibold))
                .foregroundStyle(c.textPrimary)
            Text(detail)
                .font(.system(size: 13))
                .foregroundStyle(c.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: AuroraRadius.md, style: .continuous)
                .fill(c.surface)
        )
    }
}
