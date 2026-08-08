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

    private func seedIfNeeded() throws {
        let count = try db.scalar(voices.count)
        guard count == 0 else { return }

        let seedVoices: [(String, String, String, String, String)] = [
            ("longanlingxin", "龙安灵心", "知心温暖·25岁女", "灵", "premium"),
            ("longanlufeng", "龙安鲁风", "明亮开朗·25岁男", "鲁", "premium"),
            ("longanhuan_v3.6", "龙安欢", "通用女声·25岁", "欢", "basic"),
            ("longanfengyue", "龙安风悦", "自然亲切·30岁女", "风", "basic"),
            ("longanyuanfei", "龙安元妃", "高傲妃子·30岁女", "元", "basic"),
            ("longanlingxi", "龙安灵希", "可爱甜美·25岁女", "希", "basic"),
            ("longanxiaoxin", "龙安小昕", "亲切活泼·22岁女", "昕", "basic"),
            ("longjielidou_v3.6", "龙杰力豆", "天真男童·5岁", "力", "child"),
            ("longpaopao_v3.6", "龙泡泡", "软糯可爱·5岁女", "泡", "child"),
            ("longhuohuo_v3.6", "龙火火", "顽皮少年·8岁男", "火", "role"),
            ("longchuanshu_v3.6", "龙川叔", "川普大叔·40岁男", "川", "role"),
        ]

        for v in seedVoices {
            try db.run(voices.insert(or: .ignore,
                voiceKey <- v.0,
                voiceName <- v.1,
                voiceDesc <- v.2,
                voiceAvatar <- v.3,
                voiceCategory <- v.4,
                voiceIsFavorite <- false
            ))
        }

        // 标记第一个旗舰音色为收藏
        try db.run(voices.filter(voiceKey == "longanlingxin").update(voiceIsFavorite <- true))
    }
}