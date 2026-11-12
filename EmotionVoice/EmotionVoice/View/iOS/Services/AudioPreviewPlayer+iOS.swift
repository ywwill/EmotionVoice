//
//  AudioPreviewPlayer+iOS.swift
//  iOSEmora
//
//  iOS 专属播放器：AVAudioPlayer + 后台播放 + 锁屏 NowPlaying / 远程控制。
//
//  ⚠️ 只挂在 iOSEmora target；macOS 用 Shared/Services/AudioPreviewPlayer.swift。
//     两份实现同名、公开 API 完全一致，调用方（PlaybackStatus / NowPlayingStore /
//     6 个高频小 View）一行都不用改。
//
//  与 macOS 版的差异：
//  - AVAudioSession `.playback` + UIBackgroundModes=audio → 锁屏 / 切后台继续播放
//  - MPNowPlayingInfoCenter：曲名=文件显示名、艺术家=音色名、
//    封面=与历史记录列表 `VoiceAvatar` 同一套种子渐变 + 末字
//  - MPRemoteCommandCenter：播放 / 暂停 / 拖动进度 / ±15s
//
//  ⚠️ 引擎仍是 AVAudioPlayer + 10Hz Timer。之前换 AVPlayer 用户验证无效，且
//     CPU 暴涨的根因是 SwiftUI 订阅拓扑（不是音频重采样）：宿主视图一律订阅
//     `PlaybackStatus`，高频显示只允许下沉到小 View，别在这里扩大 @Published 频率。
//

import Foundation
import AVFoundation
import Combine
import UIKit
import MediaPlayer
import SwiftUI

// MARK: - 音频阻塞操作的专用串行队列
//
// ⚠️ Xcode 27 的 "AVAudioSession Hang Risk" 诊断：
//   `setCategory` / `setActive` 是到 mediaserverd 的同步 XPC，主线程调用会掉帧；
//   `AVAudioPlayer(contentsOf:)` + `prepareToPlay()` 会 acquire 音频硬件，同样会被点名。
// Apple 建议的异步 `activateWithOptions` / `deactivateWithOptions` 是 **iOS 27.0+**，
// 本工程部署目标 17.6 用不了，所以统一把同步调用搬离主线程。
// 队列是串行的：stop 的停用 → 起播的激活 → 创建/预热 天然 FIFO，不会交错。
private let audioWorkQueue = DispatchQueue(
    label: "com.emora.audio.work", qos: .userInitiated
)

/// 只在 `audioWorkQueue` 上调用；不碰任何 MainActor 状态。
private enum AudioSessionWork {
    static func activate() -> String? {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback,
                                    mode: .spokenAudio,
                                    options: [.allowAirPlay, .allowBluetoothA2DP])
            try session.setActive(true)
            return nil
        } catch {
            return "activate audio session failed: \(error)"
        }
    }

    static func deactivate() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// `prepareToPlay()` 是整条链路里最重的一步，必须留在后台队列。
    /// ⚠️ AVFAudio 头文件要求 `enableRate` 在 `prepareToPlay()` **之前**设置，
    ///    否则 rate 不生效（旧实现是先 prepare 再 enableRate，倍速实际是失效的）。
    static func makePreparedPlayer(url: URL, rate: Float) -> (AVAudioPlayer?, String?) {
        do {
            let p = try AVAudioPlayer(contentsOf: url)
            p.enableRate = true
            p.rate = rate
            p.prepareToPlay()
            return (p, nil)
        } catch {
            return (nil, "AVAudioPlayer failed: \(error)")
        }
    }
}

/// 把非 Sendable 的 AVAudioPlayer 从后台队列安全带回主线程。
private final class PreparedPlayerBox: @unchecked Sendable {
    let player: AVAudioPlayer
    init(_ player: AVAudioPlayer) { self.player = player }
}

@MainActor
final class AudioPreviewPlayer: NSObject, ObservableObject {

    static let shared = AudioPreviewPlayer()

    /// 当前正在播放的 identifier（列表/详情页统一用 fileName）
    @Published private(set) var playingKey: String? = nil
    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var isPaused: Bool = false
    @Published private(set) var isFinished: Bool = false
    /// 当前播放进度（0.0 - 1.0），10Hz
    @Published private(set) var progress: Double = 0.0
    @Published private(set) var currentTime: Double = 0.0
    @Published private(set) var duration: Double = 0.0
    @Published var playbackRate: Float = 1.0

    static let playbackRateOptions: [(rate: Float, label: String)] = [
        (0.5, "0.5x"),
        (0.75, "0.75x"),
        (1.0, "1x"),
        (1.25, "1.25x"),
        (1.5, "1.5x"),
        (2.0, "2x")
    ]

    private var player: AVAudioPlayer?
    private var avPlayer: AVPlayer?                    // 回退：AVAudioPlayer 不支持的格式
    private var playerItemObserver: NSKeyValueObservation?
    private var endObserver: NSObjectProtocol?
    private var progressTimer: Timer?
    private var cachedURLs: [String: URL] = [:]
    /// 播放结束时 `playingKey` 会被清空；锁屏按播放重播时要恢复它，mini player 才会回来。
    private var lastIdentifier: String?
    /// 起播请求序号：后台预热完成后回主线程只认最后一次，防止快速切歌时旧请求覆盖新请求。
    private var playRequestSerial: UInt64 = 0

    // MARK: 后台 / 锁屏状态
    private var mediaSessionConfigured = false
    private var nowPlayingTitle: String?
    private var nowPlayingArtist: String?
    private var nowPlayingArtwork: MPMediaItemArtwork?
    private var artworkCache: [String: MPMediaItemArtwork] = [:]
    private var lastElapsedSecond: Int = -1

    private override init() {
        super.init()
        let nc = NotificationCenter.default
        nc.addObserver(self,
                       selector: #selector(handleAppTerminate),
                       name: UIApplication.willTerminateNotification,
                       object: nil)
        nc.addObserver(self,
                       selector: #selector(handleInterruption(_:)),
                       name: AVAudioSession.interruptionNotification,
                       object: AVAudioSession.sharedInstance())
        nc.addObserver(self,
                       selector: #selector(handleRouteChange(_:)),
                       name: AVAudioSession.routeChangeNotification,
                       object: AVAudioSession.sharedInstance())
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func handleAppTerminate() {
        stop()
        clearNowPlayingMetadata()
        UIApplication.shared.endReceivingRemoteControlEvents()
    }

    // MARK: - 公开 API（签名与 macOS 版逐字对齐）

    @discardableResult
    func play(key: String) -> Bool {
        if playingKey == key, isPlaying {
            player?.currentTime = 0
            player?.play()
            refreshNowPlaying()
            return true
        }
        stop()
        guard let url = resolveURL(forKey: key) else {
            Log(message: "AudioPreviewPlayer(iOS): audio not found for key=\(key)")
            return false
        }
        return play(url: url, identifier: key)
    }

    /// ⚠️ 必须走 `voice.audio`，基础音色 key 带前缀而 Bundle 资源名不带。
    @discardableResult
    func play(voice: Voice) -> Bool {
        guard !voice.audio.isEmpty else { return play(key: voice.key) }
        return play(audioFile: voice.audio, identifier: voice.key)
    }

    func toggle(voice: Voice) {
        if playingKey == voice.key && isPlaying {
            stop()
        } else {
            _ = play(voice: voice)
        }
    }

    @discardableResult
    func play(audioFile: String, identifier: String? = nil) -> Bool {
        let key = identifier ?? audioFile
        if playingKey == key, isPlaying {
            player?.currentTime = 0
            player?.play()
            refreshNowPlaying()
            return true
        }
        stop()
        guard let url = resolveURL(forAudio: audioFile) else {
            Log(message: "AudioPreviewPlayer(iOS): audio file not found: \(audioFile)")
            return false
        }
        return play(url: url, identifier: key)
    }

    @discardableResult
    func play(url: URL, identifier: String? = nil) -> Bool {
        let key = identifier ?? url.path

        if playingKey == key, isPlaying {
            player?.currentTime = 0
            player?.play()
            refreshNowPlaying()
            return true
        }

        stop()
        // `stop()` 会释放音频会话，起播前必须重新激活，否则切歌后锁屏不再继续播。
        // 媒体会话（UIApplication / MPRemoteCommandCenter）必须留在主线程；
        // 音频会话与播放器预热走后台串行队列。
        configureMediaSessionIfNeeded()

        playRequestSerial &+= 1
        let serial = playRequestSerial
        // 进入队列前把 MainActor 上的倍速快照下来（队列闭包不读主线程状态）。
        let rate = playbackRate
        // 单例生命周期长于 Task，这里强捕获不成环；默认 MainActor 下嵌套 weak
        // 反而会触发 ImplicitStrongCapture。
        let owner = self
        audioWorkQueue.async {
            var box: PreparedPlayerBox?
            var failure: String?
            if let sessionFailure = AudioSessionWork.activate() {
                failure = sessionFailure
            } else {
                let (p, loadFailure) = AudioSessionWork.makePreparedPlayer(url: url, rate: rate)
                box = p.map(PreparedPlayerBox.init)
                failure = loadFailure
            }
            // 快照成 let 再交给并发闭包；只把 Sendable 的结果带回主线程，
            // AVAudioPlayer 的 delegate / play() 一律在主线程设置与调用。
            let resultBox = box
            let resultFailure = failure
            Task { @MainActor in
                guard owner.playRequestSerial == serial else { return }
                owner.finishStartPlayback(resultBox?.player,
                                          failure: resultFailure,
                                          url: url, key: key)
            }
        }
        // 公开签名与 macOS 版保持一致；Bool 语义为「起播请求已受理」，
        // 真正起播在后台预热完成后回到主线程（调用方均忽略返回值）。
        return true
    }

    /// 主线程收尾：`play()` 在这里调用，AVAudioPlayerDelegate 回调才落在主线程 RunLoop。
    private func finishStartPlayback(_ p: AVAudioPlayer?, failure: String?, url: URL, key: String) {
        if let failure {
            Log(message: "AudioPreviewPlayer(iOS): \(url.lastPathComponent) \(failure)")
        }
        guard let p else {
            _ = playWithAVPlayer(url: url, key: key)
            return
        }
        // enableRate / rate 已在后台队列里、prepareToPlay 之前设好（AVFAudio 要求）。
        p.delegate = self
        guard p.duration > 0, p.play() else {
            _ = playWithAVPlayer(url: url, key: key)
            return
        }
        player = p
        duration = p.duration
        playingKey = key
        lastIdentifier = key
        isPlaying = true
        isPaused = false
        isFinished = false
        startProgressTimer()
        refreshNowPlaying()
    }

    @discardableResult
    private func playWithAVPlayer(url: URL, key: String) -> Bool {
        clearAVPlayer()
        guard FileManager.default.fileExists(atPath: url.path) else {
            Log(message: "AudioPreviewPlayer(iOS): AVPlayer file not found at \(url.path)")
            return false
        }

        let item = AVPlayerItem(url: url)
        let newPlayer = AVPlayer(playerItem: item)
        newPlayer.rate = playbackRate
        avPlayer = newPlayer
        playingKey = key
        lastIdentifier = key

        playerItemObserver = item.observe(\.status, options: [.new]) { [weak self] observed, _ in
            guard let self else { return }
            Task { @MainActor in
                switch observed.status {
                case .readyToPlay:
                    self.duration = observed.duration.seconds.isNaN ? 0 : observed.duration.seconds
                    self.isPlaying = true
                    self.isPaused = false
                    self.isFinished = false
                    newPlayer.play()
                    self.startProgressTimer()
                    self.refreshNowPlaying()
                case .failed:
                    Log(message: "AudioPreviewPlayer(iOS): AVPlayer item failed: \(observed.error?.localizedDescription ?? "unknown")")
                    self.isPlaying = false
                    self.playingKey = nil
                default:
                    break
                }
            }
        }

        endObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.handlePlaybackFinished() }
        }

        newPlayer.play()
        isPlaying = true
        isPaused = false
        isFinished = false
        startProgressTimer()
        refreshNowPlaying()
        return true
    }

    private func clearAVPlayer() {
        avPlayer?.pause()
        avPlayer = nil
        playerItemObserver?.invalidate()
        playerItemObserver = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
            self.endObserver = nil
        }
    }

    func stop() {
        // 让还在后台预热、尚未回主线程起播的请求作废（用户取消 / 快速切歌）。
        playRequestSerial &+= 1
        let wasPlaying = isPlaying
        player?.stop()
        player = nil
        clearAVPlayer()
        stopProgressTimer()
        progress = 0
        currentTime = 0
        if wasPlaying { isPlaying = false }
        isPaused = false
        isFinished = false
        playingKey = nil
        deactivateSession()
        // 只清系统锁屏展示，元数据字段保留：play(url:) 内部先调 stop()，
        // 紧接着会 refreshNowPlaying() 重新发布，不能在这里把封面/音色丢掉。
        clearNowPlayingInfo()
    }

    func pause() {
        player?.pause()
        avPlayer?.pause()
        isPaused = true
        stopProgressTimer()
        if isPlaying { isPlaying = false }
        refreshNowPlaying()
    }

    func resume() {
        guard isPaused, playingKey != nil else { return }
        activateSession()
        isFinished = false
        if let p = player {
            p.play()
        } else if let av = avPlayer {
            av.play()
        } else {
            return
        }
        isPlaying = true
        isPaused = false
        startProgressTimer()
        refreshNowPlaying()
    }

    func isPlaying(key: String) -> Bool { playingKey == key && isPlaying }

    func isPlaying(url: URL) -> Bool { playingKey == url.path && isPlaying }

    func seek(to time: TimeInterval) {
        if let p = player {
            p.currentTime = time
        } else if let av = avPlayer {
            av.seek(to: CMTime(seconds: time, preferredTimescale: 600))
        }
        isFinished = false
        updateProgress()
        refreshNowPlaying()
    }

    func skip(by seconds: Double) {
        seek(to: max(0, min(duration, currentTime + seconds)))
    }

    func togglePlayback(url: URL) {
        if isPlaying {
            pause()
        } else if isPaused {
            resume()
        } else {
            play(url: url)
        }
    }

    /// ⚠️ 调用方必须用 identifier 判定，别用 `isPlaying(url:)`。
    func togglePlayback(url: URL, identifier: String) {
        guard playingKey == identifier else {
            play(url: url, identifier: identifier)
            return
        }
        if isPlaying {
            pause()
        } else if isPaused {
            resume()
        } else {
            play(url: url, identifier: identifier)
        }
    }

    func reidentify(_ identifier: String) {
        guard playingKey != nil else { return }
        playingKey = identifier
    }

    func setPlaybackRate(_ rate: Float) {
        playbackRate = rate
        if let p = player {
            p.rate = rate
        } else if let av = avPlayer {
            av.rate = rate
        }
        refreshNowPlaying()
    }

    // MARK: - 锁屏元数据（由 NowPlayingStore 在起播前同步）

    /// - Parameters:
    ///   - title: 列表显示名 / 文件名
    ///   - artist: 音色名
    ///   - seed: 音色 code（与列表 `VoiceAvatar(seed:)` 同一个值）
    ///   - avatarText: 音色名末字（与列表头像一致）
    func setNowPlayingMetadata(title: String?, artist: String?, seed: String?, avatarText: String?) {
        guard let title, !title.isEmpty else {
            clearNowPlayingMetadata()
            return
        }
        nowPlayingTitle = title
        nowPlayingArtist = artist

        let text = (avatarText?.isEmpty == false) ? avatarText! : "声"
        let cacheKey = (seed ?? "") + "|" + text
        if let cached = artworkCache[cacheKey] {
            nowPlayingArtwork = cached
        } else if let made = makeArtwork(text: text, seed: seed ?? "") {
            artworkCache[cacheKey] = made
            nowPlayingArtwork = made
        } else {
            nowPlayingArtwork = nil
        }
        refreshNowPlaying()
    }

    func clearNowPlayingMetadata() {
        nowPlayingTitle = nil
        nowPlayingArtist = nil
        nowPlayingArtwork = nil
        clearNowPlayingInfo()
    }

    // MARK: - 进度

    private func startProgressTimer() {
        stopProgressTimer()
        let timer = Timer(timeInterval: 0.1, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.updateProgress() }
        }
        RunLoop.main.add(timer, forMode: .common)
        progressTimer = timer
    }

    private func stopProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }

    /// 只在值真的变了才写 @Published：否则 10Hz 会把订阅的小 View 全部拖着重算。
    private func updateProgress() {
        var newTime: TimeInterval = 0
        var newDuration: TimeInterval = 0

        if let p = player {
            newTime = p.currentTime
            newDuration = p.duration
        } else if let av = avPlayer {
            newTime = av.currentTime().seconds
            if let item = av.currentItem {
                let d = item.duration.seconds
                newDuration = d.isNaN ? 0 : d
            }
        }

        if abs(newTime - currentTime) >= 0.01 { currentTime = newTime }
        if abs(newDuration - duration) >= 0.01 { duration = newDuration }

        if duration > 0 {
            let newProgress = currentTime / duration
            if abs(newProgress - progress) >= 0.0005 { progress = newProgress }
        } else if progress != 0 {
            progress = 0
        }

        refreshElapsedIfNeeded()
    }

    private func handlePlaybackFinished() {
        isPlaying = false
        isPaused = false
        isFinished = true
        playingKey = nil
        stopProgressTimer()
        progress = 0
        currentTime = 0
        refreshNowPlaying()
    }

    // MARK: - 资源解析

    private func resolveURL(forKey key: String) -> URL? {
        if let cached = cachedURLs[key] { return cached }
        if let url = Bundle.main.url(forResource: key, withExtension: "m4a") {
            cachedURLs[key] = url
            return url
        }
        return nil
    }

    private func resolveURL(forAudio audio: String) -> URL? {
        if let cached = cachedURLs[audio] { return cached }
        let ns = audio as NSString
        let fileName = ns.deletingPathExtension
        let ext = ns.pathExtension.isEmpty ? "m4a" : ns.pathExtension
        if let url = Bundle.main.url(forResource: fileName, withExtension: ext) {
            cachedURLs[audio] = url
            return url
        }
        return nil
    }
}

// MARK: - 后台播放：AVAudioSession

private extension AudioPreviewPlayer {

    /// 媒体会话（UIApplication / MPRemoteCommandCenter）仍在主线程配置；
    /// 音频会话的同步 XPC 全部丢给后台串行队列。
    /// ⚠️ resume / 中断恢复 / 锁屏重播走这里：这些路径下 session 通常仍是 active，
    ///    队列里的 `setActive(true)` 只是幂等兜底，不阻塞紧随其后的主线程 `play()`。
    func activateSession() {
        configureMediaSessionIfNeeded()
        audioWorkQueue.async {
            if let failure = AudioSessionWork.activate() {
                Log(message: "AudioPreviewPlayer(iOS): \(failure)")
            }
        }
    }

    func deactivateSession() {
        audioWorkQueue.async { AudioSessionWork.deactivate() }
    }

    /// 来电 / Siri 等中断：挂起后按系统建议恢复。
    @objc func handleInterruption(_ note: Notification) {
        guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        switch type {
        case .began:
            pause()
        case .ended:
            let options = AVAudioSession.InterruptionOptions(
                rawValue: (note.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt) ?? 0
            )
            if options.contains(.shouldResume) {
                activateSession()
                resume()
            }
        @unknown default:
            break
        }
    }

    /// 耳机拔出等旧设备不可用：暂停，避免外放突然响。
    @objc func handleRouteChange(_ note: Notification) {
        guard let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: raw),
              reason == .oldDeviceUnavailable else { return }
        pause()
    }
}

// MARK: - 锁屏：NowPlaying + RemoteCommandCenter

private extension AudioPreviewPlayer {

    func configureMediaSessionIfNeeded() {
        guard !mediaSessionConfigured else { return }
        mediaSessionConfigured = true
        UIApplication.shared.beginReceivingRemoteControlEvents()
        setupRemoteCommands()
    }

    func setupRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.isEnabled = true
        center.pauseCommand.isEnabled = true
        center.togglePlayPauseCommand.isEnabled = true
        center.changePlaybackPositionCommand.isEnabled = true
        center.skipBackwardCommand.isEnabled = true
        center.skipForwardCommand.isEnabled = true
        center.skipBackwardCommand.preferredIntervals = [NSNumber(value: 15)]
        center.skipForwardCommand.preferredIntervals = [NSNumber(value: 15)]
        // 没有播放列表，锁屏的上一首/下一首交给 ±15s，不伪造切曲语义。
        center.nextTrackCommand.isEnabled = false
        center.previousTrackCommand.isEnabled = false

        center.playCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            let engine = self
            Task { @MainActor in engine.remotePlay() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            let engine = self
            Task { @MainActor in if engine.isPlaying { engine.pause() } }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            let engine = self
            Task { @MainActor in
                if engine.isPlaying { engine.pause() } else { engine.remotePlay() }
            }
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self, let position = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            let time = position.positionTime
            let engine = self
            Task { @MainActor in engine.seek(to: time) }
            return .success
        }
        center.skipBackwardCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            let engine = self
            Task { @MainActor in engine.skip(by: -15) }
            return .success
        }
        center.skipForwardCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            let engine = self
            Task { @MainActor in engine.skip(by: 15) }
            return .success
        }
    }

    /// 锁屏按播放：暂停→续播；播完→从头重播（播放器对象还留着）。
    func remotePlay() {
        if isPaused { resume(); return }
        if isPlaying { return }
        guard player != nil || avPlayer != nil else { return }
        if playingKey == nil { playingKey = lastIdentifier }
        activateSession()
        if let p = player {
            p.currentTime = 0
            p.play()
        } else if let av = avPlayer {
            av.seek(to: .zero)
            av.play()
        }
        isPlaying = true
        isPaused = false
        isFinished = false
        startProgressTimer()
        refreshNowPlaying()
    }

    func refreshNowPlaying() {
        guard let title = nowPlayingTitle else {
            clearNowPlayingInfo()
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyPlaybackDuration: max(0, duration),
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? Double(playbackRate) : 0.0,
            MPNowPlayingInfoPropertyMediaType: MPMediaType.anyAudio.rawValue
        ]
        if let artist = nowPlayingArtist, !artist.isEmpty {
            info[MPMediaItemPropertyArtist] = artist
            info[MPMediaItemPropertyAlbumTitle] = artist
        }
        if let artwork = nowPlayingArtwork {
            info[MPMediaItemPropertyArtwork] = artwork
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        lastElapsedSecond = Int(currentTime)
    }

    /// 10Hz 不要打系统 IPC：锁屏进度每秒同步一次即可。
    func refreshElapsedIfNeeded() {
        let second = Int(currentTime)
        guard second != lastElapsedSecond else { return }
        lastElapsedSecond = second
        guard var info = MPNowPlayingInfoCenter.default().nowPlayingInfo else {
            refreshNowPlaying()
            return
        }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        info[MPNowPlayingInfoPropertyPlaybackRate] = isPlaying ? Double(playbackRate) : 0.0
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    func clearNowPlayingInfo() {
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        lastElapsedSecond = -1
    }

    /// 与列表 `VoiceAvatar` 同一套「种子渐变 + 末字」绘制成 UIImage。
    func makeArtwork(text: String, seed: String) -> MPMediaItemArtwork? {
        let side: CGFloat = 600
        let size = CGSize(width: side, height: side)
        let colors = VoiceAvatar.gradient(for: seed).map { UIColor($0).cgColor }
        guard colors.count >= 2,
              let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                        colors: colors as CFArray,
                                        locations: [0.0, 1.0]) else { return nil }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        // ⚠️ 必须整张方形全幅不透明，绝不在这里自绘圆角 / addClip：
        //    `MPMediaItemArtwork` 交到锁屏 / 控制中心时透明像素会被合成成白底，
        //    自己裁圆角就会在四个角留下白色楔形、底边留一条白边（2026-11-04 实测）。
        //    圆角由系统统一裁剪，四角露出来的仍然是渐变色，视觉与列表 VoiceAvatar 一致。
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            let rect = CGRect(origin: .zero, size: size)
            // opaque 位图未绘制到的像素是黑色，先铺渐变起点色兜底
            UIColor(cgColor: colors[0]).setFill()
            ctx.cgContext.fill(rect)
            ctx.cgContext.drawLinearGradient(
                gradient,
                start: .zero,
                end: CGPoint(x: side, y: side),
                options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
            )
            let attrs: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: side * 0.44, weight: .semibold),
                .foregroundColor: UIColor.white
            ]
            let ns = NSString(string: text)
            let textSize = ns.size(withAttributes: attrs)
            ns.draw(at: CGPoint(x: (side - textSize.width) / 2,
                                y: (side - textSize.height) / 2),
                    withAttributes: attrs)
        }
        return MPMediaItemArtwork(boundsSize: size) { _ in image }
    }
}

// MARK: - AVAudioPlayerDelegate

extension AudioPreviewPlayer: AVAudioPlayerDelegate {

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.handlePlaybackFinished()
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        let msg = error?.localizedDescription ?? "unknown"
        Log(message: "AudioPreviewPlayer(iOS): decode error: \(msg)")
        Task { @MainActor in
            self.isPlaying = false
            self.playingKey = nil
            self.stopProgressTimer()
            self.refreshNowPlaying()
        }
    }
}
