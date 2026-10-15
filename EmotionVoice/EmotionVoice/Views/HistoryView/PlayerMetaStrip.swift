//
//  PlayerMetaStrip.swift
//  EmotionVoice
//
//  音频属性卡片：时长 / 格式 / 积分 / 音色
//  与「音频原文」卡片同款容器（bgSecondary + 描边 + 圆角 12），放在原文卡片上方：
//  播放区（波形 / 走带 / 控制）在上，信息区（属性 / 原文）在下，两块同款卡片成组。
//
//  对齐 UI/player_meta_placement.html 方案 B。

import SwiftUI

struct PlayerMetaStrip: View {

    let audio: AudioItem

    /// 音色名只在音频切换时解析一次，不在 body 里查库
    @State private var voiceName: String?

    var body: some View {
        HStack(spacing: 0) {
            metaColumn(icon: "clock", title: "时长".localized(), value: formatDuration(audio.duration), unit: nil)
            columnDivider
            metaColumn(icon: "waveform", title: "格式".localized(), value: formatText, unit: nil)
            columnDivider
            metaColumn(icon: "sparkles", title: "积分".localized(), value: formatCredits(audio.pointsCost), unit: nil)
            columnDivider
            metaColumn(icon: "person.wave.2", title: "音色".localized(), value: voiceName ?? "—", unit: nil)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .background(AppColor.bgSecondary)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(AppColor.borderSubtle, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .task(id: audio.id) {
            voiceName = VoiceService.shared.displayName(forKey: audio.voice)
        }
    }

    // MARK: - 单元格

    private var columnDivider: some View {
        Rectangle()
            .fill(AppColor.borderSubtle)
            .frame(width: 1, height: 26)
    }

    private func metaColumn(
        icon: String,
        title: String,
        value: String,
        unit: String?
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11))
                Text(title.localized())
                    .font(.system(size: 11))
            }
            .foregroundStyle(AppColor.textTertiary)

            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(value)
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    .foregroundStyle(AppColor.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if let unit {
                    Text(unit)
                        .font(.system(size: 11))
                        .foregroundStyle(AppColor.textTertiary)
                        .padding(.leading, 3)
                }
            }
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 派生数据

    /// 音频格式（WAV / MP3 …）：优先用记录里的 format，缺失时退回文件扩展名
    private var formatText: String {
        let raw = audio.format.trimmingCharacters(in: .whitespacesAndNewlines)
        if !raw.isEmpty { return raw.uppercased() }
        let ext = audio.fileExtension
        return ext.isEmpty ? "—" : ext.uppercased()
    }
}
