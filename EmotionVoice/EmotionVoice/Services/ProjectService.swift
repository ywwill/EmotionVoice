//
//  ProjectService.swift
//  EmotionVoice
//
//  Created by young on 2026/8/8.
//
//  现在不再有"项目"概念：每条音频 = 独立的"项目"。
//  为兼容历史调用点，文件名沿用 ProjectService。
//

import Foundation
import SQLite

/// 音频数据服务（历史上名为 ProjectService）
/// 每个音频文件本身就是一条独立记录；不再有上层项目分组。
final class ProjectService {

    static let shared = ProjectService()

    private let db = DatabaseManager.shared

    // MARK: - 音频条目

    /// 获取所有音频条目，按创建时间倒序
    func fetchAllAudios() -> [AudioItem] {
        do {
            return try db.db.prepare(db.audioItems.order(db.audioCreatedAt.desc))
                .map { row in
                    AudioItem(
                        id: row[db.audioId],
                        fileName: row[db.audioFileName],
                        displayName: row[db.audioDisplayName],
                        text: row[db.audioText],
                        voice: row[db.audioVoice],
                        format: row[db.audioFormat],
                        sampleRate: row[db.audioSampleRate],
                        duration: row[db.audioDuration],
                        pointsCost: row[db.audioPointsCost],
                        status: AudioStatus(rawValue: row[db.audioStatus]) ?? .pending,
                        createdAt: row[db.audioCreatedAt]
                    )
                }
        } catch {
            Log(message: "ProjectService.fetchAllAudios error: \(error)")
            return []
        }
    }

    /// 创建音频条目（顶层；不再需要 projectId，也不再保存完整路径）
    @discardableResult
    func createAudio(
        fileName: String,
        text: String,
        voice: String,
        format: String,
        sampleRate: Int,
        pointsCost: Int,
        status: AudioStatus = .completed,
        displayName: String? = nil,
        duration: Double = 0.0
    ) -> AudioItem? {
        let now = Date()
        do {
            let id = try db.db.run(db.audioItems.insert(
                db.audioFileName <- fileName,
                db.audioText <- text,
                db.audioVoice <- voice,
                db.audioFormat <- format,
                db.audioSampleRate <- sampleRate,
                db.audioDuration <- duration,
                db.audioDisplayName <- displayName,
                db.audioPointsCost <- pointsCost,
                db.audioStatus <- status.rawValue,
                db.audioCreatedAt <- now
            ))

            return AudioItem(
                id: id,
                fileName: fileName,
                displayName: displayName,
                text: text,
                voice: voice,
                format: format,
                sampleRate: sampleRate,
                duration: duration,
                pointsCost: pointsCost,
                status: status,
                createdAt: now
            )
        } catch {
            Log(message: "ProjectService.createAudio error: \(error)")
            return nil
        }
    }

    /// 更新音频时长（生成完成后回填，避免卡上显示 0:00）
    func updateAudioDuration(audioId: Int64, duration: Double) {
        do {
            try db.db.run(db.audioItems.filter(db.audioId == audioId)
                .update(db.audioDuration <- duration))
        } catch {
            Log(message: "ProjectService.updateAudioDuration error: \(error)")
        }
    }

    /// 重命名音频条目（修改 display_name）
    func renameAudio(id: Int64, displayName: String?) {
        do {
            try db.db.run(db.audioItems.filter(db.audioId == id)
                .update(db.audioDisplayName <- displayName))
        } catch {
            Log(message: "ProjectService.renameAudio error: \(error)")
        }
    }

    /// 删除单个音频条目及其磁盘文件
    func deleteAudio(id: Int64) {
        var fileNameToRemove: String? = nil
        if let row = try? db.db.pluck(db.audioItems.filter(db.audioId == id)) {
            fileNameToRemove = row[db.audioFileName]
        }

        do {
            try db.db.run(db.audioItems.filter(db.audioId == id).delete())
        } catch {
            Log(message: "ProjectService.deleteAudio error: \(error)")
        }

        if let name = fileNameToRemove, !name.isEmpty {
            let url = generatedAudioDirectoryURL().appendingPathComponent(name)
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// 计算文本预估积分消耗
    /// 每 1000 字 1 积分，最低 1 积分
    func estimatePoints(forText text: String) -> Int {
        let count = text.count
        if count == 0 { return 0 }
        let raw = ceil(Double(count) / 1000.0 * Constants.pointsPerThousandChars)
        return max(1, Int(raw))
    }
}