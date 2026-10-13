//
//  AudioPlayerDetailView.swift
//  EmotionVoice
//
//  播放详情面板：只负责版面编排，各区块拆到独立文件
//    - PlayerMetaStrip        元信息卡
//    - PlayerWaveformView     波形进度 + 擦洗
//    - PlayerTransportView    走带控制
//    - PlayerUtilityView      倍速 / 剩余时间 / 从头播放
//    - PlayerTranscriptView   音频文本
//    - PlaybackStatusBar      底部状态栏 + 快捷键提示
//    - PlaybackKeyboardShortcuts  快捷键事件监听
//  视觉对齐 UI/audio-player.html
//
//  性能约定（重要）：
//  - 这里**不要用 @ObservedObject 持有播放器**。播放时进度以 10Hz 刷新，
//    父视图一旦订阅，整页（元信息卡、几百字原文区、外层滚动布局）都会被拖着重算，
//    这是 CPU 打满的直接原因之一。
//  - 播放器用 `let` 传进来，订阅下沉到真正需要进度/播放态的子视图。
//  - 音色名等派生数据一次性解析后缓存进 @State，不在 body 里查库。
//

import SwiftUI

struct AudioPlayerDetailView: View {

    let audio: AudioItem
    /// 刻意不做观察，见文件头说明
    let player: AudioPreviewPlayer

    @State private var voiceName: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                PlayerMetaStrip(audio: audio, voiceName: voiceName)
                    .padding(.bottom, 22)

                PlayerWaveformView(player: player)

                PlayerTransportView(player: player, audio: audio)
                    .padding(.top, 12)

                PlayerUtilityView(player: player)
                    .padding(.top, 20)

                PlayerTranscriptView(audio: audio)
                    .padding(.top, 24)
            }
            .padding(.horizontal, 22)
            .padding(.top, 26)
            .padding(.bottom, 30)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // 音色名只在音频切换时解析一次；旧实现每次 body 求值都跑一次全表查询 + 排序
        .task(id: audio.id) {
            voiceName = VoiceService.shared.displayName(forKey: audio.voice)
        }
    }
}
