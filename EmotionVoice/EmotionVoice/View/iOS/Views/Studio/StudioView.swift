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
//   ① 音色切换 → 导航栏左侧一个 🎭 图标按钮（`.topBarLeading`），彻底移出内容流；
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
    /// 「生成音频」的二次确认。生成要扣积分，误触代价高 —— 前置校验通过后先弹窗，
    /// 用户确认才真正走 `startGeneration()`。
    @State private var confirmGenerate = false

    // MARK: 键盘让位（底部条不能压到 accessory）

    /// 「键盘 + accessory」顶边的屏幕 Y（编辑器量出来的；nil = 键盘收起）
    @State private var keyboardTop: CGFloat? = nil
    /// 内容区底边的屏幕 Y（`.global` 坐标）
    @State private var contentBottom: CGFloat = 0
    /// 底部条还要再往上让多少 pt，才不会压到 accessory
    @State private var keyboardSeam: CGFloat = 0

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
                // ⚠️ 键盘弹出时按实测的差值让位：SwiftUI 自带的键盘避让不一定算上
                // `inputAccessoryView` 那一截，底部条会压进标签条里（见 `updateKeyboardSeam`）
                .padding(.bottom, keyboardSeam)
        }
        .background(c.backgroundGrouped)
        // 内容区底边（屏幕坐标 Y）：拿它跟「键盘 + accessory 顶边」比一下就知道压进去多少
        .background {
            GeometryReader { geo in
                Color.clear.preference(
                    key: ContentBottomKey.self,
                    value: geo.frame(in: .global).maxY - geo.safeAreaInsets.bottom)
            }
        }
        .onPreferenceChange(ContentBottomKey.self) { bottom in
            contentBottom = bottom
            // ⚠️ 只在布局量完之后算：拿「键盘还没升起时」的旧底边去减键盘顶边会算出天价
            withAnimation(.easeOut(duration: 0.2)) { updateKeyboardSeam() }
        }
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
        // ⚠️ 只要离开创作页就收键盘：键盘还在屏上时进二级页，返回后底部那条会错位
        // （成因与统一收口见 `TabRouter.push`）。这里同时兜住「切标签」这类不走 push 的离开。
        .onDisappear(perform: finishEditing)
    }

    /// 窄屏才让位：宽屏本来就两栏，没有空间压力
    private var collapseChrome: Bool { !metrics.usesTwoColumnStudio && isEditingText }

    // MARK: - 键盘让位

    /// 内容区底边压进「键盘 + accessory」多少，就让开多少 —— 要求**不重叠、距离为 0**。
    ///
    /// ⚠️ 差值必须实测，不能写死：SwiftUI 自带的键盘避让带不带 accessory 那一截，
    /// 同一条生命周期里都会变（通知里的键盘框有时只有键盘本身）。
    /// ⚠️ 上限 260pt 只是兜底：真量错了（比如拿到键盘升起前的旧底边）不至于把整条顶飞。
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
        .padding(.horizontal, metrics.pageMargin)
        .padding(.bottom, 10)          // 与底部 generateBar 只隔 10pt
        .frame(maxHeight: .infinity)   // 窄屏独占剩余高度
    }

    /// 标题 + 当前音色 + 字数（32.5pt）。键盘弹出时收成 0 高，字数由底部生成条接着显示。
    ///
    /// 窄屏没有侧栏的 `voiceRow`，已选音色名无处常驻 —— 收进这行的中间：
    /// 既不被工具栏标题挤占，又随手可点换音色。宽屏两栏在侧栏已有 `voiceRow`，这里不重复。
    private var cardHeader: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(c.accent)
                    Text("文本输入".localized())
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(c.textPrimary)
                }

                if !metrics.usesTwoColumnStudio {
                    Spacer(minLength: 4)
                    voiceHeaderChip
                    Spacer(minLength: 4)
                } else {
                    Spacer(minLength: 0)
                }

                Text("%d 字".localized(editor.charCount))
                    .font(.system(size: 11.5))
                    .foregroundStyle(c.textTertiary)

                Button { clearEditor() } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "trash")
                            .font(.system(size: 10.5, weight: .semibold))
                        Text("清空".localized())
                            .font(.system(size: 11.5, weight: .medium))
                    }
                    .foregroundStyle(c.textSecondary)
                    .padding(.horizontal, 8)
                    .frame(height: 22)
                    .background(
                        Capsule(style: .continuous)
                            .fill(c.surface3)
                            .overlay(Capsule(style: .continuous).strokeBorder(c.line, lineWidth: 0.5))
                    )
                }
                .buttonStyle(.plain)
                .disabled(!editor.hasContent)
                .opacity(editor.hasContent ? 1 : 0.4)
                .accessibilityLabel("清空文本".localized())
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

    // MARK: 底部生成条

    private var generateBar: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text("预计消耗".localized())
                    .font(.system(size: 11))
                    .foregroundStyle(c.textTertiary)
                Text("≈ \(formatCredits(estimatedPoints))")
                    .font(AuroraFont.mono17)
                    .foregroundStyle(c.textPrimary)
            }
            .fixedSize()
            .lineLimit(1)

            // ⚠️ 「生成音频」改成固定宽之后，多出来的横向空间得有东西吃掉：
            // 不吃掉的话 HStack 会把它摊给各子视图，固定宽就白设了。
            Spacer(minLength: 8)

            SecondaryButton(title: "", systemImage: "sparkles", height: 44, isFullWidth: false) {
                paramsPresented = true
            }
            .frame(width: barIconWidth)
            .accessibilityLabel("语音指令".localized())

            PrimaryButton(title: "生成音频".localized(), systemImage: "waveform",
                          width: generateButtonWidth) {
                requestGeneration()
            }

            doneButton
        }
        .padding(.horizontal, metrics.pageMargin)
        .padding(.top, 8)
        .padding(.bottom, 8)
        .background(c.bar)
        .overlay(alignment: .top) { Hairline() }
        // ⚠️ 二次确认挂在这里而不是 body 根视图：根视图上已经有一个 `.alert(item:)`，
        // 同一层再挂一个 `.alert` 会互相覆盖（这也是上一版才退而求其次用了
        // `confirmationDialog` 的原因 —— 挂子视图上就不冲突了）。
        .alert("确认生成音频".localized(), isPresented: $confirmGenerate) {
            Button("取消".localized(), role: .cancel) { }
            Button("确认".localized()) { startGeneration() }
        } message: {
            Text(generateConfirmMessage)
        }
    }

    /// 底部条右侧的「完成」：收键盘。
    ///
    /// ⚠️ 位置是从键盘 accessory 挪过来的：那一排 30 个胶囊里它既不起眼又和
    /// 插标签的动作混在一起；底部生成条**不会被键盘压住**（这也是字数为什么要挪到这里的原因），
    /// 挪过来之后「放下键盘」与「开始生成」两个出口并排，拇指不用离开这一行。
    ///
    /// ⚠️ UI 必须与「生成音频」拉开差距，否则两个同样大的实心按钮会互相抢：
    ///  * **生成音频**（`PrimaryButton`）= 渐变实心 + 白字 + 投影 + 吃掉剩余宽度 → 主操作；
    ///  * **完成** = 只有 1pt 描边、**没有填充也没有投影**、强调色文字、固定 74pt 宽 → 次要动作。
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
        // 键盘没弹出时它不是必需操作，压暗一档但保留可点（点一下也没有副作用）
        .opacity(isEditingText ? 1 : 0.55)
    }

    /// 「语音指令」图标键的宽度：这一行要挤下「预计消耗 + 图标 + 生成音频 + 完成」四组，
    /// 窄屏（< 375pt）再让 6pt 出来。
    private var barIconWidth: CGFloat { metrics.width < 375 ? 40 : 46 }

    /// 「生成音频」的固定宽度。
    ///
    /// ⚠️ 它原来是 `isFullWidth` 撑满剩余宽度 —— 于是「预计消耗」的数字多一位、
    /// 或者换个屏幕宽度，主操作按钮就跟着变长变短，看着像界面在抖。固定之后
    /// 这一行只有「完成」在键盘弹出时切换透明度，宽度不再变。
    /// 窄屏（< 375pt）按 375 算过：343 − 字数 90 − 图标 40 − 完成 66 − 三处间距 30 ≈ 117，取 112。
    private var generateButtonWidth: CGFloat { metrics.width < 375 ? 112 : 128 }

    /// 收键盘。
    ///
    /// ⚠️ 先写 `isEditingText`：顶部横条要从「打字态」恢复到常规态，靠的就是这个值，
    /// 等 `textViewDidEndEditing` 的异步回调回来才改会让横条慢半拍。
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
        // 当前音色的展示交给宽屏侧栏的 voiceRow 与音色 Sheet 自己。
        ToolbarItem(placement: .topBarLeading) { voiceSwapButton }

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

    /// 导航栏左侧的音色切换按钮：只放一个 🎭 图标，不带任何文本
    ///
    /// ⚠️ 之前这里是「头像 + 音色名 + 下拉箭头」的胶囊，中文名一长就把标题挤没了，
    /// 而且名称和右侧积分胶囊抢同一条横向空间。改成纯图标后左侧恒定 34pt。
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

    // MARK: - 行为

    private func restoreFromViewModel() {
        guard editor.doc.isEmpty, !vm.ttsItems.isEmpty else { return }
        let made = TokenDocument.make(items: vm.ttsItems)
        editor.replace(doc: made.doc, marks: made.marks)
    }

    /// 点「生成音频」：先收键盘 + 同步内容 + 前置校验，通过后才弹二次确认。
    ///
    /// ⚠️ 前置校验放在弹窗**之前**：文本为空 / 没选音色时直接报警，
    /// 不该让用户先过一道确认再被告知「生成不了」。
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

    /// 一键清空：正文 + 全部情感标记一起清掉，VM 侧同步清掉（`generate()` 读的是 VM）。
    ///
    /// ⚠️ 不加二次确认弹窗：文本内容还在键盘上方可见，误触成本可控，
    /// 而且根视图已经挂了一个 `.alert(item:)`，同一层再来一个会互相覆盖。
    private func clearEditor() {
        editor.clear()
        vm.ttsItems = []
        vm.text = ""
    }

    /// 二次确认的具体内容：**音色 + 本次要扣的积分**。
    ///
    /// ⚠️ 字数不进弹窗 —— 底部条上已经常显「预计消耗」，弹窗里重复一遍只会挤掉重点。
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
        vm.generate { _ in }
    }
}

/// 内容区底边（屏幕坐标 Y）—— 键盘让位时拿它跟 accessory 顶边比对
private struct ContentBottomKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
