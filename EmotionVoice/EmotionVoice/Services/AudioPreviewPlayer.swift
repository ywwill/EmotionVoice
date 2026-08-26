//
//  AudioPreviewPlayer.swift
//  EmotionVoice
//
//  Created by young on 2026/8/9.
//
//  音色试听播放器
//  从 Bundle 的 voices/basic/ 或 voices/premium/ 子目录加载 wav 并播放。
//

import Foundation
import AVFoundation
import Combine
#if canImport(AppKit)
import AppKit
#endif

/// 基础音色试听播放器（单例）
///
/// 使用方式：
/// ```swift
/// AudioPreviewPlayer.shared.play(key: "longcanzhuyue")
/// AudioPreviewPlayer.shared.stop()
/// ```
@MainActor
final class AudioPreviewPlayer: NSObject, ObservableObject {

    static let shared = AudioPreviewPlayer()

    /// 当前正在播放的 voice key
    @Published private(set) var playingKey: String? = nil
    /// 是否正在播放
    @Published private(set) var isPlaying: Bool = false

        /// Bundle 内音频子目录（已废弃，文件平铺在 Resources 根目录）
    private let basicSubdir: String? = nil
    private let premiumSubdir: String? = nil

    private var player: AVAudioPlayer?
    private var cachedURLs: [String: URL] = [:]

    private override init() {
        super.init()
        // 监听 App 退出，保证资源释放
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppTerminate),
            name: NSApplication.willTerminateNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func handleAppTerminate() {
        player?.stop()
        player = nil
    }

    // MARK: - 公开 API

    /// 根据 voice key 播放预览音频
    /// - Parameter key: voice 参数 key（如 "longcanzhuyue"）
    /// - Returns: true 表示开始播放（或已开始播放同一文件），false 表示文件未找到
    @discardableResult
    func play(key: String) -> Bool {
        // 已经在播放同一文件 → 视为"重新触发"，重置进度从头播放
        if playingKey == key, isPlaying {
            player?.currentTime = 0
            player?.play()
            return true
        }

        // 切换音色时先停止旧的
        stop()

        guard let url = resolveURL(forKey: key) else {
            Log(message: "AudioPreviewPlayer: audio not found for key=\(key)")
            return false
        }

        Log(message: "AudioPreviewPlayer: resolved URL for \(key): \(url.path)")
        return play(url: url, identifier: key)
    }

    /// 从文件 URL 播放（用于"所有项目"中点击生成的音频）
    /// - Parameters:
    ///   - url: 音频文件 URL（本地 wav/mp3 等）
    ///   - identifier: 当前播放的标识，用于同源续播判断
    @discardableResult
    func play(url: URL, identifier: String? = nil) -> Bool {
        let key = identifier ?? url.path

        // 已经在播放同一文件 → 重置进度从头播放
        if playingKey == key, isPlaying {
            player?.currentTime = 0
            player?.play()
            return true
        }

        stop()

        do {
            let p = try AVAudioPlayer(contentsOf: url)
            p.delegate = self
            p.prepareToPlay()

            // 检查音频是否可播放
            if p.duration <= 0 {
                Log(message: "AudioPreviewPlayer: audio duration is 0 for \(url.lastPathComponent)")
                return false
            }

            guard p.play() else {
                Log(message: "AudioPreviewPlayer: play() returned false for \(url.lastPathComponent)")
                return false
            }
            self.player = p
            self.playingKey = key
            self.isPlaying = true
            Log(message: "AudioPreviewPlayer: started playing \(url.lastPathComponent), duration=\(p.duration)")
            return true
        } catch {
            Log(message: "AudioPreviewPlayer: init player failed for \(url.lastPathComponent): \(error)")
            return false
        }
    }

    /// 停止播放
    func stop() {
        let wasPlaying = isPlaying
        player?.stop()
        player = nil
        if wasPlaying {
            isPlaying = false
        }
        playingKey = nil
    }

    /// 是否正在播放指定 key
    func isPlaying(key: String) -> Bool {
        return playingKey == key && isPlaying
    }

    /// 是否正在播放指定 URL 对应的音频
    func isPlaying(url: URL) -> Bool {
        return playingKey == url.path && isPlaying
    }

    // MARK: - 资源解析

    /// 根据 key 解析 bundle 内音频 URL（按 {key}.m4a 命名约定）
    private func resolveURL(forKey key: String) -> URL? {
        if let cached = cachedURLs[key] { return cached }

        let filename = "\(key).m4a"

        // 文件直接平铺在 Resources/ 根目录
        if let url = Bundle.main.url(forResource: key, withExtension: "m4a") {
            cachedURLs[key] = url
            return url
        }

        Log(message: "AudioPreviewPlayer: m4a not found for key=\(key), filename=\(filename)")
        return nil
    }
}

// MARK: - AVAudioPlayerDelegate

extension AudioPreviewPlayer: AVAudioPlayerDelegate {

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.isPlaying = false
            self.playingKey = nil
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        let msg = error?.localizedDescription ?? "unknown"
        Log(message: "AudioPreviewPlayer: decode error: \(msg)")
        Task { @MainActor in
            self.isPlaying = false
            self.playingKey = nil
        }
    }
}
