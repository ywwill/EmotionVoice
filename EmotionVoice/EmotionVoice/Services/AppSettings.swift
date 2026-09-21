//
//  AppSettings.swift
//  EmotionVoice
//
//  应用全局配置
//

import Foundation

/// 应用全局设置
struct AppSettings {

    /// 获取当前设备的区域代码（苹果地区代码，如 CN, US, JP 等）
    static func getCurrentRegionCode() -> String {
        let locale = Locale.current
        let regionCode = locale.region?.identifier ?? "US"
        return regionCode.uppercased()  // 确保大写
    }
}
