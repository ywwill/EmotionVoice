//
//  BasicVoiceLoader.swift
//  EmotionVoice
//
//  Created by young on 2026/8/9.
//

import Foundation

/// 基础音色模板加载器
/// 从 bundle 资源 basic_voices.json 加载 597 条基础音色
final class BasicVoiceLoader {

    static let shared = BasicVoiceLoader()

    private(set) var templates: [BasicVoiceTemplate] = []
    private var isLoaded = false

    private init() {
        loadFromBundle()
    }

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
            templates = try decoder.decode([BasicVoiceTemplate].self, from: data)
            isLoaded = true
            Log(message: "BasicVoiceLoader: loaded \(templates.count) basic voice templates")
        } catch {
            Log(message: "BasicVoiceLoader: decode error: \(error)")
            isLoaded = true
        }
    }

    /// 按分类获取模板
    func templates(for category: VoiceCategory) -> [BasicVoiceTemplate] {
        templates.filter { $0.category == category }
    }

    /// 按 key 查找模板
    func template(forKey key: String) -> BasicVoiceTemplate? {
        templates.first { $0.key == key }
    }
}
