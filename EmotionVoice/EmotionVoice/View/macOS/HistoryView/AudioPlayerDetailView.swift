//
//  AudioPlayerDetailView.swift
//  EmotionVoice
//

import SwiftUI

struct AudioPlayerDetailView: View {

    let audio: AudioItem
    /// 刻意不做观察，见文件头说明
    let player: AudioPreviewPlayer

    var body: some View {
        // 波形 / 走带 / 工具 / 属性四块常驻，不参与滚动；
        // 只有原文卡片吃掉剩余高度，由它内部的 ScrollView 独立滚动。
        // 关键：外层不能有 ScrollView，否则内层拿不到确定高度会退化为按内容撑高。
        VStack(alignment: .leading, spacing: 0) {
            PlayerWaveformView(player: player)

            PlayerTransportView(player: player, audio: audio)
                .padding(.top, 12)

            PlayerUtilityView(player: player)
                .padding(.top, 20)

            PlayerMetaStrip(audio: audio)
                .padding(.top, 20)

            PlayerTranscriptView(audio: audio)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, 18)
        }
        .padding(.horizontal, 22)
        .padding(.top, 26)
        .padding(.bottom, 30)
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
