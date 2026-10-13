//
//  PlaybackKeyboardShortcuts.swift
//  EmotionVoice
//
//  播放快捷键（基于 sindresorhus/KeyboardShortcuts）
//    空格          播放 / 暂停
//    ← →          ∓ 5 秒
//    ⇧← ⇧→        ∓ 15 秒
//    Home / End   跳到开头 / 结尾
//
//  为什么换成 KeyboardShortcuts：
//  它用 Carbon 热键注册，跟 SwiftUI 焦点无关，播放面板里点来点去快捷键也不会丢；
//  旧实现用本地 NSEvent monitor 虽然也能做到，但得自己处理一堆边界。
//
//  代价（重要）：Carbon 热键会**吞掉**按键事件——它在事件派发到 App 之前就截走了。
//  所以"在回调里判断一下再决定做不做"救不回输入框：等回调跑起来，空格已经被吃掉了，
//  搜索框里一个空格都打不进去。必须反过来做：
//    · 输入框开始编辑 → 整体 disable，让空格 / 方向键回到文本控件
//    · 编辑结束       → 再 enable 回来
//  同理，没在播放时把 ←→ 也 disable，把方向键还给左侧列表做滚动 / 行导航。
//

import SwiftUI
import AppKit
import Combine
import KeyboardShortcuts

// MARK: - 快捷键定义

extension KeyboardShortcuts.Name {
    /// 播放 / 暂停
    static let playbackToggle = Self("playbackToggle", initial: Shortcut(.space))
    /// 后退 5 秒
    static let playbackBackward5 = Self("playbackBackward5", initial: Shortcut(.leftArrow))
    /// 前进 5 秒
    static let playbackForward5 = Self("playbackForward5", initial: Shortcut(.rightArrow))
    /// 后退 15 秒
    static let playbackBackward15 = Self("playbackBackward15", initial: Shortcut(.leftArrow, modifiers: [.shift]))
    /// 前进 15 秒
    static let playbackForward15 = Self("playbackForward15", initial: Shortcut(.rightArrow, modifiers: [.shift]))
    /// 跳到开头
    static let playbackToStart = Self("playbackToStart", initial: Shortcut(.home))
    /// 跳到结尾
    static let playbackToEnd = Self("playbackToEnd", initial: Shortcut(.end))
}

/// 按用途分组，方便整体 enable / disable
private enum PlaybackShortcut {
    static let toggle: [KeyboardShortcuts.Name] = [
        KeyboardShortcuts.Name.playbackToggle
    ]

    static let skipSeek: [KeyboardShortcuts.Name] = [
        KeyboardShortcuts.Name.playbackBackward5,
        KeyboardShortcuts.Name.playbackForward5,
        KeyboardShortcuts.Name.playbackBackward15,
        KeyboardShortcuts.Name.playbackForward15,
        KeyboardShortcuts.Name.playbackToStart,
        KeyboardShortcuts.Name.playbackToEnd
    ]

    static var all: [KeyboardShortcuts.Name] { toggle + skipSeek }
}

// MARK: - 控制器

/// 播放快捷键控制器（全局单例）
///
/// 热键是全局注册的，一个 App 里只注册一次；但"按下去作用在哪条音频上"只有界面知道，
/// 所以播放面板出现时把 `player` / `audio` 交过来，消失时再收回。
@MainActor
final class PlaybackShortcutsController {

    static let shared = PlaybackShortcutsController()

    // MARK: 当前上下文

    private var player: AudioPreviewPlayer?
    private var currentAudio: AudioItem?

    /// 是否有可操作的音频（正在播或已暂停可续播）
    private var hasActiveItem = false
    /// 焦点是否在可编辑文本里（搜索框、重命名…）
    private var isEditingText = false

    private var playingKeySink: AnyCancellable?

    private init() {
        registerHandlers()
        observeTextEditing()
        // 面板还没出来，先别吞键盘；等 setActive 再按状态开
        KeyboardShortcuts.disable(PlaybackShortcut.all)
    }

    // MARK: - 上下文

    /// 播放面板出现 / 切换音频时调用
    func setActive(player: AudioPreviewPlayer, audio: AudioItem) {
        self.player = player
        self.currentAudio = audio

        playingKeySink?.cancel()
        playingKeySink = player.$playingKey.sink { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshActiveItem() }
        }
        refreshActiveItem()
    }

    /// 播放面板消失时调用
    ///
    /// 只在"消失的确实是当前这一条"时才收，避免切换音频时旧视图的 onDisappear
    /// 晚于新视图的 onAppear、把刚设好的上下文清掉。
    func clear(audioID: Int64) {
        guard currentAudio?.id == audioID else { return }

        player = nil
        currentAudio = nil
        hasActiveItem = false
        playingKeySink?.cancel()
        playingKeySink = nil
        // 面板都没了，别再吞键盘
        KeyboardShortcuts.disable(PlaybackShortcut.all)
    }

    private func refreshActiveItem() {
        hasActiveItem = player?.playingKey != nil
        applyShortcutState()
    }

    // MARK: - 开关

    private func applyShortcutState() {
        guard !isEditingText else {
            // 输入框里一律放行，让空格 / 方向键回到文本控件
            KeyboardShortcuts.disable(PlaybackShortcut.all)
            return
        }

        KeyboardShortcuts.enable(PlaybackShortcut.toggle)

        // 没在播就把 ←→ 还给列表（滚动 / 行导航）
        if hasActiveItem {
            KeyboardShortcuts.enable(PlaybackShortcut.skipSeek)
        } else {
            KeyboardShortcuts.disable(PlaybackShortcut.skipSeek)
        }
    }

    // MARK: - 注册

    private func registerHandlers() {
        // 播放/暂停走 keyUp，避免长按 / 连按的重复触发
        KeyboardShortcuts.onKeyUp(for: .playbackToggle) { [weak self] in
            MainActor.assumeIsolated { self?.handleToggle() }
        }

        KeyboardShortcuts.onKeyDown(for: .playbackBackward5) { [weak self] in
            MainActor.assumeIsolated { self?.handleSkip(-5) }
        }
        KeyboardShortcuts.onKeyDown(for: .playbackForward5) { [weak self] in
            MainActor.assumeIsolated { self?.handleSkip(5) }
        }
        KeyboardShortcuts.onKeyDown(for: .playbackBackward15) { [weak self] in
            MainActor.assumeIsolated { self?.handleSkip(-15) }
        }
        KeyboardShortcuts.onKeyDown(for: .playbackForward15) { [weak self] in
            MainActor.assumeIsolated { self?.handleSkip(15) }
        }
        KeyboardShortcuts.onKeyDown(for: .playbackToStart) { [weak self] in
            MainActor.assumeIsolated { self?.handleSeek(to: 0) }
        }
        KeyboardShortcuts.onKeyDown(for: .playbackToEnd) { [weak self] in
            MainActor.assumeIsolated { self?.handleSeekToEnd() }
        }
    }

    /// 输入框开始 / 结束编辑 → 整体开关
    private func observeTextEditing() {
        NotificationCenter.default.addObserver(
            forName: NSText.didBeginEditingNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.isEditingText = true
                self?.applyShortcutState()
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSText.didEndEditingNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.isEditingText = false
                self?.applyShortcutState()
            }
        }
    }

    // MARK: - 动作

    private func handleToggle() {
        // 空格始终用于播放/暂停（没播放时从头开始）
        guard let player, let audio = currentAudio else { return }
        player.togglePlayback(url: audio.absoluteURL)
    }

    private func handleSkip(_ delta: Double) {
        // 没有正在播放的内容时就什么都不做；此刻快捷键已被 disable，事件不会走到这里
        guard let player, player.playingKey != nil else { return }
        player.skip(by: delta)
    }

    private func handleSeek(to time: Double) {
        guard let player, player.playingKey != nil else { return }
        player.seek(to: time)
    }

    private func handleSeekToEnd() {
        guard let player, player.playingKey != nil else { return }
        player.seek(to: player.duration)
    }
}

// MARK: - ViewModifier

private struct PlaybackShortcutInstaller: ViewModifier {

    let player: AudioPreviewPlayer
    let audio: AudioItem

    func body(content: Content) -> some View {
        content
            .onAppear {
                PlaybackShortcutsController.shared.setActive(player: player, audio: audio)
            }
            .onDisappear {
                PlaybackShortcutsController.shared.clear(audioID: audio.id)
            }
            // 换音频后控制器里的 audio 会过期，重新交一次
            .onChange(of: audio.id) { _, _ in
                PlaybackShortcutsController.shared.setActive(player: player, audio: audio)
            }
    }
}

extension View {
    /// 播放面板可见期间把播放快捷键指向这里（空格 / ←→ / ⇧←→ / Home / End）
    func playbackKeyboardShortcuts(player: AudioPreviewPlayer, audio: AudioItem) -> some View {
        modifier(PlaybackShortcutInstaller(player: player, audio: audio))
    }
}
