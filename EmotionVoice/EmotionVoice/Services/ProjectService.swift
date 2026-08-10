//
//  ProjectService.swift
//  EmotionVoice
//
//  Created by young on 2026/8/8.
//

import Foundation
import SQLite

/// 项目/音频数据服务
final class ProjectService {

    static let shared = ProjectService()

    private let db = DatabaseManager.shared

    // MARK: - 项目

    /// 获取所有项目
    func fetchAllProjects() -> [Project] {
        do {
            return try db.db.prepare(db.projects.order(db.projectUpdatedAt.desc))
                .map { row in
                    Project(
                        id: row[db.projectId],
                        name: row[db.projectName],
                        folder: row[db.projectFolder].flatMap(ProjectFolder.init(rawValue:)),
                        createdAt: row[db.projectCreatedAt],
                        updatedAt: row[db.projectUpdatedAt]
                    )
                }
        } catch {
            Log(message: "ProjectService.fetchAllProjects error: \(error)")
            return []
        }
    }

    /// 创建项目
    @discardableResult
    func createProject(name: String, folder: ProjectFolder?) -> Project? {
        let now = Date()
        do {
            let id = try db.db.run(db.projects.insert(
                db.projectName <- name,
                db.projectFolder <- folder?.rawValue,
                db.projectCreatedAt <- now,
                db.projectUpdatedAt <- now
            ))
            return Project(id: id, name: name, folder: folder, createdAt: now, updatedAt: now)
        } catch {
            Log(message: "ProjectService.createProject error: \(error)")
            return nil
        }
    }

    // MARK: - 音频条目

    /// 获取项目的所有音频条目
    func fetchAudios(projectId: Int64) -> [AudioItem] {
        do {
            return try db.db.prepare(
                db.audioItems
                    .filter(db.audioProjectId == projectId)
                    .order(db.audioCreatedAt.desc)
            ).map { row in
                AudioItem(
                    id: row[db.audioId],
                    projectId: row[db.audioProjectId],
                    title: row[db.audioTitle],
                    text: row[db.audioText],
                    voice: row[db.audioVoice],
                    format: row[db.audioFormat],
                    sampleRate: row[db.audioSampleRate],
                    duration: row[db.audioDuration],
                    filePath: row[db.audioFilePath],
                    pointsCost: row[db.audioPointsCost],
                    status: AudioStatus(rawValue: row[db.audioStatus]) ?? .pending,
                    createdAt: row[db.audioCreatedAt]
                )
            }
        } catch {
            Log(message: "ProjectService.fetchAudios error: \(error)")
            return []
        }
    }

    /// 创建音频条目
    @discardableResult
    func createAudio(
        projectId: Int64,
        title: String,
        text: String,
        voice: String,
        format: String,
        sampleRate: Int,
        pointsCost: Int,
        status: AudioStatus = .completed
    ) -> AudioItem? {
        let now = Date()
        do {
            let id = try db.db.run(db.audioItems.insert(
                db.audioProjectId <- projectId,
                db.audioTitle <- title,
                db.audioText <- text,
                db.audioVoice <- voice,
                db.audioFormat <- format,
                db.audioSampleRate <- sampleRate,
                db.audioDuration <- 0.0,
                db.audioFilePath <- nil,
                db.audioPointsCost <- pointsCost,
                db.audioStatus <- status.rawValue,
                db.audioCreatedAt <- now
            ))
            // 更新项目 updatedAt
            try db.db.run(db.projects.filter(db.projectId == projectId)
                .update(db.projectUpdatedAt <- now))

            return AudioItem(
                id: id, projectId: projectId,
                title: title, text: text, voice: voice,
                format: format, sampleRate: sampleRate,
                duration: 0.0, filePath: nil,
                pointsCost: pointsCost, status: status,
                createdAt: now
            )
        } catch {
            Log(message: "ProjectService.createAudio error: \(error)")
            return nil
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