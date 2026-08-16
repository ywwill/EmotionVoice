//
//  Project.swift
//  EmotionVoice
//
//  Created by young on 2026/8/8.
//

import Foundation

/// 音频条目磁盘存储目录（相对于 Documents/）
/// 与 DatabaseManager 的路径约定保持一致，避免散落多处拼接。
let kGeneratedAudioSubdirectory = "GeneratedAudio"

/// 计算音频条目所在的完整目录 URL。
/// 例：file:///…/Documents/GeneratedAudio
func generatedAudioDirectoryURL() -> URL {
    let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    return docs.appendingPathComponent(kGeneratedAudioSubdirectory, isDirectory: true)
}

/// 确保目录存在（不存在则创建）
func ensureGeneratedAudioDirectoryExists() {
    let dir = generatedAudioDirectoryURL()
    try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
}

/// 音频状态
enum AudioStatus: String, CaseIterable, Identifiable {
    case completed = "completed"
    case generating = "generating"
    case pending = "pending"
    case failed = "failed"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .completed: return "已完成"
        case .generating: return "生成中"
        case .pending: return "待处理"
        case .failed: return "失败"
        }
    }
}

/// 音频条目
/// 一个音频文件 = 一条记录，本身就是"项目"。
/// 没有更上层的项目分组概念。
struct AudioItem: Identifiable, Hashable {
    let id: Int64
    /// 真实文件名（含扩展名，例如 "2026-08-16_11-35-42.wav"），始终存在
    let fileName: String
    /// 用户可编辑的显示名；为空时使用 fileName
    var displayName: String?
    var text: String
    var voice: String
    var format: String
    var sampleRate: Int
    var duration: Double
    var pointsCost: Int
    var status: AudioStatus
    var createdAt: Date

    /// UI 显示名：displayName 非空则用 displayName，否则用 fileName
    var shownName: String {
        if let d = displayName, !d.isEmpty { return d }
        return fileName
    }

    /// 扩展名（如 "wav" / "mp3"），无扩展名则为空
    var fileExtension: String {
        let url = URL(fileURLWithPath: fileName)
        return url.pathExtension
    }

    /// 磁盘上的绝对 URL：Documents/GeneratedAudio/<fileName>
    /// 不存在时返回 URL 但 isPlayable 由调用方另判。
    var absoluteURL: URL {
        generatedAudioDirectoryURL().appendingPathComponent(fileName)
    }

    /// 音频文件是否真实存在于磁盘上
    var isOnDisk: Bool {
        !fileName.isEmpty && FileManager.default.fileExists(atPath: absoluteURL.path)
    }

    /// 从完整路径中提取文件名（最后一段）。找不到则返回原串。
    /// （保留此工具方法以便旧调用方/外部数据兼容）
    static func deriveFileName(fromPath path: String?) -> String {
        guard let path, !path.isEmpty else { return "" }
        return (path as NSString).lastPathComponent
    }
}