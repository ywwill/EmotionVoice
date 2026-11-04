//
//  AppUpdateViews.swift
//  iOSEmora

import SwiftUI

// MARK: - 顶部横幅
struct AppUpdateBanner: View {
    @Environment(\.aurora) private var c
    @Environment(\.screenMetrics) private var metrics

    @ObservedObject var manager: AppUpdateManager
    let info: AppUpdateInfo

    /// 浮层模式下要让开的导航栏高度（inline 导航栏固定 44pt）
    static let navBarClearance: CGFloat = 44

    var body: some View {
        HStack(spacing: 10) {
            Button {
                manager.presentedUpdate = info
            } label: {
                HStack(spacing: 10) {
                    icon

                    VStack(alignment: .leading, spacing: 1) {
                        Text("发现新版本 %@".localized(info.version))
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(c.textPrimary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                        Text("查看更新内容".localized())
                            .font(.system(size: 11.5))
                            .foregroundStyle(c.textTertiary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }

                    Spacer(minLength: 4)
                }
                // 空白区（Spacer）也要吃点击，否则只有文字 / 图标附近能点
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                manager.openAppStore()
            } label: {
                Text("更新".localized())
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(c.ctaForeground)
                    .padding(.horizontal, 13)
                    .frame(height: 28)
                    .background(
                        Capsule(style: .continuous).fill(c.ctaGradient)
                    )
                    .contentShape(Capsule(style: .continuous))
            }
            .buttonStyle(.plain)

            // 横幅**只在非强制更新时出现**（`showsBanner` 里挡掉了 forceUpdate），
            // 所以这里不用再区分强制态：关闭按钮永远给。
            Button {
                manager.dismissBanner()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(c.textTertiary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("关闭".localized())
        }
        .padding(.leading, 12)
        .padding(.trailing, 4)
        .frame(height: 50)
        .background(
            RoundedRectangle(cornerRadius: AuroraRadius.md, style: .continuous)
                .fill(c.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: AuroraRadius.md, style: .continuous)
                        .strokeBorder(c.line, lineWidth: 0.5)
                )
        )
        .shadow(color: c.shadow, radius: 14, x: 0, y: 6)
        .padding(.horizontal, metrics.pageMargin)
        .padding(.top, 6)
        .padding(.bottom, 6)
    }

    private var icon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(AuroraDecor.popGradient)
                .frame(width: 30, height: 30)
            Image(systemName: "arrow.down")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.white)
        }
    }
}

// MARK: - 更新详情弹窗
struct AppUpdateSheet: View {
    @Environment(\.aurora) private var c
    @Environment(\.screenMetrics) private var metrics

    @ObservedObject var manager: AppUpdateManager
    let info: AppUpdateInfo

    private var isForced: Bool { info.forceUpdate }

    var body: some View {
        VStack(spacing: 0) {
            SheetNavBar(
                title: "发现新版本".localized(),
                leading: {
                    if isForced {
                        Color.clear.frame(width: 44, height: 44)
                    } else {
                        Button {
                            manager.dismissPresentedUpdate()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 19, weight: .medium))
                                .foregroundStyle(c.textTertiary)
                                .frame(width: 44, height: 44)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("关闭".localized())
                    }
                },
                trailing: { Color.clear.frame(width: 44, height: 44) }
            )

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    versionBlock
                        .padding(.horizontal, metrics.pageMargin)
                        .padding(.top, 4)

                    if !info.localizedNotes.isEmpty {
                        GroupTitle(text: "更新内容".localized(), topPadding: 20)
                        notesBlock
                            .padding(.horizontal, metrics.pageMargin)
                    }

                    Spacer(minLength: 16)
                }
            }

            footer
        }
        .background(c.backgroundGrouped)
        .interactiveDismissDisabled(isForced)
    }

    // MARK: 版本
    private var versionBlock: some View {
        HStack(spacing: 8) {
            Text("当前版本".localized())
                .font(AuroraFont.footnote)
                .foregroundStyle(c.textTertiary)
            Text(manager.currentVersion)
                .font(AuroraFont.mono13)
                .foregroundStyle(c.textSecondary)

            Image(systemName: "arrow.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(c.textTertiary)

            Text(info.version)
                .font(AuroraFont.mono13)
                .foregroundStyle(c.accent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: 更新内容
    private var notesBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(info.localizedNotes.enumerated()), id: \.offset) { _, note in
                HStack(alignment: .top, spacing: 8) {
                    Circle()
                        .fill(c.accent.opacity(0.55))
                        .frame(width: 5, height: 5)
                        .padding(.top, 7)
                    Text(note)
                        .font(.system(size: 14))
                        .foregroundStyle(c.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: AuroraRadius.md, style: .continuous)
                .fill(c.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: AuroraRadius.md, style: .continuous)
                        .strokeBorder(c.line, lineWidth: 0.5)
                )
        )
    }

    // MARK: 底部按钮
    private var footer: some View {
        VStack(spacing: 8) {
            PrimaryButton(title: "立即更新".localized(),
                          systemImage: "arrow.down.circle.fill",
                          height: 46) {
                manager.openAppStore()
            }

            if !isForced {
                // ⚠️ 给个图标：上面「立即更新」是 图标 + 文字 横排，这里只有文字的话
                //    两行文字的居中基准不一致，看起来是错的齐。
                SecondaryButton(title: "稍后再说".localized(),
                                systemImage: "clock",
                                height: 44) {
                    manager.dismissPresentedUpdate()
                }
            }
        }
        .padding(.horizontal, metrics.pageMargin)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }
}
