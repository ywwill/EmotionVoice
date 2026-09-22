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
    /// 是否处于暂停状态（保持播放器，可恢复播放）
    @Published private(set) var isPaused: Bool = false
    /// 当前播放进度（0.0 - 1.0）
    @Published private(set) var progress: Double = 0.0
    /// 当前播放时间（秒）
    @Published private(set) var currentTime: Double = 0.0
    /// 音频总时长（秒）
    @Published private(set) var duration: Double = 0.0
    /// 当前倍速
    @Published var playbackRate: Float = 1.0

    /// 可选的倍速选项
    static let playbackRateOptions: [(rate: Float, label: String)] = [
        (0.5, "0.5x"),
        (0.75, "0.75x"),
        (1.0, "1x"),
        (1.25, "1.25x"),
        (1.5, "1.5x"),
        (2.0, "2x")
    ]

        /// Bundle 内音频子目录（已废弃，文件平铺在 Resources 根目录）
    private let basicSubdir: String? = nil
    private let premiumSubdir: String? = nil

    private var player: AVAudioPlayer?
    private var avPlayer: AVPlayer?  // 回退播放器，用于播放 AVAudioPlayer 不支持的格式
    private var playerItemObserver: NSKeyValueObservation?  // 监听 AVPlayer 播放状态
    private var progressTimer: Timer?  // 进度更新定时器
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

        // 优先使用 AVAudioPlayer
        do {
            let p = try AVAudioPlayer(contentsOf: url)
            p.delegate = self
            p.prepareToPlay()
            p.rate = playbackRate
            p.enableRate = true

            // 检查音频是否可播放
            if p.duration <= 0 {
                Log(message: "AudioPreviewPlayer: AVAudioPlayer duration is 0 for \(url.lastPathComponent), trying AVPlayer")
                // 尝试使用 AVPlayer
                return playWithAVPlayer(url: url, key: key)
            }

            guard p.play() else {
                Log(message: "AudioPreviewPlayer: AVAudioPlayer play() returned false, trying AVPlayer")
                return playWithAVPlayer(url: url, key: key)
            }
            self.player = p
            self.duration = p.duration
            self.playingKey = key
            self.isPlaying = true
            self.startProgressTimer()
            Log(message: "AudioPreviewPlayer: started playing \(url.lastPathComponent), duration=\(p.duration)")
            return true
        } catch {
            Log(message: "AudioPreviewPlayer: AVAudioPlayer failed for \(url.lastPathComponent): \(error)")
            Log(message: "AudioPreviewPlayer: trying AVPlayer as fallback")
            return playWithAVPlayer(url: url, key: key)
        }
    }
    
    /// 使用 AVPlayer 播放（回退方案）
    @discardableResult
    private func playWithAVPlayer(url: URL, key: String) -> Bool {
        // 停止旧的 AVPlayer
        avPlayer?.pause()
        avPlayer = nil
        playerItemObserver?.invalidate()
        playerItemObserver = nil

        // 确保文件存在
        guard FileManager.default.fileExists(atPath: url.path) else {
            Log(message: "AudioPreviewPlayer: AVPlayer file not found at \(url.path)")
            return false
        }

        // 创建 AVPlayer
        let playerItem = AVPlayerItem(url: url)
        let newPlayer = AVPlayer(playerItem: playerItem)
        newPlayer.rate = playbackRate
        self.avPlayer = newPlayer
        self.playingKey = key

        // 监听播放状态
        playerItemObserver = playerItem.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor in
                switch item.status {
                case .readyToPlay:
                    self?.duration = item.duration.seconds.isNaN ? 0 : item.duration.seconds
                    self?.isPlaying = true
                    newPlayer.play()
                    self?.startProgressTimer()
                    Log(message: "AudioPreviewPlayer: AVPlayer ready and playing \(url.lastPathComponent)")
                case .failed:
                    Log(message: "AudioPreviewPlayer: AVPlayer item failed: \(item.error?.localizedDescription ?? "unknown error")")
                    self?.isPlaying = false
                    self?.playingKey = nil
                case .unknown:
                    break
                @unknown default:
                    break
                }
            }
        }

        // 监听播放结束
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.isPlaying = false
                self?.isPaused = false
                self?.playingKey = nil
                self?.stopProgressTimer()
            }
        }

        // 开始播放
        newPlayer.play()
        return true
    }

    /// 停止播放
    func stop() {
        let wasPlaying = isPlaying
        player?.stop()
        player = nil
        avPlayer?.pause()
        avPlayer = nil
        playerItemObserver?.invalidate()
        playerItemObserver = nil
        stopProgressTimer()
        // 重置进度
        progress = 0
        currentTime = 0
        if wasPlaying {
            isPlaying = false
        }
        isPaused = false
        playingKey = nil
    }

    /// 暂停播放（保持当前状态，波形图不消失）
    func pause() {
        player?.pause()
        avPlayer?.pause()
        isPaused = true
        if isPlaying {
            isPlaying = false
        }
    }

    /// 恢复播放（从暂停位置继续）
    func resume() {
        guard isPaused, playingKey != nil else { return }
        
        if let p = player {
            p.play()
            isPlaying = true
            isPaused = false
            startProgressTimer()
        } else if let av = avPlayer {
            av.play()
            isPlaying = true
            isPaused = false
            startProgressTimer()
        }
    }

    /// 是否正在播放指定 key
    func isPlaying(key: String) -> Bool {
        return playingKey == key && isPlaying
    }

    /// 是否正在播放指定 URL 对应的音频
    func isPlaying(url: URL) -> Bool {
        return playingKey == url.path && isPlaying
    }
    
    /// 跳转到指定时间
    func seek(to time: TimeInterval) {
        if let p = player {
            p.currentTime = time
        } else if let av = avPlayer {
            av.seek(to: CMTime(seconds: time, preferredTimescale: 600))
        }
        updateProgress()
    }

    /// 设置倍速播放
    func setPlaybackRate(_ rate: Float) {
        playbackRate = rate
        if let p = player {
            p.rate = rate
        } else if let av = avPlayer {
            av.rate = rate
        }
    }

    // MARK: - 进度更新

    /// 启动进度更新定时器
    private func startProgressTimer() {
        stopProgressTimer()
        progressTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updateProgress()
            }
        }
    }

    /// 停止进度更新定时器
    private func stopProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }

    /// 更新当前进度
    private func updateProgress() {
        if let p = player {
            currentTime = p.currentTime
            duration = p.duration
        } else if let av = avPlayer {
            currentTime = av.currentTime().seconds
            if let item = av.currentItem {
                let d = item.duration.seconds
                duration = d.isNaN ? 0 : d
            }
        }

        if duration > 0 {
            progress = currentTime / duration
        } else {
            progress = 0
        }
    }

    // MARK: - 资源解析

    /// 根据 key 解析 bundle 内音频 URL（按 {key}.m4a 命名约定）
    private func resolveURL(forKey key: String) -> URL? {
        if let cached = cachedURLs[key] { return cached }
        // 文件直接平铺在 Resources/ 根目录
        if let url = Bundle.main.url(forResource: key, withExtension: "m4a") {
            cachedURLs[key] = url
            return url
        }
        return nil
    }
}

// MARK: - AVAudioPlayerDelegate

extension AudioPreviewPlayer: AVAudioPlayerDelegate {

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.isPlaying = false
            self.isPaused = false
            self.playingKey = nil
            self.stopProgressTimer()
            self.progress = 0
            self.currentTime = 0
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        let msg = error?.localizedDescription ?? "unknown"
        Log(message: "AudioPreviewPlayer: decode error: \(msg)")
        Task { @MainActor in
            self.isPlaying = false
            self.playingKey = nil
            self.stopProgressTimer()
        }
    }
}
