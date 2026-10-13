//
//  DatabaseManager.swift
//  EmotionVoice
//
//  Created by young on 2026/8/8.
//

import Foundation
import SQLite

/// SQLite 数据库管理器
/// 使用 SQLite.swift 提供的类型安全 DSL
final class DatabaseManager {

    static let shared = DatabaseManager()

    let db: Connection

    // MARK: - 数据表

    /// 音频条目（每个音频就是一个独立的"项目"）
    let audioItems = Table("audio_items")
    /// 音色（收藏状态 + JSON 同步下来的目录数据）
    let voices = Table("voices")
    /// 消耗记录
    let consumptionRecords = Table("consumption_records")
    /// 购买记录
    let purchaseRecords = Table("purchase_records")

    // MARK: - 音频条目字段

    let audioId = SQLite.Expression<Int64>("id")
    /// 文件名（含扩展名，例如 "2026-08-16_11-35-42.wav"）
    let audioFileName = SQLite.Expression<String>("file_name")
    let audioText = SQLite.Expression<String>("text")
    let audioVoice = SQLite.Expression<String>("voice")
    let audioFormat = SQLite.Expression<String>("format")
    let audioSampleRate = SQLite.Expression<Int>("sample_rate")
    let audioDuration = SQLite.Expression<Double>("duration")
    let audioDisplayName = SQLite.Expression<String?>("display_name")
    let audioPointsCost = SQLite.Expression<Double>("points_cost")
    let audioStatus = SQLite.Expression<String>("status")
    let audioCreatedAt = SQLite.Expression<Date>("created_at")

    // MARK: - 音色字段
    //
    // 只存语言无关的语义 code 与稳定 key；文案（名 / 特质）在读出后
    // 按 audio 文件名的 stem 从 VoiceCatalog.strings 取，库里不存任何文本。

    /// 便捷整数 id（旗舰 1/2，基础 3 起），同时作为主键
    let voiceIdx = SQLite.Expression<Int>("idx")
    /// voice 参数 key（如 longanlingxin / qwen-audio-3.0-tts-plus-longcanzhuyue），唯一
    let voiceKey = SQLite.Expression<String>("key")
    /// 层级：premium / basic
    let voiceTier = SQLite.Expression<String>("tier")
    let voiceIsFavorite = SQLite.Expression<Bool>("is_favorite")
    /// 场景 code：daily / companion / ...
    let voiceSceneKey = SQLite.Expression<String>("scene_key")
    /// 年龄
    let voiceAge = SQLite.Expression<Int>("age")
    /// 性别 code：female / male / unknown
    let voiceGenderCode = SQLite.Expression<String>("gender_code")
    /// 预览音频文件名（如 longanlingxin.m4a）
    let voiceAudio = SQLite.Expression<String>("audio")
    /// 语种 code：zh / en
    let voiceLangCode = SQLite.Expression<String>("lang_code")

    // MARK: - 消耗记录字段

    let consumeId = SQLite.Expression<Int64>("id")
    let consumeVoiceName = SQLite.Expression<String>("voice_name")
    let consumeVoiceKey = SQLite.Expression<String>("voice_key")
    let consumeAudioDuration = SQLite.Expression<Double>("audio_duration")
    let consumePoints = SQLite.Expression<Double>("points")
    let consumeCreatedAt = SQLite.Expression<Date>("created_at")

    // MARK: - 购买记录字段

    let purchaseId = SQLite.Expression<Int64>("id")
    let purchaseQuantity = SQLite.Expression<Int>("quantity")
    let purchaseCreatedAt = SQLite.Expression<Date>("created_at")

    // MARK: - 音色同步状态（UserDefaults）

    /// 期望音色行数。与版本号一起作为"是否需要读取 JSON"的快速判断依据，
    /// 二者都匹配时启动阶段完全跳过 basic_voices.json 的读取。
    private let voiceCountKey = "EmotionVoice.basicVoicesCount"
    private let fingerprintVersionKey = "EmotionVoice.basicVoicesFingerprintVersion"
    /// 手动版本号：改了 basic_voices.json（或音色处理逻辑）后必须 +1，
    /// 否则启动不会重新同步。不再依赖内容哈希自动检测，见 syncVoicesIfNeeded。
    private let currentFingerprintVersion = 6

    private init() {
        // 直接放在用户的 Documents 目录下，方便开发者调试
        let docs = FileManager.default.urls(for: .documentDirectory,
                                            in: .userDomainMask).first!
        let dbPath = docs.appendingPathComponent("emotionvoice.sqlite3").path
        Log(message: "数据库: \(dbPath)")

        do {
            db = try Connection(dbPath)
            try createTables()
            try syncVoicesIfNeeded()
        } catch {
            fatalError("数据库初始化失败: \(error)")
        }
    }

    // MARK: - 建表

    private func createTables() throws {
        try db.run(audioItems.create(ifNotExists: true) { t in
            t.column(audioId, primaryKey: .autoincrement)
            t.column(audioFileName)
            t.column(audioText)
            t.column(audioVoice)
            t.column(audioFormat)
            t.column(audioSampleRate)
            t.column(audioDuration, defaultValue: 0.0)
            t.column(audioDisplayName)
            t.column(audioPointsCost, defaultValue: 0)
            t.column(audioStatus)
            t.column(audioCreatedAt)
        })

        try db.run(voices.create(ifNotExists: true) { t in
            t.column(voiceIdx, primaryKey: true)
            t.column(voiceKey, unique: true)
            t.column(voiceTier, defaultValue: VoiceTier.basic.rawValue)
            t.column(voiceIsFavorite, defaultValue: false)
            t.column(voiceSceneKey, defaultValue: VoiceSceneCode.daily.rawValue)
            t.column(voiceAge, defaultValue: 0)
            t.column(voiceGenderCode, defaultValue: VoiceGenderCode.unknown.rawValue)
            t.column(voiceAudio, defaultValue: "")
            t.column(voiceLangCode, defaultValue: VoiceLangCode.zh.rawValue)
        })

        try db.run(consumptionRecords.create(ifNotExists: true) { t in
            t.column(consumeId, primaryKey: .autoincrement)
            t.column(consumeVoiceName)
            t.column(consumeVoiceKey)
            t.column(consumeAudioDuration, defaultValue: 0.0)
            t.column(consumePoints, defaultValue: 0)
            t.column(consumeCreatedAt)
        })

        try db.run(purchaseRecords.create(ifNotExists: true) { t in
            t.column(purchaseId, primaryKey: .autoincrement)
            t.column(purchaseQuantity, defaultValue: 0)
            t.column(purchaseCreatedAt)
        })
    }

    // MARK: - 音色同步（唯一入口）

    /// 启动入口：仅在「版本号提升」或「DB 行数对不上」时才读取 basic_voices.json 并重建。
    /// 版本号一致且行数一致 → 直接返回，全程不触碰 BasicVoiceLoader，零 JSON 读取。
    ///
    /// 旗舰音色不再硬编码在代码里，而是 basic_voices.json 中 tier = premium 的条目，
    /// 这样音色数据只有 JSON 一个来源。
    private func syncVoicesIfNeeded() throws {
        let rowCount = try db.scalar(voices.count)

        // 便宜的短路判断：只查 UserDefaults 和 DB 行数，不读 JSON
        let versionChanged = storedFingerprintVersion != currentFingerprintVersion
        let countMismatch = storedVoiceCount != rowCount
        guard versionChanged || countMismatch else {
            return
        }

        // 需要读 JSON 的情况：版本号提升 / DB 行数对不上（被清空或首次启动）
        BasicVoiceLoader.shared.loadFromBundle()
        let templates = BasicVoiceLoader.shared.templates
        guard !templates.isEmpty else {
            Log(message: "DatabaseManager: 无音色模板，跳过同步")
            return
        }

        try rebuildVoices(from: templates)
        setStoredSyncMeta(templates: templates)
        Log(message: "DatabaseManager: 重建 \(templates.count) 条音色完成（version \(currentFingerprintVersion)）")
    }

    // 说明：已移除原来的内容哈希（computeFingerprint）。版本号 + 期望行数已足够判断
    // 是否需要重建；代价是改了 JSON 内容必须同步把 currentFingerprintVersion +1，
    // 否则启动不会重新同步（生产环境无影响，bundle 内 JSON 随构建固定）。

    private var storedFingerprintVersion: Int {
        UserDefaults.standard.integer(forKey: fingerprintVersionKey)
    }

    private var storedVoiceCount: Int {
        UserDefaults.standard.integer(forKey: voiceCountKey)
    }

    private func setStoredSyncMeta(templates: [BasicVoiceTemplate]) {
        UserDefaults.standard.set(currentFingerprintVersion, forKey: fingerprintVersionKey)
        UserDefaults.standard.set(templates.count, forKey: voiceCountKey)
    }

    /// 以 JSON 为准重建音色表：清表后整批写入，仅保留收藏状态
    private func rebuildVoices(from templates: [BasicVoiceTemplate]) throws {
        let premiumKeys = Set(templates.filter { $0.tier == .premium }.map { $0.key })

        // 清表前先取出收藏状态
        var savedFavorites: [String: Bool] = [:]
        for row in try db.prepare(voices) {
            savedFavorites[row[voiceKey]] = row[voiceIsFavorite]
        }

        try db.transaction {
            try db.run(voices.delete())

            for t in templates {
                try db.run(voices.insert(
                    voiceIdx <- t.idx,
                    voiceKey <- t.key,
                    voiceTier <- t.tier.rawValue,
                    voiceSceneKey <- t.scene.rawValue,
                    voiceAge <- t.age,
                    voiceGenderCode <- t.gender.rawValue,
                    voiceAudio <- t.audio,
                    voiceLangCode <- t.lang.rawValue,
                    voiceIsFavorite <- (savedFavorites[t.key] ?? false)
                ))
            }

            // 旗舰音色默认收藏
            for key in premiumKeys {
                try db.run(voices.filter(voiceKey == key).update(voiceIsFavorite <- true))
            }
        }
    }
}
