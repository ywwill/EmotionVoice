//
//  EmotionVoiceApp.swift
//  EmotionVoice
//
//  Created by young on 2026/8/8.
//

import SwiftUI

class AppDelegate: NSObject, NSApplicationDelegate {
    
    // 关闭程序
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
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
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}

/// 窗口外观 + 首屏最大化。
///
/// 负责三件与「界面可读 / 不被 Dock 遮挡」相关的事：
/// 1. 透明标题栏 + 自定义背景，保持设计稿的全屏深色观感；
/// 2. 约束最小尺寸（与 ContentView 的 .frame(minWidth:minHeight:) 对齐）；
/// 3. **每次 app 打开都把窗口铺满「可视区域」**（排除顶部菜单栏与底部 Dock），
///    既不落到 Dock 后面，也不会让内容被窗口裁切。
private struct WindowAccessor: NSViewRepresentable {
    /// 设计稿约定的最小可用尺寸，需与 ContentView 的 .frame(minWidth:minHeight:) 保持一致。
    private static let designMinSize = NSSize(width: 1000, height: 800)

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }

            // 标题栏透明，但保留 traffic light（关闭/最小化/缩放）
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.backgroundColor = NSColor(hex: 0x0E0F12)
            window.isMovableByWindowBackground = true

            // 最小尺寸与 ContentView 对应；极小屏按可视高度下限钳制，避免被撑爆越界。
            let visibleHeight = (window.screen ?? NSScreen.main)?.visibleFrame.height
            let minHeight = visibleHeight.map { max(640, min(Self.designMinSize.height, $0 - 40)) }
                                      ?? Self.designMinSize.height
            window.minSize = NSSize(width: Self.designMinSize.width, height: minHeight)

            // 首屏：铺满可视区域（菜单栏与 Dock 之外的全部可用空间）。
            // 极小屏若可视区域比最小尺寸还小，退化为居中放置最小尺寸窗口，避免越界。
            if let visible = (window.screen ?? NSScreen.main)?.visibleFrame {
                var frame = visible
                if visible.width < window.minSize.width || visible.height < window.minSize.height {
                    let w = min(window.minSize.width, visible.width)
                    let h = min(window.minSize.height, visible.height)
                    frame = CGRect(x: visible.minX + (visible.width - w) / 2,
                                   y: visible.minY + (visible.height - h) / 2,
                                   width: w, height: h)
                }
                window.setFrame(frame, display: true, animate: false)
            }
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

extension NSColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1.0) {
        let r = CGFloat((hex >> 16) & 0xFF) / 255.0
        let g = CGFloat((hex >> 8) & 0xFF) / 255.0
        let b = CGFloat((hex >> 0) & 0xFF) / 255.0
        self.init(srgbRed: r, green: g, blue: b, alpha: alpha)
    }
}
