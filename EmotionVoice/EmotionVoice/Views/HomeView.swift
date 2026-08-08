//
//  HomeView.swift
//  EmotionVoice
//
//  Created by young on 2026/8/8.
//

import SwiftUI

/// 首页
struct HomeView: View {

    @EnvironmentObject var appState: AppState
    @State private var recentProjects: [Project] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {

            // Hero 区域
            HeroSection()

            // 快速开始
            quickActionsSection

            // 本月统计
            monthlyStatsSection

            // 最近项目
            recentProjectsSection

            Spacer(minLength: 0)
        }
        .padding(32)
        .onAppear {
            recentProjects = ProjectService.shared.fetchAllProjects()
        }
    }

    // MARK: - 快速开始

    private var quickActionsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(title: "快速开始".localized())

            HStack(spacing: 12) {
                QuickActionCard(
                    icon: "📝",
                    title: "文本转语音".localized(),
                    desc: "粘贴文字，3秒生成专业音频".localized(),
                    cta: "立即新建".localized(),
                    gradient: [AppColor.accentPrimary, AppColor.accentSecondary]
                ) {
                    appState.selectedSection = .voiceStudio
                }

                QuickActionCard(
                    icon: "🎭",
                    title: "探索音色库".localized(),
                    desc: "浏览500+精选音色，支持方言角色".localized(),
                    cta: "浏览音色".localized(),
                    gradient: [Color(hex: 0x6B8BC9), Color(hex: 0x5577B0)]
                ) {
                    appState.selectedSection = .voices
                }

                QuickActionCard(
                    icon: "📂",
                    title: "打开最近项目".localized(),
                    desc: "继续未完成的创作".localized(),
                    cta: "查看项目".localized(),
                    gradient: [Color(hex: 0x8AA5A0), Color(hex: 0x6F8A85)]
                ) {
                    appState.selectedSection = .projects
                }
            }
        }
    }

    // MARK: - 本月统计

    private var monthlyStatsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(
                title: "本月统计".localized(),
                action: "详细报告".localized(),
                actionIcon: "arrow.right"
            )

            HStack(spacing: 0) {
                StatItem(value: "\(appState.monthlyUsed)", label: "积分消耗".localized())
                Divider().background(AppColor.borderSubtle)
                StatItem(value: "28", label: "音频生成".localized())
                Divider().background(AppColor.borderSubtle)
                StatItem(value: "12.4", unit: "h", label: "总音频时长".localized())
                Divider().background(AppColor.borderSubtle)
                StatItem(value: "18", label: "音色使用".localized())
            }
            .padding(20)
            .background(AppColor.bgSecondary)
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.large)
                    .stroke(AppColor.borderSubtle, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.large))
        }
    }

    // MARK: - 最近项目

    private var recentProjectsSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionTitle(
                title: "最近项目".localized(),
                action: "查看全部".localized(),
                actionIcon: "arrow.right"
            )

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 12),
                          GridItem(.flexible(), spacing: 12)],
                spacing: 12
            ) {
                if recentProjects.isEmpty {
                    emptyProjectsHint
                } else {
                    ForEach(recentProjects.prefix(4)) { project in
                        ProjectCard(project: project)
                    }
                }
            }
        }
    }

    private var emptyProjectsHint: some View {
        HStack {
            Spacer()
            VStack(spacing: 8) {
                Text("暂无数据".localized())
                    .font(AppFont.bodyMedium)
                    .foregroundStyle(AppColor.textTertiary)
                Button {
                    appState.selectedSection = .voiceStudio
                } label: {
                    Text("新建项目".localized())
                        .font(.system(size: 12, weight: .medium))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .background(AppColor.accentPrimary.opacity(0.15))
                        .foregroundStyle(AppColor.accentPrimary)
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.vertical, 32)
        .gridCellColumns(2)
    }
}

// MARK: - Hero

private struct HeroSection: View {

    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(alignment: .center, spacing: 24) {
            // 左：文案
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    heroTitle(lead: "让文字".localized(),
                              accent: "开口说话".localized())
                    heroTitle(lead: "让声音".localized(),
                              accent: "传递情感".localized())
                }
                .font(.system(size: 36, weight: .bold))
                .lineSpacing(2)

                Text("基于业界领先的情感语音合成引擎，20+ 种情感表达，500+ 精选音色。让你的 macOS 变成专业录音棚。".localized())
                    .font(AppFont.bodyMedium)
                    .foregroundStyle(AppColor.textSecondary)
                    .lineLimit(3)
                    .frame(maxWidth: 440, alignment: .leading)

                HStack(spacing: 12) {
                    PrimaryButton(title: "开始创作".localized(), icon: "play.fill") {
                        appState.selectedSection = .voiceStudio
                    }
                    SecondaryButton(title: "浏览音色库".localized(), icon: nil) {
                        appState.selectedSection = .voices
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // 右：波形可视化
            heroVisual
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(40)
        .background(
            LinearGradient(
                colors: [
                    AppColor.bgTertiary.opacity(0.6),
                    AppColor.bgSecondary.opacity(0.3)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.xlarge)
                .stroke(AppColor.borderSubtle, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.xlarge))
        .overlay(alignment: .topTrailing) {
            // 装饰光晕
            Circle()
                .fill(
                    RadialGradient(
                        colors: [AppColor.accentPrimary.opacity(0.15), Color.clear],
                        center: .center,
                        startRadius: 10,
                        endRadius: 150
                    )
                )
                .frame(width: 300, height: 300)
                .offset(x: 100, y: -100)
                .allowsHitTesting(false)
        }
    }

    private func heroTitle(lead: String, accent: String) -> some View {
        (
            Text(lead)
                .foregroundStyle(AppColor.textPrimary)
            + Text(accent)
                .foregroundStyle(AppColor.accentPrimary)
        )
        .font(.system(size: 36, weight: .bold))
    }

    private var heroVisual: some View {
        VStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: AppRadius.medium)
                    .fill(AppColor.bgTertiary)
                    .frame(height: 180)

                WaveformView()
                    .frame(height: 80)
                    .padding(.horizontal, 30)

                // 浮动情感标签
                VStack {
                    HStack {
                        Spacer()
                        Text("[excited]")
                            .font(AppFont.monoSmall)
                            .foregroundStyle(AppColor.accentGlow)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(AppColor.bgElevated)
                            .overlay(
                                RoundedRectangle(cornerRadius: AppRadius.small)
                                    .stroke(AppColor.borderMedium, lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: AppRadius.small))
                            .padding(16)
                    }
                    Spacer()
                    HStack {
                        Text("00:32 · 28 积分".localized())
                            .font(AppFont.monoSmall)
                            .foregroundStyle(AppColor.textSecondary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(AppColor.bgElevated)
                            .overlay(
                                RoundedRectangle(cornerRadius: AppRadius.small)
                                    .stroke(AppColor.borderMedium, lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: AppRadius.small))
                            .padding(16)
                        Spacer()
                    }
                }
            }

            // 音色信息
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    if let v = appState.selectedVoice {
                        Text(v.name)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(AppColor.textPrimary)
                        Text(v.desc)
                            .font(AppFont.monoSmall)
                            .foregroundStyle(AppColor.textTertiary)
                    }
                }
                Spacer()
                Text("专业版".localized())
                    .font(AppFont.monoSmall)
                    .foregroundStyle(AppColor.textTertiary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(AppColor.bgTertiary)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.small))
        }
    }
}

// MARK: - 快速操作卡

private struct QuickActionCard: View {

    let icon: String
    let title: String
    let desc: String
    let cta: String
    let gradient: [Color]
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: AppRadius.small)
                        .fill(
                            LinearGradient(
                                colors: gradient,
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Text(icon)
                        .font(.system(size: 16))
                }
                .frame(width: 36, height: 36)

                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppColor.textPrimary)

                Text(desc)
                    .font(AppFont.bodySmall)
                    .foregroundStyle(AppColor.textSecondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Text(cta + " →")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(AppColor.accentPrimary)
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColor.bgSecondary)
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.medium)
                    .stroke(AppColor.borderSubtle, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - 统计项

private struct StatItem: View {

    let value: String
    var unit: String? = nil
    let label: String

    var body: some View {
        VStack(spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 24, weight: .bold, design: .monospaced))
                    .foregroundStyle(AppColor.textPrimary)
                if let unit {
                    Text(unit)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(AppColor.accentPrimary)
                }
            }
            Text(label)
                .font(AppFont.caption)
                .foregroundStyle(AppColor.textTertiary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - 项目卡

private struct ProjectCard: View {

    let project: Project

    var body: some View {
        Button {
            // 进入项目详情
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 12) {
                    Text("📁")
                        .font(.system(size: 20))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(project.name)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(AppColor.textPrimary)
                            .lineLimit(1)
                        Text(metaLine)
                            .font(AppFont.monoSmall)
                            .foregroundStyle(AppColor.textTertiary)
                    }
                    Spacer()
                }

                ProgressBar(progress: progress)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColor.bgSecondary)
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.medium)
                    .stroke(AppColor.borderSubtle, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium))
        }
        .buttonStyle(.plain)
    }

    private var progress: Double {
        // 演示数据：基于 updatedAt 时间距离
        let days = Date().timeIntervalSince(project.updatedAt) / 86400
        if days < 1 { return 1.0 }
        if days < 3 { return 0.6 }
        if days < 7 { return 0.4 }
        return 0.2
    }

    private var metaLine: String {
        let audios = ProjectService.shared.fetchAudios(projectId: project.id)
        let totalDuration = audios.reduce(0.0) { $0 + $1.duration }
        let minutes = Int(totalDuration / 60)
        if audios.isEmpty {
            return "\(project.updatedAt.shortDateString)"
        }
        let voiceName = VoiceService.shared.fetchAll()
            .first(where: { $0.key == audios.first?.voice })?.name ?? "—"
        return "\(audios.count) 个音频 · \(minutes) 分钟 · \(voiceName)"
    }
}

private struct ProgressBar: View {

    let progress: Double

    var body: some View {
        HStack(spacing: 8) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(AppColor.bgElevated)
                    RoundedRectangle(cornerRadius: 2)
                        .fill(
                            LinearGradient(
                                colors: [AppColor.accentPrimary, AppColor.accentGlow],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geo.size.width * progress)
                }
            }
            .frame(height: 3)

            Text(progress >= 0.99 ? "已完成".localized() : "\(Int(progress * 100))%")
                .font(AppFont.monoSmall)
                .foregroundStyle(progress >= 0.99 ? AppColor.statusSuccess : AppColor.textSecondary)
                .frame(width: 50, alignment: .trailing)
        }
    }
}