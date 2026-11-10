//
//  PlayerTransportView.swift
//  EmotionVoice
//
//  走带控制：后退 15 / 5，播放暂停，前进 5 / 15
//
//  ⚠️ 高度是「文本区能拿多少」的直接变量（详情页竖向固定堆叠，上面多 1pt 就从
//     原文卡片扣 1pt）。所以这里比 HTML 稿整体收一档：播放键 62 → 52、
//     15s 档 52 → 42、5s 档 40 → 32。层级比例（52 : 42 : 32）保持与原设计一致，
//     缩的是绝对尺寸，不是主次关系。
//

import SwiftUI

/// 只订阅播放态的子视图，播放/暂停按钮随之切换，不影响父视图重绘
struct PlayerTransportView: View {

    @ObservedObject var player: AudioPreviewPlayer
    let audio: AudioItem

    var body: some View {
        HStack(spacing: 22) {
            skipButton(systemName: "gobackward.15", side: 42, glyph: 27) { player.skip(by: -15) }
            skipButton(systemName: "gobackward.5", side: 32, glyph: 19) { player.skip(by: -5) }

            playButton

            skipButton(systemName: "goforward.5", side: 32, glyph: 19) { player.skip(by: 5) }
            skipButton(systemName: "goforward.15", side: 42, glyph: 27) { player.skip(by: 15) }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 播放键

    private var playButton: some View {
        Button {
            player.togglePlayback(url: audio.absoluteURL)
        } label: {
            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 22))
                .foregroundStyle(Color(hex: 0x241505))
                .frame(width: 52, height: 52)
                .background(
                    LinearGradient(
                        colors: [AppColor.accentGlow, AppColor.accentSecondary],
                        startPoint: UnitPoint(x: 0.15, y: 0),
                        endPoint: UnitPoint(x: 0.85, y: 1)
                    )
                )
                .clipShape(Circle())
                .shadow(color: AppColor.accentPrimary.opacity(0.28), radius: 18, y: 6)
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
    }

    // MARK: - 快进/快退键

    private func skipButton(
        systemName: String,
        side: CGFloat,
        glyph: CGFloat,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: glyph))
                .foregroundStyle(AppColor.textSecondary)
                .frame(width: side, height: side)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .help(helpText(for: systemName))
    }

    private func helpText(for systemName: String) -> String {
        switch systemName {
        case "gobackward.15": return "后退 15 秒"
        case "gobackward.5":  return "后退 5 秒"
        case "goforward.5":   return "前进 5 秒"
        case "goforward.15":  return "前进 15 秒"
        default:              return ""
        }
    }
}
