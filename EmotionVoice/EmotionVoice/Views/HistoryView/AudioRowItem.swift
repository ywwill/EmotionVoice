//
//  AudioRowItem.swift
//  EmotionVoice
//
//  音频列表中的单个垂直条目
//

import SwiftUI

struct AudioRowItem: View {

    let audio: AudioItem
    let isSelected: Bool
    let isPlaying: Bool
    let isSelectionMode: Bool
    let isChecked: Bool
    let onSelect: () -> Void
    let onToggleSelection: () -> Void
    let onRename: () -> Void
    let onExport: () -> Void
    let onDelete: () -> Void
    let onBatchSelect: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            // 选择框（批量选择模式时显示）
            if isSelectionMode {
                Button {
                    onToggleSelection()
                } label: {
                    Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 18))
                        .foregroundStyle(isChecked ? AppColor.accentPrimary : AppColor.textTertiary)
                }
                .buttonStyle(.plain)
            }

            // 头像
            avatarView

            // 信息
            VStack(alignment: .leading, spacing: 4) {
                Text(audio.shownName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(AppColor.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                HStack(spacing: 8) {
                    Text(voiceName ?? "—")
                        .font(.system(size: 11))
                        .foregroundStyle(AppColor.textTertiary)

                    Text("·")
                        .foregroundStyle(AppColor.textTertiary)

                    Text(audio.duration.durationString)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(AppColor.textTertiary)
                }
            }

            Spacer()

            // 更多菜单按钮（选择模式下隐藏）
            if !isSelectionMode {
                moreButton
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? AppColor.bgElevated : (isHovered ? AppColor.bgTertiary.opacity(0.5) : Color.clear))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    isChecked && isSelectionMode
                        ? AppColor.accentPrimary
                        : (isSelected
                            ? AppColor.borderMedium
                            : (isPlaying ? AppColor.accentPrimary.opacity(0.3) : Color.clear)),
                    lineWidth: 1
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .onHover { hovering in
            isHovered = hovering
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if isSelectionMode {
                onToggleSelection()
            } else {
                onSelect()
            }
        }
    }

    // MARK: - 子视图

    private var avatarView: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [AppColor.accentPrimary, AppColor.accentSecondary],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 40, height: 40)

            Text(avatarChar)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(AppColor.bgPrimary)
        }
        .opacity(isPlaying ? 1.0 : 0.9)
        .shadow(
            color: isPlaying ? AppColor.accentPrimary.opacity(0.4) : .clear,
            radius: isPlaying ? 8 : 0
        )
        .animation(
            isPlaying ? Animation.easeInOut(duration: 2).repeatForever(autoreverses: true) : .default,
            value: isPlaying
        )
    }

    private var moreButton: some View {
        Menu {
            // 批量操作（第一行）
            Button {
                onBatchSelect()
            } label: {
                Label("批量操作", systemImage: "checkmark.circle")
            }

            Divider()

            Button {
                onRename()
            } label: {
                Label("编辑名称", systemImage: "pencil")
            }

            Button {
                onExport()
            } label: {
                Label("导出", systemImage: "square.and.arrow.up")
            }

            Divider()

            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("删除", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 14))
                .foregroundStyle(
                    isSelected
                        ? AppColor.textSecondary
                        : AppColor.textTertiary
                )
                .frame(width: 32, height: 32)
                .background(
                    Circle()
                        .fill(Color.clear)
                )
        }
        .menuStyle(.borderlessButton)
        .opacity(isHovered || isSelected || isSelectionMode ? 1 : 0)
        .animation(.easeInOut(duration: 0.15), value: isHovered)
    }

    // MARK: - 计算属性

    private var voiceName: String? {
        guard !audio.voice.isEmpty else { return nil }
        return VoiceService.shared.fetchAll()
            .first(where: { $0.key == audio.voice })?.name
    }

    private var avatarChar: String {
        if let name = voiceName {
            return String(name.prefix(1))
        }
        return "音"
    }
}
