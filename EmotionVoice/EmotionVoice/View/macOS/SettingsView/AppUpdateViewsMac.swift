//
//  AppUpdateViewsMac.swift
//  EmotionVoice
//
//  检查更新的 macOS UI：
//   ① `AppUpdateBannerMac` —— 浮在内容区顶部的一张小卡片（Z 轴叠加，
//      不占布局高度、不把页面内容往下挤，宽度按内容自适应；只在非强制更新时出现）
//   ② `AppUpdateSheetMac`  —— 更新详情弹窗（force_update 时不给关闭 / 稍后，界面上不写「强制」）
//
//  ⚠️ 类名带 `Mac` 后缀：iOS 端有同名职责的 `AppUpdateBanner` / `AppUpdateSheet`
//     （`View/iOS/Views/Settings/AppUpdateViews.swift`），两边分属不同 target，
//     但保持类型名不同，避免以后误把两份文件塞进同一个 target。
//

import SwiftUI

// MARK: - 顶部横幅

struct AppUpdateBannerMac: View {
    @ObservedObject var manager: AppUpdateManager
    let info: AppUpdateInfo

    /// 浮层距内容区顶边的留白（纯视觉间距，不占布局高度）
    static let topInset: CGFloat = 12

    var body: some View {
        HStack(spacing: 10) {
            // 左侧整块（图标 + 两行文案）点开更新详情。
            // ⚠️ 不挂在外层 HStack 上：外层 `.onTapGesture` 会和右侧两个按钮抢手势
            //    （iOS 横幅的 ✕ 曾因此完全点不动，见 AppUpdateViews.swift）。
            Button {
                manager.presentedUpdate = info
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AppColor.accentPrimary)

                    VStack(alignment: .leading, spacing: 1) {
                        Text("发现新版本 %@".localized(info.version))
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(AppColor.textPrimary)
                            .lineLimit(1)
                        Text("查看更新内容".localized())
                            .font(AppFont.caption)
                            .foregroundStyle(AppColor.textTertiary)
                            .lineLimit(1)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            // ⚠️ 这里刻意不放 Spacer：横幅改成浮层后要按内容自适应宽度，
            //    Spacer 会把整张卡片拉成左右撑满的横条。
            HStack(spacing: 4) {
                Button {
                    manager.openAppStore()
                } label: {
                    Text("更新".localized())
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(AppColor.accentPrimary)
                        )
                        .foregroundStyle(AppColor.bgPrimary)
                        .contentShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .pointingHandCursor()

                // 横幅只在非强制更新时出现（`showsBanner` 挡掉了 forceUpdate），关闭永远给
                Button {
                    manager.dismissBanner()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(AppColor.textTertiary)
                        .padding(5)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
                .help("关闭".localized())
            }
            .padding(.leading, 12)
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .frame(height: 42)
        // 浮层化：卡片底 + 描边 + 投影（原来的整条 `bgSecondary` 色带 + 下边线
        // 只适合占满一行的顶条，浮起来会像贴死在顶部的横条）
        .background(
            RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                .fill(AppColor.bgElevated)
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.medium, style: .continuous)
                        .strokeBorder(AppColor.borderMedium, lineWidth: 0.5)
                )
        )
        .shadow(color: .black.opacity(0.35), radius: 16, x: 0, y: 6)
        // 左右各留 16：卡片按内容自适应宽度，不撑满内容区
        .padding(.horizontal, 16)
    }
}

// MARK: - 更新详情弹窗

struct AppUpdateSheetMac: View {
    @ObservedObject var manager: AppUpdateManager
    let info: AppUpdateInfo

    private var isForced: Bool { info.forceUpdate }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            versionRow
                .padding(.top, 4)

            if !info.localizedNotes.isEmpty {
                Text("更新内容".localized())
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppColor.textTertiary)
                    .textCase(.uppercase)
                    .tracking(0.06)
                    .padding(.top, 18)
                    .padding(.bottom, 8)

                notesBlock
            }

            Spacer(minLength: 20)

            footer
        }
        .padding(24)
        .frame(width: 460)
        .frame(maxHeight: 560)
        .background(AppColor.bgPrimary)
        .interactiveDismissDisabled(isForced)
    }

    // MARK: 头

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("发现新版本".localized())
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(AppColor.textPrimary)
            }

            Spacer(minLength: 8)

            if !isForced {
                Button {
                    manager.dismissPresentedUpdate()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppColor.textTertiary)
                        .frame(width: 22, height: 22)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
                .help("关闭".localized())
            }
        }
    }

    // MARK: 版本

    private var versionRow: some View {
        HStack(spacing: 8) {
            Text("当前版本".localized())
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textTertiary)
            Text(manager.currentVersion)
                .font(AppFont.monoSmall)
                .foregroundStyle(AppColor.textSecondary)

            Image(systemName: "arrow.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(AppColor.textTertiary)

            Text(info.version)
                .font(AppFont.monoSmall)
                .foregroundStyle(AppColor.accentPrimary)
        }
    }

    private var notesBlock: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(info.localizedNotes.enumerated()), id: \.offset) { _, note in
                    HStack(alignment: .top, spacing: 8) {
                        Circle()
                            .fill(AppColor.accentPrimary.opacity(0.6))
                            .frame(width: 4, height: 4)
                            .padding(.top, 6)
                        Text(note)
                            .font(.system(size: 12.5))
                            .foregroundStyle(AppColor.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
        }
        .frame(maxHeight: 200)
        .background(
            RoundedRectangle(cornerRadius: AppRadius.medium)
                .fill(AppColor.bgSecondary)
                .overlay(
                    RoundedRectangle(cornerRadius: AppRadius.medium)
                        .stroke(AppColor.borderSubtle, lineWidth: 1)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium))
    }

    // MARK: 底部

    private var footer: some View {
        HStack(spacing: 10) {
            Spacer()

            if !isForced {
                SecondaryButton(title: "稍后再说".localized()) {
                    manager.dismissPresentedUpdate()
                }
            }

            PrimaryButton(title: "立即更新".localized(), icon: "arrow.down.circle.fill") {
                manager.openAppStore()
            }
        }
    }
}
