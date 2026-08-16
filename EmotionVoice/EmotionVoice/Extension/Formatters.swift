//
//  Formatters.swift
//  EmotionVoice
//
//  Created by young on 2026/8/8.
//

import Foundation

extension Int {
    /// 千分位格式化（如 1280 -> "1,280"）
    var separatedThousands: String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.groupingSeparator = ","
        return f.string(from: NSNumber(value: self)) ?? "\(self)"
    }
}

extension Double {
    /// 时长格式化（秒 -> "00:32" 或 "01:30:45"）
    var durationString: String {
        let total = Int(self)
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}

extension Date {
    /// 显示为 "YYYY-MM-DD"
    var shortDateString: String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: self)
    }

    /// 紧凑时间戳 "yyyyMMddHHmmss"（用于生成项目命名）
    var timestampString: String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMddHHmmss"
        return f.string(from: self)
    }

    /// 相对时间（如 "2 天前"）
    var relativeString: String {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "zh_CN")
        f.unitsStyle = .short
        return f.localizedString(for: self, relativeTo: Date())
    }
}