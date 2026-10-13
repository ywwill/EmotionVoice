//
//  PlaybackKeyboardShortcuts.swift
//  EmotionVoice
//
//  播放快捷键：空格 播放/暂停，←→ ±5 秒，⇧←→ ±15 秒，Home/End 跳首尾
//
//  为什么用本地事件监听而不是 `.onKeyPress`：
//  `.onKeyPress` 只在视图获得焦点时才投递，而播放面板里没有可接受焦点的控件，
//  用户点一下左侧列表焦点就丢了，快捷键会时灵时不灵。本地 monitor 在面板可见期间
//  一直生效，更符合播放器的预期。
//  唯一的代价是要自己判断"当前焦点是不是在输入框里"，否则会抢走搜索框的空格。
//

import SwiftUI
import AppKit

/// 快捷键对应的动作（抽出来方便测试与复用）
enum PlaybackKeyAction {
    case togglePlay
    case skip(Double)
    case seekTo(Double)
}

/// 把 keyDown 事件翻译成播放动作；不该处理的返回 nil
enum PlaybackKeyResolver {

    /// Shift 是唯一允许参与快捷键的修饰键（⇧←→ = 15 秒）
    private static let allowedModifiers: NSEvent.ModifierFlags = [.shift]

    static func action(for event: NSEvent) -> PlaybackKeyAction? {
        // 去掉大写锁定（capsLock 在 deviceIndependentFlagsMask 内，开着时会让所有
        // 快捷键全部失效），并拦截带 ⌘ / ⌥ / ⌃ 的组合交给系统。
        let flags = event.modifierFlags
            .intersection(.deviceIndependentFlagsMask)
            .subtracting(.capsLock)
        guard flags.subtracting(Self.allowedModifiers).isEmpty else { return nil }

        let isShift = flags.contains(.shift)

        switch event.keyCode {
        case 49:  // Space
            return isShift ? nil : .togglePlay
        case 123: // ←
            return .skip(isShift ? -15 : -5)
        case 124: // →
            return .skip(isShift ? 15 : 5)
        case 125, 126: // ↑ ↓ 交给列表做行导航，不拦截
            return nil
        case 115: // Home
            return .seekTo(0)
        case 119: // End
            return .seekTo(.infinity) // 由调用方夹到 duration
        default:
            return nil
        }
    }

    /// 焦点在"正在编辑"的可编辑文本里时才放行，避免抢走搜索框的按键。
    /// 只读文本（如原文卡片的选择态）、列表、空白区域一律接管为播放快捷键——
    /// 旧实现用 `responder is NSTextView || 类名含 "Text"` 判断，会把右侧面板里
    /// 进入选择态的只读文本视图误判为"输入框"而放行方向键，导致快进失效。
    static func shouldIntercept() -> Bool {
        guard let responder = NSApp.keyWindow?.firstResponder else { return true }
        if let tv = responder as? NSTextView, tv.isEditable { return false }
        if let tf = responder as? NSTextField, tf.isEditable { return false }
        return true
    }
}

// MARK: - ViewModifier

private struct PlaybackKeyboardMonitor: ViewModifier {

    let player: AudioPreviewPlayer
    let audio: AudioItem

    @State private var monitorToken: Any?

    func body(content: Content) -> some View {
        content
            .onAppear(perform: install)
            .onDisappear(perform: uninstall)
            // 换音频后闭包里的 audio 会过期，重装一次拿到新的 URL
            .onChange(of: audio.id) { _, _ in
                uninstall()
                install()
            }
    }

    private func install() {
        guard monitorToken == nil else { return }
        monitorToken = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [player, audio] event in
            guard PlaybackKeyResolver.shouldIntercept(),
                  let action = PlaybackKeyResolver.action(for: event) else { return event }

            switch action {
            case .togglePlay:
                // 空格始终用于播放/暂停（没播放时从头开始）
                player.togglePlayback(url: audio.absoluteURL)
            case .skip(let delta):
                // 没有正在播放的内容时，把方向键交还给左侧列表做行导航，
                // 而不是吞成一个无操作的"快进"
                guard player.playingKey != nil else { return event }
                player.skip(by: delta)
            case .seekTo(let time):
                guard player.playingKey != nil else { return event }
                player.seek(to: min(time, player.duration))
            }
            return nil
        }
    }

    private func uninstall() {
        if let token = monitorToken {
            NSEvent.removeMonitor(token)
            monitorToken = nil
        }
    }
}

extension View {
    /// 在播放面板可见期间接管播放快捷键
    func playbackKeyboardShortcuts(player: AudioPreviewPlayer, audio: AudioItem) -> some View {
        modifier(PlaybackKeyboardMonitor(player: player, audio: audio))
    }
}
