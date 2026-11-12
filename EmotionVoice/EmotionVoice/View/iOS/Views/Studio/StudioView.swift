//
//  StudioView.swift
//  iOSEmora
//

import SwiftUI
import UIKit
import Combine
// typecheck 编不进 SPM 包，替身在 tools/ios_typecheck/Shims.swift；真机构建仍 import 真包。
#if canImport(AlertToast)
import AlertToast
#endif

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
    /// mini player 是挂在 `RootTabView` 的全局浮层，和本页 `generateBar` 抢同一块地方。
    @StateObject private var nowPlaying = NowPlayingStore.shared

    // MARK: 编辑器状态
    @StateObject private var editor = TokenEditorStore()

    /// 仅 `IOSPerfDebug.usePlainTextEditor` 打开时使用的对照用文本
    @State private var debugText: String = ""

    /// 编辑器是否持有焦点（键盘是否弹出）。一次会话只翻两次，不在打字路径上。
    @State private var isEditingText = false

    // MARK: Sheet / 弹窗

    @State private var paramsPresented = false
    @State private var voicePickerPresented = false
    @State private var alertItem: AlertItem? = nil
    @State private var confirmGenerate = false
    @ObservedObject private var drafts = DraftStore.shared
    @State private var draftsPresented = false
    private enum DraftToastKind { case saved, restored }
    @State private var showDraftToast = false
    @State private var draftToastKind: DraftToastKind = .saved

    /// 「键盘 + accessory」顶边的屏幕 Y（编辑器量出来的；nil = 键盘收起）
    @State private var keyboardTop: CGFloat? = nil
    /// 内容区底边的屏幕 Y（`.global` 坐标）
    @State private var contentBottom: CGFloat = 0
    /// 底部条还要再往上让多少 pt，才不会压到 accessory
    @State private var keyboardSeam: CGFloat = 0

    var body: some View {
        VStack(spacing: 0) {
            if metrics.usesTwoColumnStudio {
                GeometryReader { geo in
                    ScrollView {
                        wideLayout(editorHeight: max(geo.size.height - 20,
                                                     metrics.editorMinHeight))
                            .padding(.bottom, 10)
                    }
                    .scrollDismissesKeyboard(.immediately)
                }
            } else {
                narrowLayout
            }

            generateBar
                .padding(.bottom, keyboardSeam)
        }
        .background(c.backgroundGrouped)
        .background {
            GeometryReader { geo in
                Color.clear.preference(
                    key: ContentBottomKey.self,
                    value: geo.frame(in: .global).maxY - geo.safeAreaInsets.bottom)
            }
        }
        .onPreferenceChange(ContentBottomKey.self) { bottom in
            contentBottom = bottom
            withAnimation(.easeOut(duration: 0.2)) { updateKeyboardSeam() }
        }
        .navigationTitle("创作".localized())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbarContent }
        .sheet(isPresented: $paramsPresented) {
            StudioParamSheet(vm: vm, voicePickerPresented: $voicePickerPresented)
                .presentationDetents([.large])
        }
        .sheet(isPresented: $voicePickerPresented) {
            VoicePickerSheet(selectedKey: $vm.selectedVoiceKey)
                .presentationDetents([.large])
        }
        .sheet(isPresented: $draftsPresented) {
            DraftSheet(store: drafts,
                       canSave: !currentSnapshot.isEmpty,
                       needsConfirm: !currentSnapshot.isEmpty,
                       onSave: {
                           draftsPresented = false
                           saveCurrentDraft()
                       },
                       onRestoreConfirmed: { d in
                           draftsPresented = false
                           performDraftRestore(d)
                       })
                .presentationDetents([.large])
                .presentationDragIndicator(.hidden)
        }
        .alert(item: $alertItem) { item in
            Alert(title: Text(item.title), message: Text(item.message),
                  dismissButton: .default(Text("好".localized())))
        }
        .onAppear {
            StudioParamStore.shared.restoreIfNeeded(to: vm)
            restoreFromViewModel()
            restoreSelectedVoice()
            PendingEditorCommit.handler = { [weak editor] in editor?.flush() }
        }
        .onChange(of: vm.selectedVoiceKey) { _, _ in
            if let voice = vm.voice { appState.selectedVoice = voice }
        }
        .onChange(of: vm.rate) { _, _ in StudioParamStore.shared.save(from: vm) }
        .onChange(of: vm.volume) { _, _ in StudioParamStore.shared.save(from: vm) }
        .onChange(of: vm.selectedFormat) { _, _ in StudioParamStore.shared.save(from: vm) }
        .onChange(of: vm.sampleRate) { _, _ in StudioParamStore.shared.save(from: vm) }
        .onDisappear {
            finishEditing()
            autoSaveCurrentDraft()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            autoSaveCurrentDraft()
        }
        .toast(isPresenting: $showDraftToast,
               duration: 1.0,
               tapToDismiss: false,
               offsetY: draftToastOffsetY) {
            draftToastAlert
        }
    }

    private var draftToastOffsetY: CGFloat {
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
        let topInset = window?.safeAreaInsets.top ?? 0
        let bar = AppUpdateBanner.navBarClearance + (metrics.isPadClass ? 8 : 0)
        return max(0, topInset + bar + 8 - 33)
    }

    private var collapseChrome: Bool { !metrics.usesTwoColumnStudio && isEditingText }

    private func updateKeyboardSeam() {
        guard let top = keyboardTop, contentBottom > 0 else {
            keyboardSeam = 0
            return
        }
        let overlap = contentBottom - top
        keyboardSeam = min(max(overlap, 0), 260)
    }

    // MARK: - 布局

    private var narrowLayout: some View {
        VStack(spacing: 0) {
            paramsStrip
            textCard(horizontalInset: metrics.pageMargin)
        }
    }

    private func wideLayout(editorHeight: CGFloat) -> some View {
        HStack(alignment: .top, spacing: 16) {
            textCard(horizontalInset: 0)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: editorHeight)
            if metrics.isPadClass {
                StudioParamContent(vm: vm,
                                   voicePickerPresented: $voicePickerPresented,
                                   sampleRateColumns: 2)
                    .frame(width: metrics.studioSidebarWidth, height: editorHeight)
            } else {
                VStack(spacing: 12) {
                    voiceRow
                    paramsSummary
                }
                .frame(width: metrics.studioSidebarWidth)
            }
        }
        .padding(.horizontal, metrics.pageMargin)
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
                    // 侧栏放宽后「… · 22.05 kHz」在 iPad 上仍差两三个字；
                    // 缩一档显示全，比尾部截成「22.05 k…」可读。
                    .minimumScaleFactor(0.8)
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
    private func textCard(horizontalInset: CGFloat) -> some View {
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
                                    },
                                    onKeyboardTopChanged: { top in
                                        // 与键盘动画同步（升起约 0.25s），否则底部条会先跳一下再跟上
                                        withAnimation(.easeOut(duration: 0.25)) {
                                            keyboardTop = top
                                            if top == nil { keyboardSeam = 0 }
                                        }
                                    })
                    .frame(width: geo.size.width, height: geo.size.height)
                }
            }
        }
        .background(cardBackground(radius: AuroraRadius.lg))
        .clipShape(RoundedRectangle(cornerRadius: AuroraRadius.lg, style: .continuous))
        .padding(.horizontal, horizontalInset)
        .padding(.bottom, 10)          // 与底部 generateBar 只隔 10pt
        .frame(maxHeight: .infinity)   // 窄屏独占剩余高度
    }

    private var cardHeader: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 8) {
                if !collapseChrome {
                    if !metrics.usesTwoColumnStudio {
                        voiceHeaderChip
                    }
                    Spacer(minLength: 4)
                    Text("%d 字".localized(editor.charCount))
                        .font(.system(size: 11.5))
                        .foregroundStyle(c.textTertiary)
                } else {
                    Spacer(minLength: 0)
                }
                draftCapsule
            }
            .padding(.horizontal, 16)
            .frame(height: collapseChrome ? 30 : 32)

            if !collapseChrome {
                Hairline()
                    .padding(.horizontal, 16)
            }
        }
        .frame(height: collapseChrome ? 30 : 32.5)
        .clipped()
        .animation(.easeOut(duration: 0.22), value: collapseChrome)
    }

    /// 草稿胶囊：26pt 高、accentSoft 底 + 描边、角标 16×16，>99 显示 99+、为 0 隐藏。
    private var draftCapsule: some View {
        Button {
            // ⚠️ 打开 Sheet 前先收键盘；恢复后也不自动聚焦、不弹键盘。
            finishEditing()
            draftsPresented = true
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "folder")
                    .font(.system(size: 11, weight: .semibold))
                Text("草稿".localized())
                    .font(.system(size: 11.5, weight: .bold))
                if drafts.count > 0 {
                    Text(drafts.count > 99 ? "99+" : "\(drafts.count)")
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                        .frame(minWidth: 16, minHeight: 16)
                        .padding(.horizontal, 3)
                        .background(Capsule().fill(c.accent))
                }
            }
            .foregroundStyle(c.accent)
            .padding(.horizontal, 9)
            .frame(height: 26)
            .background(
                Capsule()
                    .fill(c.accentSoft)
                    .overlay(Capsule().strokeBorder(c.line2, lineWidth: 0.5))
            )
            // 整条热区
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// 文本卡标题行中间的「当前音色」：窄屏专用，点开选音色 Sheet。
    private var voiceHeaderChip: some View {
        Button { voicePickerPresented = true } label: {
            HStack(spacing: 4) {
                Image(systemName: "waveform")
                    .font(.system(size: 11, weight: .semibold))
                Text(currentVoice?.localizedName ?? "未选择音色".localized())
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .foregroundStyle(c.accent)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("当前音色".localized())
    }

    private var miniPlayerInset: CGFloat {
        guard nowPlaying.currentItem != nil, keyboardTop == nil else { return 0 }
        return MiniPlayerView.height + 12
    }

    private var generateBar: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text("预计".localized())
                    .font(.system(size: 11))
                    .foregroundStyle(c.textTertiary)
                Text("≈ " + formatCredits(estimatedPoints))
                    .font(AuroraFont.mono17)
                    .foregroundStyle(c.textPrimary)
            }
            .fixedSize()
            .lineLimit(1)

            Spacer(minLength: 8)

            if !metrics.isPadClass {
                SecondaryButton(title: "", systemImage: "sparkles", height: 44, isFullWidth: false) {
                    paramsPresented = true
                }
                .frame(width: barIconWidth)
                .accessibilityLabel("语音指令".localized())
            }

            PrimaryButton(title: "生成语音".localized(), systemImage: "waveform",
                          width: generateButtonWidth) {
                requestGeneration()
            }

            doneButton
        }
        .padding(.horizontal, metrics.pageMargin)
        .padding(.top, 8)
        .padding(.bottom, 8 + miniPlayerInset)
        .background(c.bar)
        .animation(RootTabView.dockAnimation, value: miniPlayerInset)
        .overlay(alignment: .top) { Hairline() }
        .alert("确认生成语音".localized(), isPresented: $confirmGenerate) {
            Button("取消".localized(), role: .cancel) { }
            Button("确认".localized()) { startGeneration() }
        } message: {
            Text(generateConfirmMessage)
        }
    }

    private var doneButton: some View {
        Button { finishEditing() } label: {
            Text("完成".localized())
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(c.accent)
                .frame(width: metrics.width < 375 ? 66 : 74, height: 44)
                .background(
                    RoundedRectangle(cornerRadius: AuroraRadius.md, style: .continuous)
                        .strokeBorder(c.accent.opacity(0.42), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .opacity(isEditingText ? 1 : 0.55)
    }

    private var barIconWidth: CGFloat { metrics.width < 375 ? 40 : 46 }

    private var generateButtonWidth: CGFloat { metrics.width < 375 ? 112 : 128 }

    private func finishEditing() {
        isEditingText = false
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
    }

    // MARK: 导航栏

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        // 左侧：音色切换入口（纯图标，不占横向空间）。
        // 音色名与头像一律不进导航栏 —— 窄屏横向空间全留给编辑区，
        // 当前音色的展示交给宽屏侧栏的音色区与音色 Sheet 自己。
        ToolbarItem(placement: .topBarLeading) { voiceSwapButton }

        ToolbarItem(placement: .topBarTrailing) {
            HStack(spacing: 6) {
                StudioCreditCapsule()

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

    private var voiceSwapButton: some View {
        Button { voicePickerPresented = true } label: {
            Text("🎭")
                .font(.system(size: 19))
                .frame(width: 34, height: 34)
                .background(
                    Circle()
                        .fill(c.surface3)
                        .overlay(
                            Circle().strokeBorder(c.line2, lineWidth: 0.5)
                        )
                )
                .contentShape(Circle())
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

    // MARK: 草稿行为
    private var currentSnapshot: DraftSnapshot {
        var snap = DraftSnapshot.capture(from: vm)
        snap.items = TokenDocument.contentItems(doc: editor.doc, marks: editor.marks)
        return snap
    }

    private func saveCurrentDraft() {
        editor.flush()
        let snap = currentSnapshot
        guard !snap.isEmpty else { return }
        drafts.save(snap, source: .manual)
        presentDraftToast(.saved)
    }

    /// 静默兜底：退后台 / 离开创作页 / 恢复前，恒定覆盖单条「自动保存」。
    private func autoSaveCurrentDraft() {
        editor.flush()
        let snap = currentSnapshot
        guard !snap.isEmpty else { return }
        drafts.save(snap, source: .auto, notify: false)
    }

    private func applyDraftSnapshot(_ d: Draft) {
        finishEditing()
        vm.apply(d, appState: appState)
        let made = TokenDocument.make(items: d.items)
        editor.replace(doc: made.doc, marks: made.marks)
        vm.ttsItems = d.items
        vm.text = TokenDocument.plainText(doc: made.doc)
    }

    private func performDraftRestore(_ d: Draft) {
        // 未落盘的输入先提交给编辑器状态，再取快照（与 `autoSaveCurrentDraft` 一致）。
        editor.flush()
        let before = currentSnapshot
        guard let full = drafts.load(id: d.id) else { return }
        drafts.stashBeforeRestore(before)
        applyDraftSnapshot(full)
        drafts.restore(full.id)
        presentDraftToast(.restored)
    }

    /// 触发一条短提示：先写 kind，再让 isPresenting 走一次 false→true，重启 AlertToast 的计时。
    private func presentDraftToast(_ kind: DraftToastKind) {
        draftToastKind = kind
        showDraftToast = false
        DispatchQueue.main.async { self.showDraftToast = true }
    }

    /// 两条提示共用同一外观，只换文案与对勾颜色。
    private var draftToastAlert: AlertToast {
        let title: String
        let color: Color
        switch draftToastKind {
        case .saved:
            title = "草稿已保存".localized()
            color = c.success
        case .restored:
            title = "草稿已恢复".localized()
            color = c.accent
        }
        return AlertToast(displayMode: .hud,
                          type: .complete(color),
                          title: title,
                          style: .style(backgroundColor: c.surface,
                                        titleColor: c.textPrimary))
    }

    private func restoreFromViewModel() {
        guard editor.doc.isEmpty, !vm.ttsItems.isEmpty else { return }
        let made = TokenDocument.make(items: vm.ttsItems)
        editor.replace(doc: made.doc, marks: made.marks)
    }

    private func restoreSelectedVoice() {
        guard let voice = vm.voice else {
            vm.selectedVoiceKey = appState.selectedVoice?.key ?? appState.defaultVoiceKey
            return
        }
        if appState.selectedVoice?.key != voice.key {
            appState.selectedVoice = voice
        }
    }

    private func requestGeneration() {
        // 可能还有一个「结束编辑」回调在路上，这里先收键盘，让顶部横条同步恢复
        finishEditing()
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
        confirmGenerate = true
    }

    /// 二次确认的具体内容：**音色 + 本次要扣的积分**。
    ///
    /// ⚠️ 字数不进弹窗 —— 底部条上已经常显「预计」，弹窗里重复一遍只会挤掉重点。
    private var generateConfirmMessage: String {
        let name = currentVoice?.localizedName ?? "未选择音色".localized()
        return "音色：%@\n消耗：%@ 积分".localized(name, formatCredits(estimatedPoints))
    }

    private func startGeneration() {
        let needed = estimatedPoints
        guard CreditManager.shared.hasEnoughCredits(for: .normalTTS(characterCount: TextSplitter.calculateCharCount(vm.plainText))) else {
            uiState.purchaseSheetPresented = true
            uiState.showToast(.failure("积分不足，还需要 %@ 积分".localized(formatCredits(needed - appState.creditsBalance))))
            return
        }

        appState.showGenerationModal = true
        vm.generate { success in
            // 生成成功后音频进「项目 / 历史」；草稿只打标，30 天后清理，两者不混列。
            if success { drafts.markGenerated() }
        }
    }
}


/// 内容区底边（屏幕坐标 Y）—— 键盘让位时拿它跟 accessory 顶边比对
private struct ContentBottomKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private struct StudioCreditCapsule: View {
    @Environment(\.aurora) private var c
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var uiState: IOSUIState

    var body: some View {
        Button { uiState.purchaseSheetPresented = true } label: {
            HStack(spacing: 4) {
                Image(systemName: "diamond.fill")
                    .font(.system(size: 11))
                Text(formatCredits(appState.creditsBalance))
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .contentTransition(.numericText(value: appState.creditsBalance))
                    .animation(.smooth(duration: 0.45), value: appState.creditsBalance)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(c.accent)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(Capsule(style: .continuous).fill(c.accentSoft))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("购买积分".localized())
    }
}
