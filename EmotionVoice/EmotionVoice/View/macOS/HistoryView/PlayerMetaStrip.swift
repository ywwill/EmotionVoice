//
//  PlayerMetaStrip.swift
//  EmotionVoice
//
//  音频属性行：时长 / 格式 / 积分 / 音色
//
//  设计取舍（原为「四列 × 两行 + 分隔竖线」的同款卡片，高 65pt 且和下方原文卡片
//  各占一张卡，视觉上是两块并重的信息块）：
//  · 这些都是**只读、看一眼就够**的次要信息，不该和「原文」平分注意力，更不该
//    占掉一行卡片的高度——详情页竖向固定堆叠，这里每省 1pt 都直接给正文。
//  · 所以压成**一行**：图标 + 值，项间一条 10pt 细竖线，无卡片底色、无标题行。
//    高度 65 → 20，腾出的 45pt 全给下面的原文卡片。
//  · 层级用颜色表达而非容器：图标 textTertiary、值 textSecondary，比正文
//    （textPrimary / quaternary）更淡，读的时候自然跳过。
//  · 标签（「时长」「格式」）不再单独成行，改为 `.help()` 悬浮说明；
//    图标本身已经表意，中文用户也能从值的形态（03:21 / WAV / 12.50 积分）认出。
//

import SwiftUI

struct PlayerMetaStrip: View {

    let audio: AudioItem

    /// 音色名只在音频切换时解析一次，不在 body 里查库
    @State private var voiceName: String?

    var body: some View {
        HStack(spacing: 10) {
            metric(icon: "clock", value: formatDuration(audio.duration), help: "时长".localized())
            divider
            metric(icon: "waveform", value: formatText, help: "音频格式".localized())
            divider
            metric(
                icon: "sparkles",
                value: formatCredits(audio.pointsCost),
                unit: "积分".localized(),
                help: "消耗".localized()
            )
            divider
            metric(icon: "person.wave.2", value: voiceName ?? "—", flexes: true, help: "音色".localized())

            Spacer(minLength: 0)
        }
        .frame(height: 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: audio.id) {
            voiceName = VoiceService.shared.displayName(forKey: audio.voice)
        }
    }

    // MARK: - 单元格

    private var divider: some View {
        Rectangle()
            .fill(AppColor.borderMedium)
            .frame(width: 1, height: 10)
    }

    private func metric(
        icon: String,
        value: String,
        unit: String? = nil,
        flexes: Bool = false,
        help: String
    ) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(AppColor.textTertiary)

            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(AppColor.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if let unit {
                    Text(unit)
                        .font(.system(size: 10.5))
                        .foregroundStyle(AppColor.textTertiary)
                }
            }
        }
        // 音色名长度不可控：让它成为唯一可压缩项，其余字段固定宽度不换行
        .layoutPriority(flexes ? -1 : 1)
        .fixedSize(horizontal: false, vertical: true)
        .help(help.localized())
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
