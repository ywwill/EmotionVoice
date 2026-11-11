//
//  StudioDraft.swift
//  iOSEmora
//

import SwiftUI
import UIKit

private enum DraftForm: Identifiable {
    case delete(Draft)

    var id: String {
        switch self {
        case .delete(let d): return "delete-\(d.id)"
        }
    }

    var draft: Draft {
        switch self {
        case .delete(let d): return d
        }
    }
}

struct DraftSheet: View {
    @Environment(\.aurora) private var c
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: DraftStore
    let canSave: Bool
    let needsConfirm: Bool
    let onSave: () -> Void
    let onRestoreConfirmed: (Draft) -> Void

    @State private var search = ""
    @State private var confirm: Draft? = nil
    @State private var form: DraftForm? = nil
    @State private var renameTarget: Draft? = nil
    @State private var renameText = ""

    private var filteredManual: [Draft] {
        guard !search.isEmpty else { return store.manual }
        return store.manual.filter {
            $0.title.localizedCaseInsensitiveContains(search)
                || $0.preview.localizedCaseInsensitiveContains(search)
        }
    }

    private var filteredAuto: [Draft] {
        guard !search.isEmpty else { return store.auto }
        return store.auto.filter {
            $0.title.localizedCaseInsensitiveContains(search)
                || $0.preview.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        ZStack {
            c.backgroundGrouped.ignoresSafeArea()

            VStack(spacing: 0) {
                grabber
                header
                saveButton
                if store.count > 0 {
                    AuroraSearchField(text: $search, placeholder: "搜索草稿".localized())
                        .padding(.horizontal, 16)
                        .padding(.bottom, 12)
                }
                if store.count == 0 {
                    emptyView
                } else if filteredManual.isEmpty && filteredAuto.isEmpty {
                    noResults
                } else {
                    list
                }
            }
            .overlay { if let d = confirm { restoreActionSheet(d) } }
            .overlay { if let f = form { formDialog(f) } }
            .overlay {
                if let d = renameTarget {
                    RenameDialog(text: $renameText,
                                 onCancel: { renameTarget = nil },
                                 onSave: { commitRename(d) })
                }
            }
        }
        .animation(.easeOut(duration: 0.18), value: confirm?.id)
        .animation(.easeOut(duration: 0.18), value: form?.id)
    }

    private var grabber: some View {
        Capsule()
            .fill(c.textTertiary.opacity(0.45))
            .frame(width: 36, height: 5)
            .padding(.top, 9)
            .padding(.bottom, 4)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text("草稿".localized())
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(c.textPrimary)
            }
            Spacer()
            Button {
                dismiss()
            } label: {
                Text("完成".localized())
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(c.accent)
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 6)
        .padding(.bottom, 12)
    }

    private var saveButton: some View {
        Button {
            guard canSave else { return }
            onSave()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "square.and.pencil")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 26, height: 26)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.2)))
                VStack(alignment: .leading, spacing: 2) {
                    Text("保存当前编辑".localized())
                        .font(.system(size: 14, weight: .bold))
                    Text("包含正文、标签、音色与全部参数".localized())
                        .font(.system(size: 10.5))
                        .opacity(0.88)
                }
                Spacer(minLength: 0)
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 13)
            .frame(height: 52)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(c.ctaGradient))
            .shadow(color: c.ctaStart.opacity(0.24), radius: 12, y: 5)
            .opacity(canSave ? 1 : 0.45)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!canSave)
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    private func groupHeader(_ title: String, count: Int) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 11.5, weight: .bold))
                .foregroundStyle(c.textSecondary)
            Spacer()
            Text("\(count)")
                .font(.system(size: 10.5, design: .monospaced))
                .foregroundStyle(c.textTertiary)
        }
        .padding(.vertical, 4)
    }

    private var list: some View {
        List {
            if !filteredManual.isEmpty {
                groupHeader("已保存的草稿".localized(), count: filteredManual.count)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
                ForEach(filteredManual) { d in card(d) }
            }
            if !filteredAuto.isEmpty {
                groupHeader("自动保存".localized(), count: filteredAuto.count)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                    .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                ForEach(filteredAuto) { d in card(d) }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
    }

    private func card(_ d: Draft) -> some View {
        DraftCardView(draft: d, isEditing: store.editingDraftID == d.id)
            .contentShape(Rectangle())
            .onTapGesture { restore(d) }
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 9, trailing: 16))
            .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                Button(role: .destructive) {
                    form = .delete(d)
                } label: {
                    Label("删除".localized(), systemImage: "trash.fill")
                }
                Button {
                    store.duplicate(id: d.id)
                } label: {
                    Label("复制".localized(), systemImage: "square.on.square")
                }
                .tint(c.info)
                Button {
                    beginRename(d)
                } label: {
                    Label("重命名".localized(), systemImage: "square.and.pencil")
                }
                .tint(c.success)
            }
            // 长按菜单只留三个动作（预览全文已去掉：列表副标题就能看清内容）
            .contextMenu {
                Button {
                    beginRename(d)
                } label: {
                    Label("重命名".localized(), systemImage: "square.and.pencil")
                }
                Button {
                    store.duplicate(id: d.id)
                } label: {
                    Label("复制".localized(), systemImage: "square.on.square")
                }
                Button(role: .destructive) {
                    form = .delete(d)
                } label: {
                    Label("删除".localized(), systemImage: "trash")
                }
            }
    }

    private var emptyView: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 0)
            ZStack(alignment: .bottomTrailing) {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(c.surface3)
                    .frame(width: 88, height: 88)
                Image(systemName: "doc")
                    .font(.system(size: 38))
                    .foregroundStyle(c.accent)
                    .frame(width: 88, height: 88)
                Circle()
                    .fill(c.ctaGradient)
                    .frame(width: 26, height: 26)
                    .overlay(Circle().stroke(c.backgroundGrouped, lineWidth: 4))
                    .offset(x: 6, y: 6)
            }
            Text("还没有草稿".localized())
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(c.textPrimary)
            Text("写到一半想先放一放？把这段内容存成草稿，随时点一下就能接着写。".localized())
                .font(.system(size: 12.5))
                .foregroundStyle(c.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 34)
            Button {
                guard canSave else { return }
                onSave()
            } label: {
                Text("保存当前编辑".localized())
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 11)
                    .background(RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(c.ctaGradient))
            }
            .buttonStyle(.plain)
            .disabled(!canSave)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.bottom, 40)
    }

    private var noResults: some View {
        VStack(spacing: 8) {
            Spacer(minLength: 0)
            Image(systemName: "magnifyingglass")
                .font(.system(size: 30))
                .foregroundStyle(c.textTertiary)
            Text("没有找到匹配的草稿".localized())
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(c.textSecondary)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func restore(_ d: Draft) {
        if needsConfirm {
            confirm = d
        } else {
            dismiss()
            onRestoreConfirmed(d)
        }
    }

    /// 重命名入口：预填当前标题，交给 `RenameDialog` 输入。
    private func beginRename(_ d: Draft) {
        renameText = d.title
        renameTarget = d
    }

    private func commitRename(_ d: Draft) {
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        renameTarget = nil
        guard !trimmed.isEmpty, trimmed != d.title else { return }
        store.rename(id: d.id, title: trimmed)
    }

    private func applyForm(_ f: DraftForm) {
        switch f {
        case .delete(let d): store.delete(id: d.id)
        }
        form = nil
    }

    // MARK: 浮层

    private func restoreActionSheet(_ d: Draft) -> some View {
        ZStack(alignment: .bottom) {
            c.scrim
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { confirm = nil }
            VStack(spacing: 8) {
                VStack(spacing: 0) {
                    VStack(spacing: 4) {
                        Text("恢复这份草稿？".localized())
                            .font(.system(size: 12.5, weight: .bold))
                            .foregroundStyle(c.textPrimary)
                        Text(d.title)
                            .font(.system(size: 11))
                            .foregroundStyle(c.textTertiary)
                            .lineLimit(1)
                        Text("当前内容会自动另存为新草稿".localized())
                            .font(.system(size: 11))
                            .foregroundStyle(c.textSecondary)
                    }
                    .multilineTextAlignment(.center)
                    .padding(15)
                    .frame(maxWidth: .infinity)
                    Hairline()
                    Button {
                        confirm = nil
                        dismiss()
                        onRestoreConfirmed(d)
                    } label: {
                        Text("恢复".localized())
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 50)
                            .background(c.ctaGradient)
                    }
                    .buttonStyle(.plain)
                }
                .background(c.surface)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: c.shadow, radius: 30, y: 10)
                Button {
                    confirm = nil
                } label: {
                    Text("取消".localized())
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(c.accent)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(c.surface)
                }
                .buttonStyle(.plain)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: c.shadow, radius: 30, y: 10)
            }
            .padding(.horizontal, 9)
            .padding(.bottom, 26)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func formDialog(_ f: DraftForm) -> some View {
        ZStack {
            c.scrim.ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture { form = nil }
            VStack(spacing: 12) {
                Image(systemName: "trash")
                    .font(.system(size: 20))
                    .foregroundStyle(c.danger)
                    .frame(width: 42, height: 42)
                    .background(Circle().fill(c.surface3))
                Text("删除这份草稿？".localized())
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(c.textPrimary)
                Text("删除后无法恢复。".localized())
                    .font(.system(size: 12))
                    .foregroundStyle(c.textSecondary)
                    .multilineTextAlignment(.center)
                if !f.draft.title.isEmpty {
                    Text(f.draft.title)
                        .font(.system(size: 11.5))
                        .foregroundStyle(c.textTertiary)
                        .lineLimit(1)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(c.surface3))
                }
                HStack(spacing: 8) {
                    Button {
                        form = nil
                    } label: {
                        Text("取消".localized())
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(c.textPrimary)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(RoundedRectangle(cornerRadius: 12).fill(c.surface3))
                    }
                    .buttonStyle(.plain)
                    Button {
                        applyForm(f)
                    } label: {
                        Text("删除".localized())
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(RoundedRectangle(cornerRadius: 12).fill(c.danger))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(20)
            .frame(width: 300)
            .background(c.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: c.shadow, radius: 24, y: 10)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct DraftCardView: View {
    @Environment(\.aurora) private var c
    let draft: Draft
    let isEditing: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(c.accentSoft)
                Image(systemName: draft.isAuto ? "clock" : "doc")
                    .font(.system(size: 15))
                    .foregroundStyle(c.accent)
            }
            .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(draft.title)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(c.textPrimary)
                        .lineLimit(1)
                    if draft.isAuto { badge("自动".localized(), c.textTertiary) }
                    if isEditing { badge("编辑中".localized(), c.success) }
                    if draft.isGenerated { badge("已生成".localized(), c.textTertiary) }
                }

                if !draft.subtitle.isEmpty {
                    Text(draft.subtitle)
                        .font(.system(size: 11.5))
                        .foregroundStyle(c.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .multilineTextAlignment(.leading)
                }
                HStack(spacing: 6) {
                    Text(draft.metaText)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(c.textTertiary)
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    Text(draft.timeText)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(c.textTertiary)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(c.textTertiary.opacity(0.6))
        }
        .padding(12)
        .frame(minHeight: 78, alignment: .leading)
        .background(c.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .strokeBorder(c.line, lineWidth: 0.5))
    }

    private func badge(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(c.surface3))
    }
}
