//
//  StudioParamSheet.swift
//  iOSEmora
//
//  参数面板：macOS 右侧三张卡（音色切换 / 音频控制 / 语音指令）在 iPhone 上合成一张
//  medium detent 的 `StudioParamSheet`；iPad 工作台侧栏直接铺开同一份 `StudioParamContent`。
//
//  ⚠️ 两者共用一份正文，改参数控件只改一处；`StudioParamSheet` 只负责 SheetNavBar 外壳。
//     iPhone 的 Sheet 层级、间距、控件行为与拆分前逐字一致。
//

import SwiftUI

// 四项参数的持久化走 `Shared/ViewModels/VoiceStudioViewModel.swift` 里的
// `StudioParamStore`（iOS / macOS 共用），本文件不再重复定义。

// MARK: - iPhone 用的 Sheet

struct StudioParamSheet: View {
    @Environment(\.aurora) private var c
    @Environment(\.dismiss) private var dismiss

    @ObservedObject var vm: VoiceStudioViewModel
    @Binding var voicePickerPresented: Bool

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

            // 正文与 iPad 侧栏共用
            StudioParamContent(vm: vm, voicePickerPresented: $voicePickerPresented)
        }
        .background(c.backgroundGrouped)
    }
}

// MARK: - 共用正文（iPhone Sheet / iPad 工作台侧栏）

/// 参数正文：不含 SheetNavBar，也不假设自己被 presented。
///
/// `sampleRateColumns` 只给 iPad 侧栏传 2 —— 侧栏比 Sheet 窄，3 列会把
/// 「采样率 + 用途」两行字挤到换行；不传就按 `metrics.sampleRateColumns` 走档位默认。
struct StudioParamContent: View {
    @Environment(\.aurora) private var c
    @Environment(\.screenMetrics) private var metrics

    @ObservedObject var vm: VoiceStudioViewModel
    @Binding var voicePickerPresented: Bool
    var sampleRateColumns: Int? = nil

    @State private var showInstructionGuide = false

    private static let instructionLimit = 1000

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                voiceSection
                audioControlHeader
                audioControlCard
                sampleRateSection
                instructionSection
                Spacer(minLength: 20)
            }
        }
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

    /// 「音频控制」标题行 + 右侧「重置」。
    ///
    /// ⚠️ 不能用共享的 `GroupTitle`：它自带 `.frame(maxWidth: .infinity)`，
    /// 塞不进 trailing 按钮。这里的字号 / tracking / 上下间距与 `GroupTitle` 逐项对齐。
    /// 重置覆盖「音频控制 + 采样率」两块的四项参数，放在这组标题上而不是导航栏
    /// （`SheetNavBar` 两侧宽度不等会把标题挤偏）。
    private var audioControlHeader: some View {
        HStack(spacing: 8) {
            Text("音频控制".localized().uppercased())
                .font(.system(size: 11.5, weight: .semibold))
                .tracking(0.6)
                .foregroundStyle(c.textTertiary)
            Spacer(minLength: 0)
            Button {
                StudioParamStore.shared.reset(on: vm)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 11, weight: .semibold))
                    Text("重置".localized())
                        .font(.system(size: 12.5, weight: .medium))
                }
                .foregroundStyle(c.accent)
                .padding(.horizontal, 8)
                .frame(height: 30)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("重置".localized())
            .accessibilityHint("恢复语速、音量、格式与采样率的默认参数".localized())
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

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
                                count: sampleRateColumns ?? metrics.sampleRateColumns)
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

                // 语言默认全部展开，不提供收起入口（与 macOS 端一致）
                FlowLayout(spacing: 6, lineSpacing: 6) {
                    ForEach(Constants.nlLanguages) { item in
                        AuroraChip(title: item.name.localized(),
                                   isSelected: vm.selectedLanguage == item.name) {
                            vm.toggleLanguage(item.name)
                        }
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
