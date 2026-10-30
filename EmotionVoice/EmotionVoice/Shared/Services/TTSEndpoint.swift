//
//  TTSEndpoint.swift
//  EmotionVoice
//
//  TTS 通道：走 Supabase Edge Function `bailian-tts`。
//
//  客户端不再持有任何百炼密钥 —— API Key / WorkspaceId / 模型协议
//  全部收在 Supabase 的 function secrets 里（见 supabase/functions/bailian-tts）。
//

import Foundation

/// 一次 TTS WebSocket 握手的地址与请求头
struct TTSEndpoint {

    let url: URL
    let headers: [String: String]

    /// 按当前区域构造端点
    ///
    /// 例：`wss://dpyyhbqqmegencxekkcr.supabase.co/functions/v1/bailian-tts?region=CN`
    static func current() throws -> TTSEndpoint {
        var components = URLComponents()
        components.scheme = "wss"
        components.host = "\(kSupabaseProjectRef).supabase.co"
        components.path = "/functions/v1/\(kTTSEdgeFunctionName)"
        components.queryItems = [
            URLQueryItem(name: "region", value: RegionManager.shared.edgeRegionCode)
        ]

        guard let url = components.url else { throw TTSError.invalidRequest }

        return TTSEndpoint(
            url: url,
            headers: [
                "Authorization": "Bearer \(kSupabasePublishableKey)",
                "apikey": kSupabasePublishableKey,
                // publishable key 是公开的，真正拦住滥用的是这个应用级 secret
                // （对应函数侧的 APP_SECRET）。原生客户端可以在握手阶段带自定义 header。
                "x-app-secret": kSupabaseAppSecret
            ]
        )
    }
}
