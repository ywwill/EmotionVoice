//
//  Project.swift
//  EmotionVoice
//
//  Created by young on 2026/8/8.
//

import Foundation

/// 项目分组
enum ProjectFolder: String, CaseIterable, Identifiable {
    case audiobook = "有声书"
    case podcast = "播客"
    case shortVideo = "短视频配音"
    case ad = "广告配音"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .audiobook: return "📖"
        case .podcast: return "🎙️"
        case .shortVideo: return "🎬"
        case .ad: return "📢"
        }
    }
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

/// 项目
struct Project: Identifiable, Hashable {
    let id: Int64
    var name: String
    var folder: ProjectFolder?
    var createdAt: Date
    var updatedAt: Date
}

/// 音频条目
struct AudioItem: Identifiable, Hashable {
    let id: Int64
    let projectId: Int64
    var title: String
    var text: String
    var voice: String
    var format: String
    var sampleRate: Int
    var duration: Double
    var filePath: String?
    var pointsCost: Int
    var status: AudioStatus
    var createdAt: Date
}