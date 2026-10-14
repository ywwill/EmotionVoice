//
//  PlaybackStatusBar.swift
//  EmotionVoice
//
//  播放面板底部状态栏：播放状态 + 快捷键提示
//  对齐 UI/audio-player.html 的 .statusbar
//

import SwiftUI

struct PlaybackStatusBar: View {

    @ObservedObject var player: AudioPreviewPlayer

    var body: some View {
        HStack(spacing: 12) {
            // 状态：圆点 + 文案
            HStack(spacing: 7) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 6, height: 6)
                    .shadow(color: statusGlow, radius: player.isPlaying ? 8 : 0)

                Text(statusText)
                    .font(.system(size: 11))
                    .foregroundStyle(AppColor.textTertiary)
            }

            Spacer()

            // 快捷键提示
            HStack(spacing: 14) {
                hint(caps: ["空格"], text: "播放 / 暂停")
                hint(caps: ["←", "→"], text: "5 秒")
                hint(caps: ["⌘", "←", "→"], text: "15 秒")
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 34)
        .background(Color(hex: 0x0C0D10).opacity(0.7))
        .overlay(alignment: .top) {
            Divider().background(AppColor.borderSubtle)
        }
    }

    // MARK: - 状态

    private var statusColor: Color {
        if player.isPlaying { return AppColor.statusSuccess }
        if player.isPaused { return AppColor.accentPrimary }
        return AppColor.textTertiary
    }

    private var statusGlow: Color {
        player.isPlaying ? AppColor.statusSuccess.opacity(0.7) : .clear
    }

    private var statusText: String {
        if player.isPlaying {
            return "正在播放".localized() + " · " + PlayerTextMetrics.formatRate(player.playbackRate)
        }
        if player.isPaused {
            return "已暂停".localized() + " · " +  PlayerTextMetrics.formatTime(player.currentTime)
        }
        if player.isFinished {
            return "播放结束".localized()
        }
        return "已就绪".localized()
    }

    // MARK: - 快捷键提示

    private func hint(caps: [String], text: String) -> some View {
        HStack(spacing: 5) {
            HStack(spacing: 3) {
                ForEach(caps, id: \.self) { keyCap($0) }
            }
            Text(text.localized())
        }
        .font(.system(size: 11))
        .foregroundStyle(AppColor.textTertiary)
    }

    private func keyCap(_ label: String) -> some View {
        Text(label.localized())
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(AppColor.textSecondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(AppColor.bgTertiary)
            .overlay(
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(AppColor.borderSubtle, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
    }
}
