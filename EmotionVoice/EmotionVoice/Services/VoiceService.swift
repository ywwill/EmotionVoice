//
//  VoiceService.swift
//  EmotionVoice
//
//  Created by young on 2026/8/8.
//

import Foundation
import SQLite

/// 音色数据服务
final class VoiceService {

    static let shared = VoiceService()

    private let db = DatabaseManager.shared

    // MARK: - 全量（保留旧接口供其他模块使用）

    /// 获取所有音色
    func fetchAll() -> [Voice] {
        do {
            return try db.db.prepare(db.voices.order(db.voiceCategory.asc, db.voiceName.asc))
                .map { Self.rowToVoice($0, db: db) }
        } catch {
            Log(message: "VoiceService.fetchAll error: \(error)")
            return []
        }
    }

    /// 按分类获取
    func fetch(by category: VoiceCategory) -> [Voice] {
        fetchAll().filter { $0.category == category }
    }

    // MARK: - SQL 分页查询（按分类 + 搜索文本）

    /// 按分类+搜索文本查询总数（轻量）
    func count(category: VoiceCategory?, searchText: String) -> Int {
        do {
            var query = db.voices
            if let pred = predicate(category: category, searchText: searchText) {
                query = query.filter(pred)
            }
            return try db.db.scalar(query.count)
        } catch {
            Log(message: "VoiceService.count error: \(error)")
            return 0
        }
    }

    /// 按分类+搜索文本分页查询（limit + offset）
    /// - Parameter orderByPremiumFirst: 若为 true 且 category == nil，则优先按 premium 排序（旗舰音色始终在前）
    func fetch(category: VoiceCategory?, searchText: String, limit: Int, offset: Int, orderByPremiumFirst: Bool = false) -> [Voice] {
        do {
            // 搜索过滤
            let needle = searchText.trimmingCharacters(in: .whitespaces)
            var predicateExpr: SQLite.Expression<Bool>?
            if !needle.isEmpty {
                let like = "%\(needle)%"
                predicateExpr = (db.voiceName.like(like) ||
                                 db.voiceDesc.like(like) ||
                                 db.voiceScene.like(like) ||
                                 db.voiceLang.like(like))
            }

            if orderByPremiumFirst && category == nil {
                // "全部"分类：按 dimension（premium > language > scene > role > age）排序，
                // 旗舰维度优先，再按 premium 字段，最后按名称。该排序无法在 SQL 端精确表达，
                // 因此拉全表后在内存中排序，再按 offset/limit 切片。
                var query = db.voices
                if let p = predicateExpr {
                    query = query.filter(p)
                }
                let all = try db.db.prepare(query).map { Self.rowToVoice($0, db: db) }
                let sorted = Self.sortForAllCategory(all)
                let start = min(offset, sorted.count)
                let end = min(offset + limit, sorted.count)
                return Array(sorted[start..<end])
            }

            // 其他场景：SQL 端按 category + name 排序 + limit/offset
            var query = db.voices.order(db.voiceCategory.asc, db.voiceName.asc)
            if let cat = category, let p = categoryPredicate(cat) {
                if let extra = predicateExpr {
                    query = query.filter(p && extra)
                } else {
                    query = query.filter(p)
                }
            } else if let extra = predicateExpr {
                query = query.filter(extra)
            }

            return try db.db.prepare(query.limit(limit, offset: offset)).map { Self.rowToVoice($0, db: db) }
        } catch {
            Log(message: "VoiceService.fetch(paged) error: \(error)")
            return []
        }
    }

    /// "全部"分类下的展示顺序：
    /// 1) dimension 优先级：premium > language > scene > role > age
    /// 2) 同维度内：premium 类目排前
    /// 3) 同类目下：按 name 字典序
    private static func sortForAllCategory(_ voices: [Voice]) -> [Voice] {
        voices.sorted { a, b in
            let da = dimensionRank(a.category.dimension)
            let db_ = dimensionRank(b.category.dimension)
            if da != db_ { return da < db_ }

            let aIsPremium = a.category == .premium
            let bIsPremium = b.category == .premium
            if aIsPremium != bIsPremium { return aIsPremium }

            return a.name < b.name
        }
    }

    private static func dimensionRank(_ dim: VoiceCategoryDimension) -> Int {
        switch dim {
        case .premium:  return 0
        case .language: return 1
        case .scene:    return 2
        case .role:     return 3
        case .age:      return 4
        }
    }

    /// 收藏总数
    func countFavorites() -> Int {
        do {
            return try db.db.scalar(db.voices.filter(db.voiceIsFavorite == true).count)
        } catch {
            return 0
        }
    }

    /// 按收藏+搜索文本分页查询
    func fetchFavorites(searchText: String, limit: Int, offset: Int) -> [Voice] {
        do {
            var query = db.voices.filter(db.voiceIsFavorite == true)

            // 搜索过滤
            let needle = searchText.trimmingCharacters(in: .whitespaces)
            if !needle.isEmpty {
                let like = "%\(needle)%"
                query = query.filter(
                    db.voiceName.like(like) ||
                    db.voiceDesc.like(like) ||
                    db.voiceScene.like(like) ||
                    db.voiceLang.like(like)
                )
            }

            // 收藏页同样按 dimension 排序（旗舰在前），SQL 端无法精确表达，使用内存排序 + 分片
            let all = try db.db.prepare(query).map { Self.rowToVoice($0, db: db) }
            let sorted = Self.sortForAllCategory(all)
            let start = min(offset, sorted.count)
            let end = min(offset + limit, sorted.count)
            return Array(sorted[start..<end])
        } catch {
            Log(message: "VoiceService.fetchFavorites error: \(error)")
            return []
        }
    }

    /// 按收藏+搜索文本查询总数
    func countFavorites(searchText: String) -> Int {
        do {
            var query = db.voices.filter(db.voiceIsFavorite == true)

            let needle = searchText.trimmingCharacters(in: .whitespaces)
            if !needle.isEmpty {
                let like = "%\(needle)%"
                query = query.filter(
                    db.voiceName.like(like) ||
                    db.voiceDesc.like(like) ||
                    db.voiceScene.like(like) ||
                    db.voiceLang.like(like)
                )
            }

            return try db.db.scalar(query.count)
        } catch {
            Log(message: "VoiceService.countFavorites error: \(error)")
            return 0
        }
    }

    // MARK: - WHERE 子句构造

    /// 构造分类+搜索的 WHERE 子句
    /// - Returns: nil 表示无过滤条件；Expression<Bool>(value: false) 表示永远无匹配
    private func predicate(category: VoiceCategory?, searchText: String) -> SQLite.Expression<Bool>? {
        var conditions: [SQLite.Expression<Bool>] = []

        // 分类过滤
        if let category = category {
            guard let pred = categoryPredicate(category) else {
                return SQLite.Expression<Bool>(value: false)
            }
            conditions.append(pred)
        }

        // 搜索过滤
        let needle = searchText.trimmingCharacters(in: .whitespaces)
        if !needle.isEmpty {
            let like = "%\(needle)%"
            // 多字段 OR 实现 name/desc/scene/lang 任一匹配
            conditions.append(
                db.voiceName.like(like) ||
                db.voiceDesc.like(like) ||
                db.voiceScene.like(like) ||
                db.voiceLang.like(like)
            )
        }

        if conditions.isEmpty { return nil }
        if conditions.count == 1 { return conditions[0] }
        return conditions.dropFirst().reduce(conditions[0]) { $0 && $1 }
    }

    /// 将 VoiceCategory 翻译为 SQL 谓词
    /// 与 VoiceCategory.matches(_:) 行为对齐
    private func categoryPredicate(_ category: VoiceCategory) -> SQLite.Expression<Bool>? {
        switch category {
        case .premium:
            return db.voiceCategory == VoiceCategory.premium.rawValue

        case .chinese:
            return db.voiceLang.like("%中文%")
        case .english:
            return db.voiceLang.like("%英文%")

        case .sceneDaily:      return db.voiceScene == "日常对话"
        case .sceneCompanion:  return db.voiceScene == "情感陪伴"
        case .sceneCustomer:   return db.voiceScene == "客服"
        case .sceneReading:    return db.voiceScene == "有声阅读"
        case .sceneSocial:     return db.voiceScene == "社交互动"
        case .sceneAnime:      return db.voiceScene == "动漫配音"
        case .sceneNews:       return db.voiceScene == "新闻播报"
        case .sceneLive:       return db.voiceScene == "电商直播"
        case .sceneClassic:    return db.voiceScene == "古风有声书"
        case .sceneSports:     return db.voiceScene == "体育解说"
        case .sceneAudiobook:  return db.voiceScene == "有声书配音"
        case .sceneRadio:      return db.voiceScene == "深夜电台"
        case .sceneKnowledge:  return db.voiceScene == "知识分享"
        case .sceneComedy:     return db.voiceScene == "娱乐搞笑"
        case .sceneBusiness:   return db.voiceScene == "商务汇报"
        case .sceneAssistant:  return db.voiceScene == "智能助手"
        case .sceneSpeech:     return db.voiceScene == "演讲朗诵"

        // 角色：使用 scene 子串匹配（与 matches 中 contains 一致）
        case .roleAnime:    return db.voiceScene.like("%动漫配音%")
        case .roleLive:    return db.voiceScene.like("%电商直播%")
        case .roleClassic: return db.voiceScene.like("%古风有声书%")
        case .roleRadio:   return db.voiceScene.like("%深夜电台%")

        // 年龄：age 区间
        case .ageChild:  return db.voiceAge < 13
        case .ageTeen:   return db.voiceAge >= 13 && db.voiceAge < 18
        case .ageYoung:  return db.voiceAge >= 18 && db.voiceAge < 36
        case .ageMiddle: return db.voiceAge >= 36 && db.voiceAge < 60
        case .ageSenior: return db.voiceAge >= 60
        }
    }

    /// 将 SQLite Row 转为 Voice
    private static func rowToVoice(_ row: Row, db: DatabaseManager) -> Voice {
        Voice(
            key: row[db.voiceKey],
            name: row[db.voiceName],
            desc: row[db.voiceDesc],
            avatar: row[db.voiceAvatar],
            category: VoiceCategory(rawValue: row[db.voiceCategory]) ?? .chinese,
            isFavorite: row[db.voiceIsFavorite],
            scene: row[db.voiceScene],
            age: row[db.voiceAge],
            gender: row[db.voiceGender],
            audio: row[db.voiceAudio],
            lang: row[db.voiceLang]
        )
    }

    // MARK: - 切换收藏

    /// 切换收藏
    @discardableResult
    func toggleFavorite(key: String) -> Bool {
        do {
            let row = try db.db.pluck(db.voices.filter(db.voiceKey == key))
            guard let row else { return false }
            let newValue = !row[db.voiceIsFavorite]
            try db.db.run(db.voices.filter(db.voiceKey == key).update(db.voiceIsFavorite <- newValue))
            return newValue
        } catch {
            Log(message: "VoiceService.toggleFavorite error: \(error)")
            return false
        }
    }
}
