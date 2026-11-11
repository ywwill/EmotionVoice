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
    let onCopy: () -> Void
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

            // 信息列
            // ⚠️ 左栏固定 340pt，扣掉列表/行内边距后一行约 292pt。按用户要求移除头像
            // （省 52pt），并把「更多」按钮上移到名称行右侧 —— 第二行整行留给元信息，
            // 「音色名 · 时长 · 文件大小 · HH:mm」一行完整显示，不折行、不截断。
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(audio.shownName)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AppColor.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer(minLength: 4)

                    // 更多菜单按钮（选择模式下隐藏）
                    if !isSelectionMode {
                        moreButton
                    }
                }

                HStack(spacing: 5) {
                    metaText(voiceName ?? "—")
                    metaDot
                    metaText(formatDuration(audio.duration), monospaced: true)
                    if audio.fileSize > 0 {
                        metaDot
                        metaText(formatDataSize(audio.fileSize), monospaced: true)
                    }
                    metaDot
                    // 组头已给出「今天 / 昨天 / 日期」，行内只补时分，方便同组内区分先后
                    metaText(timeText, monospaced: true)
                }
                .fixedSize(horizontal: true, vertical: false)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)
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

    /// 元信息字段：固定自身完整宽度，绝不参与 HStack 的宽度压缩（否则中文音色名
    /// 会被逐字换行、等宽的时长/大小会被截尾）；整行再 fixedSize，保证单行不折行。
    private func metaText(_ text: String, monospaced: Bool = false) -> some View {
        Text(text)
            .font(monospaced ? .system(size: 11, design: .monospaced) : .system(size: 11))
            .foregroundStyle(AppColor.textTertiary)
            .fixedSize(horizontal: true, vertical: false)
    }

    private var metaDot: some View {
        Text("·")
            .font(.system(size: 11))
            .foregroundStyle(AppColor.textTertiary)
            .fixedSize(horizontal: true, vertical: false)
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
                title: "编辑".localized(),
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

            // 复制（复制音频文件 + 记录）
            moreMenuItem(
                icon: "square.on.square",
                title: "复制".localized(),
                isDestructive: false
            ) {
                isMenuOpen = false
                onCopy()
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

    /// 固定 24 小时制 `HH:mm`，不随 locale 变成 AM/PM，三语下版式一致。
    private var timeText: String {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: audio.createdAt)
        return String(format: "%02d:%02d", comps.hour ?? 0, comps.minute ?? 0)
    }

    /// 走 VoiceService 的 key 缓存查询。
    /// 旧实现这里调 `fetchAll()` 全表扫描，一屏 20 行就是 20 次全表查询。
    private var voiceName: String? {
        VoiceService.shared.displayName(forKey: audio.voice)
    }
}
