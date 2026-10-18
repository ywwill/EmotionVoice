//
//  RegionConfig.swift
//  EmotionVoice
//
//  区域配置管理 - 根据用户区域自动选择中国或国际节点
//
//  ⚠️ 这里只保留「区域判断」。上游的 WebSocket 地址、API Key、WorkspaceId
//  已经全部移到 Supabase Edge Function 的 secrets 里（supabase/functions/bailian-tts），
//  客户端只把区域代号（CN / INTL）作为 query 参数传给边缘函数。
//

import Foundation

/// 区域配置
struct RegionConfig {
    /// 传给边缘函数的区域代号
    let edgeRegionCode: String
}

/// 区域配置管理器
class RegionManager {

    static let shared = RegionManager()

    private init() {}

    // MARK: - 配置

    /// 中国区域配置（北京）
    private static let chinaConfig = RegionConfig(edgeRegionCode: "CN")

    /// 国际区域配置（新加坡）
    private static let internationalConfig = RegionConfig(edgeRegionCode: "INTL")

    // MARK: - 区域判断

    /// 获取当前区域代码
    static func getCurrentRegionCode() -> String {
        let locale = Locale.current
        let regionCode = locale.region?.identifier ?? "US"
        return regionCode.uppercased()
    }

    /// 判断是否为中国区域（不区分大小写）
    static func isChinaRegion(_ regionCode: String) -> Bool {
        return regionCode.uppercased() == "CN"
    }

    /// 判断是否为中国区域（使用当前系统区域）
    static var isCurrentRegionChina: Bool {
        return isChinaRegion(getCurrentRegionCode())
    }

    // MARK: - 获取配置

    /// 根据当前区域获取配置
    var currentConfig: RegionConfig {
        return Self.isCurrentRegionChina ? Self.chinaConfig : Self.internationalConfig
    }

    /// 传给 TTS 边缘函数的区域代号（CN / INTL）
    var edgeRegionCode: String {
        return currentConfig.edgeRegionCode
    }

    /// 强制使用指定区域配置（用于测试或用户手动选择）
    func config(for regionCode: String) -> RegionConfig {
        return Self.isChinaRegion(regionCode) ? Self.chinaConfig : Self.internationalConfig
    }
}
