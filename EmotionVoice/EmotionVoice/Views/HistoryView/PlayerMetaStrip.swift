//
//  PlayerMetaStrip.swift
//  EmotionVoice
//
//  播放详情顶部的元信息卡（时长 / 字数 / 积分 / 音色）
//

import SwiftUI

struct PlayerMetaStrip: View {

    let audio: AudioItem
    /// 由外部解析好传进来，这里不查库
    let voiceName: String?

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            metaCell(icon: "clock", title: "音频时长", value: audio.duration.durationString, unit: nil)
            metaCell(icon: "doc.text", title: "文本字数", value: "\(charCount)", unit: "字")
            metaCell(icon: "sparkles", title: "消耗积分", value: formatCredits(audio.pointsCost), unit: "分")
            metaCell(icon: "person.wave.2", title: "使用音色", value: voiceName ?? "—", unit: nil)
        }
    }

    // MARK: - 单元格

    private func metaCell(
        icon: String,
        title: String,
        value: String,
        unit: String?
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(title.localized())
                    .font(.system(size: 11))
            }
            .foregroundStyle(AppColor.textTertiary)

            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text(value)
                    .font(.system(size: 17, weight: .semibold, design: .monospaced))
                    .foregroundStyle(AppColor.textPrimary)
                    .lineLimit(1)
                if let unit {
                    Text(unit)
                        .font(.system(size: 11))
                        .foregroundStyle(AppColor.textTertiary)
                        .padding(.leading, 3)
                }
            }
            .padding(.top, 3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(alignment: .top) {
            AppColor.bgTertiary
        }
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(AppColor.borderSubtle, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .frame(minWidth: 120)
    }

    // MARK: - 派生数据

    private var charCount: Int {
        PlayerTextMetrics.charCount(of: audio.text)
    }
}
