//
//  GenerationBackgroundKeeper.swift
//  iOSEmora
//
//  TTS 生成期间的后台执行保活。
//
//  ⚠️ 关键认知：`UIBackgroundModes` 现在只声明 audio（播放器后台播放所需），
//  **任何** background mode 都不能让 `URLSessionWebSocketTask` 在用户按 Home 之后继续收流：
//    - audio      只在真的在播放或录制音频时保活，生成阶段没有音频会话；
//    - fetch / processing 需要 `BGTaskScheduler` 注册任务 + 提交请求（processing 还要
//      `BGTaskSchedulerPermittedIdentifiers`），工程从未使用，原 plist 里是无效声明，已移除。
//
//  真正生效的是 `UIApplication.beginBackgroundTask`：它不需要任何
//  UIBackgroundModes 声明，在 app 进入后台后给一段连续的执行时间（通常约 30s，
//  以 `backgroundTimeRemaining` 为准）。这段时间里进程不被挂起，
//  `URLSessionWebSocketTask` 的 receive 就能继续拿分片。
//  `BailianTTSService` 侧只保留 `waitsForConnectivity`：
//  `shouldUseExtendedBackgroundIdleMode` 自 iOS 18.4 起已标记 Not supported，不再作为保 socket 手段。
//
//  边界：额度到期后系统会挂起进程，WebSocket 断线且**不可续传**（协议由边缘函数
//  驱动，重连只会拿到一条没有任务的空连接）。所以这里在到期 / 后台结束时
//  发一条本地通知，让用户知道该回前台或重新生成。长文本的可靠后台方案只能是
//  「服务端任务化 + 结果轮询 / 推送」，不能靠延长前台连接。
//

import UIKit
import UserNotifications

@MainActor
final class GenerationBackgroundKeeper {

    static let shared = GenerationBackgroundKeeper()

    private var taskID: UIBackgroundTaskIdentifier = .invalid
    private var isGenerating = false
    /// 后台额度是否被系统收回（到期后不再重复发「完成」通知）
    private var didExpire = false
    private var didAskNotificationAuthorization = false

    private init() {}

    // MARK: - 生命周期

    /// 生成开始。
    ///
    /// 在前台就申请 `beginBackgroundTask` 是刻意为之：系统只在 app 真正进入后台后
    /// 才开始计时，不必等 `didEnterBackgroundNotification`，也不会错过那一刻。
    func start() {
        guard !isGenerating else { return }
        isGenerating = true
        didExpire = false
        requestProvisionalNotificationIfNeeded()

        let id = UIApplication.shared.beginBackgroundTask(
            withName: "com.emotionvoice.tts.generate"
        ) { [weak self] in
            // expirationHandler 不在主线程保证内，回 MainActor 收尾
            guard let self else { return }
            Task { @MainActor in self.handleExpiration() }
        }
        taskID = id

        if id == .invalid {
            Log(message: "[BG] beginBackgroundTask 申请失败，本次后台接收不受保护")
        } else {
            Log(message: String(format: "[BG] 生成开始，后台可用额度约 %.0fs",
                                UIApplication.shared.backgroundTimeRemaining))
        }
    }

    /// 生成结束（成功 / 失败 / 用户取消都走这里）
    func finish(success: Bool) {
        guard isGenerating else { return }
        isGenerating = false
        let expired = didExpire
        didExpire = false
        endTask()

        // 到期提醒已经在 handleExpiration 里发过，不重复打扰
        guard !expired else { return }
        guard UIApplication.shared.applicationState != .active else { return }

//        notify(title: success ? "语音生成完成".localized() : "生成已结束".localized(),
//               body: "返回 App 查看结果".localized())
    }

    // MARK: - 到期

    private func handleExpiration() {
        guard isGenerating else { return }
        didExpire = true
        endTask()
        Log(message: "[BG] 后台执行时间到期，进程即将挂起，WebSocket 会被断开")

        // 主动断开比等 60s 请求超时更好：让生成流程尽快收敛（已有分片会按
        // BailianTTSService 既有容错策略落盘，回前台后由失败提示 / 弹窗体现）。
        BailianTTSService.shared.closeConnection()

//        guard UIApplication.shared.applicationState != .active else { return }
//        notify(title: "后台接收时间已用完".localized(),
//               body: "请返回 App 继续接收".localized())
    }

    private func endTask() {
        guard taskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(taskID)
        taskID = .invalid
    }

    // MARK: - 本地通知

    /// `.provisional` 是静默授权：不会弹权限框打断用户第一次点「生成」，
    /// 通知直接进通知中心；用户之后可在系统设置里自行升级为横幅。
    private func requestProvisionalNotificationIfNeeded() {
        guard !didAskNotificationAuthorization else { return }
        didAskNotificationAuthorization = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.provisional]) { _, _ in }
    }

    private func notify(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(
            identifier: "tts-generation-\(Int(Date().timeIntervalSince1970))",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request) { _ in }
    }
}
