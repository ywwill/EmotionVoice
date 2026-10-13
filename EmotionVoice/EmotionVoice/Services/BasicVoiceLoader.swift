//
//  BasicVoiceLoader.swift
//  EmotionVoice
//
//  Created by young on 2026/8/9.
//

import Foundation

/// 基础音色模板加载器
/// 从 bundle 资源 basic_voices.json 加载全部音色（含旗舰）
final class BasicVoiceLoader {

    static let shared = BasicVoiceLoader()

    private(set) var templates: [BasicVoiceTemplate] = []
    private var isLoaded = false

    /// 不再预加载：单例构造时不读 JSON，只有显式调用 loadFromBundle() 才读。
    /// 这样 DatabaseManager 在"无需同步"的快速路径里不碰 shared，就能彻底跳过文件读取。
    private init() {}

    /// 加载 JSON（懒加载，重复调用安全）
    func loadFromBundle() {
        guard !isLoaded else { return }

        guard let url = Bundle.main.url(forResource: "basic_voices", withExtension: "json") else {
            Log(message: "BasicVoiceLoader: basic_voices.json not found in bundle")
            isLoaded = true
            return
        }

        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            let file = try decoder.decode(VoiceCatalogFile.self, from: data)
            templates = file.voices
            isLoaded = true
            let premium = templates.filter { $0.tier == .premium }.count
            Log(message: "BasicVoiceLoader: loaded \(templates.count) voice templates (v\(file.version), premium \(premium))")
        } catch {
            Log(message: "BasicVoiceLoader: decode error: \(error)")
            isLoaded = true
        }
    }

    /// 旗舰音色模板
    var premiumTemplates: [BasicVoiceTemplate] {
        templates.filter { $0.tier == .premium }
    }

    /// 按 key 查找模板
    func template(forKey key: String) -> BasicVoiceTemplate? {
        templates.first { $0.key == key }
    }
}
