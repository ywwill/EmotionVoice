//
//  VoiceStudioDraft.swift
//  EmotionVoice
//

import SwiftUI
import AppKit

enum DraftDialog {
    case restore(Draft)
    case rename(Draft)
    case delete(Draft)
}

struct DraftModalView: View {
    @ObservedObject var store: DraftStore
    @Binding var isPresented: Bool

    let isKeyboardActive: Bool
    let canSave: Bool
    let onSave: () -> Void
    let onRestore: (Draft) -> Void
    let onRename: (Draft) -> Void
    let onDuplicate: (Draft) -> Void
    let onDelete: (Draft) -> Void

    @FocusState private var listFocused: Bool
    @State private var selection: Int = 0

    private var allDrafts: [Draft] { store.manual + store.auto }

    var body: some View {
        ZStack {
            // 遮罩：点空白关闭。不用 material —— 工作台本身是暗色，透上来只会干扰阅读。
            Rectangle()
                .fill(Color.black.opacity(0.55))
                .contentShape(Rectangle())
                .onTapGesture { close() }

            VStack(alignment: .leading, spacing: 0) {
                header
                saveRow
                Divider().background(AppColor.borderSubtle)
                if store.count == 0 {
                    emptyView
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            if !store.manual.isEmpty {
                                sectionHeader("已保存的草稿".localized(), count: store.manual.count)
                                ForEach(store.manual) { d in
                                    row(d)
                                }
                            }
                            if !store.auto.isEmpty {
                                sectionHeader("自动保存".localized(), count: store.auto.count)
                                ForEach(store.auto) { d in
                                    row(d)
                                }
                            }
                        }
                        .padding(.horizontal, 10)
                        .padding(.bottom, 8)
                    }
                    .frame(maxHeight: 420)
                }
                footer
            }
            .frame(width: 440)
            // 卡片比工作台底（bgPrimary）亮一档，配大阴影才有「浮起」感；
            // 与列表 footer 同色，靠 Divider 分栏（保持原面板视觉）。
            .background(AppColor.bgTertiary)
            .clipShape(RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16)
                .stroke(AppColor.borderMedium, lineWidth: 1))
            .shadow(color: .black.opacity(0.55), radius: 32, y: 14)
        }
        .focusable(isKeyboardActive)
        .focusEffectDisabled()
        .focused($listFocused)
        .onAppear {
            DispatchQueue.main.async { listFocused = true }
        }
        .onChange(of: isKeyboardActive) { _, active in
            if active { listFocused = true }
        }
        .onExitCommand { close() }
        .onKeyPress(.upArrow) {
            guard isKeyboardActive, !allDrafts.isEmpty else { return .handled }
            selection = max(0, selection - 1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            guard isKeyboardActive, !allDrafts.isEmpty else { return .handled }
            selection = min(selection + 1, allDrafts.count - 1)
            return .handled
        }
        .onKeyPress(.return) {
            guard isKeyboardActive, allDrafts.indices.contains(selection) else { return .handled }
            onRestore(allDrafts[selection])
            return .handled
        }
    }

    /// 统一关闭入口：所有路径都带一点淡出，避免「啪」一下消失。
    private func close() {
        withAnimation(.easeOut(duration: 0.14)) { isPresented = false }
    }

    private func row(_ d: Draft) -> some View {
        DraftRowView(draft: d,
                     isEditing: store.editingDraftID == d.id,
                     isSelected: allDrafts.firstIndex(where: { $0.id == d.id }) == selection,
                     onRestore: { onRestore(d) },
                     onRename: { onRename(d) },
                     onDuplicate: { onDuplicate(d) },
                     onDelete: { onDelete(d) })
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "folder")
                .font(.system(size: 12))
                .foregroundStyle(AppColor.accentGlow)
            Text("草稿".localized())
                .font(.system(size: 12.5, weight: .bold))
                .foregroundStyle(AppColor.textPrimary)
            Text("\(store.count)")
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundStyle(AppColor.textSecondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 2)
                .background(Capsule().fill(AppColor.bgElevated))
            Spacer()
            Button {
                close()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(AppColor.textTertiary)
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 10)
    }

    private var saveRow: some View {
        Button(action: onSave) {
            HStack(spacing: 9) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 13))
                    .foregroundStyle(AppColor.accentGlow)
                VStack(alignment: .leading, spacing: 2) {
                    Text("保存当前编辑".localized())
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(AppColor.accentGlow)
                    Text("包含正文、标签、音色与全部参数".localized())
                        .font(.system(size: 9.5))
                        .foregroundStyle(AppColor.textTertiary)
                }
                Spacer(minLength: 0)
                Image(systemName: "plus")
                    .font(.system(size: 11))
                    .foregroundStyle(AppColor.accentGlow)
            }
            .padding(11)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(AppColor.accentWash)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(AppColor.accentLine,
                                    style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .disabled(!canSave)
        .opacity(canSave ? 1 : 0.45)
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
    }

    private func sectionHeader(_ title: String, count: Int) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 9.5, weight: .bold))
                .foregroundStyle(AppColor.textTertiary)
            Spacer()
            Text("\(count)")
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundStyle(AppColor.textTertiary)
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private var emptyView: some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.badge.plus")
                .font(.system(size: 22))
                .foregroundStyle(AppColor.accentGlow)
                .frame(width: 48, height: 48)
                .background(RoundedRectangle(cornerRadius: 14).fill(AppColor.accentWash))
            Text("还没有草稿".localized())
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppColor.textPrimary)
            Text("写到一半想先放一放？把这段内容存成草稿，随时点一下就能接着写。".localized())
                .font(.system(size: 10.5))
                .foregroundStyle(AppColor.textTertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button(action: onSave) {
                HStack(spacing: 5) {
                    Image(systemName: "plus")
                        .font(.system(size: 10))
                    Text("保存当前编辑".localized())
                        .font(.system(size: 10.5, weight: .bold))
                }
                .foregroundStyle(AppColor.bgPrimary)
                .padding(.horizontal, 13)
                .padding(.vertical, 7)
                .background(Capsule().fill(AppColor.accentPrimary))
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
            .disabled(!canSave)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 26)
        .frame(maxWidth: .infinity)
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Image(systemName: "info.circle")
                .font(.system(size: 9))
            Text(store.count == 0
                 ? "⌘ S 快速保存".localized()
                 : "恢复前会自动保存当前内容".localized())
                .font(.system(size: 9.5))
            Spacer()
        }
        .foregroundStyle(AppColor.textTertiary)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(AppColor.bgTertiary)
        .overlay(alignment: .top) { Divider().background(AppColor.borderSubtle) }
    }
}

private struct DraftRowView: View {
    let draft: Draft
    let isEditing: Bool
    let isSelected: Bool
    let onRestore: () -> Void
    let onRename: () -> Void
    let onDuplicate: () -> Void
    let onDelete: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: onRestore) {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: draft.isAuto ? "clock" : "doc")
                    .font(.system(size: 12))
                    .foregroundStyle(draft.isAuto ? AppColor.textTertiary : AppColor.accentGlow)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 7)
                            .fill(draft.isAuto ? AppColor.bgHover : AppColor.accentWash)
                    )
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 4) {
                        Text(draft.title)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(AppColor.textPrimary)
                            .lineLimit(1)
                        if draft.isAuto { badge("自动".localized(), AppColor.textTertiary) }
                        if isEditing { badge("编辑中".localized(), AppColor.statusSuccess) }
                        if draft.isGenerated { badge("已生成".localized(), AppColor.textTertiary) }
                    }
                    if !draft.subtitle.isEmpty {
                        Text(draft.subtitle)
                            .font(.system(size: 9.5))
                            .foregroundStyle(AppColor.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    HStack(spacing: 6) {
                        Text(draft.metaText)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(AppColor.textTertiary)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        // 日期 + 时间：草稿可能放很久，只给时刻分不清是哪天
                        Text(draft.timeText)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(AppColor.textTertiary)
                            .lineLimit(1)
                            .fixedSize()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(9)
            .background(RoundedRectangle(cornerRadius: 8)
                .fill(hovering ? AppColor.bgHover
                      : (isSelected ? AppColor.accentWash : Color.clear)))
            // 整条热区：留白区域也能点，不是只有文字部分
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .onHover { hovering = $0 }
        .contextMenu {
            Button("重命名".localized(), action: onRename)
            Button("复制".localized(), action: onDuplicate)
            Divider()
            Button("删除".localized(), action: onDelete)
        }
    }

    private func badge(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.system(size: 8.5, weight: .semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .overlay(RoundedRectangle(cornerRadius: 4)
                .stroke(color.opacity(0.4), lineWidth: 0.5))
    }
}

struct DraftDialogView: View {
    let kind: DraftDialog
    @Binding var renameText: String
    let onCancel: () -> Void
    let onConfirm: () -> Void

    @FocusState private var renameFocused: Bool

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color.black.opacity(0.55))
                .contentShape(Rectangle())
                .onTapGesture(perform: onCancel)
            VStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 18))
                    .foregroundStyle(AppColor.accentGlow)
                    .frame(width: 38, height: 38)
                    .background(RoundedRectangle(cornerRadius: 11).fill(AppColor.accentWash))
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppColor.textPrimary)
                if !message.isEmpty {
                    Text(message)
                        .font(.system(size: 10.5))
                        .foregroundStyle(AppColor.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if case .rename = kind {
                    TextField("草稿名称".localized(), text: $renameText)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11))
                        .focused($renameFocused)
                        .onSubmit(onConfirm)
                }
                if case .restore = kind { noteBox }
                HStack(spacing: 8) {
                    dialogButton("取消".localized(), filled: false, action: onCancel)
                    dialogButton(confirmTitle, filled: true, action: onConfirm)
                }
            }
            .padding(20)
            .frame(width: 322)
            .background(AppColor.bgTertiary)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14)
                .stroke(AppColor.borderMedium, lineWidth: 1))
            .shadow(color: .black.opacity(0.6), radius: 30, y: 12)
        }
        .onAppear {
            guard case .rename = kind else { return }
            DispatchQueue.main.async { renameFocused = true }
        }
    }

    private var icon: String {
        switch kind {
        case .restore: return "arrow.uturn.backward"
        case .rename: return "pencil"
        case .delete: return "trash"
        }
    }

    private var title: String {
        switch kind {
        case .restore: return "恢复这份草稿？".localized()
        case .rename: return "重命名草稿".localized()
        case .delete: return "删除这份草稿？".localized()
        }
    }

    private var message: String {
        switch kind {
        case .restore(let d):
            return "「%@」会替换当前编辑区的全部内容，包含情绪标签、音色与参数。".localized(d.title)
        case .rename: return ""
        case .delete: return "删除后无法恢复。".localized()
        }
    }

    private var confirmTitle: String {
        switch kind {
        case .restore: return "恢复".localized()
        case .rename: return "保存".localized()
        case .delete: return "删除".localized()
        }
    }

    private var noteBox: some View {
        HStack(alignment: .top, spacing: 7) {
            Image(systemName: "info.circle")
                .font(.system(size: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text("当前内容会自动另存为新草稿".localized())
            }
        }
        .font(.system(size: 9.5))
        .foregroundStyle(AppColor.textTertiary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background(RoundedRectangle(cornerRadius: 8).fill(AppColor.bgHover))
    }

    private func dialogButton(_ title: String, filled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(filled ? AppColor.bgPrimary : AppColor.textPrimary)
                .frame(maxWidth: .infinity, minHeight: 30)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(filled ? AppColor.accentPrimary : AppColor.bgElevated)
                )
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
    }
}
