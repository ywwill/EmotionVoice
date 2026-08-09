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

    /// 项目
    let projects = Table("projects")
    /// 音频条目
    let audioItems = Table("audio_items")
    /// 音色（收藏）
    let voices = Table("voices")
    /// 交易记录
    let transactions = Table("transactions")
    /// 统计
    let monthlyStats = Table("monthly_stats")

    // MARK: - 项目字段
    let projectId = SQLite.Expression<Int64>("id")
    let projectName = SQLite.Expression<String>("name")
    let projectFolder = SQLite.Expression<String?>("folder")
    let projectCreatedAt = SQLite.Expression<Date>("created_at")
    let projectUpdatedAt = SQLite.Expression<Date>("updated_at")

    // MARK: - 音频条目字段
    let audioId = SQLite.Expression<Int64>("id")
    let audioProjectId = SQLite.Expression<Int64>("project_id")
    let audioTitle = SQLite.Expression<String>("title")
    let audioText = SQLite.Expression<String>("text")
    let audioVoice = SQLite.Expression<String>("voice")
    let audioFormat = SQLite.Expression<String>("format")
    let audioSampleRate = SQLite.Expression<Int>("sample_rate")
    let audioDuration = SQLite.Expression<Double>("duration")
    let audioFilePath = SQLite.Expression<String?>("file_path")
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

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory,
                                                   in: .userDomainMask).first!
        let dbFolder = appSupport.appendingPathComponent("EmotionVoice", isDirectory: true)
        if !FileManager.default.fileExists(atPath: dbFolder.path) {
            try? FileManager.default.createDirectory(at: dbFolder,
                                                     withIntermediateDirectories: true)
        }
        let dbPath = dbFolder.appendingPathComponent("emotionvoice.sqlite3").path

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
        try db.run(projects.create(ifNotExists: true) { t in
            t.column(projectId, primaryKey: .autoincrement)
            t.column(projectName)
            t.column(projectFolder)
            t.column(projectCreatedAt)
            t.column(projectUpdatedAt)
        })

        try db.run(audioItems.create(ifNotExists: true) { t in
            t.column(audioId, primaryKey: .autoincrement)
            t.column(audioProjectId)
            t.column(audioTitle)
            t.column(audioText)
            t.column(audioVoice)
            t.column(audioFormat)
            t.column(audioSampleRate)
            t.column(audioDuration, defaultValue: 0.0)
            t.column(audioFilePath)
            t.column(audioPointsCost, defaultValue: 0)
            t.column(audioStatus)
            t.column(audioCreatedAt)
            t.foreignKey(audioProjectId, references: projects, projectId, delete: .cascade)
        })

        try db.run(voices.create(ifNotExists: true) { t in
            t.column(voiceKey, primaryKey: true)
            t.column(voiceName)
            t.column(voiceDesc)
            t.column(voiceAvatar)
            t.column(voiceCategory)
            t.column(voiceIsFavorite, defaultValue: false)
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

    // MARK: - 种子数据

    /// 旗舰音色：始终保留，不被 JSON 覆盖
    private let premiumVoices: [(String, String, String, String, String)] = [
        ("longanlingxin", "龙安灵心", "知心温暖·25岁女", "灵", "premium"),
        ("longanlufeng", "龙安鲁风", "明亮开朗·25岁男", "鲁", "premium"),
    ]

    private func seedIfNeeded() throws {
        // 1. 确保 2 个旗舰音色始终存在（幂等）
        try ensurePremiumVoices()

        // 2. 如果 voices 表数量过少（首次或老用户），从 JSON 基础音色种子数据补充
        let totalCount = try db.scalar(voices.count)
        if totalCount < 100 {
            // 先清理旧的非旗舰音色（老 demo 种子数据）
            try purgeLegacyNonPremiumVoices()
            // 再批量插入 JSON 模板
            try seedBasicVoicesFromTemplate()
        }

        // 3. 默认收藏：第一个旗舰音色
        try db.run(voices.filter(voiceKey == "longanlingxin").update(voiceIsFavorite <- true))
    }

    /// 清理旧的非旗舰种子音色（仅删除以 'long' 开头的 demo key，避免误删真实数据）
    private func purgeLegacyNonPremiumVoices() throws {
        let premiumKeys = Set(premiumVoices.map { $0.0 })
        // 取出全部非 premium 音色
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
            print("DatabaseManager: purged \(toDelete.count) legacy non-premium voices")
        }
    }

    /// 旗舰音色幂等插入（已存在则跳过）
    private func ensurePremiumVoices() throws {
        for v in premiumVoices {
            let exists = try db.scalar(
                voices.filter(voiceKey == v.0).count
            )
            if exists == 0 {
                try db.run(voices.insert(or: .ignore,
                    voiceKey <- v.0,
                    voiceName <- v.1,
                    voiceDesc <- v.2,
                    voiceAvatar <- v.3,
                    voiceCategory <- v.4,
                    voiceIsFavorite <- false
                ))
            }
        }
    }

    /// 从基础音色 JSON 模板批量插入数据库
    private func seedBasicVoicesFromTemplate() throws {
        // 触发懒加载
        BasicVoiceLoader.shared.loadFromBundle()
        let templates = BasicVoiceLoader.shared.templates

        guard !templates.isEmpty else {
            print("DatabaseManager: no basic voice templates available, skipping seed")
            return
        }

        // 开启事务加速批量插入
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
                    voiceIsFavorite <- false
                ))
            }
        }
        print("DatabaseManager: seeded \(templates.count) basic voice templates")
    }
}