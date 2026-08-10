//
//  HeroSection.swift
//  EmotionVoice
//
//  Created: young on 2026/8/8.
//

import SwiftUI

// MARK: - Hero

struct HeroSection: View {

    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
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
                    PrimaryButton(title: "开始创作".localized(), icon: "play.fill", size: .large) {
                        withAnimation(.easeInOut(duration: 0.22)) {
                            appState.selectedSection = .voiceStudio
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: 280, alignment: .top)

            // 右：波形可视化（填满左侧高度）
            heroVisual
                .frame(maxWidth: .infinity)
                .frame(minHeight: 280, alignment: .top)
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
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                WaveformView()
                    .frame(height: 100)
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .layoutPriority(1)

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
        .frame(maxHeight: .infinity)
    }
}
