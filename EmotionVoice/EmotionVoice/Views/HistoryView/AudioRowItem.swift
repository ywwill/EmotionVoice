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
    @State private var isMenuOpen: Bool = false

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
        Button {
            isMenuOpen = true
        } label: {
            Image(systemName: "ellipsis.circle")
                .font(.system(size: 14))
                .foregroundStyle(
                    isSelected
                        ? AppColor.textSecondary
                        : AppColor.textTertiary
                )
                .frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $isMenuOpen, arrowEdge: .trailing) {
            moreMenuContent
                .background(Color.clear)
        }
        .opacity(isHovered || isSelected || isSelectionMode ? 1 : 0)
        .animation(.easeInOut(duration: 0.15), value: isHovered)
    }

    // MARK: - 更多菜单内容（自定义：左图标 + 右标题）

    private var moreMenuContent: some View {
        VStack(spacing: 0) {
            // 批量操作
            moreMenuItem(
                icon: "checkmark.circle",
                title: "批量操作".localized(),
                isDestructive: false
            ) {
                isMenuOpen = false
                onBatchSelect()
            }

            Divider().background(AppColor.borderSubtle)

            // 编辑名称
            moreMenuItem(
                icon: "square.and.pencil",
                title: "编辑名称".localized(),
                isDestructive: false
            ) {
                isMenuOpen = false
                onRename()
            }

            // 导出
            moreMenuItem(
                icon: "square.and.arrow.up",
                title: "导出".localized(),
                isDestructive: false
            ) {
                isMenuOpen = false
                onExport()
            }

            Divider().background(AppColor.borderSubtle)

            // 删除
            moreMenuItem(
                icon: "trash",
                title: "删除".localized(),
                isDestructive: true
            ) {
                isMenuOpen = false
                onDelete()
            }
        }
        .frame(width: 180)
        .padding(8)
        .background(AppColor.bgElevated)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 4)
    }

    private func moreMenuItem(
        icon: String,
        title: String,
        isDestructive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13))
                    .foregroundStyle(isDestructive ? AppColor.statusError : AppColor.textSecondary)
                    .frame(width: 18)

                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(isDestructive ? AppColor.statusError : AppColor.textPrimary)

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
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
