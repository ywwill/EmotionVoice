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

    /// 倍速 "1×" / "1.5×"
    static func formatRate(_ rate: Float) -> String {
        String(format: "%.2g×", rate)
    }
}
