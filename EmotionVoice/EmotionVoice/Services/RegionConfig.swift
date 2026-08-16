//
//  RegionConfig.swift
//  EmotionVoice
//
//  区域配置管理 - 根据用户区域自动选择中国或国际服务器
//

import Foundation

/// 区域配置
struct RegionConfig {
    /// WebSocket URL 模板（需要替换 WorkspaceId）
    let wsUrlTemplate: String
    /// API Key
    let apiKey: String
    /// Workspace ID
    let workspaceId: String

    /// 获取完整的 WebSocket URL
    var wsUrl: String {
        return String(format: wsUrlTemplate, workspaceId)
    }
}

/// 区域配置管理器
final class RegionManager {

    static let shared = RegionManager()

    private init() {}

    // MARK: - 配置

    /// 中国区域配置（北京）
    private static let chinaConfig = RegionConfig(
        wsUrlTemplate: "wss://%@.cn-beijing.maas.aliyuncs.com/api-ws/v1/inference",
        apiKey: "sk-964c3945bd89460f976f6b8bf13442b7",
        workspaceId: "llm-quamnoopzri4mr6r"
    )

    /// 国际区域配置（新加坡）
    private static let internationalConfig = RegionConfig(
        wsUrlTemplate: "wss://%@.ap-southeast-1.maas.aliyuncs.com/api-ws/v1/inference",
        apiKey: "sk-557be4f42f724dd0848c08bc20f89c05",
        workspaceId: "llm-4z5f5e3xl478r32c"
    )

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

    /// 获取 WebSocket URL
    var wsUrl: String {
        return currentConfig.wsUrl
    }

    /// 获取 API Key
    var apiKey: String {
        return currentConfig.apiKey
    }

    /// 获取 Workspace ID
    var workspaceId: String {
        return currentConfig.workspaceId
    }

    /// 强制使用指定区域配置（用于测试或用户手动选择）
    func config(for regionCode: String) -> RegionConfig {
        return Self.isChinaRegion(regionCode) ? Self.chinaConfig : Self.internationalConfig
    }
}
