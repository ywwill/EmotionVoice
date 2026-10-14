//
//  PlayerTextMetrics.swift
//  EmotionVoice
//
//  播放面板共用的文案/时间格式化，避免每个子视图各写一份
//

import Foundation
import NaturalLanguage

enum PlayerTextMetrics {

    // MARK: - 文本统计

    /// 字符数
    static func charCount(of text: String) -> Int {
        text.count
    }

    /// 语句数
    ///
    /// 用 `NLTokenizer(.sentence)` 而不是按标点计数：系统分词器能正确处理
    /// 中英混排、省略号、引号内标点等情况，计数和用户在界面上看到的句子一致。
    static func sentenceCount(of text: String) -> Int {
        guard !text.isEmpty else { return 1 }
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var count = 0
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { _, _ in
            count += 1
            return true
        }
        return max(1, count)
    }

    // MARK: - 时间

    /// "02:17"（分钟补零，与设计稿一致）
    static func formatTime(_ seconds: Double) -> String {
        guard seconds.isFinite && !seconds.isNaN else { return "00:00" }
        let total = max(0, Int(seconds))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }

    /// 倍速 "1x" / "1.25x" / "1.5x"
    ///
    /// 优先复用 `AudioPreviewPlayer.playbackRateOptions` 里的标签，让倍速按钮、
    /// 菜单项、状态栏三处显示完全一致。
    ///
    /// 不要改用 `%.2g`：它是「保留 2 位有效数字」，会把 1.25 截成 "1.2"。
    /// 兜底用 `%g`（默认 6 位有效数字 + 去掉尾随 0），既不会截断，
    /// 也能把 1.0 / 2.0 显示成 "1x" / "2x"。
    static func formatRate(_ rate: Float) -> String {
        if let label = AudioPreviewPlayer.playbackRateOptions.first(where: { $0.rate == rate })?.label {
            return label
        }
        return String(format: "%gx", rate)
    }
}
