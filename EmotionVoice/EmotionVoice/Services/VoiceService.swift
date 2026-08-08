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

    /// 获取所有音色
    func fetchAll() -> [Voice] {
        do {
            return try db.db.prepare(db.voices.order(db.voiceCategory.asc, db.voiceName.asc))
                .map { row in
                    Voice(
                        key: row[db.voiceKey],
                        name: row[db.voiceName],
                        desc: row[db.voiceDesc],
                        avatar: row[db.voiceAvatar],
                        category: VoiceCategory(rawValue: row[db.voiceCategory]) ?? .basic,
                        isFavorite: row[db.voiceIsFavorite]
                    )
                }
        } catch {
            print("VoiceService.fetchAll error: \(error)")
            return []
        }
    }

    /// 按分类获取
    func fetch(by category: VoiceCategory) -> [Voice] {
        fetchAll().filter { $0.category == category }
    }

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
            print("VoiceService.toggleFavorite error: \(error)")
            return false
        }
    }
}