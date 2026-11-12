//
//  EmotionVoiceApp.swift
//  EmotionVoice
//
//  Created by young on 2026/8/8.
//

import SwiftUI
import AppKit
import KeyboardShortcuts

// MARK: - 草稿保存快捷键（KeyboardShortcuts）

extension KeyboardShortcuts.Name {
    /// 保存：固定默认 ⌘S
    static let saveDraft = Self("saveDraft", initial: Shortcut(.s, modifiers: [.command]))
}

/// ⌘S 由 sindresorhus/KeyboardShortcuts 注册，与播放快捷键同一套机制：
/// Carbon 热键不依赖 SwiftUI 焦点，NSTextView 正在打字时也能保存。
///
/// ⚠️ 热键是**全局**的：App 失活后不注销会抢走别的应用的 ⌘S
/// （`PlaybackShortcutsController` 已经踩过这个坑），所以必须跟随 App 激活状态 enable / disable。
@MainActor
final class DraftShortcutController {

    static let shared = DraftShortcutController()

    private var isAppActive: Bool = NSApp.isActive

    private init() {
        KeyboardShortcuts.onKeyDown(for: .saveDraft) { [weak self] in
            MainActor.assumeIsolated { self?.saveDraft() }
        }
        observeAppActivation()
        applyState()
    }

    /// App 启动时主动拉起单例，保证热键与激活监听在窗口出现前就装好。
    func start() { applyState() }

    private func saveDraft() {
        guard isAppActive else { return }
        // 与「保存」按钮 / 文件菜单共用同一入口：saveSignal 会让 VoiceStudioView 弹顶部提示。
        DraftStore.shared.saveFromSharedVM()
    }

    private func applyState() {
        if isAppActive {
            KeyboardShortcuts.enable([.saveDraft])
        } else {
            KeyboardShortcuts.disable([.saveDraft])
        }
    }

    private func observeAppActivation() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.isAppActive = true
                self?.applyState()
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.isAppActive = false
                self?.applyState()
            }
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {

    override init() {
        super.init()
        // WindowGroup 会把窗口 frame 存进 UserDefaults（"NSWindow Frame <autosaveName>"）。
        // 下次启动 AppKit 会先恢复历史尺寸，窗口一出生就是上次的小窗；而本 app 的约定是
        // 「每次打开都铺满可视区域」，所以在最早的时机把这些记录清掉，让 .defaultSize 生效。
        // 沙盒内 UserDefaults 只属于本 app，按前缀删不会波及其他 app。
        Self.clearSavedWindowFrames()
        LaunchWindowCoordinator.shared.start()
        // 草稿保存快捷键：与窗口尺寸初始化一样，在最早的时机装好热键与激活监听。
        DraftShortcutController.shared.start()
    }

    private static func clearSavedWindowFrames() {
        let defaults = UserDefaults.standard
        for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("NSWindow Frame ") {
            defaults.removeObject(forKey: key)
        }
    }

    // 关闭程序
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    /// App 启动完成（进程内只来一次）：排一次评分申请。
    ///
    /// ⚠️ 评分不要挂在 SwiftUI 根视图上：那儿有 `.task` / `scenePhase` 两个入口，
    /// 启动瞬间就申请时窗口还不是 key，StoreKit 会把请求挂起、反复投递，
    /// 用户看到的就是「一次启动弹好几次」。这里等「窗口上屏 + App 激活」再调一次，
    /// 见 `LaunchReviewRequester`。
    func applicationDidFinishLaunching(_ notification: Notification) {
        LaunchReviewRequester.requestOnceAfterLaunch()
    }
}

@main
struct EmotionVoiceApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .preferredColorScheme(.dark)
                .background(WindowAccessor())
        }
        .windowStyle(.hiddenTitleBar)
        .windowToolbarStyle(.unifiedCompact)
        // 让 AppKit 建窗时就用可视区域的尺寸，而不是 ContentView 的 minSize(1000×800)。
        // 这是消除「小窗→全屏」跳变的关键：尺寸在窗口上屏之前就已经是对的。
        .defaultSize(width: LaunchWindowSizing.defaultWindowSize.width,
                     height: LaunchWindowSizing.defaultWindowSize.height)
        .commands {
            CommandGroup(replacing: .newItem) { }
            // 实际触发走 DraftShortcutController 注册的全局热键（与焦点无关）。
            // 菜单项保留 ⌘S 显示 + 点击入口，并在热键未注册时兜底；Carbon 会先截走
            // 按键事件，正常情况下两条通道不会同时保存。
            CommandGroup(replacing: .saveItem) {
                Button("保存".localized()) {
                    DraftStore.shared.saveFromSharedVM()
                }
                .keyboardShortcut("s", modifiers: .command)
            }
        }
    }
}

/// 首屏窗口尺寸的唯一计算入口。
///
/// Scene 的 .defaultSize 和 WindowAccessor 的 frame 校正共用同一套规则，避免两处
/// 逻辑分叉导致窗口被二次调整（二次调整正是肉眼可见的跳动来源）。
private enum LaunchWindowSizing {
    /// 设计稿约定的最小可用尺寸，需与 ContentView 的 .frame(minWidth:minHeight:) 保持一致。
    static let designMinSize = NSSize(width: 1000, height: 800)

    /// App body 求值时机很早，NSScreen.main 有可能尚未就绪，给一个保守兜底。
    static var visibleFrame: NSRect {
        (NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
            ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
    }

    /// 极小屏按可视高度下限钳制最小高度，避免窗口被撑爆越界。
    static func minSize(forVisibleHeight height: CGFloat) -> NSSize {
        NSSize(width: designMinSize.width,
               height: max(640, min(designMinSize.height, height - 40)))
    }

    /// 铺满可视区域（排除菜单栏与 Dock）；可视区域比最小尺寸还小时退化为居中最小窗口。
    static func targetFrame(visible: NSRect, minSize: NSSize) -> NSRect {
        guard visible.width >= minSize.width, visible.height >= minSize.height else {
            let w = min(minSize.width, visible.width)
            let h = min(minSize.height, visible.height)
            return NSRect(x: visible.minX + (visible.width - w) / 2,
                          y: visible.minY + (visible.height - h) / 2,
                          width: w, height: h)
        }
        return visible
    }

    static var defaultWindowSize: CGSize {
        let visible = visibleFrame
        let frame = targetFrame(visible: visible,
                                minSize: minSize(forVisibleHeight: visible.height))
        return CGSize(width: frame.width, height: frame.height)
    }

    /// 像素级相等的 frame 不必再 setFrame，省掉一次无意义的 resize / 重绘。
    static func frameNeedsUpdate(_ current: NSRect, to target: NSRect) -> Bool {
        abs(current.origin.x - target.origin.x) > 0.5
            || abs(current.origin.y - target.origin.y) > 0.5
            || abs(current.width - target.width) > 0.5
            || abs(current.height - target.height) > 0.5
    }
}

/// 启动首帧保护。
///
/// 正常路径下 WindowAccessor 在窗口 orderFront 之前就完成配置，下面这段不会起作用。
/// 但若某次系统版本 / 启动路径让窗口先上屏，用户就会看到默认小窗再跳成全屏：
/// 此时先把窗口透明化，等配置完成（或超时兜底）再淡入，保证「一次出现即最终尺寸」。
private final class LaunchWindowCoordinator: NSObject {
    static let shared = LaunchWindowCoordinator()

    private var hidden = NSHashTable<NSWindow>.weakObjects()
    private var configured = NSHashTable<NSWindow>.weakObjects()
    private var isObserving = false
    private var handledFirstWindow = false
    private let armedAt = CFAbsoluteTimeGetCurrent()
    /// 配置回调万一没来，也不能让窗口一直透明。
    private let revealTimeout: TimeInterval = 0.8

    func start() {
        guard !isObserving else { return }
        isObserving = true
        // AppKit 没有 didBecomeVisible；主窗口在启动时成为 main / key 的两个通知
        // 都在 orderFront 过程中同步 post，用 selector 版可以在同一帧内把 alpha 置 0。
        for name in [NSWindow.didBecomeMainNotification, NSWindow.didBecomeKeyNotification] {
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(windowDidBecomeVisible(_:)),
                name: name,
                object: nil
            )
        }
    }

    @objc private func windowDidBecomeVisible(_ note: Notification) {
        guard let window = note.object as? NSWindow,
              !handledFirstWindow,
              !configured.contains(window),
              // 只兜「启动那一瞬」。窗口若是很久之后才成为 key/main，说明用户早已看到
              // 正常窗口，这时再去透明化反而会闪一下。
              CFAbsoluteTimeGetCurrent() - armedAt < 0.5,
              window.level == .normal,
              window.styleMask.contains(.titled),
              window.contentViewController != nil
        else { return }

        handledFirstWindow = true
        window.alphaValue = 0
        hidden.add(window)

        DispatchQueue.main.asyncAfter(deadline: .now() + revealTimeout) { [weak self, weak window] in
            guard let window else { return }
            self?.reveal(window)
        }
    }

    func windowConfigured(_ window: NSWindow) {
        configured.add(window)
        reveal(window)
    }

    private func reveal(_ window: NSWindow) {
        guard hidden.contains(window) else { return }
        hidden.remove(window)
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            window.animator().alphaValue = 1
        }
    }
}

/// 窗口外观 + 首屏最大化。
///
/// 负责三件与「界面可读 / 不被 Dock 遮挡」相关的事：
/// 1. 透明标题栏 + 自定义背景，保持设计稿的全屏深色观感；
/// 2. 约束最小尺寸（与 ContentView 的 .frame(minWidth:minHeight:) 对齐）；
/// 3. 把窗口对齐到「可视区域」（排除顶部菜单栏与底部 Dock）。
///
/// ⚠️ 配置刻意放在 `viewDidMoveToWindow` 里同步执行：makeNSView 时 view.window 还是 nil，
/// 旧实现用 `DispatchQueue.main.async` 推迟一拍，那一拍恰好落在窗口上屏之后，
/// 于是出现「先小窗、再变全屏」。现在窗口第一次拿到 window 引用时就配好，不跨 runloop。
private struct WindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { ConfiguringView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class ConfiguringView: NSView {
        private var didConfigure = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard !didConfigure, let window = self.window else { return }
            didConfigure = true
            configure(window)
        }

        private func configure(_ window: NSWindow) {
            // 标题栏透明，但保留 traffic light（关闭/最小化/缩放）
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.backgroundColor = NSColor(hex: 0x0E0F12)
            window.isMovableByWindowBackground = true

            // 关掉 SwiftUI 的 frame autosave：尺寸由本 app 每次启动决定，
            // 避免退出时又把某个中间态的 frame 存回去、下次启动恢复成小窗。
            if !window.frameAutosaveName.isEmpty {
                window.setFrameAutosaveName("")
            }

            let visible = (window.screen ?? NSScreen.main ?? NSScreen.screens.first)?.visibleFrame
                ?? LaunchWindowSizing.visibleFrame
            window.minSize = LaunchWindowSizing.minSize(forVisibleHeight: visible.height)
            let target = LaunchWindowSizing.targetFrame(visible: visible, minSize: window.minSize)

            // display:false —— 不强制同步重绘，交给紧随其后的首个绘制周期。
            if LaunchWindowSizing.frameNeedsUpdate(window.frame, to: target) {
                window.setFrame(target, display: false)
            }

            LaunchWindowCoordinator.shared.windowConfigured(window)
        }
    }
}

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1.0) {
        let r = CGFloat((hex >> 16) & 0xFF) / 255.0
        let g = CGFloat((hex >> 8) & 0xFF) / 255.0
        let b = CGFloat((hex >> 0) & 0xFF) / 255.0
        self.init(srgbRed: r, green: g, blue: b, alpha: alpha)
    }
}
