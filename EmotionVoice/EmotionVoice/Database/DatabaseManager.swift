//
//  DatabaseManager.swift
//  EmotionVoice
//
//  Created by young on 2026/8/8.
//

import Foundation
import SQLite
import CryptoKit

/// SQLite 数据库管理器
/// 使用 SQLite.swift 提供的类型安全 DSL
final class DatabaseManager {

    static let shared = DatabaseManager()

    let db: Connection

    // MARK: - 数据表

    /// 音频条目（每个音频就是一个独立的"项目"）
    let audioItems = Table("audio_items")
    /// 音色（收藏）
    let voices = Table("voices")
    /// 交易记录
    let transactions = Table("transactions")
    /// 统计
    let monthlyStats = Table("monthly_stats")

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
    let audioPointsCost = SQLite.Expression<Int>("points_cost")
    let audioStatus = SQLite.Expression<String>("status")
    let audioCreatedAt = SQLite.Expression<Date>("created_at")

    // MARK: - 音色字段
    let voiceKey = SQLite.Expression<String>("key")
    let voiceName = SQLite.Expression<String>("name")
    let voiceDesc = SQLite.Expression<String>("desc")
    let voiceAvatar = SQLite.Expression<String>("avatar")
    let voiceCategory = SQLite.Expression<String>("category")
    let voiceIsFavorite = SQLite.Expression<Bool>("is_favorite")
    /// 适用场景
    let voiceScene = SQLite.Expression<String?>("scene")
    /// 年龄
    let voiceAge = SQLite.Expression<Int?>("age")
    /// 性别
    let voiceGender = SQLite.Expression<String?>("gender")
    /// 预览音频文件名（如 longanlingxin.m4a），可空
    let voiceAudio = SQLite.Expression<String?>("audio")

    // MARK: - 交易记录字段
    let txId = SQLite.Expression<Int64>("id")
    let txType = SQLite.Expression<String>("type")
    let txTitle = SQLite.Expression<String>("title")
    let txAmount = SQLite.Expression<Int>("amount")
    let txMeta = SQLite.Expression<String?>("meta")
    let txCreatedAt = SQLite.Expression<Date>("created_at")

    // MARK: - 月度统计字段
    let statMonth = SQLite.Expression<String>("month")
    let statPointsUsed = SQLite.Expression<Int>("points_used")
    let statAudioCount = SQLite.Expression<Int>("audio_count")
    let statVoiceCount = SQLite.Expression<Int>("voice_count")

    // MARK: - JSON 同步指纹
    private let fingerprintKey = "EmotionVoice.basicVoicesFingerprint"
    private let fingerprintVersionKey = "EmotionVoice.basicVoicesFingerprintVersion"
    private let currentFingerprintVersion = 4   // 增加此值可强制全量重新同步

    private     init() {
        // 直接放在用户的 Documents 目录下，方便开发者调试
        let docs = FileManager.default.urls(for: .documentDirectory,
                                            in: .userDomainMask).first!
        let dbPath = docs.appendingPathComponent("emotionvoice.sqlite3").path
        Log(message: "数据库: \(dbPath)")

        do {
            db = try Connection(dbPath)
            try createTables()
            try seedIfNeeded()
        } catch {
            fatalError("数据库初始化失败: \(error)")
        }
    }

    // MARK: - 表创建

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
            t.column(voiceKey, primaryKey: true)
            t.column(voiceName)
            t.column(voiceDesc)
            t.column(voiceAvatar)
            t.column(voiceCategory)
            t.column(voiceIsFavorite, defaultValue: false)
            t.column(voiceScene)
            t.column(voiceAge)
            t.column(voiceGender)
            t.column(voiceAudio)
        })

        try db.run(transactions.create(ifNotExists: true) { t in
            t.column(txId, primaryKey: .autoincrement)
            t.column(txType)
            t.column(txTitle)
            t.column(txAmount)
            t.column(txMeta)
            t.column(txCreatedAt)
        })

        try db.run(monthlyStats.create(ifNotExists: true) { t in
            t.column(statMonth, primaryKey: true)
            t.column(statPointsUsed, defaultValue: 0)
            t.column(statAudioCount, defaultValue: 0)
            t.column(statVoiceCount, defaultValue: 0)
        })
    }

    /// 种子数据

    /// 旗舰音色：内置到代码中（不依赖 JSON），保证可被播放
    private struct PremiumVoice {
        let key: String
        let name: String
        let desc: String
        let avatar: String
        let audio: String
        let scene: String
        let age: Int
        let gender: String
    }

    private let premiumVoices: [PremiumVoice] = [
        PremiumVoice(
            key: "longanlingxin", name: "龙安灵心",
            desc: "知心温暖·25岁女", avatar: "灵",
            audio: "longanlingxin.m4a",
            scene: "情感陪伴", age: 25, gender: "女"
        ),
        PremiumVoice(
            key: "longanlufeng", name: "龙安鲁风",
            desc: "明亮开朗·25岁男", avatar: "鲁",
            audio: "longanlufeng.m4a",
            scene: "知识分享", age: 25, gender: "男"
        ),
    ]

    /// 启动入口：确保旗舰存在 + 检测 JSON 是否变更，如变更则重新同步基础音色
    private func seedIfNeeded() throws {
        // 1. 旗舰音色幂等插入
        try ensurePremiumVoices()

        // 2. 检测 JSON 是否变更，决定是否重新同步基础音色
        try syncBasicVoicesIfNeeded()

        // 3. 默认收藏：两个旗舰音色
        for v in premiumVoices {
            try db.run(voices.filter(voiceKey == v.key).update(voiceIsFavorite <- true))
        }
    }

    /// 计算当前 JSON 的指纹（基于排序后的 keys）
    private func computeFingerprint() -> String {
        // 触发懒加载
        BasicVoiceLoader.shared.loadFromBundle()
        let templates = BasicVoiceLoader.shared.templates
        let joined = templates
            .map { "\($0.key):\($0.category.rawValue):\($0.scene):\($0.age):\($0.gender)" }
            .sorted()
            .joined(separator: "|")
        let data = Data(joined.utf8)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    /// 已存指纹
    private var storedFingerprint: String {
        UserDefaults.standard.string(forKey: fingerprintKey) ?? ""
    }
    private var storedFingerprintVersion: Int {
        UserDefaults.standard.integer(forKey: fingerprintVersionKey)
    }
    private func setStoredFingerprint(_ value: String) {
        UserDefaults.standard.set(value, forKey: fingerprintKey)
        UserDefaults.standard.set(currentFingerprintVersion, forKey: fingerprintVersionKey)
    }

    /// 同步基础音色：JSON 指纹与本地不一致时重置非旗舰音色并重新插入
    private func syncBasicVoicesIfNeeded() throws {
        let current = computeFingerprint()
        let stored = storedFingerprint
        let version = storedFingerprintVersion

        // 老库：没有任何 JSON 来源数据，先把老 demo 数据清掉，按当前 JSON 全量灌入
        let totalCount = try db.scalar(voices.count)
        if totalCount < 100 {
            try purgeLegacyNonPremiumVoices()
            try seedBasicVoicesFromTemplate()
            setStoredFingerprint(current)
            Log(message: "DatabaseManager: initial seed done, fingerprint=\(current.prefix(12))…")
            return
        }

        // 已存在基础音色：仅在 JSON 指纹发生变化 / 版本号变化时重新同步
        if version != currentFingerprintVersion || stored != current {
            try resyncBasicVoicesFromTemplate()
            setStoredFingerprint(current)
            Log(message: "DatabaseManager: JSON changed, resynced non-premium voices, fingerprint=\(current.prefix(12))…")
        }
    }

    /// 清理旧的非旗舰种子音色（仅在首次发现旧数据时调用一次）
    private func purgeLegacyNonPremiumVoices() throws {
        let premiumKeys = Set(premiumVoices.map { $0.key })
        let nonPremium = try db.prepare(voices.filter(voiceCategory != "premium"))
        var toDelete: [String] = []
        for row in nonPremium {
            let key = row[voiceKey]
            if !premiumKeys.contains(key) {
                toDelete.append(key)
            }
        }
        for key in toDelete {
            try db.run(voices.filter(voiceKey == key).delete())
        }
        if !toDelete.isEmpty {
            Log(message: "DatabaseManager: purged \(toDelete.count) legacy non-premium voices")
        }
    }

    /// 旗舰音色幂等插入（已存在则更新元数据，保留收藏状态）
    private func ensurePremiumVoices() throws {
        for v in premiumVoices {
            // 取当前收藏状态（不存在则视为 false）
            let existingFav = (try? db.pluck(voices.filter(voiceKey == v.key)))?[voiceIsFavorite] ?? false
            // 先尝试插入（如果不存在）
            try db.run(voices.insert(or: .ignore,
                voiceKey <- v.key,
                voiceName <- v.name,
                voiceDesc <- v.desc,
                voiceAvatar <- v.avatar,
                voiceCategory <- "premium",
                voiceIsFavorite <- existingFav,
                voiceScene <- v.scene,
                voiceAge <- v.age,
                voiceGender <- v.gender,
                voiceAudio <- v.audio
            ))
            // 更新元数据，确保与代码一致；不覆盖收藏
            try db.run(voices.filter(voiceKey == v.key).update(
                voiceName <- v.name,
                voiceDesc <- v.desc,
                voiceAvatar <- v.avatar,
                voiceCategory <- "premium",
                voiceScene <- v.scene,
                voiceAge <- v.age,
                voiceGender <- v.gender,
                voiceAudio <- v.audio
            ))
        }
    }

    /// 首次批量插入基础音色（无重复检查）
    private func seedBasicVoicesFromTemplate() throws {
        BasicVoiceLoader.shared.loadFromBundle()
        let templates = BasicVoiceLoader.shared.templates
        guard !templates.isEmpty else {
            Log(message: "DatabaseManager: no basic voice templates available, skipping seed")
            return
        }
        try db.transaction {
            for t in templates {
                let cat: String
                switch t.category {
                case .premium: cat = "premium"
                case .basic:   cat = "basic"
                case .child:   cat = "child"
                case .role:    cat = "role"
                }
                try db.run(voices.insert(or: .ignore,
                    voiceKey <- t.key,
                    voiceName <- t.name,
                    voiceDesc <- t.displayDesc,
                    voiceAvatar <- t.avatar,
                    voiceCategory <- cat,
                    voiceIsFavorite <- false,
                    voiceScene <- t.scene,
                    voiceAge <- Int(t.age),
                    voiceGender <- t.gender,
                    voiceAudio <- t.audio
                ))
            }
        }
        Log(message: "DatabaseManager: seeded \(templates.count) basic voice templates")
    }

    /// JSON 变更时重置非旗舰音色（保留收藏、删除多余的、插入新增的）
    private func resyncBasicVoicesFromTemplate() throws {
        BasicVoiceLoader.shared.loadFromBundle()
        let templates = BasicVoiceLoader.shared.templates
        guard !templates.isEmpty else {
            Log(message: "DatabaseManager: no templates; skip resync")
            return
        }

        let premiumKeys = Set(premiumVoices.map { $0.key })
        let newKeys = Set(templates.map { $0.key })

        try db.transaction {
            // 1) 先采集所有非旗舰音色的收藏状态，以便稍后还原
            var savedFavorites: [String: Bool] = [:]
            let nonPremiumRows = try db.prepare(voices.filter(voiceCategory != "premium"))
            for row in nonPremiumRows {
                savedFavorites[row[voiceKey]] = row[voiceIsFavorite]
            }

            // 2) 删除 JSON 中已不存在的非旗舰条目（保留收藏也无意义）
            var toDelete: [String] = []
            for (key, _) in savedFavorites where !newKeys.contains(key) && !premiumKeys.contains(key) {
                toDelete.append(key)
            }
            for key in toDelete {
                try db.run(voices.filter(voiceKey == key).delete())
            }
            if !toDelete.isEmpty {
                Log(message: "DatabaseManager: resync removed \(toDelete.count) obsolete voices")
            }

            // 3) 逐条 upsert：以 JSON 为准更新描述/分类/场景/年龄/性别
            for t in templates {
                let cat: String
                switch t.category {
                case .premium: cat = "premium"
                case .basic:   cat = "basic"
                case .child:   cat = "child"
                case .role:    cat = "role"
                }
                let ageInt = Int(t.age)
                let existing = try db.pluck(voices.filter(voiceKey == t.key))
                if existing != nil {
                    try db.run(voices.filter(voiceKey == t.key).update(
                        voiceName <- t.name,
                        voiceDesc <- t.displayDesc,
                        voiceAvatar <- t.avatar,
                        voiceCategory <- cat,
                        voiceScene <- t.scene,
                        voiceAge <- ageInt,
                        voiceGender <- t.gender,
                        voiceAudio <- t.audio,
                        voiceIsFavorite <- (savedFavorites[t.key] ?? false)
                    ))
                } else {
                    try db.run(voices.insert(
                        voiceKey <- t.key,
                        voiceName <- t.name,
                        voiceDesc <- t.displayDesc,
                        voiceAvatar <- t.avatar,
                        voiceCategory <- cat,
                        voiceIsFavorite <- false,
                        voiceScene <- t.scene,
                        voiceAge <- ageInt,
                        voiceGender <- t.gender,
                        voiceAudio <- t.audio
                    ))
                }
            }

            // 4) 还原非旗舰音色的收藏状态
            for (key, fav) in savedFavorites where newKeys.contains(key) {
                try db.run(voices.filter(voiceKey == key).update(voiceIsFavorite <- fav))
            }

            // 5) 两个旗舰音色默认收藏
            for v in premiumVoices {
                try db.run(voices.filter(voiceKey == v.key).update(voiceIsFavorite <- true))
            }
        }
        Log(message: "DatabaseManager: resynced \(templates.count) basic voice templates")
    }
}
