//
//  AudioPreviewPlayer.swift
//  EmotionVoice
//
//  Created by young on 2026/8/9.
//
//  音色试听播放器。
//  根据 Voice.key 查找 BasicVoiceLoader 中的 audio 文件名，
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

    /// Bundle 内音频子目录（与 Resources/voices/basic 对应）
    private let basicSubdir = "voices/basic"
    /// Bundle 内旗舰音频子目录
    private let premiumSubdir = "voices/premium"
    /// Bundle 内兜底子目录（兼容平铺目录）
    private let fallbackSubdir = "voices"

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
            Log(message: "AudioPreviewPlayer: m4a not found in bundle for key=\(key)")
            return false
        }

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
            guard p.play() else {
                Log(message: "AudioPreviewPlayer: play() returned false for \(url.lastPathComponent)")
                return false
            }
            self.player = p
            self.playingKey = key
            self.isPlaying = true
            return true
        } catch {
            Log(message: "AudioPreviewPlayer: init player failed for url: \(error)")
            return false
        }
    }

    /// 停止播放
    func stop() {
        player?.stop()
        player = nil
        if isPlaying {
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

    /// 解析 key 对应的 bundle 内 m4a URL
    /// 1) 优先查 BasicVoiceLoader 提供的 audio 文件名（基础音色）
    /// 2) 其次从 DB 拿 voice.audio（用于旗舰/其他）
    /// 3) 兜底：直接用 "{key}.m4a"
    private func resolveURL(forKey key: String) -> URL? {
        if let cached = cachedURLs[key] { return cached }

        // 1) BasicVoiceLoader 模板（基础音色 JSON）
        BasicVoiceLoader.shared.loadFromBundle()
        let templateAudio = BasicVoiceLoader.shared.template(forKey: key)?.audio

        // 2) 数据库里登记的 audio 字段（旗舰音色已写入）
        let dbAudio: String? = {
            for v in VoiceService.shared.fetchAll() where v.key == key {
                return v.audio.isEmpty ? nil : v.audio
            }
            return nil
        }()

        let candidates: [String] = {
            var list: [String] = []
            if let n = templateAudio, !n.isEmpty { list.append(n) }
            if let n = dbAudio, !n.isEmpty { list.append(n) }
            list.append("\(key).m4a")  // 兜底
            return list
        }()

        // 旗舰音色优先 premium/，基础音色优先 basic/，兜底搜索 voices/ 和根目录
        let prioritySubdirs: [String]
        if key.hasPrefix("longan") {
            prioritySubdirs = [premiumSubdir, basicSubdir, fallbackSubdir, ""]
        } else {
            prioritySubdirs = [basicSubdir, premiumSubdir, fallbackSubdir, ""]
        }

        for name in candidates {
            for subdir in prioritySubdirs {
                if let url = locate(name: name, in: subdir) {
                    cachedURLs[key] = url
                    return url
                }
            }
        }
        return nil
    }

    /// 在 bundle 指定子目录中查找文件
    private func locate(name: String, in subdir: String) -> URL? {
        if subdir.isEmpty {
            return Bundle.main.url(forResource: (name as NSString).deletingPathExtension,
                                   withExtension: (name as NSString).pathExtension)
        }
        guard let dirURL = Bundle.main.url(forResource: subdir, withExtension: nil) else {
            return nil
        }
        let candidate = dirURL.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: candidate.path) ? candidate : nil
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
