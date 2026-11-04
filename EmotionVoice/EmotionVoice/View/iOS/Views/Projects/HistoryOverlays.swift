//
//  HistoryOverlays.swift
//  iOSEmora
//
//  历史记录全局浮层：mini player / ⋯ 菜单 / 撤销 Toast。
//  从 HistoryComponents.swift 拆出：代码逐字搬移，未改动任何逻辑（原 private 类型按需放开为 internal）。
//

import SwiftUI
import Combine

// MARK: - mini player（全局常驻）

/// ⚠️ 这是**浮层**而不是列表卡片：品牌渐变底 + 白字 + 彩色投影，
/// 和列表里的白底行卡一眼区分开。整卡点击即展开，不需要单独的展开箭头。
struct MiniPlayerView: View {
    @Environment(\.aurora) private var c
    @ObservedObject private var player = AudioPreviewPlayer.shared

    /// 列表底部占位按这个高度算，避免两处写死数字对不上。
    static let height: CGFloat = 56

    let item: AudioItem
    let voiceName: String
    let onExpand: () -> Void
    let onToggle: () -> Void
    let onClose: () -> Void

    /// ⚠️ 只有播放器当前播的**就是这一条**时，时间 / 进度 / 播放态才可信：
    ///    音色库试听复用同一个 `AudioPreviewPlayer`，会把 `playingKey` 顶到音色 key 上，
    ///    而 mini player 按设计依旧常驻（用户没点 ✕），此时不能显示别人那条的进度。
    private var isCurrent: Bool { player.playingKey == item.fileName }

    private var showsPlaying: Bool { isCurrent && player.isPlaying }

    var body: some View {
        HStack(spacing: 10) {
            VoiceAvatar(text: String(voiceName.suffix(1)), seed: item.voice, size: 36, corner: 10)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(.white.opacity(0.38), lineWidth: 0.8)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(item.shownName)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Text("\(voiceName) · \(formatDuration(isCurrent ? player.currentTime : 0)) / \(formatDuration(max(isCurrent ? player.duration : 0, item.duration)))")
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.72))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 4) {
                Button(action: onToggle) {
                    ZStack {
                        Circle().fill(.white)
                        Image(systemName: showsPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(c.ctaStart)
                    }
                    .frame(width: 32, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(showsPlaying ? "暂停".localized() : "播放".localized())

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.82))
                        .frame(width: 26, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("关闭".localized())
            }
        }
        .padding(.horizontal, 12)
        .frame(height: Self.height)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(c.ctaGradient)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(.white.opacity(0.24), lineWidth: 0.8)
        }
        // ⚠️ 进度条不要自带 clipShape（对齐 `RowProgressTrack`）：2pt 高的条套 16pt
        //    连续圆角，裁剪路径会向左右溢出卡片。圆角交给下面整卡唯一这一层统一裁。
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(.white.opacity(0.85))
                .frame(height: 2)
                .scaleEffect(x: isCurrent ? max(min(player.progress, 1), 0.001) : 0.001, anchor: .leading)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        // ⚠️ shadow 必须挂在 clipShape 之后，挂在 background 里会连阴影一起被裁掉
        .shadow(color: c.ctaStart.opacity(0.34), radius: 20, x: 0, y: 8)
        // 整卡展开：子 Button 的命中优先级更高，不会连带触发 onExpand
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .onTapGesture(perform: onExpand)
    }
}

// MARK: - ⋯ 菜单

/// 导航栏「⋯」菜单。
/// ⚠️ 它是 overlay 里就地插入的（没有系统 Sheet 动画），所以自己带
///    缩放 + 淡入 + 下移的进场；`appeared` 由 onAppear 翻转，每次新建视图都会重跑。
///    「排序方式」点开后原地展开两个可选项，选中项打勾 —— 不是盲切排序。
struct HistoryMoreMenu: View {
    @Environment(\.aurora) private var c
    let deletedCount: Int
    let sortOrder: HistorySortOrder
    let onTrash: () -> Void
    let onSortChange: (HistorySortOrder) -> Void
    let onDismiss: () -> Void

    @State private var appeared = false
    @State private var sortExpanded = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // 淡遮罩：既给菜单层次，也拦截列表点击
            c.scrim
                .opacity(appeared ? 0.42 : 0)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: onDismiss)
                .animation(.easeOut(duration: 0.22), value: appeared)

            VStack(spacing: 0) {
                menuRow(icon: "clock", tint: c.info,
                        title: "最近删除".localized(),
                        badge: "%d 条".localized(deletedCount),
                        action: { onTrash(); onDismiss() })

                menuRow(icon: "slider.horizontal.3", tint: c.accent,
                        title: "排序方式".localized(),
                        badge: sortOrder.title,
                        expanded: sortExpanded) {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                        sortExpanded.toggle()
                    }
                }

                if sortExpanded { sortOptions }

                Text("已删除的项目保留 30 天，到期自动清除".localized())
                    .font(.system(size: 11))
                    .foregroundStyle(c.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(c.surface2)
            }
            .frame(width: 252)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(c.surface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(c.line, lineWidth: 0.5)
                    )
            )
            // ⚠️ footer 是矩形铺满，会把卡片底部两个圆角盖成直角；整张卡裁成圆角。
            //    阴影必须画在裁剪之后（挂在 background 里会一起被裁掉）。
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: c.shadow, radius: 28, x: 0, y: 14)
            // overlay 的坐标从导航栏下方的内容区顶部算起：菜单紧贴 ⋯ 按钮下沿即可，
            // 之前 52pt 把菜单推到离按钮快 100pt 的地方。
            .padding(.trailing, 12)
            .padding(.top, 8)
            .scaleEffect(appeared ? 1 : 0.85, anchor: .topTrailing)
            .offset(y: appeared ? 0 : -10)
            .opacity(appeared ? 1 : 0)
            .animation(.spring(response: 0.3, dampingFraction: 0.82), value: appeared)
        }
        .onAppear { appeared = true }
    }

    // MARK: 排序子选项

    private var sortOptions: some View {
        VStack(spacing: 0) {
            ForEach(HistorySortOrder.allCases, id: \.rawValue) { order in
                Button {
                    onSortChange(order)
                    onDismiss()
                } label: {
                    let selected = order == sortOrder
                    HStack(spacing: 10) {
                        Image(systemName: order == .newest ? "arrow.down.to.line" : "arrow.up.to.line")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(selected ? c.accent : c.textTertiary)
                            .frame(width: 26)
                        Text(order.title)
                            .font(.system(size: 13))
                            .foregroundStyle(selected ? c.accent : c.textPrimary)
                        Spacer(minLength: 0)
                        if selected {
                            Image(systemName: "checkmark")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(c.accent)
                        }
                    }
                    .padding(.horizontal, 12)
                    .frame(height: 38)
                    .background(selected ? c.accentSoft.opacity(0.6) : Color.clear)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .background(c.surface2.opacity(0.6))
        .overlay(alignment: .bottom) { Rectangle().fill(c.line).frame(height: 0.5) }
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: 菜单行

    private func menuRow(icon: String, tint: Color, title: String, badge: String,
                         expanded: Bool = false,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(tint.opacity(0.13))
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(tint)
                }
                .frame(width: 26, height: 26)

                Text(title)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(c.textPrimary)
                Spacer(minLength: 0)
                Text(badge)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(c.textTertiary)
                Image(systemName: expanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(c.textTertiary)
            }
            .padding(.horizontal, 12)
            .frame(height: 46)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) { Rectangle().fill(c.line).frame(height: 0.5) }
    }
}

// MARK: - 撤销 Toast（底部，5 秒倒计时）

struct UndoToastView: View {
    @Environment(\.aurora) private var c
    let message: UndoToastMessage
    let onUndo: () -> Void

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 15))
                .foregroundStyle(c.success)
            Text(message.text)
                .font(.system(size: 12.5))
                .foregroundStyle(c.textPrimary)
                .lineLimit(1)
            Spacer(minLength: 0)
            Button(action: onUndo) {
                Text("撤销".localized())
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(c.accent)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 13)
        .frame(height: 46)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(c.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(c.line, lineWidth: 0.5)
                )
                .shadow(color: c.shadow, radius: 16, x: 0, y: 6)
        )
        .overlay(alignment: .bottom) {
            TimelineView(.periodic(from: message.createdAt, by: 0.05)) { context in
                let elapsed = context.date.timeIntervalSince(message.createdAt)
                let remain = max(0, 1 - elapsed / message.duration)
                Rectangle()
                    .fill(c.success.opacity(0.8))
                    .frame(height: 2)
                    .scaleEffect(x: max(remain, 0.001), anchor: .leading)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}
