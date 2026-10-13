//
//  PlayerUtilityView.swift
//  EmotionVoice
//
//  倍速菜单 + 剩余时间 + 从头播放
//

import SwiftUI

struct PlayerUtilityView: View {

    @ObservedObject var player: AudioPreviewPlayer

    var body: some View {
        HStack(spacing: 8) {
            speedMenu

            Text(remainingHint)
                .font(.system(size: 11))
                .foregroundStyle(AppColor.textTertiary)

            Spacer()

            rewindButton
        }
        .padding(.top, 18)
        .overlay(alignment: .top) {
            Divider().background(AppColor.borderSubtle)
        }
    }

    // MARK: - 倍速

    private var speedMenu: some View {
        Menu {
            ForEach(AudioPreviewPlayer.playbackRateOptions, id: \.rate) { option in
                Button {
                    player.setPlaybackRate(option.rate)
                } label: {
                    HStack {
                        Text(option.label)
                        if player.playbackRate == option.rate {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "speedometer")
                    .font(.system(size: 11))
                    .foregroundStyle(AppColor.textTertiary)

                Text(PlayerTextMetrics.formatRate(player.playbackRate))
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundStyle(AppColor.accentPrimary)

                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(AppColor.textTertiary)
            }
            .padding(.horizontal, 11)
            .frame(height: 32)
            .background(AppColor.bgTertiary)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(AppColor.borderSubtle, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }

    // MARK: - 从头播放

    private var rewindButton: some View {
        Button {
            player.seek(to: 0)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "backward.end.fill")
                    .font(.system(size: 11))
                Text("从头播放")
                    .font(.system(size: 11))
            }
            .foregroundStyle(AppColor.textSecondary)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(AppColor.bgTertiary)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(AppColor.borderSubtle, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
    }

    // MARK: - 派生文案

    private var remainingHint: String {
        let rate = max(Double(player.playbackRate), 0.01)
        let left = max(0, player.duration - player.currentTime) / rate
        return "剩余约 " + PlayerTextMetrics.formatTime(left)
    }
}
