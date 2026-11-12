//
//  VoiceStudioView.swift
//  EmotionVoice
//
//  Created by young on 2026/8/8.
//

import SwiftUI
import AppKit

/// 语音合成工作台
struct VoiceStudioView: View {

    @EnvironmentObject var appState: AppState
    @EnvironmentObject private var uiState: MacUIState
    @StateObject private var vm = VoiceStudioViewModel.shared
    @ObservedObject private var drafts = DraftStore.shared
    var isActive: Bool = true

    @State private var showVoiceLibrarySheet: Bool = false
    private var showGenerationModal: Bool { appState.showGenerationModal }
    /// 积分不足时弹出购买页面
    @State private var showCreditsPurchaseSheet: Bool = false
    
    /// 语气控制说明弹窗
    @State private var showEmotionRulePopover: Bool = false
    /// 中断说明弹窗
    @State private var showInterruptRulePopover: Bool = false
    /// 拟声效果说明弹窗
    @State private var showRichLanguageRulePopover: Bool = false
    /// 语音指令说明弹窗
    @State private var showNLRulePopover: Bool = false

    // MARK: 草稿
    @State private var showDraftModal: Bool = false
    /// 恢复确认 / 重命名 / 删除共用一个自定义 Dialog，避免多个 .alert 互相覆盖。
    @State private var draftDialog: DraftDialog? = nil
    @State private var draftRenameText: String = ""

    var body: some View {
        studioContent
            .overlay {
                if showDraftModal {
                    DraftModalView(store: drafts,
                                   isPresented: $showDraftModal,
                                   isKeyboardActive: draftDialog == nil,
                                   canSave: !currentSnapshot.isEmpty,
                                   onSave: saveCurrentDraft,
                                   onRestore: requestRestore,
                                   onRename: { d in
                                       draftRenameText = d.title
                                       presentDraftDialog(.rename(d))
                                   },
                                   onDuplicate: { d in drafts.duplicate(id: d.id) },
                                   onDelete: { d in presentDraftDialog(.delete(d)) },
                                   onDeleteAll: { presentDraftDialog(.deleteAll) })
                        .transition(.opacity)
                }
            }
            .overlay {
                if let dialog = draftDialog {
                    DraftDialogView(kind: dialog,
                                    renameText: $draftRenameText,
                                    onCancel: { draftDialog = nil },
                                    onConfirm: { confirmDraftDialog(dialog) })
                }
            }
            .allowsHitTesting(isActive && !showGenerationModal)
            .suppressesCursorRects(showGenerationModal)
            .sheet(isPresented: $showVoiceLibrarySheet) {
                VoiceLibrarySheet()
                    .frame(width: 1400, height: 830)
            }
            .sheet(isPresented: $showCreditsPurchaseSheet) {
                CreditsPurchaseView()
                    .frame(width: 600, height: 600)
            }
            .onAppear {
            // 初始化音色：上次使用的音色优先，没有则回落到旗舰默认音色（idx 1）
            appState.resolveSelectedVoice()
            vm.selectedVoiceKey = appState.selectedVoice?.key ?? appState.defaultVoiceKey
            // 记忆的音色在当前音色库中已不存在时，兜底到旗舰默认音色
            if vm.voice == nil {
                vm.selectedVoiceKey = appState.defaultVoiceKey
                appState.selectedVoice = appState.defaultVoice
            }
            StudioParamStore.shared.restoreIfNeeded(to: vm, defaults: studioParamDefaults)
        }
        .onChange(of: appState.selectedVoice?.key) { _, newKey in
            // 从音色库跳转过来时同步选中音色
            if let newKey, !newKey.isEmpty {
                vm.selectedVoiceKey = newKey
            }
        }
        .onChange(of: isActive) { _, active in
            guard !active else { return }
            // 本页常驻：失活时收掉所有挂在本页的浮层，避免它们浮到别的分区上。
            // 生成弹窗在 AppState / GenerationOverlay 上，是刻意跨页存在的，不动。
            showVoiceLibrarySheet = false
            showCreditsPurchaseSheet = false
            showEmotionRulePopover = false
            showInterruptRulePopover = false
            showRichLanguageRulePopover = false
            showNLRulePopover = false
            showDraftModal = false
            draftDialog = nil
            // 常驻页失活 = 用户离开创作台：静默兜底一条覆盖式「自动保存」。
            autoSaveCurrent()
        }
        // 四项参数实时落盘：改完即使立刻退出 App 也不丢。
        // ⚠️ 不再像以前那样回写 `appState.defaultFormat` / `defaultSampleRate`：
        //    工作台调参数不该改写用户在设置页配的全局默认值（与 iOS 一致）。
        .onChange(of: vm.rate) { _, _ in StudioParamStore.shared.save(from: vm) }
        .onChange(of: vm.volume) { _, _ in StudioParamStore.shared.save(from: vm) }
        .onChange(of: vm.selectedFormat) { _, _ in StudioParamStore.shared.save(from: vm) }
        .onChange(of: vm.sampleRate) { _, _ in StudioParamStore.shared.save(from: vm) }
        // ⌘S / 文件菜单 / 卡片按钮共用 saveSignal，统一弹一条「草稿已保存」。
        .onChange(of: drafts.saveSignal) { _, _ in
            uiState.showToast(.success("草稿已保存".localized()))
        }
        // 退出 App 前再兜一次，覆盖「没切过页就直接 ⌘Q」的路径。
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            autoSaveCurrent()
        }
    }

    private var studioParamDefaults: StudioParamValues {
        StudioParamValues(rate: StudioParamValues.factory.rate,
                          volume: StudioParamValues.factory.volume,
                          format: appState.defaultFormat,
                          sampleRate: appState.defaultSampleRate)
    }

    // MARK: - 草稿入口

    private var currentSnapshot: DraftSnapshot { DraftSnapshot.capture(from: vm) }

    private var clearButton: some View {
        Button {
            clearEditor()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "xmark.circle")
                    .font(.system(size: 10, weight: .semibold))
                Text("清空".localized())
                    .font(.system(size: 10.5, weight: .semibold))
            }
            .foregroundStyle(AppColor.textSecondary)
            .padding(.horizontal, 9)
            .frame(height: 24)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(AppColor.borderMedium, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .disabled(currentSnapshot.isEmpty)
        .opacity(currentSnapshot.isEmpty ? 0.45 : 1)
        .help("清空".localized())
    }

    private var draftSaveButton: some View {
        Button {
            saveCurrentDraft()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 10, weight: .semibold))
                Text("保存".localized())
                    .font(.system(size: 10.5, weight: .semibold))
            }
            .foregroundStyle(AppColor.accentGlow)
            .padding(.horizontal, 9)
            .frame(height: 24)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(AppColor.accentWash)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(AppColor.accentLine,
                                    style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .disabled(currentSnapshot.isEmpty)
        .opacity(currentSnapshot.isEmpty ? 0.45 : 1)
        .help("⌘ S 快速保存".localized())
    }

    /// 「草稿 N」：角标 >99 显示 99+、为 0 时隐藏。
    private var draftListButton: some View {
        Button {
            // 打开前先结算编辑器去抖：列表里的「保存当前编辑」和空态判断都要读最新内容。
            commitEditor()
            withAnimation(.easeOut(duration: 0.16)) { showDraftModal = true }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "folder")
                    .font(.system(size: 10, weight: .semibold))
                Text("草稿".localized())
                    .font(.system(size: 10.5, weight: .semibold))
                if drafts.count > 0 {
                    Text(drafts.count > 99 ? "99+" : "\(drafts.count)")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(AppColor.bgPrimary)
                        .frame(minWidth: 15, minHeight: 15)
                        .padding(.horizontal, 3)
                        .background(Capsule().fill(AppColor.accentPrimary))
                }
            }
            .foregroundStyle(showDraftModal ? AppColor.accentGlow : AppColor.textSecondary)
            .padding(.horizontal, 9)
            .frame(height: 24)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(AppColor.borderMedium, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
    }

    // MARK: - 草稿行为

    /// 清空编辑区：复用 VM 的 `clearText()`（正文 + 标签 + 上一条生成结果），
    /// 并把「编辑中」标记摘下 —— 工作区内容已与那条草稿不一致，不该再标它。
    private func clearEditor() {
        commitEditor()
        guard !currentSnapshot.isEmpty else { return }
        // `clearTokensTrigger` 会重建 NSTextView，先交出 firstResponder 避免光标错位
        resignTextEditor()
        vm.clearText()
        drafts.markEditing(nil)
    }

    private func saveCurrentDraft() {
        commitEditor()
        let snap = currentSnapshot
        guard !snap.isEmpty else { return }
        // 顶部提示统一由 saveSignal 弹，快捷键 / 菜单 / 按钮三条通道不会重复提示
        drafts.save(snap, source: .manual)
    }

    /// 静默兜底：退后台 / 切分区 / 恢复前，恒定覆盖单条「自动保存」。
    private func autoSaveCurrent() {
        commitEditor()
        let snap = currentSnapshot
        guard !snap.isEmpty else { return }
        drafts.save(snap, source: .auto, notify: false)
    }

    /// 把编辑器里还在去抖窗口（0.35s）内的输入立刻结算给 VM。
    /// ⚠️ 保存 / 恢复前必须调用：否则 `currentSnapshot` 读到的是旧内容，
    ///    而那条迟到的回调会在 `vm.apply` 之后才跑，把刚恢复的正文又写回旧内容。
    private func commitEditor() {
        EmotionTokenTextView.active?.commitPendingChangesNow()
    }

    private func requestRestore(_ d: Draft) {
        commitEditor()
        // 状态矩阵：仅「当前编辑区非空 + 点草稿」才需要确认。
        // ⚠️ 这里**不关**列表：确认层直接压在列表上，取消后还能接着挑另一条；
        //    真正恢复成功才由 `performRestore` 收起 modal。
        if currentSnapshot.isEmpty {
            performRestore(d)
        } else {
            presentDraftDialog(.restore(d))
        }
    }

    /// 打开草稿自定义 Dialog。**必须先让编辑区交出 firstResponder**：
    /// 这层浮层是普通 SwiftUI overlay，不会自己变成 key window，NSTextView 仍然是
    /// first responder —— 弹窗挡住编辑区的时候，打字 / 空格会继续落到下面的正文里。
    /// ⚠️ 同时 `draftDialog != nil` 会参与 `isInteractive`，编辑区顺带变成不可编辑、
    ///    不注册 I-beam；Dialog 关掉后 `updateNSView` 再把焦点还回编辑区。
    private func presentDraftDialog(_ dialog: DraftDialog) {
        resignTextEditor()
        draftDialog = dialog
    }

    private func performRestore(_ d: Draft) {
        // 恢复成功就收起草稿 modal（内容整体切换，留在列表上没有意义）。
        showDraftModal = false
        // ⚠️ 先把编辑器里未同步的输入结算给 VM，再取兜底快照：
        //    否则 `before` 是旧内容，而且那条迟到的同步回调会在 `vm.apply` 之后才执行，
        //    把刚写进 binding 的新正文又覆盖回旧内容 —— 表现就是「点恢复，编辑器没变化」。
        commitEditor()
        let before = currentSnapshot

        guard let full = drafts.load(id: d.id) else { return }

        // 恢复前兜底：现有内容存成**一条新的草稿**（不覆盖「上次编辑」那个单槽位）。
        // 这样连续切换多份草稿，中间每一份内容都留得住，谁都不会被下一次兜底盖掉。
        drafts.stashBeforeRestore(before)

        // ⚠️ 恢复会重建 NSTextView 内容：先交出 firstResponder 再写，避免光标错位。
        resignTextEditor()
        vm.apply(full, appState: appState)
        // 正文不再被兜底覆盖，所以「编辑中」可以老实标在目标上（含「上次编辑」那条）。
        drafts.restore(full.id)

        uiState.showToast(.success("草稿已恢复".localized()))
    }

    /// 让编辑区交出键盘。
    /// ⚠️ 先看 `mainWindow` 再看 `keyWindow`：从 NSPopover（草稿列表）里点出来的动作，
    ///    `keyWindow` 可能是 popover 自己的窗口，拿它去找 NSTextView 会找不到、白跑一趟。
    private func resignTextEditor() {
        for window in [NSApp.mainWindow, NSApp.keyWindow].compactMap({ $0 }) {
            if window.firstResponder is NSTextView {
                window.makeFirstResponder(nil)
                return
            }
        }
    }

    private func confirmDraftDialog(_ dialog: DraftDialog) {
        switch dialog {
        case .restore(let d):
            draftDialog = nil
            performRestore(d)
        case .rename(let d):
            drafts.rename(id: d.id, title: draftRenameText)
            draftDialog = nil
        case .delete(let d):
            drafts.delete(id: d.id)
            draftDialog = nil
        case .deleteAll:
            drafts.deleteAll()
            draftDialog = nil
        }
    }

    /// 工作台主体（不含生成弹窗）
    private var studioContent: some View {
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
        .padding(.horizontal, 15)
        .padding(.vertical, 15)
        // 撑满所在区域，遮罩才能铺满整个窗口；两列高度仍是内容自身高度并垂直居中
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 文本编辑器

    /// 编辑区是否可交互 / 可抢焦点：分区可见、且没有被浮层（生成弹窗 / 草稿 modal / 草稿 Dialog）挡住。
    /// ⚠️ 草稿列表改成 modal 后同样要参与这个判据，否则鼠标点卡片、按空格回车
    ///    仍会落进底下的正文（overlay 不会自动变成 key window）。
    /// ⚠️ 草稿 Dialog 虽然只是 SwiftUI overlay，但它出现时键盘必须归它所有；
    ///    `presentDraftDialog` 会立刻交出 firstResponder，这里保证状态持续成立
    ///    （打字、I-beam、选中全部关掉），Dialog 消失后 `updateNSView` 会把焦点还回编辑区。
    private var isEditorInteractive: Bool {
        isActive && !showGenerationModal && draftDialog == nil && !showDraftModal
    }

    private var textEditorCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("%d 字".localized(vm.charCount))
                    .font(AppFont.monoSmall)
                    .foregroundStyle(AppColor.textTertiary)
                Spacer(minLength: 8)
                draftSaveButton
                draftListButton
                clearButton
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
                insertTokenCategory: vm.insertTokenCategory,
                clearTrigger: vm.clearTokensTrigger,
                textBinding: $vm.text,
                // 生成弹窗 / 草稿 Dialog / 分区隐藏期间让文本域彻底不可交互：
                // 不抢焦点、不注册 I-beam 光标区。isInteractive 变化时
                // updateNSView 会置 isEditable/isSelectable = false 并交出 firstResponder。
                isInteractive: isEditorInteractive
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

    /// 情感控制面板：包含语气控制（23个）和拟声效果（7个）
    /// 采用分组式布局，参考拟声效果的视觉风格
    private var emotionCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 标题区：语气控制 + 数量统计
            HStack {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 12))
                    .foregroundStyle(AppColor.accentPrimary)
                Text("语气控制".localized())
                    .font(.system(size: 14, weight: .semibold))
                
                Button {
                    showEmotionRulePopover.toggle()
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 13))
                        .foregroundStyle(AppColor.textTertiary)
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
                .popover(isPresented: $showEmotionRulePopover) {
                    RulePopover(title: "语气控制".localized()) {
                        RuleBullet(text: "控制类标签用于设定语音的情感或风格".localized())
                        RuleBullet(text: "将标签写在文本中，标签会作用于其后的所有文本".localized())
                        RuleBullet(text: "直到遇到下一个控制类标签，或被中断标签提前结束".localized())
                    }
                }

                Spacer()
            }

            // 中断：不是一种情绪，而是「从这里恢复正常语气」的作用域边界
            HStack(spacing: 6) {
                InterruptTagButton {
                    vm.insertInterrupt()
                }

                Button {
                    showInterruptRulePopover.toggle()
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 13))
                        .foregroundStyle(AppColor.textTertiary)
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
                .popover(isPresented: $showInterruptRulePopover) {
                    RulePopover(title: Constants.interruptItem.label.localized()) {
                        RuleBullet(text: "终止前一个语气标签的作用".localized())
                        RuleBullet(text: "从插入位置起，文本回到音色本身的默认状态朗读，不带任何情绪基调".localized())
                        RuleBullet(text: "作用持续到下一个语气标签，期间可以正常插入拟声效果".localized())
                    }
                }

                Spacer()
            }

            // 控制类情感网格（23 个）- 使用流式布局，参考拟声效果风格
            emotionTagsGrid

            // 分隔区域：拟声效果
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "waveform.badge.plus")
                        .font(.system(size: 11))
                        .foregroundStyle(AppColor.accentPrimary)
                    Text("拟声效果".localized())
                        .font(.system(size: 14, weight: .semibold))
                    Button {
                        showRichLanguageRulePopover.toggle()
                    } label: {
                        Image(systemName: "info.circle")
                            .font(.system(size: 13))
                            .foregroundStyle(AppColor.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .pointingHandCursor()
                    .popover(isPresented: $showRichLanguageRulePopover) {
                        RulePopover(title: "拟声效果".localized()) {
                            RuleBullet(text: "在当前位置插入一段拟声效果".localized())
                            RuleBullet(text: "不影响前后文本的情感风格".localized())
                        }
                    }
                    
                    Spacer()
                }

                // 拟声标签网格（流式布局，自动换行）
                FlowLayout(spacing: 6) {
                    ForEach(Constants.richLanguageTags) { tag in
                        RichLanguageTagButton(tag: tag) {
                            vm.insertEmotion(tag: tag.tag)
                        }
                    }
                }
            }
            .padding(12)
            // 后台接收卡片锚在这个区块的右下角：关掉生成弹窗后接收仍在跑，
            // 它是工作台里唯一能看出"还在接收"的地方。
            // 7 个拟声标签在宽屏下排不满一行，右侧是空的，卡片正好落在空白里不压标签。
            .overlay(alignment: .bottomTrailing) {
                if vm.isGenerating && !appState.showGenerationModal {
                    BackgroundReceivingCard {
                        appState.showGenerationModal = true
                    }
                    .padding(.trailing, 10)
                    .padding(.bottom, 8)
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .opacity
                    ))
                }
            }
            .animation(.easeInOut(duration: 0.25), value: vm.isGenerating)
        }
        .padding(18)
        .background(AppColor.bgSecondary)
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.large)
                .stroke(AppColor.borderSubtle, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.large))
    }

    /// 控制类情感标签网格（23 个情感按钮）
    /// 使用流式布局，自动换行，参考拟声效果风格
    private var emotionTagsGrid: some View {
        FlowLayout(spacing: 6) {
            ForEach(Constants.emotions) { emotion in
                EmotionTagButton(emotion: emotion) {
                    vm.insertEmotion(tag: emotion.tag)
                }
            }
        }
    }

    // MARK: - 情感卡片子组件

    /// 说明弹窗容器（语气控制 / 中断 / 拟声效果 三处共用）
    ///
    /// 抽出来的原因：三处弹窗的版式完全一样（标题 + bullet 列表 + 16pt 内边距），
    /// 之前各写一份，改版式要同时改三处。
    struct RulePopover<Content: View>: View {
        let title: String
        @ViewBuilder var content: Content

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.bottom, 4)
                content
                    .foregroundStyle(AppColor.textSecondary)
            }
            .padding(16)
            .presentationCompactAdaptation(.popover)
        }
    }

    /// 说明弹窗里的一条 bullet
    struct RuleBullet: View {
        let text: String

        var body: some View {
            HStack(alignment: .top, spacing: 8) {
                Circle()
                    .fill(AppColor.accentPrimary)
                    .frame(width: 5, height: 5)
                    .padding(.top, 6)
                Text(text)
                    .font(AppFont.caption)
            }
        }
    }

    /// 中断标签按钮
    ///
    /// 语义上它不是一个「语气」，而是**撤销语气**：插入到文本里表示
    /// 「从这里开始用音色本身的默认状态朗读」，直到遇到下一个语气标签。
    /// 所以它单列在语气网格之外，视觉上也刻意做成安静的次级样式。
    struct InterruptTagButton: View {
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.uturn.backward.circle")
                        .font(.system(size: 12))
                        .foregroundStyle(AppColor.textPrimary)
                    Text(Constants.interruptItem.label.localized())
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(AppColor.textPrimary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(AppColor.bgTertiary.opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.small)
                    .stroke(AppColor.borderSubtle, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.small))
            }
            .buttonStyle(.plain)
            .help(Constants.interruptItem.description.localized())
            .pointingHandCursor()
        }
    }

    /// 语气控制标签按钮
    /// 包含 emoji 和中文标签，参考拟声效果的视觉风格
    struct EmotionTagButton: View {
        let emotion: EmotionItem
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                HStack(spacing: 5) {
                    Text(emotion.emoji)
                        .font(.system(size: 14))
                    Text(emotion.label.localized())
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(AppColor.textPrimary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(AppColor.bgSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.small)
                        .stroke(AppColor.borderSubtle, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.small))
            }
            .buttonStyle(.plain)
            .help(emotion.description.localized())
            .pointingHandCursor()
        }
    }

    /// 拟声效果标签按钮
    /// 包含 emoji 和中文标签
    struct RichLanguageTagButton: View {
        let tag: EmotionItem
        let action: () -> Void

        var body: some View {
            Button(action: action) {
                HStack(spacing: 5) {
                    Text(tag.emoji)
                        .font(.system(size: 14))
                    Text(tag.label.localized())
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(AppColor.textPrimary)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(AppColor.bgSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.small)
                        .stroke(AppColor.borderSubtle, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.small))
            }
            .buttonStyle(.plain)
            .help(tag.description.localized())
            .pointingHandCursor()
        }
    }

    // MARK: - 右侧面板

    private var editPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                voiceCard
                audioControlCard
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
                Text("%d 个可用".localized(appState.voices.count))
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textTertiary)
            }

            // 当前音色
            if let voice = vm.voice {
                HStack(spacing: 10) {
                    AvatarView(text: voice.localizedAvatar, size: 40, seed: voice.key)
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Text(voice.localizedName)
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
                        if !voice.localizedDesc.isEmpty {
                            Text(voice.localizedDesc)
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
                            .padding(.vertical, 6)
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
            //
            // 播放态的订阅下沉到 VoiceRowPlayback 内部：工作台本体不再订阅播放器，
            // 否则试听/播放时 10Hz 的刷新会把整页（含 NSTextView 编辑器）拖着重算。
            // 与 AudioPlayerDetailView 的"订阅下沉"约定一致。
            VStack(spacing: 4) {
                ForEach(alternateVoices) { v in
                    VoiceRowPlayback(
                        voice: v,
                        isSelected: vm.selectedVoiceKey == v.key
                    ) {
                        vm.selectedVoiceKey = v.key
                        appState.selectedVoice = v
                    } onPreview: {
                        AudioPreviewPlayer.shared.toggle(voice: v)
                    }
                }
            }

            Button {
                showVoiceLibrarySheet = true
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "square.grid.2x2")
                        .font(.system(size: 10))
                    Text("查看更多音色".localized())
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

    /// 备选音色：只显示用户收藏的音色，最多显示 6 个（旗舰优先，其次按名字典序）
    private var alternateVoices: [Voice] {
        let all = appState.voices

        let favorites = all.filter { $0.isFavorite }

        return favorites
            .sorted { a, b in
                if a.isPremium != b.isPremium { return a.isPremium }
                return a.name < b.name
            }
            .prefix(6)
            .map { $0 }
    }

    // MARK: - 音频控制卡片（语速/音量）

    /// 语速/音量卡片。移出 emotionCard，统一在右侧面板集中展示音频输出参数。
    /// 横向空间受限，slider 在该卡片内采用上下纵向排列。
    private var audioControlCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("🎚️ 语音控制".localized())
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                // 「重置」覆盖下面语速 / 音量 / 格式 / 采样率四项，与 iOS 参数 Sheet 同构。
                // 音色、语音指令不参与重置。
                // ⚠️ 别传 studioParamDefaults：设置页里存过 WAV 会让「重置」回到 WAV。
                //    重置的语义是「恢复出厂默认」（当前 mp3 / 22050 / 1.0x / 100%），
                //    设置页那两项只影响「首次启动、无存档」时的起点。
                Button {
                    StudioParamStore.shared.reset(on: vm)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 11, weight: .semibold))
                        Text("重置".localized())
                            .font(.system(size: 12, weight: .medium))
                    }
                    .foregroundStyle(AppColor.accentPrimary)
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
                .accessibilityLabel("重置".localized())
                .accessibilityHint("恢复语速、音量、格式与采样率的默认参数".localized())
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
            
            HStack {
                Text("格式".localized())
                    .font(AppFont.caption)

                HStack(spacing: 4) {
                    ForEach(["mp3", "wav"], id: \.self) { format in
                        let selected = vm.selectedFormat.lowercased() == format.lowercased()
                        Button {
                            vm.selectedFormat = format.uppercased()
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
                Button {
                    showNLRulePopover.toggle()
                } label: {
                    Image(systemName: "info.circle")
                        .font(.system(size: 13))
                        .foregroundStyle(AppColor.textTertiary)
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
                .popover(isPresented: $showNLRulePopover) {
                    NLRulePopover()
                        .presentationCompactAdaptation(.popover)
                }
                Spacer()
                Text("自然语言".localized())
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textTertiary)
            }

            // 语言选择区域
            nlLanguageSelector

            // 预设描述区域
            nlPresetsSelector

            HStack {
                HStack {
                    Image(systemName: "lightbulb.min")
                        .font(.system(size: 10))
                        .foregroundStyle(.yellow)
                    Text("详细描述 = 更好的效果".localized())
                        .font(AppFont.monoSmall)
                        .foregroundStyle(AppColor.textTertiary)
                }
                
                Spacer()
                Text("\(vm.nlInstruction.count) / 1000")
                    .font(AppFont.monoSmall)
                    .foregroundStyle(vm.nlInstruction.count >= 1000 ? AppColor.accentPrimary : AppColor.textTertiary)
            }
            
            // 输入框
            ZStack(alignment: .topLeading) {
                if vm.nlInstruction.isEmpty {
                    Text("描述你想听到的声音...".localized())
                        .font(AppFont.bodyMedium)
                        .foregroundStyle(AppColor.textTertiary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 3)
                        .allowsHitTesting(false)
                }
                TextEditor(text: Binding(
                    get: { vm.nlInstruction },
                    set: { newValue in
                        // 限制字符数不超过 1000
                        if newValue.count <= 1000 {
                            vm.nlInstruction = newValue
                        }
                    }
                ))
                    .font(AppFont.bodyMedium)
                    .foregroundStyle(AppColor.textPrimary)
                    .scrollContentBackground(.hidden)
                    .padding(.horizontal, 2)
                    .padding(.vertical, 3)
            }
            .background(AppColor.bgTertiary)
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.small)
                    .stroke(AppColor.borderSubtle, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.small))
            .frame(height: 120)
        }
        .padding(16)
        .background(AppColor.bgSecondary)
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.large)
                .stroke(AppColor.borderSubtle, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.large))
    }

    // MARK: - 语言选择器

    /// 语言选择区域：只切换 chip 选中态 / language_hints，与下方「描述预设」的指令输入框互不影响。
    /// ⚠️ 别在这里调用 `vm.updateNLInstruction()` 之类把语言名写进输入框的方法。
    private var nlLanguageSelector: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("🌐 语言".localized())
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppColor.textTertiary)

            // 语言选择网格（流式布局）
            FlowLayout(spacing: 4) {
                ForEach(Constants.nlLanguages) { lang in
                    Button {
                        // 切换语言选择
                        vm.toggleLanguage(lang.name)
                    } label: {
                        Text(lang.name.localized())
                            .font(.system(size: 10))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(vm.selectedLanguage == lang.name ? AppColor.accentPrimary : AppColor.bgTertiary)
                            .foregroundStyle(vm.selectedLanguage == lang.name ? .white : AppColor.textSecondary)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)
                    .pointingHandCursor()
                }
            }
        }
        .padding(10)
        .background(AppColor.bgTertiary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.small))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.small)
                .stroke(AppColor.borderSubtle, lineWidth: 1)
        )
    }

    // MARK: - 预设描述选择器

    /// 预设描述区域：点击后应用预设内容（单选切换）
    private var nlPresetsSelector: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("✨ 描述预设".localized())
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(AppColor.textTertiary)

            // 预设芯片网格（流式布局，撑满宽度）
            FlowLayout(spacing: 6) {
                ForEach(vm.nlPresets, id: \.self) { preset in
                    Button {
                        // 应用预设（单选切换）
                        vm.applyPreset(preset)
                    } label: {
                        Text(preset.localized())
                            .font(AppFont.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(vm.selectedPreset == preset ? AppColor.accentPrimary : AppColor.bgTertiary)
                            .foregroundStyle(vm.selectedPreset == preset ? .white : AppColor.textSecondary)
                            .clipShape(Capsule())
                            .overlay(
                                Capsule().stroke(vm.selectedPreset == preset ? AppColor.accentPrimary : AppColor.borderSubtle, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .pointingHandCursor()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(10)
        .background(AppColor.bgTertiary.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.small))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.small)
                .stroke(AppColor.borderSubtle, lineWidth: 1)
        )
    }

    // MARK: - 辅助方法

    /// 生成栏：生成按钮 + 积分信息
    /// - 生成音频按钮（主操作）
    /// - 总积分余额 / 本月已用 / 预计
    /// - 跳转积分中心入口
    private var generateBar: some View {
        let state = appState
        
        return HStack(spacing: 10) {
            // 左侧：生成音频按钮
            PrimaryButton(title: "生成语音".localized(), icon: "waveform") {
                // 1. 验证文本和音色
                if !validateInputs() { return }
                // 2. 验证积分是否足够（按实际消耗的小数值比较，无向上取整）
                let points = vm.estimatedPoints
                guard CreditsService.shared.canConsume(points) else {
                    showCreditsPurchaseSheet = true
                    return
                }
                // 3. 积分充足，开始生成（弹窗开关在 AppState 上，全局承载）
                state.showGenerationModal = true
                vm.generate { success in
                    if success {
                        state.refreshCredits()
                        // 生成成功后音频进「项目 / 历史」；草稿只打标，30 天后清理，两者不混列。
                        drafts.markGenerated()
                    }
                }
            }
            
            Spacer()
            
            // 右侧：积分信息
            HStack(spacing: 5) {
                
                VStack(alignment: .leading) {
                    // 剩余
                    HStack {
                        Text("剩余")
                            .font(AppFont.monoSmall)
                            .foregroundStyle(AppColor.textTertiary)
                        Text(formatCredits(state.creditsBalance))
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(AppColor.accentPrimary)
                    }
                    
                    Rectangle()
                        .fill(AppColor.borderSubtle)
                        .frame(height: 1)
                    
                    // 预计
                    HStack {
                        Text("预计")
                            .font(AppFont.monoSmall)
                            .foregroundStyle(AppColor.textTertiary)
                        Text(formatCredits(vm.estimatedPoints))
                            .font(.system(size: 12, weight: .semibold))
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
    
    /// 验证输入是否正确（仅检查文本和音色，不含积分检查）
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
        return true
    }
}

// MARK: - 音色行的播放态订阅

/// 把"这个音色现在是不是在放"的订阅关在这一层
///
/// 工作台本体用非观察的方式持有播放器，播放时 10Hz 的 progress / currentTime
/// 更新只会让这一个小小的行视图重绘，不会牵动整页（含 NSTextView 编辑器）。
/// 与 `AudioPlayerDetailView` 的注释里那条约定是同一件事。
private struct VoiceRowPlayback: View {

    let voice: Voice
    let isSelected: Bool
    var onTap: () -> Void
    var onPreview: () -> Void

    @ObservedObject private var player = AudioPreviewPlayer.shared

    var body: some View {
        VoiceRow(
            voice: voice,
            isSelected: isSelected,
            isPlaying: player.isPlaying(key: voice.key),
            action: onTap,
            onPreview: onPreview
        )
    }
}

// MARK: - 语音指令说明弹窗

/// 语音指令编写指南弹窗
struct NLRulePopover: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // 标题
                Text("如何编写高质量的声音描述")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(AppColor.textPrimary)

                // 核心原则
                VStack(alignment: .leading, spacing: 10) {
                    Text("核心原则")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppColor.accentPrimary)

                    ruleRow(
                        "1",
                        "具体而非模糊",
                        "使用描绘声音特质的词语，如 “低沉” “清脆” “语速偏快”，避免 “好听” “普通” 等模糊的表述。"
                    )

                    ruleRow(
                        "2",
                        "多维而非单一",
                        "好的描述通常涵盖多个维度，如性别、年龄、情感等。仅写 “女声” 过于宽泛，难以生成有特色的音色。"
                    )

                    ruleRow(
                        "3",
                        "客观而非主观",
                        "聚焦声音的物理和感知特征。例如，用 “音调偏高，富有活力” 代替 “我最喜欢的声音”。"
                    )

                    ruleRow(
                        "4",
                        "原创而非模仿",
                        "描述声音的特质，而非要求模仿特定人物，如名人或演员。模型不支持模仿特定人物，且此类要求可能涉及版权风险。"
                    )

                    ruleRow(
                        "5",
                        "简洁而非冗余",
                        "确保每个词都有明确作用，避免重复的同义词或无意义的修饰。"
                    )
                }

                Divider()

                // 描述维度参考
                VStack(alignment: .leading, spacing: 12) {
                    Text("描述维度参考")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppColor.accentPrimary)

                    Text("建议组合以下维度描述声音，维度越丰富，生成效果越精准。")
                        .font(AppFont.caption)
                        .foregroundStyle(AppColor.textSecondary)

                    dimensionTable()
                }

                Divider()

                // 示例
                VStack(alignment: .leading, spacing: 10) {
                    Text("示例")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppColor.accentPrimary)

                    exampleRow("标准播音风格", "吐字清晰精准，字正腔圆")
                    exampleRow("年轻女性声音", "语速较快，带有明显的上扬语调，适合介绍时尚产品")
                    exampleRow("沉稳中年男性", "语速缓慢，音色低沉有磁性，适合朗读新闻或纪录片解说")
                    exampleRow("温柔知性女性", "30岁左右，语调平和，适合有声书朗读")
                    exampleRow("可爱儿童声音", "大约8岁女孩，说话略带稚气，适合动画角色配音")
                }
            }
            .padding(20)
        }
        .textSelection(.enabled)
        .frame(width: 500, height: 600)
    }

    private func ruleRow(_ number: String, _ title: String, _ content: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(number.localized())
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 18, height: 18)
                .background(AppColor.accentPrimary)
                .clipShape(Circle())
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(title.localized())
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppColor.textPrimary)
                Text(content.localized())
                    .font(AppFont.caption)
                    .foregroundStyle(AppColor.textSecondary)
            }
        }
    }

    private func dimensionTable() -> some View {
        let rows: [(String, String)] = [
            ("性别", "男性、女性、中性"),
            ("年龄", "儿童、青少年、青年、中年、老年"),
            ("音调", "高音、中音、低音、偏高、偏低"),
            ("语速", "快速、中速、缓慢、偏快、偏慢"),
            ("情感", "开朗、沉稳、温柔、严肃、活泼、冷静、治愈"),
            ("特点", "有磁性、清脆、沙哑、圆润、甜美、浑厚、有力"),
            ("用途", "新闻播报、广告配音、有声书、动画角色、语音助手")
        ]

        return VStack(spacing: 0) {
            // 表头
            HStack(spacing: 0) {
                Text("维度")
                    .frame(width: 60, alignment: .leading)
                Text("描述示例")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(AppColor.textPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(AppColor.bgTertiary)

            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                dimensionRow(row.0, row.1, index: index)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(AppColor.borderSubtle, lineWidth: 1)
        )
    }

    private func dimensionRow(_ label: String, _ content: String, index: Int) -> some View {
        HStack(spacing: 0) {
            Text(label.localized())
                .frame(width: 60, alignment: .leading)
            Text(content.localized())
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(AppFont.caption)
        .foregroundStyle(AppColor.textSecondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(index % 2 == 0 ? Color.clear : AppColor.bgTertiary.opacity(0.3))
    }

    private func exampleRow(_ title: String, _ content: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(AppColor.accentPrimary)
                Text(title.localized())
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(AppColor.textPrimary)
            }
            Text(content.localized())
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textSecondary)
                .padding(.leading, 18)
        }
        .padding(.vertical, 4)
    }
}
