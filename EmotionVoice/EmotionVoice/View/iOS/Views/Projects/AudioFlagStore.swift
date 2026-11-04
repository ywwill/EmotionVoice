//
//  AudioFlagStore.swift
//  iOSEmora
//
//  音频条目的「收藏 / 最近删除」轻量标记 + 当前播放项。
//
//  ⚠️ 不碰 audio_items 表：项目约定永不迁移，create(ifNotExists:) 给旧库加列不生效，
//     也禁止 DROP 重建（会丢已有音频）。收藏与软删一律按 audio id 存独立 JSON，
//     磁盘文件在「到期清理 / 彻底删除」前原样保留；撤销 = 清掉 deleted_at 标记。
//
//  ⚠️ 三处入口（播放详情页 / 列表左滑 / 多选工具条）共用这一个 store，
//     不要各自用 View 的本地 @State，否则列表角标、收藏计数、筛选结果不同步。
//

import Foundation
import SwiftUI
import Combine

// MARK: - 收藏 / 最近删除

@MainActor
final class AudioFlagStore: ObservableObject {

    static let shared = AudioFlagStore()

    /// 最近删除保留天数（设计稿默认 30 天）
    static let retentionDays: Int = 30

    @Published private(set) var favoriteIDs: Set<Int64> = []
    @Published private(set) var deletedAt: [Int64: Date] = [:]

    private let defaults = UserDefaults.standard
    private let favoritesKey = "emora.audio.favorites.v1"
    private let deletedKey = "emora.audio.deleted.v1"

    private init() {
        if let data = defaults.data(forKey: favoritesKey),
           let array = try? JSONDecoder().decode([Int64].self, from: data) {
            favoriteIDs = Set(array)
        }
        if let data = defaults.data(forKey: deletedKey),
           let dict = try? JSONDecoder().decode([String: TimeInterval].self, from: data) {
            var restored: [Int64: Date] = [:]
            for (key, stamp) in dict {
                if let id = Int64(key) { restored[id] = Date(timeIntervalSince1970: stamp) }
            }
            deletedAt = restored
        }
    }

    // MARK: 收藏

    func isFavorite(_ id: Int64) -> Bool { favoriteIDs.contains(id) }

    @discardableResult
    func toggleFavorite(_ id: Int64) -> Bool {
        setFavorite(id, !favoriteIDs.contains(id))
        return favoriteIDs.contains(id)
    }

    func setFavorite(_ id: Int64, _ on: Bool) {
        if on { favoriteIDs.insert(id) } else { favoriteIDs.remove(id) }
        persist()
    }

    func setFavorites(_ ids: [Int64], to on: Bool) {
        for id in ids {
            if on { favoriteIDs.insert(id) } else { favoriteIDs.remove(id) }
        }
        persist()
    }

    /// 计数恒为全量：只在传入的「未删除」全集里数，不受搜索 / 筛选影响。
    func favoriteCount(in ids: [Int64]) -> Int {
        var n = 0
        for id in ids where favoriteIDs.contains(id) { n += 1 }
        return n
    }

    // MARK: 最近删除

    var deletedCount: Int { deletedAt.count }
    var deletedIDs: Set<Int64> { Set(deletedAt.keys) }
    func isDeleted(_ id: Int64) -> Bool { deletedAt[id] != nil }
    func deletedDate(for id: Int64) -> Date? { deletedAt[id] }

    func markDeleted(_ ids: [Int64], at date: Date = Date()) {
        for id in ids { deletedAt[id] = date }
        persist()
    }

    func restore(_ ids: [Int64]) {
        for id in ids { deletedAt.removeValue(forKey: id) }
        persist()
    }

    /// 只清标记；磁盘文件与库记录由调用方删（彻底删除 / 到期清理）。
    func clearFlags(_ ids: [Int64]) {
        for id in ids { deletedAt.removeValue(forKey: id) }
        persist()
    }

    func remainingDays(for id: Int64) -> Int {
        guard let date = deletedAt[id] else { return Self.retentionDays }
        let elapsed = Date().timeIntervalSince(date)
        return max(0, Self.retentionDays - Int(floor(elapsed / 86400)))
    }

    /// 到期清理：返回已过期的 id，调用方负责删磁盘 + 库记录。
    /// ⚠️ 只在 App 启动 / 进页面时调一次，别在 body 里调。
    @discardableResult
    func purgeExpired() -> [Int64] {
        let cutoff = Date().addingTimeInterval(-Double(Self.retentionDays) * 86400)
        var expired: [Int64] = []
        for (id, date) in deletedAt where date < cutoff { expired.append(id) }
        if !expired.isEmpty {
            for id in expired { deletedAt.removeValue(forKey: id) }
            persist()
        }
        return expired
    }

    // MARK: 持久化

    private func persist() {
        if let data = try? JSONEncoder().encode(Array(favoriteIDs)) {
            defaults.set(data, forKey: favoritesKey)
        }
        var dict: [String: TimeInterval] = [:]
        for (id, date) in deletedAt { dict[String(id)] = date.timeIntervalSince1970 }
        if let data = try? JSONEncoder().encode(dict) {
            defaults.set(data, forKey: deletedKey)
        }
    }
}

// MARK: - 低频播放态（CPU 性能）

/// ⚠️ `AudioPreviewPlayer` 的 `progress` / `currentTime` 每 0.1s 写 @Published，
///    一旦用 @StateObject/@ObservedObject 订阅，整个视图 body 会以 10Hz 全量重算。
///    macOS 早就把订阅关在几十行的小 View 里（见 `AudioPlayerDetailView` /
///    `VoiceRowPlayback` / `ModalAudioPlayer` 开头注释），宿主一律 `let player` 不订阅。
///    iOS 大视图只需要低频播放态，用这个代理：它订阅的是**单个 @Published 的
///    publisher**，这些 publisher 只在自身值变化时发值，不会被 progress/currentTime
///    带着一起发。高频显示（波形、时间、进度条）请直接订阅 `AudioPreviewPlayer.shared`。
@MainActor
final class PlaybackStatus: ObservableObject {

    static let shared = PlaybackStatus()

    @Published private(set) var playingKey: String?
    @Published private(set) var isPlaying = false
    @Published private(set) var isPaused = false
    @Published private(set) var isFinished = false
    @Published private(set) var playbackRate: Float = 1.0
    @Published private(set) var duration: Double = 0

    private let engine = AudioPreviewPlayer.shared
    private var bag = Set<AnyCancellable>()

    private init() {
        engine.$playingKey.sink { [weak self] in self?.playingKey = $0 }.store(in: &bag)
        engine.$isPlaying.sink { [weak self] in self?.isPlaying = $0 }.store(in: &bag)
        engine.$isPaused.sink { [weak self] in self?.isPaused = $0 }.store(in: &bag)
        engine.$isFinished.sink { [weak self] in self?.isFinished = $0 }.store(in: &bag)
        engine.$playbackRate.sink { [weak self] in self?.playbackRate = $0 }.store(in: &bag)
        engine.$duration.sink { [weak self] in self?.duration = $0 }.store(in: &bag)
    }
}

// MARK: - 当前播放项

/// mini player 的展示来源。
///
/// ⚠️ `AudioPreviewPlayer.playingKey` 只是字符串标识（文件名），不足以渲染
/// 「名称 / 音色 / 进度」；这里单独记一条 AudioItem，播放本身仍由播放器单例负责。
@MainActor
final class NowPlayingStore: ObservableObject {

    static let shared = NowPlayingStore()

    @Published private(set) var currentItem: AudioItem? = nil
    /// ⚠️ body 里不许查库：音色名在起播时由调用方一并缓存进来。
    @Published private(set) var currentVoiceName: String = ""

    private let player = AudioPreviewPlayer.shared

    private init() {}

    func attach(_ item: AudioItem, voiceName: String? = nil) {
        let isDifferent = currentItem?.id != item.id
        currentItem = item
        if let voiceName {
            currentVoiceName = voiceName
        } else if isDifferent {
            currentVoiceName = ""
        }
        applyNowPlayingMetadata(item)
    }

    /// 锁屏信息必须在起播前就位：`play(url:)` 内部会先 `stop()`，
    /// 等播起来再补元数据会先闪一次空封面 / 上一条的音色。
    /// 封面用与列表 `VoiceAvatar` 相同的 seed + 末字，保证锁屏与历史记录一致。
    private func applyNowPlayingMetadata(_ item: AudioItem) {
        let name = currentVoiceName.isEmpty ? item.voice : currentVoiceName
        player.setNowPlayingMetadata(title: item.shownName,
                                     artist: name,
                                     seed: item.voice,
                                     avatarText: String(name.suffix(1)))
    }

    /// 行内试听 / mini player 的统一入口：同一条切换播放、不同条直接换曲。
    /// ⚠️ 一律用 `identifier = fileName` 起播，详情页才能用 playingKey 判等。
    func toggle(_ item: AudioItem, voiceName: String? = nil) {
        guard item.isOnDisk else { return }
        attach(item, voiceName: voiceName)
        player.togglePlayback(url: item.absoluteURL, identifier: item.fileName)
    }

    func start(_ item: AudioItem, voiceName: String? = nil) {
        guard item.isOnDisk else { return }
        attach(item, voiceName: voiceName)
        player.play(url: item.absoluteURL, identifier: item.fileName)
    }

    func isCurrent(_ item: AudioItem) -> Bool {
        currentItem?.id == item.id && player.playingKey == item.fileName
    }

    func clearIfMatches(_ ids: Set<Int64>) {
        guard let item = currentItem, ids.contains(item.id) else { return }
        close()
    }

    /// mini player 的「关闭」：停播 + 清掉当前项，浮层随即收起。
    func close() {
        player.stop()
        player.clearNowPlayingMetadata()
        currentItem = nil
        currentVoiceName = ""
    }
}
