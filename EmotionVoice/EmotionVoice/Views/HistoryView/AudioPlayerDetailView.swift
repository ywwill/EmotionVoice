//
//  AudioPlayerDetailView.swift
//  EmotionVoice
//
//  播放详情面板，显示音频信息、波形进度条、播放控制等
//

import SwiftUI

struct AudioPlayerDetailView: View {

    let audio: AudioItem
    @ObservedObject var player: AudioPreviewPlayer

    @State private var isDraggingSlider: Bool = false
    @State private var sliderValue: Double = 0.0

    var body: some View {
        ScrollView {
            VStack(spacing: 15) {
                // 音频头部信息
                audioHeader

                // 波形/进度条
                waveformSection

                // 播放控制
                playbackControls

                // 倍速控制
                speedControl

                Divider()
                    .background(AppColor.borderSubtle)

                // 原文
                originalTextSection
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 音频头部

    private var audioHeader: some View {
        HStack(spacing: 8) {
            HStack(spacing: 8) {
                Text(voiceDescription)
                    .font(.system(size: 12))
                    .foregroundStyle(AppColor.textTertiary)

                Text("·")
                    .foregroundStyle(AppColor.textTertiary.opacity(0.5))

                Text(audio.duration.durationString)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(AppColor.textTertiary)

                Text("·")
                    .foregroundStyle(AppColor.textTertiary.opacity(0.5))

                Text("\(audio.pointsCost) 积分")
                    .font(.system(size: 12))
                    .foregroundStyle(AppColor.textTertiary)
            }
            
            Spacer()
        }
    }

    // MARK: - 波形/进度条

    private var waveformSection: some View {
        VStack(spacing: 16) {
            // 波形进度条（带点击/拖动功能）
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // 背景波形
                    HStack(spacing: 2) {
                        ForEach(0..<waveformBarCount(in: geometry.size.width), id: \.self) { index in
                            let height = waveformHeight(for: index)
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(AppColor.bgElevated)
                                .frame(width: waveformBarWidth(for: geometry.size.width), height: height)
                        }
                    }
                    .frame(height: 56)

                    // 进度覆盖波形
                    HStack(spacing: 2) {
                        ForEach(0..<waveformBarCount(in: geometry.size.width), id: \.self) { index in
                            let progress = Double(index) / Double(waveformBarCount(in: geometry.size.width))
                            let height = waveformHeight(for: index)
                            RoundedRectangle(cornerRadius: 1.5)
                                .fill(progress <= currentProgress ? AppColor.accentPrimary : Color.clear)
                                .frame(width: waveformBarWidth(for: geometry.size.width), height: height)
                        }
                    }
                    .frame(height: 56)
                    .mask(
                        Rectangle()
                            .frame(width: geometry.size.width * currentProgress)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    )

                    // 进度滑块
                    Circle()
                        .fill(.white)
                        .frame(width: 12, height: 12)
                        .shadow(color: AppColor.accentPrimary.opacity(0.4), radius: 4)
                        .offset(x: geometry.size.width * currentProgress - 6)
                        .opacity(player.isPlaying || isDraggingSlider ? 1 : 0)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            isDraggingSlider = true
                            let progress = max(0, min(1, value.location.x / geometry.size.width))
                            sliderValue = progress
                            player.seek(to: progress * player.duration)
                        }
                        .onEnded { _ in
                            isDraggingSlider = false
                        }
                )
            }
            .frame(height: 56)

            // 时间显示
            HStack {
                Text(formatTime(isDraggingSlider ? sliderValue * player.duration : player.currentTime))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(AppColor.textTertiary)
                    .frame(width: 44, alignment: .leading)

                Spacer()

                Text(formatTime(player.duration))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(AppColor.textTertiary)
                    .frame(width: 44, alignment: .trailing)
            }
        }
        .padding(20)
        .background(AppColor.bgTertiary)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - 辅助方法

    private func waveformBarCount(in width: CGFloat) -> Int {
        max(40, Int(width / 5))
    }

    private func waveformBarWidth(for width: CGFloat) -> CGFloat {
        CGFloat(width / CGFloat(waveformBarCount(in: width))) - 2
    }

    // MARK: - 播放控制

    private var playbackControls: some View {
        HStack(spacing: 12) {
            // 后退 15 秒
            controlButton(icon: "gobackward.15", action: { skip(by: -15) })

            // 后退 5 秒
            controlButton(icon: "gobackward.5", action: { skip(by: -5) })

            // 播放/暂停
            Button {
                togglePlayback()
            } label: {
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(
                        LinearGradient(
                            colors: [AppColor.accentPrimary, AppColor.accentSecondary],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(Circle())
                    .shadow(color: AppColor.accentPrimary.opacity(0.3), radius: 8, y: 4)
            }
            .buttonStyle(.plain)

            // 前进 5 秒
            controlButton(icon: "goforward.5", action: { skip(by: 5) })

            // 前进 15 秒
            controlButton(icon: "goforward.15", action: { skip(by: 15) })
        }
    }

    private func controlButton(icon: String, action: @escaping () -> Void) -> some View {
        Button {
            action()
        } label: {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(AppColor.textSecondary)
                .frame(width: 44, height: 36)
                .background(AppColor.bgTertiary)
                .clipShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
    }

    // MARK: - 倍速控制

    private var speedControl: some View {
        HStack(spacing: 10) {
            Text("播放速度")
                .font(.system(size: 11))
                .foregroundStyle(AppColor.textTertiary)

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
                HStack(spacing: 4) {
                    Text(String(format: "%.2g×", player.playbackRate))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(AppColor.textSecondary)
                }
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(AppColor.bgTertiary)
                .clipShape(RoundedRectangle(cornerRadius: 18))
            }
            .menuStyle(.borderlessButton)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    // MARK: - 原文

    private var originalTextSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("原文")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(AppColor.textTertiary)
                .textCase(.uppercase)

            ScrollView {
                Text(audio.text.isEmpty ? "暂无原文内容" : audio.text)
                    .font(.system(size: 13))
                    .foregroundStyle(audio.text.isEmpty ? AppColor.textTertiary : AppColor.textPrimary)
                    .lineSpacing(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 160)
        }
        .padding(16)
        .background(AppColor.bgSecondary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(AppColor.borderSubtle, lineWidth: 1)
        )
    }

    // MARK: - 辅助方法

    private var currentProgress: Double {
        if isDraggingSlider {
            return sliderValue
        }
        guard player.duration > 0 else { return 0 }
        return player.progress
    }

    private func waveformHeight(for index: Int) -> CGFloat {
        let base: CGFloat = 8
        let variance: CGFloat = 32
        let seed = Double(index) * 0.15
        let height = sin(seed) * 12 + cos(seed * 0.8) * 8 + 6
        return base + CGFloat(max(0, height))
    }

    private func formatTime(_ time: Double) -> String {
        guard !time.isNaN && time.isFinite else { return "0:00" }
        let minutes = Int(time) / 60
        let seconds = Int(time) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    private func togglePlayback() {
        if player.isPlaying {
            player.pause()
        } else if player.isPaused {
            // 暂停状态，恢复播放
            player.resume()
        } else {
            // 未播放状态，开始播放
            if let url = audio.absoluteURL as URL? {
                player.play(url: url)
            }
        }
    }

    private func skip(by seconds: Double) {
        let newTime = max(0, min(player.duration, player.currentTime + seconds))
        player.seek(to: newTime)
    }

    // MARK: - 计算属性

    private var voiceName: String? {
        guard !audio.voice.isEmpty else { return nil }
        return VoiceService.shared.fetchAll()
            .first(where: { $0.key == audio.voice })?.name
    }

    private var voiceDescription: String {
        guard let voice = voiceName else { return "未知音色" }
        return voice
    }
}
