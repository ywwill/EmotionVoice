//
//  EmotionVoiceApp.swift
//  EmotionVoice
//
//  Created by young on 2026/8/8.
//

import SwiftUI

@main
struct EmotionVoiceApp: App {

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
            CommandGroup(replacing: .newItem) {
                Button("新建项目".localized()) {
                    _ = ProjectService.shared.createProject(
                        name: "未命名项目".localized() + " " + Date().shortDateString,
                        folder: nil
                    )
                }
                .keyboardShortcut("n")
            }
        }
    }
}

/// 让窗口背景融入设计（透明标题栏 + 保留 traffic light 可交互）
private struct WindowAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            if let window = view.window {
                // 标题栏透明，但保留 traffic light（关闭/最小化/缩放）
                window.titlebarAppearsTransparent = true
                window.titleVisibility = .hidden
                window.backgroundColor = NSColor(hex: 0x0E0F12)
                window.isMovableByWindowBackground = true
                // 设置窗口尺寸约束，允许缩放
                window.minSize = NSSize(width: 1200, height: 900)
                window.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
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
