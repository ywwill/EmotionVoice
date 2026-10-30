//
//  StudioView.swift
//  iOSEmora
//
//  创作工作台（对应 macOS「语音合成」）
//
//  macOS 的「左 980pt 编辑区 + 右 350pt 参数栏」在 iPhone 上收成单列。
//
//  ⚠️ iPhone 垂直空间极其紧张：**一切能给编辑器的都要给编辑器**。
//  键盘 + accessory 吃掉 ~450pt，再减掉导航栏 / 底部生成条，内容区只剩 200~250pt。所以：
//   ① 音色显示 + 切换 → 导航栏左侧胶囊（`.topBarLeading`），彻底移出内容流；
//   ② 音频参数 → 顶部一条 34pt 摘要条，点开参数 Sheet 才有全量控件；
//   ③ 文本卡标题行（含字数）也是非必要装饰；
//   ②③ 在键盘弹出时收成 0 高，字数挪到底部生成条（bottom bar 不会被键盘压住）。
//  展开态（iPhone Duo / iPad）`usesTwoColumnStudio` 为真 → 回到「左编辑 + 右参数」两栏，不参与收缩。
//

import SwiftUI
import UIKit

/// 性能排查开关。
///
/// `usePlainTextEditor = true` 时，创作页用系统原生 `TextEditor` 顶替自绘编辑器
/// （不加载 `TokenCapsuleOverlay`、不挂键盘 accessory 的 UIHostingController）。
/// 用来判定「输入 / 切标签卡顿」是否与 `TokenTextEditor` 有关：
///  * 换成原生后依旧卡 → 与编辑器无关，去查 `RootTabView` 与各标签页 body；
///  * 换成原生后流畅 → 瓶颈确实在自绘编辑器（胶囊层绘制 / accessory）。
enum IOSPerfDebug {
    static let usePlainTextEditor = false
}

struct StudioView: View {
    @Environment(\.aurora) private var c
    @Environment(\.screenMetrics) private var metrics
    @Environment(\.colorScheme) private var scheme

    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var uiState: IOSUIState
    @EnvironmentObject private var router: TabRouter

    @StateObject private var vm = VoiceStudioViewModel.shared

    // MARK: 编辑器状态

    /// 编辑器内容仓库。
    /// ⚠️ 内容刻意不放 `@State`：那样每敲一个字都会让整个 StudioView body（含
    /// UIViewRepresentable 的 updateUIView、键盘 accessory 的 SwiftUI 树）重算一次。
    /// 仓库里只有「字数」这种低频值会发布，且做了 0.25s 合并。
    @StateObject private var editor = TokenEditorStore()

    /// 仅 `IOSPerfDebug.usePlainTextEditor` 打开时使用的对照用文本
    @State private var debugText: String = ""

    /// 编辑器是否持有焦点（键盘是否弹出）。一次会话只翻两次，不在打字路径上。
    @State private var isEditingText = false

    // MARK: Sheet / 弹窗

    @State private var paramsPresented = false
    @State private var voicePickerPresented = false
    @State private var alertItem: AlertItem? = nil

    var body: some View {
        VStack(spacing: 0) {
            if metrics.usesTwoColumnStudio {
                ScrollView {
                    wideLayout
                        .padding(.bottom, 10)
                }
                .scrollDismissesKeyboard(.interactively)
            } else {
                // 窄屏不套 ScrollView：音色行 + 参数行是固定高度，
                // 输入框独占剩余空间撑到底部，与 generateBar 只隔 10pt。
                narrowLayout
            }

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

    /// 窄屏才让位：宽屏本来就两栏，没有空间压力
    private var collapseChrome: Bool { !metrics.usesTwoColumnStudio && isEditingText }

    // MARK: - 布局

    private var narrowLayout: some View {
        VStack(spacing: 0) {
            paramsStrip
            textCard
        }
    }

    private var wideLayout: some View {
        HStack(alignment: .top, spacing: 16) {
            // 宽屏在 ScrollView 里，高度是无界的 —— 必须给个下限，否则撑满修饰会塌成 0
            VStack(spacing: 0) { textCard.frame(minHeight: metrics.editorMinHeight) }
            VStack(spacing: 12) {
                voiceRow
                paramsSummary
            }
            .frame(width: 300)
        }
        .pagePadding()
    }

    // MARK: 音色行（仅宽屏侧栏；窄屏由导航栏左侧胶囊承担）

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
        if let age = v.age, age > 0 { parts.append("%d 岁".localized(age)) }
        return parts.joined(separator: " · ")
    }

    // MARK: 参数摘要

    /// 窄屏顶部唯一的横条：音频参数总览 + 语音指令状态，点开完整参数 Sheet。
    ///
    /// ⚠️ 键盘弹出时整条连同上下间距收成 0 高 —— 打字时可视区只剩两百出头，
    /// 这 52pt 是最该让出来的空间（`collapseChrome`）。宽屏侧栏走 `paramsSummary`，不参与收缩。
    private var paramsStrip: some View {
        paramsStripContent
            .padding(.horizontal, metrics.pageMargin)
            .padding(.vertical, 9)
            .frame(height: collapseChrome ? 0 : 52)     // 34 内容 + 2×9 间距
            .opacity(collapseChrome ? 0 : 1)
            .clipped()
            .animation(.easeOut(duration: 0.22), value: collapseChrome)
    }

    private var paramsStripContent: some View {
        Button { paramsPresented = true } label: {
            HStack(spacing: 7) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(c.accent)
                Text(paramsText)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(c.textSecondary)
                    .lineLimit(1)
                if !vm.nlInstruction.isEmpty {
                    instructionBadge
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(c.textTertiary)
            }
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(cardBackground(radius: AuroraRadius.md))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var instructionBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: "sparkles")
                .font(.system(size: 8.5, weight: .semibold))
            Text("指令".localized())
                .font(.system(size: 10.5, weight: .semibold))
        }
        .foregroundStyle(c.accent)
        .padding(.horizontal, 6)
        .frame(height: 17)
        .background(Capsule(style: .continuous).fill(c.accentSoft))
    }

    /// 宽屏（两栏）侧栏里的参数卡
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
            cardHeader

            // ⚠️ 只有 GeometryReader 能拿到「扣掉标题行之后还剩多少」，
            // 用 `.frame(maxHeight: .infinity)` 顶 UITextView 是不行的：
            // UIViewRepresentable 没有有意义的 intrinsicContentSize，SwiftUI 会把它压成 0 高。
            GeometryReader { geo in
                if IOSPerfDebug.usePlainTextEditor {
                    // A/B 对照：系统原生编辑器，不加载胶囊层、不挂 accessory
                    TextEditor(text: $debugText)
                        .font(.system(size: 16))
                        .foregroundStyle(c.textPrimary)
                        .scrollContentBackground(.hidden)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 12)
                        .frame(width: geo.size.width, height: geo.size.height)
                } else {
                    TokenTextEditor(store: editor,
                                    palette: c,
                                    isDark: scheme == .dark,
                                    onEditingChanged: { editing in
                                        isEditingText = editing
                                    })
                    .frame(width: geo.size.width, height: geo.size.height)
                }
            }
        }
        .background(cardBackground(radius: AuroraRadius.lg))
        .clipShape(RoundedRectangle(cornerRadius: AuroraRadius.lg, style: .continuous))
        .padding(.horizontal, metrics.pageMargin)
        .padding(.bottom, 10)          // 与底部 generateBar 只隔 10pt
        .frame(maxHeight: .infinity)   // 窄屏独占剩余高度
    }

    /// 标题 + 字数（32.5pt）。键盘弹出时收成 0 高，字数由底部生成条接着显示。
    private var cardHeader: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center) {
                HStack(spacing: 6) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(c.accent)
                    Text("文本输入".localized())
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(c.textPrimary)
                }
                Spacer(minLength: 0)
                Text("%d 字".localized(editor.charCount))
                    .font(.system(size: 11.5))
                    .foregroundStyle(c.textTertiary)
            }
            .padding(.horizontal, 16)
            .frame(height: 32)

            Hairline()
                .padding(.horizontal, 16)
        }
        .frame(height: collapseChrome ? 0 : 32.5)
        .opacity(collapseChrome ? 0 : 1)
        .clipped()
        .animation(.easeOut(duration: 0.22), value: collapseChrome)
    }

    // MARK: 底部生成条

    private var generateBar: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text("预计消耗".localized())
                    .font(.system(size: 11))
                    .foregroundStyle(c.textTertiary)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("≈ \(formatCredits(estimatedPoints))")
                        .font(AuroraFont.mono17)
                        .foregroundStyle(c.textPrimary)
                    // 卡标题行被收起时，字数改由这里兜住
                    Text("%d 字".localized(editor.charCount))
                        .font(.system(size: 11.5, design: .monospaced))
                        .foregroundStyle(c.textTertiary)
                }
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
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(c.bar)
        .overlay(alignment: .top) { Hairline() }
    }

    // MARK: 导航栏

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        // 左侧：音色（显示 + 切换）。inline 标题居中时左边这块原本是空的，
        // 挪过来既省掉内容区顶部那一大块，又让「当前音色」在任何滚动位置都可见。
        ToolbarItem(placement: .topBarLeading) { voiceChip }

        ToolbarItem(placement: .topBarTrailing) {
            HStack(spacing: 6) {
                Button { uiState.purchaseSheetPresented = true } label: {
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
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("购买积分".localized())

                Button { router.openSettings() } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(c.accent)
                        .frame(width: 30, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("设置".localized())
            }
        }
    }

    /// 导航栏左侧的音色胶囊：头像 + 名称 + 下拉箭头，点开音色 Sheet
    private var voiceChip: some View {
        Button { voicePickerPresented = true } label: {
            HStack(spacing: 6) {
                VoiceAvatar(text: currentVoice?.localizedAvatar ?? "声",
                            seed: currentVoice?.key ?? "default",
                            size: 26,
                            corner: 8)
                Text(currentVoice?.localizedName ?? "选择音色".localized())
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(c.textPrimary)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(c.textTertiary)
            }
            .padding(.horizontal, 8)
            .frame(maxWidth: metrics.`class` == .compact ? 116 : 148)
            .frame(height: 30)
            .background(
                Capsule(style: .continuous)
                    .fill(c.surface3)
                    .overlay(
                        Capsule(style: .continuous).strokeBorder(c.line2, lineWidth: 0.5)
                    )
            )
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("更换音色".localized())
    }

    // MARK: - 数据

    private var currentVoice: Voice? {
        vm.voice
    }

    private var plainText: String {
        TokenDocument.plainText(doc: editor.doc)
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
        guard editor.doc.isEmpty, !vm.ttsItems.isEmpty else { return }
        let made = TokenDocument.make(items: vm.ttsItems)
        editor.replace(doc: made.doc, marks: made.marks)
    }

    private func startGeneration() {
        // 可能还有一个「结束编辑」回调在路上，这里先收键盘，让顶部横条同步恢复
        isEditingText = false
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
        // 字数可能还压在 0.25s 的合并窗口里，生成前先推一次
        editor.flush()
        // 结构性内容先同步进 VM：生成链路读的是 ttsItems / plainText
        vm.ttsItems = TokenDocument.contentItems(doc: editor.doc, marks: editor.marks)
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
