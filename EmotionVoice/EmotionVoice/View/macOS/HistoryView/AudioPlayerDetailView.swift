//
//  AudioPlayerDetailView.swift
//  EmotionVoice
//

import SwiftUI

struct AudioPlayerDetailView: View {

    let audio: AudioItem
    /// 刻意不做观察，见文件头说明
    let player: AudioPreviewPlayer

    /// 字级时间轴只在这里读一次（AudioTimelineStore 有 NSCache），
    /// 再分发给波形刻度 / 阅读区 / 状态栏三处，避免各自读盘。
    @State private var timeline: AudioTimeline?

    var body: some View {
        // 波形 / 走带 / 工具 / 属性四块常驻，不参与滚动；
        // 只有原文卡片吃掉剩余高度，由它内部的 ScrollView 独立滚动。
        // 关键：外层不能有 ScrollView，否则内层拿不到确定高度会退化为按内容撑高。
        //
        // ⚠️ 这里每个 `.padding(.top)` 都是「从原文卡片身上抢的高度」：
        //    上面四块的固定高度 + 间隙一共 300pt 左右，剩下的才归正文。
        //    调大任何一个之前先想清楚正文还够不够读。
        VStack(alignment: .leading, spacing: 0) {
            PlayerWaveformView(player: player, timeline: timeline)

            PlayerTransportView(player: player, audio: audio)
                .padding(.top, 10)

            PlayerUtilityView(player: player)
                .padding(.top, 10)

            // 属性行不是卡片，是原文卡片的「副标题」——所以贴紧下方，离上方留空
            PlayerMetaStrip(audio: audio)
                .padding(.top, 14)

            PlayerTranscriptView(audio: audio, player: player, timeline: timeline)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .padding(.top, 10)
        }
        .padding(.horizontal, 22)
        .padding(.top, 20)
        .padding(.bottom, 22)
        // 不再锁 760 宽：只靠左右 padding 留白，剩余宽度全部交给内容
        // （锁宽时窗口一拉大，正文两边会各空出一大块，波形也被一起挤窄）
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: audio.id) {
            timeline = audio.timeline
        }
    }
}
