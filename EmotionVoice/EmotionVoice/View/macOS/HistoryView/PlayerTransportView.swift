//
//  PlayerTransportView.swift
//  EmotionVoice
//
//  走带控制：后退 15 / 5，播放暂停，前进 5 / 15
//  对齐 UI/audio-player.html 的层级：15s 档 52px、5s 档 40px、播放键 62px
//

import SwiftUI

/// 只订阅播放态的子视图，播放/暂停按钮随之切换，不影响父视图重绘
struct PlayerTransportView: View {

    @ObservedObject var player: AudioPreviewPlayer
    let audio: AudioItem

    var body: some View {
        HStack(spacing: 20) {
            skipButton(systemName: "gobackward.15", side: 52, glyph: 34) { player.skip(by: -15) }
            skipButton(systemName: "gobackward.5", side: 40, glyph: 24) { player.skip(by: -5) }

            playButton

            skipButton(systemName: "goforward.5", side: 40, glyph: 24) { player.skip(by: 5) }
            skipButton(systemName: "goforward.15", side: 52, glyph: 34) { player.skip(by: 15) }
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 播放键

    private var playButton: some View {
        Button {
            player.togglePlayback(url: audio.absoluteURL)
        } label: {
            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: 26))
                .foregroundStyle(Color(hex: 0x241505))
                .frame(width: 62, height: 62)
                .background(
                    LinearGradient(
                        colors: [AppColor.accentGlow, AppColor.accentSecondary],
                        startPoint: UnitPoint(x: 0.15, y: 0),
                        endPoint: UnitPoint(x: 0.85, y: 1)
                    )
                )
                .clipShape(Circle())
                .shadow(color: AppColor.accentPrimary.opacity(0.28), radius: 22, y: 8)
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
