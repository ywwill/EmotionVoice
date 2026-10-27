//
//  PlayerDetailView.swift
//  iOSEmora
//
//  播放详情（push 进项目标签的导航栈）
//
//  与 macOS 右侧详情面板的差异：
//  - macOS 的四列 meta 条在 iPhone 上折成 **2×2**（宽屏回到 4 列）
//  - 底部状态栏**去掉三组键帽提示**（iOS 没有键盘快捷键），只留播放状态
//  - 倍速菜单 0.5–2x 六档保留（macOS 的 `playbackRateOptions`）
//  - 波形整卡可点击 / 拖动定位（44pt 触摸高度）
//  - 右侧时间可点切换「总时长 ⇄ −剩余」
//

import SwiftUI

struct PlayerDetailView: View {
    @Environment(\.aurora) private var c
    @Environment(\.screenMetrics) private var metrics

    let item: AudioItem

    @StateObject private var player = AudioPreviewPlayer.shared
    @State private var showsRemaining = true
    @State private var isSharing = false
    @State private var voiceName: String = ""

    private var url: URL { item.absoluteURL }
    private var isThisPlaying: Bool { player.isPlaying(url: url) }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                waveformCard
                    .padding(.horizontal, metrics.pageMargin)
                    .padding(.top, 12)

                transportRow

                controlRow

                metaCard
                    .padding(.horizontal, metrics.pageMargin)

                textCard
                    .padding(.horizontal, metrics.pageMargin)
                    .padding(.top, 12)

                statusLine
                    .padding(.horizontal, metrics.pageMargin + 4)
                    .padding(.top, 14)

                Spacer(minLength: 24)
            }
        }
        .background(c.backgroundGrouped)
        .navigationTitle(item.shownName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { isSharing = true } label: {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(c.accent)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .sheet(isPresented: $isSharing) {
            ShareSheet(items: [url])
        }
        .onAppear {
            voiceName = VoiceService.shared.fetchByKeys([item.voice]).first?.localizedName ?? item.voice
            if !isThisPlaying, item.isOnDisk {
                player.play(url: url, identifier: item.fileName)
            }
        }
        .onDisappear { player.stop() }
    }

    // MARK: 波形卡

    private var waveformCard: some View {
        VStack(spacing: 0) {
            WaveformScrubber(progress: player.progress,
                             seed: item.fileName,
                             tint: c.accent,
                             trackTint: c.slot) { fraction in
                player.seek(to: fraction * max(player.duration, item.duration))
            }
            .frame(height: 44)

            HStack {
                Text(formatDuration(player.currentTime))
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(c.textSecondary)
                Spacer(minLength: 0)
                Button { showsRemaining.toggle() } label: {
                    Text(trailingTimeText)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(c.textTertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 8)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: AuroraRadius.lg, style: .continuous)
                .fill(c.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: AuroraRadius.lg, style: .continuous)
                        .strokeBorder(c.line, lineWidth: 0.5)
                )
        )
    }

    private var trailingTimeText: String {
        let total = max(player.duration, item.duration)
        guard showsRemaining, total > 0 else { return formatDuration(total) }
        return "−" + formatDuration(max(0, total - player.currentTime))
    }

    // MARK: 走带

    private var transportRow: some View {
        HStack(spacing: 22) {
            transportButton("backward.end.fill", size: 30) { player.seek(to: 0) }
            transportButton("gobackward.15", size: 24) { player.skip(by: -15) }

            Button {
                if isThisPlaying { player.pause() } else { player.play(url: url, identifier: item.fileName) }
            } label: {
                ZStack {
                    Circle().fill(c.ctaGradient)
                    Image(systemName: isThisPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(c.ctaForeground)
                }
                .frame(width: 64, height: 64)
            }
            .buttonStyle(.plain)

            transportButton("goforward.15", size: 24) { player.skip(by: 15) }
            transportButton("forward.end.fill", size: 30) {
                player.seek(to: max(player.duration, item.duration))
            }
        }
        .padding(.top, 16)
        .padding(.bottom, 4)
        .frame(maxWidth: .infinity)
    }

    private func transportButton(_ systemName: String, size: CGFloat,
                                 action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(c.textSecondary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: 倍速 / 剩余 / 从头播放

    private var controlRow: some View {
        HStack(spacing: 10) {
            Menu {
                ForEach(AudioPreviewPlayer.playbackRateOptions, id: \.rate) { option in
                    Button {
                        player.setPlaybackRate(option.rate)
                    } label: {
                        HStack {
                            Text(option.label)
                            if abs(player.playbackRate - option.rate) < 0.001 {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "speedometer")
                        .font(.system(size: 13, weight: .semibold))
                    Text(rateLabel)
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                }
                .foregroundStyle(c.accent)
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background(
                    Capsule(style: .continuous)
                        .fill(c.accentSoft)
                )
            }

            Spacer(minLength: 0)

            Text(String(format: "剩余约 %@".localized(),
                        formatDuration(max(0, max(player.duration, item.duration) - player.currentTime))))
                .font(.system(size: 12))
                .foregroundStyle(c.textTertiary)

            Spacer(minLength: 0)

            Button { player.seek(to: 0) } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 12, weight: .semibold))
                    Text("从头播放".localized())
                        .font(.system(size: 12.5))
                }
                .foregroundStyle(c.textSecondary)
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background(
                    Capsule(style: .continuous)
                        .fill(c.surface3)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, metrics.pageMargin)
        .padding(.top, 10)
        .padding(.bottom, 14)
    }

    private var rateLabel: String {
        let r = player.playbackRate
        if r == r.rounded() { return String(format: "%.0fx", r) }
        return String(format: "%.2fx", r)
    }

    // MARK: meta 卡（手机 2×2 / 宽屏 4 列）

    private var metaCard: some View {
        let cols = metrics.metaColumns
        let items: [(String, String, String)] = [
            ("clock", "时长".localized(), formatDuration(max(item.duration, player.duration))),
            ("waveform", "格式".localized(), item.format.uppercased()),
            ("diamond.fill", "积分".localized(), formatCredits(item.pointsCost)),
            ("person.wave.2.fill", "音色".localized(), voiceName)
        ]
        let rows = Int(ceil(Double(items.count) / Double(cols)))

        return VStack(spacing: 0) {
            ForEach(0..<rows, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<cols, id: \.self) { col in
                        let idx = row * cols + col
                        if idx < items.count {
                            metaCell(icon: items[idx].0, key: items[idx].1, value: items[idx].2)
                            if col < cols - 1 { separator(vertical: true) }
                        } else {
                            Spacer(minLength: 0)
                        }
                    }
                }
                if row < rows - 1 { separator(vertical: false) }
            }
        }
        .background(
            RoundedRectangle(cornerRadius: AuroraRadius.lg, style: .continuous)
                .fill(c.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: AuroraRadius.lg, style: .continuous)
                        .strokeBorder(c.line, lineWidth: 0.5)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: AuroraRadius.lg, style: .continuous))
    }

    private func separator(vertical: Bool) -> some View {
        Group {
            if vertical {
                Rectangle().fill(c.line).frame(width: 0.5)
            } else {
                Rectangle().fill(c.line).frame(height: 0.5)
            }
        }
    }

    private func metaCell(icon: String, key: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                    .foregroundStyle(c.textTertiary)
                Text(key)
                    .font(.system(size: 11))
                    .foregroundStyle(c.textTertiary)
            }
            Text(value)
                .font(.system(size: 16, weight: .semibold, design: .monospaced))
                .foregroundStyle(c.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    // MARK: 文本卡

    private var textCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(String(format: "%d 字 · %d 句".localized(),
                            item.text.count, sentenceCount))
                    .font(.system(size: 11.5))
                    .foregroundStyle(c.textTertiary)
                Spacer(minLength: 0)
                Button {
                    UIPasteboard.general.string = item.text
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 11))
                        Text("复制".localized())
                            .font(.system(size: 12))
                    }
                    .foregroundStyle(c.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(
                        Capsule(style: .continuous).fill(c.surface3)
                    )
                }
                .buttonStyle(.plain)
            }
            Text(item.text)
                .font(.system(size: 14.5))
                .lineSpacing(1.62 * 14.5 - 14.5)
                .foregroundStyle(c.textPrimary)
                .textSelection(.enabled)
                .padding(.top, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: AuroraRadius.lg, style: .continuous)
                .fill(c.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: AuroraRadius.lg, style: .continuous)
                        .strokeBorder(c.line, lineWidth: 0.5)
                )
        )
    }

    // MARK: 状态行

    private var statusLine: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(isThisPlaying ? c.success : c.textTertiary)
                .frame(width: 7, height: 7)
            Text(isThisPlaying
                 ? String(format: "正在播放 · %@".localized(), rateLabel)
                 : "已暂停".localized())
                .font(.system(size: 12))
                .foregroundStyle(c.textSecondary)
            Spacer(minLength: 0)
        }
    }

    private var sentenceCount: Int {
        item.text.components(separatedBy: CharacterSet(charactersIn: "。！？!?；;\n"))
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .count
    }
}

// MARK: - 可拖动波形

/// 44pt 高的波形定位条：已播部分着色，整卡可点击 / 拖动定位。
private struct WaveformScrubber: View {
    let progress: Double
    let seed: String
    let tint: Color
    let trackTint: Color
    let onSeek: (Double) -> Void

    var barCount: Int = 44

    var body: some View {
        GeometryReader { geo in
            let gap: CGFloat = 2
            let barW = max(2, (geo.size.width - gap * CGFloat(barCount - 1)) / CGFloat(barCount))
            let cut = geo.size.width * CGFloat(min(max(progress, 0), 1))

            ZStack(alignment: .leading) {
                // 底
                HStack(alignment: .center, spacing: gap) {
                    ForEach(0..<barCount, id: \.self) { i in
                        bar(width: barW, index: i, color: trackTint, height: geo.size.height)
                    }
                }
                // 已播
                HStack(alignment: .center, spacing: gap) {
                    ForEach(0..<barCount, id: \.self) { i in
                        bar(width: barW, index: i, color: tint, height: geo.size.height)
                    }
                }
                .mask(alignment: .leading) {
                    Rectangle().frame(width: max(cut, 0), height: geo.size.height)
                }
                // 播放头
                Rectangle()
                    .fill(AuroraDecor.rose)
                    .frame(width: 2, height: geo.size.height)
                    .offset(x: min(max(cut, 0), geo.size.width - 2))
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onEnded { value in
                        let f = Double(min(max(value.location.x / max(geo.size.width, 1), 0), 1))
                        onSeek(f)
                    }
            )
        }
    }

    private func bar(width: CGFloat, index: Int, color: Color, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
            .fill(color)
            .frame(width: width, height: max(4, envelope(index) * height))
    }

    /// 由文件名派生的确定性包络（同一条音频每次进来波形一致）
    private func envelope(_ index: Int) -> CGFloat {
        let seedValue = abs(seed.hashValue % 97)
        let t = Double(index) / Double(max(barCount - 1, 1))
        let v = 0.38
            + 0.32 * sin(t * 11.3 + Double(seedValue) * 0.21)
            + 0.18 * sin(t * 29.7 + 1.4 + Double(seedValue) * 0.07)
        return CGFloat(min(max(v, 0.12), 1))
    }
}
