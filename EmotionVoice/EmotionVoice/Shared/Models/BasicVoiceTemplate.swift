//
//  BasicVoiceTemplate.swift
//  EmotionVoice
//
//  Created by young on 2026/8/9.
//
//  对应 basic_voices.json（v4 schema）。
//  只含语言无关的语义数据与稳定 key，不含任何文案 —— 文案在 VoiceCatalog.strings 中按 stem 取。
//  stem = 从 key 去掉模型前缀 qwen-audio-3.0-tts-plus- 得到（与 audio 文件名去扩展名一致）。
//

import Foundation

/// JSON 文件根节点
struct VoiceCatalogFile: Decodable {
    let version: Int
    let voices: [BasicVoiceTemplate]
}

/// 音色模板（JSON 中的一条）
struct BasicVoiceTemplate: Hashable {

    // MARK: - 逻辑字段（语言无关）

    /// 便捷整数 id（旗舰 1/2，基础 3 起）；同时作为数据库主键
    let idx: Int
    /// voice 参数 key（基础音色带模型前缀，旗舰为裸 key）
    let key: String
    /// 层级：旗舰 / 基础
    let tier: VoiceTier
    /// 语种
    let lang: VoiceLangCode
    /// 性别
    let gender: VoiceGenderCode
    /// 年龄
    let age: Int
    /// 适用场景
    let scene: VoiceSceneCode
    /// 预览音频文件名
    let audio: String

    // MARK: - 本地化 key

    /// 短标识：剥掉模型前缀（与 audio 文件名去扩展名一致），用于 VoiceCatalog.strings 取文案
    var stem: String {
        let prefix = "qwen-audio-3.0-tts-plus-"
        return key.hasPrefix(prefix) ? String(key.dropFirst(prefix.count)) : key
    }
}

// MARK: - Decodable

extension BasicVoiceTemplate: Decodable {

    private enum CodingKeys: String, CodingKey {
        case idx, key, tier, lang, gender, age, scene, audio
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        key = try c.decode(String.self, forKey: .key)
        audio = try c.decode(String.self, forKey: .audio)

        // 数值字段容错：缺失时给安全默认值，避免整表解析失败
        idx = (try? c.decode(Int.self, forKey: .idx)) ?? 0
        age = (try? c.decode(Int.self, forKey: .age)) ?? 0

        // 枚举字段一律走容错构造：未知 code 落到安全默认值
        tier = VoiceTier(code: (try? c.decode(String.self, forKey: .tier)) ?? "basic")
        lang = VoiceLangCode(code: (try? c.decode(String.self, forKey: .lang)) ?? "zh")
        gender = VoiceGenderCode(code: (try? c.decode(String.self, forKey: .gender)) ?? "unknown")
        scene = VoiceSceneCode(code: (try? c.decode(String.self, forKey: .scene)) ?? "daily")
    }
}
