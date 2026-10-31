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

    /// 每页加载的音频数量
    static let pageSize: Int = 50

    /// 获取音频条目（支持分页）
    /// - Parameters:
    ///   - page: 页码（从1开始）
    ///   - pageSize: 每页数量
    /// - Returns: (音频列表, 总数)
    func fetchAudios(page: Int, pageSize: Int = ProjectService.pageSize) -> (audios: [AudioItem], total: Int) {
        let offset = (page - 1) * pageSize
        var allAudios: [AudioItem] = []
        var totalCount: Int = 0

        do {
            // 获取总数
            totalCount = try db.db.scalar(db.audioItems.count)

            // 获取分页数据
            let query = db.audioItems
                .order(db.audioCreatedAt.desc)
                .limit(pageSize, offset: offset)

            allAudios = try db.db.prepare(query).map { row in
                AudioItem(
                    id: row[db.audioId],
                    fileName: row[db.audioFileName],
                    displayName: row[db.audioDisplayName],
                    text: row[db.audioText],
                    voice: row[db.audioVoice],
                    format: row[db.audioFormat],
                    sampleRate: row[db.audioSampleRate],
                    duration: row[db.audioDuration],
                    fileSize: row[db.audioFileSize],
                    pointsCost: row[db.audioPointsCost],
                    status: AudioStatus(rawValue: row[db.audioStatus]) ?? .pending,
                    createdAt: row[db.audioCreatedAt]
                )
            }
        } catch {
            Log(message: "ProjectService.fetchAudios error: \(error)")
        }

        return (allAudios, totalCount)
    }

    /// 获取所有音频条目，按创建时间倒序
    func fetchAllAudios() -> [AudioItem] {
        return fetchAudios(page: 1, pageSize: Int.max).audios
    }

    /// 创建音频条目（顶层；不再需要 projectId，也不再保存完整路径）
    @discardableResult
    func createAudio(
        fileName: String,
        text: String,
        voice: String,
        format: String,
        sampleRate: Int,
        pointsCost: Double,
        status: AudioStatus = .completed,
        displayName: String? = nil,
        duration: Double = 0.0
    ) -> AudioItem? {
        let now = Date()
        let fileSize = fileSizeOfAudio(named: fileName)
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
                db.audioCreatedAt <- now,
                db.audioFileSize <- fileSize
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
                fileSize: fileSize,
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

    /// 复制音频条目：在磁盘上复制音频文件，并在库内新建一条相同元数据的记录。
    /// 新记录显示名为原显示名 + " 副本"（原无自定义显示名则沿用新的时间戳文件名）。
    /// - Parameter source: 要复制的音频
    /// - Returns: 新建的音频条目；源文件不存在或复制/入库失败时返回 nil
    ///
    /// ⚠️ 拆成「复制文件（重活）+ 写库」两步是为了让 iOS 的左滑「复制」能把第一步
    /// 挪出主线程，详见 `stageDuplicatedFile`。
    func duplicateAudio(_ source: AudioItem) -> AudioItem? {
        guard let newFileName = Self.stageDuplicatedFile(sourceURL: source.absoluteURL,
                                                         fileExtension: source.fileExtension) else {
            return nil
        }
        return finishDuplicate(source: source, newFileName: newFileName)
    }

    /// 复制流程里唯一的重活：挑一个新文件名，把音频文件复制到 `GeneratedAudio/`。
    ///
    /// ⚠️ 刻意做成 **`nonisolated static`**：它只依赖 `FileManager`，不碰那个 SQLite 连接，
    /// 所以能安全地脱离主线程。iOS 的左滑「复制」在主线程上做这一步（同步文件复制，
    /// 音频文件动辄几 MB，几十毫秒起步）会把左滑菜单的回弹动画卡在半路 ——
    /// 表现就是**「被复制的那一行先消失、隔一下才回来」**。
    /// - Returns: 新文件名；源文件不存在 / 复制失败时返回 nil
    nonisolated static func stageDuplicatedFile(sourceURL: URL, fileExtension: String) -> String? {
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            Log(message: "ProjectService.stageDuplicatedFile: 源文件不存在 - \(sourceURL.path)")
            return nil
        }

        let ext = fileExtension
        let baseName = Date().filenameTimestamp
        let dir = generatedAudioDirectoryURL()
        var attempt = 0
        var newFileName: String
        var newURL: URL
        repeat {
            newFileName = ext.isEmpty
                ? "\(baseName)\(attempt == 0 ? "" : "-\(attempt)")"
                : "\(baseName)\(attempt == 0 ? "" : "-\(attempt)").\(ext)"
            newURL = dir.appendingPathComponent(newFileName)
            attempt += 1
        } while FileManager.default.fileExists(atPath: newURL.path)

        do {
            try FileManager.default.copyItem(at: sourceURL, to: newURL)
        } catch {
            Log(message: "ProjectService.stageDuplicatedFile: 复制文件失败 - \(error.localizedDescription)")
            return nil
        }
        return newFileName
    }

    /// 文件就位之后，在库里建一条元数据相同的新记录（只有一次 INSERT，留在主线程即可）。
    func finishDuplicate(source: AudioItem, newFileName: String) -> AudioItem? {
        // 新显示名：仅当原记录有自定义显示名时追加"副本"
        let newDisplayName: String?
        if let name = source.displayName, !name.isEmpty {
            newDisplayName = "\(name) " + "副本".localized()
        } else {
            newDisplayName = nil
        }

        return createAudio(
            fileName: newFileName,
            text: source.text,
            voice: source.voice,
            format: source.format,
            sampleRate: source.sampleRate,
            pointsCost: source.pointsCost,
            status: .completed,
            displayName: newDisplayName,
            duration: source.duration
        )
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

    /// 读磁盘计算音频文件大小（字节）；文件不存在返回 0
    private func fileSizeOfAudio(named fileName: String) -> Int {
        let url = generatedAudioDirectoryURL().appendingPathComponent(fileName)
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? Int64 else { return 0 }
        return Int(size)
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
