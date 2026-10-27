//
//  StudioView.swift
//  iOSEmora
//
//  创作工作台（对应 macOS「语音合成」）
//
//  macOS 的「左 980pt 编辑区 + 右 350pt 参数栏」在 iPhone 上收成单列：
//  音色行 → 参数摘要 → 文本卡 → 底部生成条；三张参数卡合并成一张 medium detent 的参数 Sheet。
//  展开态（iPhone Duo / iPad）下自动回到两栏。
//

import SwiftUI

struct StudioView: View {
    @Environment(\.aurora) private var c
    @Environment(\.screenMetrics) private var metrics
    @Environment(\.colorScheme) private var scheme

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var uiState: IOSUIState
    @EnvironmentObject private var router: TabRouter

    @StateObject private var vm = VoiceStudioViewModel.shared

    // MARK: 编辑器状态

    @State private var doc: String = ""
    @State private var marks: [EmotionMark] = []
    @State private var editorMinHeight: CGFloat = 170

    // MARK: Sheet / 弹窗

    @State private var paramsPresented = false
    @State private var voicePickerPresented = false
    @State private var alertItem: AlertItem? = nil

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    if metrics.usesTwoColumnStudio {
                        wideLayout
                    } else {
                        narrowLayout
                    }
                }
                .padding(.bottom, 8)
            }
            .scrollDismissesKeyboard(.interactively)

            generateBar
        }
        .background(c.backgroundGrouped)
        .navigationTitle("创作".localized())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .sheet(isPresented: $paramsPresented) {
            StudioParamSheet(vm: vm, voicePickerPresented: $voicePickerPresented)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $voicePickerPresented) {
            VoicePickerSheet(selectedKey: $vm.selectedVoiceKey)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .alert(item: $alertItem) { item in
            Alert(title: Text(item.title), message: Text(item.message),
                  dismissButton: .default(Text("好".localized())))
        }
        .onAppear(perform: restoreFromViewModel)
    }

    // MARK: - 布局

    private var narrowLayout: some View {
        VStack(spacing: 0) {
            voiceRow
            paramsSummary
            textCard
        }
    }

    private var wideLayout: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(spacing: 0) { textCard }
            VStack(spacing: 12) {
                voiceRow
                paramsSummary
            }
            .frame(width: 300)
        }
        .pagePadding()
    }

    // MARK: 音色行

    private var voiceRow: some View {
        Button { voicePickerPresented = true } label: {
            HStack(spacing: 11) {
                VoiceAvatar(text: currentVoice?.localizedAvatar ?? "声",
                            seed: currentVoice?.key ?? "default",
                            size: 40)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(currentVoice?.localizedName ?? "未选择音色".localized())
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(c.textPrimary)
                            .lineLimit(1)
                        if currentVoice?.isPremium == true {
                            premiumBadge
                        }
                    }
                    Text(voiceSubtitle)
                        .font(.system(size: 12.5))
                        .foregroundStyle(c.textSecondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                HStack(spacing: 3) {
                    Text("更换".localized())
                        .font(.system(size: 13, weight: .medium))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(c.accent)
                .padding(.horizontal, 11)
                .frame(height: 30)
                .background(
                    Capsule(style: .continuous).fill(c.accentSoft)
                )
            }
            .padding(11)
            .background(cardBackground(radius: AuroraRadius.lg))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, metrics.pageMargin)
        .padding(.top, 10)
        .padding(.bottom, 10)
    }

    private var premiumBadge: some View {
        HStack(spacing: 2) {
            Image(systemName: "star.fill")
                .font(.system(size: 8))
            Text("旗舰".localized())
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(Color(hex: 0xFFB457))
        .padding(.horizontal, 6)
        .frame(height: 16)
        .background(
            Capsule(style: .continuous)
                .fill(Color(hex: 0xFFB457).opacity(0.16))
        )
    }

    private var voiceSubtitle: String {
        guard let v = currentVoice else { return "".localized() }
        var parts: [String] = []
        if !v.localizedDesc.isEmpty { parts.append(v.localizedDesc) }
        let scene = v.localizedScene
        if !scene.isEmpty { parts.append(scene) }
        if let age = v.age, age > 0 { parts.append(String(format: "%d 岁".localized(), age)) }
        return parts.joined(separator: " · ")
    }

    // MARK: 参数摘要

    private var paramsSummary: some View {
        Button { paramsPresented = true } label: {
            HStack(spacing: 10) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(c.accent)
                Text(paramsText)
                    .font(AuroraFont.mono13)
                    .foregroundStyle(c.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(c.textTertiary)
            }
            .padding(.horizontal, 14)
            .frame(height: 40)
            .background(cardBackground(radius: AuroraRadius.md))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, metrics.pageMargin)
        .padding(.bottom, 10)
    }

    private var paramsText: String {
        let rate = String(format: "%.1fx", vm.rate)
        let volume = String(format: "%d%%", Int(vm.volume.rounded()))
        let rateText = String(format: "%@ kHz", sampleRateText)
        return "\(rate) · \(volume) · \(vm.selectedFormat.uppercased()) · \(rateText)"
    }

    private var sampleRateText: String {
        let v = Double(vm.sampleRate) / 1000.0
        if v == v.rounded() { return String(format: "%.0f", v) }
        return String(format: "%.2f", v)
    }

    // MARK: 文本卡

    private var textCard: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                HStack(spacing: 6) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(c.accent)
                    Text("文本输入".localized())
                        .font(AuroraFont.sectionTitle)
                        .foregroundStyle(c.textPrimary)
                }
                Spacer(minLength: 0)
                Text(String(format: "%d 字".localized(), plainText.count))
                    .font(.system(size: 11.5))
                    .foregroundStyle(c.textTertiary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 10)

            Hairline()
                .padding(.horizontal, 16)

            TokenTextEditor(doc: $doc,
                            marks: $marks,
                            palette: c,
                            isDark: scheme == .dark,
                            minHeight: metrics.editorMinHeight)
            .frame(minHeight: metrics.editorMinHeight)
        }
        .background(cardBackground(radius: AuroraRadius.lg))
        .padding(.horizontal, metrics.pageMargin)
    }

    // MARK: 底部生成条

    private var generateBar: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 1) {
                Text("预计消耗".localized())
                    .font(.system(size: 11))
                    .foregroundStyle(c.textTertiary)
                Text("≈ \(formatCredits(estimatedPoints))")
                    .font(AuroraFont.mono17)
                    .foregroundStyle(c.textPrimary)
            }
            .fixedSize()

            SecondaryButton(title: "", systemImage: "sparkles", height: 44, isFullWidth: false) {
                paramsPresented = true
            }
            .frame(width: 52)
            .accessibilityLabel("语音指令".localized())

            PrimaryButton(title: "生成音频".localized(), systemImage: "waveform") {
                startGeneration()
            }
        }
        .padding(.horizontal, metrics.pageMargin)
        .padding(.top, 10)
        .padding(.bottom, 10)
        .background(c.bar)
        .overlay(alignment: .top) { Hairline() }
    }

    // MARK: 导航栏

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            HStack(spacing: 14) {
                Button { router.openSettings() } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "diamond.fill")
                            .font(.system(size: 11))
                        Text(formatCredits(appState.creditsBalance))
                            .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    }
                    .foregroundStyle(c.accent)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(Capsule(style: .continuous).fill(c.accentSoft))
                }
                .buttonStyle(.plain)

                Button { router.openSettings() } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(c.accent)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - 数据

    private var currentVoice: Voice? {
        vm.voice
    }

    private var plainText: String {
        TokenDocument.plainText(doc: doc)
    }

    private var estimatedPoints: Double {
        let count = TextSplitter.calculateCharCount(plainText)
        return CreditManager.shared.calculateCreditsDouble(for: .normalTTS(characterCount: count))
    }

    private func cardBackground(radius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .fill(c.surface)
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(c.line, lineWidth: 0.5)
            )
    }

    // MARK: - 行为

    private func restoreFromViewModel() {
        guard doc.isEmpty, !vm.ttsItems.isEmpty else { return }
        let made = TokenDocument.make(items: vm.ttsItems)
        doc = made.doc
        marks = made.marks
    }

    private func startGeneration() {
        // 结构性内容先同步进 VM：生成链路读的是 ttsItems / plainText
        vm.ttsItems = TokenDocument.contentItems(doc: doc, marks: marks)
        vm.text = plainText

        guard !vm.plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            alertItem = AlertItem(title: "无法生成".localized(),
                                  message: "请先输入要合成的文本".localized())
            return
        }
        guard vm.voice != nil else {
            alertItem = AlertItem(title: "无法生成".localized(),
                                  message: "请先选择一个音色".localized())
            return
        }

        let needed = estimatedPoints
        guard CreditManager.shared.hasEnoughCredits(for: .normalTTS(characterCount: TextSplitter.calculateCharCount(vm.plainText))) else {
            uiState.purchaseSheetPresented = true
            uiState.showToast(.failure(String(format: "积分不足，还需要 %@ 积分".localized(), formatCredits(needed - appState.creditsBalance))))
            return
        }

        appState.showGenerationModal = true
        vm.generate { _ in }
    }
}
