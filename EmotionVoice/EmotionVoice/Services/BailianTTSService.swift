//
//  BailianTTSService.swift
//  EmotionVoice
//
//  阿里云百炼语音合成服务 - 流式版本（经 Supabase Edge Function 代理）
//
//  通道：客户端 ←WebSocket→ supabase/functions/bailian-tts ←WebSocket→ 阿里云百炼
//
//  百炼的 API Key / WorkspaceId / 模型协议（run-task → continue-task → finish-task、
//  控制类标签切段）都在边缘函数里，客户端只发一次 `synthesize` 请求，
//  然后原样消费上游转发回来的事件（`task-started`/`result-generated`/`task-finished`）
//  与二进制音频分片。
//
//  使用 URLSessionWebSocketTask，支持连接复用。
//

import Foundation
import AVFoundation

// MARK: - 常量定义

/// 阿里云百炼 TTS 服务（经 Supabase Edge Function 代理）
final class BailianTTSService {

    static let shared = BailianTTSService()

    // MARK: - 状态
    private var webSocketTask: URLSessionWebSocketTask?
    private var urlSession: URLSession?
    private var isConnected = false
    private var currentTaskId: String?

    // 连接复用锁
    private let connectionLock = NSLock()

    private init() {}

    // MARK: - 公开接口

    /// 语音合成（流式接收）
    func synthesize(
        text: String,
        voice: String,
        emotion: String? = nil,
        rate: Double = 1.0,
        volume: Double = 100,
        sampleRate: Int = 48000,
        format: String = "wav",
        nlInstruction: String? = nil
    ) async throws -> Data {
        return try await withCheckedThrowingContinuation { continuation in
            synthesizeStream(
                text: text,
                voice: voice,
                emotion: emotion,
                rate: rate,
                volume: volume,
                sampleRate: sampleRate,
                format: format,
                nlInstruction: nlInstruction,
                onAudio: nil,
                completion: { result in
                    continuation.resume(with: result)
                }
            )
        }
    }

    /// 语音合成（流式接收，带实时回调）
    func synthesizeStream(
        text: String,
        voice: String,
        emotion: String? = nil,
        rate: Double = 1.0,
        volume: Double = 100,
        sampleRate: Int = 48000,
        format: String = "wav",
        nlInstruction: String? = nil,
        onAudio: ((Data) -> Void)? = nil,
        completion: @escaping (Result<Data, Error>) -> Void
    ) {
        Task {
            do {
                let audioData = try await synthesizeAsync(
                    text: text,
                    voice: voice,
                    emotion: emotion,
                    rate: rate,
                    volume: volume,
                    sampleRate: sampleRate,
                    format: format,
                    nlInstruction: nlInstruction,
                    onAudio: onAudio
                )
                completion(.success(audioData))
            } catch {
                completion(.failure(error))
            }
        }
    }

    /// 异步语音合成
    private func synthesizeAsync(
        text: String,
        voice: String,
        emotion: String?,
        rate: Double,
        volume: Double,
        sampleRate: Int,
        format: String,
        nlInstruction: String?,
        onAudio: ((Data) -> Void)?
    ) async throws -> Data {
        // 关键不变量：同一时刻只允许一个 TTS 任务占用 WebSocket。
        // 原实现使用 NSLock，但 NSLock 跨 await 持有会触发 Swift 6 诊断。
        // 这里改为基于 actor 的异步互斥，跨 await 安全且不会死锁。
        try await ttsPipeline.run {
            try await self.performSynthesize(
                text: text,
                voice: voice,
                emotion: emotion,
                rate: rate,
                volume: volume,
                sampleRate: sampleRate,
                format: format,
                nlInstruction: nlInstruction,
                onAudio: onAudio
            )
        }
    }

    /// 异步 FIFO 互斥器：保证闭包按到达顺序串行执行。
    /// 基于 actor 的"忙/闲"标志 + 等待队列。
    /// 任意时刻只有一个调用方能进入临界区，其余按 FIFO 等待。
    actor AsyncMutex {
        private var isBusy: Bool = false
        private var waiters: [CheckedContinuation<Void, Never>] = []

        /// 进入临界区执行 work；同一时刻只允许一个执行。
        func run<T>(_ work: () async throws -> T) async rethrows -> T {
            if isBusy {
                await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
                    waiters.append(cont)
                }
            }
            isBusy = true
            defer {
                isBusy = false
                if !waiters.isEmpty {
                    let next = waiters.removeFirst()
                    next.resume()
                }
            }
            return try await work()
        }
    }

    private let ttsPipeline = AsyncMutex()

    /// 实际 TTS 任务体（在持有 ttsPipeline 串行权限的前提下执行）
    private func performSynthesize(
        text: String,
        voice: String,
        emotion: String?,
        rate: Double,
        volume: Double,
        sampleRate: Int,
        format: String,
        nlInstruction: String?,
        onAudio: ((Data) -> Void)?
    ) async throws -> Data {
        // 生成任务 ID（仅同步修改本地状态，无需长持锁）
        let taskId = UUID().uuidString
        connectionLock.lock()
        currentTaskId = taskId
        connectionLock.unlock()

        var completeAudioData = Data()

        // 确保 WebSocket 连接
        try await ensureConnection()

        // 一次性把参数交给边缘函数：
        // run-task / 控制类标签切段 / continue-task / finish-task 由服务端完成
        let request = buildSynthesizeRequest(
            taskId: taskId,
            text: text,
            voice: voice,
            emotion: emotion,
            rate: rate,
            volume: volume,
            sampleRate: sampleRate,
            format: format,
            instruction: nlInstruction
        )

        // DEBUG: 输出文本（>200 字符时截断显示）便于排查「多标签只生效一个」问题
        let preview: String
        if text.count > 200 {
            preview = String(text.prefix(200)) + "...（共 \(text.count) 字符）"
        } else {
            preview = text
        }
        Log(message: "发送 synthesize 请求，voice=\(voice) 文本长度: \(text.count) 字符")
        Log(message: "  完整文本: \(preview)")

        try await sendMessage(request)

        // 等待 task-started 事件
        try await waitForTaskStarted()

        // 接收音频流（不逐帧打日志：分片很密，刷屏且没信息量）
        var isTaskFinished = false

        while !isTaskFinished {
            do {
                // 直接接收消息，根据类型处理
                let message = try await receive()

                if let jsonText = message.text {
                    // JSON 文本消息：只关心任务级事件，中间过程事件直接忽略
                    if let json = try? JSONSerialization.jsonObject(with: jsonText.data(using: .utf8)!) as? [String: Any],
                       let event = (json["header"] as? [String: Any])?["event"] as? String {

                        switch event {
                        case "task-finished":
                            isTaskFinished = true

                        case "task-failed":
                            isTaskFinished = true
                            let errorCode = (json["header"] as? [String: Any])?["error_code"] as? String ?? "Unknown"
                            let errorMessage = (json["header"] as? [String: Any])?["error_message"] as? String ?? "Unknown error"
                            throw TTSError.serverError("[\(errorCode)] \(errorMessage)")

                        default:
                            break
                        }
                    }
                } else if let binaryData = message.binaryData {
                    if !binaryData.isEmpty {
                        completeAudioData.append(binaryData)
                        onAudio?(binaryData)
                    }
                }

            } catch {
                Log(message: "接收消息出错: \(error.localizedDescription)")
                if completeAudioData.isEmpty {
                    throw error
                }
                isTaskFinished = true
            }
        }

        if completeAudioData.isEmpty {
            throw TTSError.noAudioData
        }

        // 音频生成完成后主动断开连接，下次使用时再重新建立
        closeConnectionInternal()

        // 诊断：音频头是否正常（WAV 以 RIFF 开头；合并多段时最容易在这里出错）
        let hasRIFFHeader = completeAudioData.count >= 4 &&
            completeAudioData[0] == 0x52 && // R
            completeAudioData[1] == 0x49 && // I
            completeAudioData[2] == 0x46 && // F
            completeAudioData[3] == 0x46    // F
        Log(message: "音频生成完成: \(completeAudioData.count) bytes, hasRIFFHeader=\(hasRIFFHeader)，已断开 WebSocket 连接")

        return completeAudioData
    }

    // MARK: - 消息接收结果

    private struct ReceivedMessage {
        var text: String?
        var binaryData: Data?
    }

    // MARK: - 请求构建

    /// 交给边缘函数的一次性合成请求。
    ///
    /// 文本里的 `[happy]` / `[laughing]` 等标签原样上传，由服务端
    /// 做「无标签时补 emotion」与「按控制类标签切段」两件事。
    private func buildSynthesizeRequest(
        taskId: String,
        text: String,
        voice: String,
        emotion: String?,
        rate: Double,
        volume: Double,
        sampleRate: Int,
        format: String,
        instruction: String?
    ) -> String {
        var payload: [String: Any] = [
            "action": "synthesize",
            "task_id": taskId,
            "text": text,
            "voice": voice,
            "rate": rate,
            "volume": volume,
            "sample_rate": sampleRate,
            "format": format.lowercased()
        ]

        if let emotion = emotion, !emotion.isEmpty {
            payload["emotion"] = emotion
        }
        if let instruction = instruction, !instruction.isEmpty {
            payload["instruction"] = instruction
        }

        return serializeToJson(payload)
    }

    private func serializeToJson(_ dict: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: []),
              let jsonString = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return jsonString
    }

    // MARK: - WebSocket 管理

    private func ensureConnection() async throws {
        if isConnected && webSocketTask != nil {
            Log(message: "复用现有 WebSocket 连接")
            return
        }

        closeConnectionInternal()

        let endpoint = try TTSEndpoint.current()
        // 日志里不要把 secret 打出来
        Log(message: "[WS CONNECT] 建立 WebSocket 连接: \(endpoint.url.absoluteString)")

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 300

        urlSession = URLSession(configuration: config)

        var request = URLRequest(url: endpoint.url)
        for (name, value) in endpoint.headers {
            request.setValue(value, forHTTPHeaderField: name)
        }

        webSocketTask = urlSession?.webSocketTask(with: request)
        webSocketTask?.resume()

        isConnected = true
        Log(message: "[WS CONNECT] 连接已建立")
    }

    private func sendMessage(_ message: String) async throws {
        guard let webSocketTask = webSocketTask else {
            throw TTSError.connectionError
        }

        // 打印发送的 WebSocket 消息（不打印整包，避免文本过长）
        if let json = try? JSONSerialization.jsonObject(with: message.data(using: .utf8)!) as? [String: Any],
           let action = json["action"] as? String {
            Log(message: "[WS SEND] action=\(action)")
        } else {
            Log(message: "[WS SEND] \(message.prefix(120))")
        }

        let wsMessage = URLSessionWebSocketTask.Message.string(message)
        try await webSocketTask.send(wsMessage)
    }

    private func receive() async throws -> ReceivedMessage {
        guard let webSocketTask = webSocketTask else {
            throw TTSError.connectionError
        }

        do {
            let message = try await webSocketTask.receive()

            switch message {
            case .string(let text):
                return ReceivedMessage(text: text, binaryData: nil)

            case .data(let data):
                return ReceivedMessage(text: nil, binaryData: data)

            @unknown default:
                return ReceivedMessage(text: nil, binaryData: nil)
            }
        } catch {
            // 协议由边缘函数驱动（run-task / continue-task / finish-task 都在服务端），
            // 连接一旦断开无法"重连续传"——重连只会拿到一条没有任务的空连接。
            // 这里如实上抛，由调用方按「已有音频就接受、一点没有就报错」处理。
            Log(message: "[WS ERROR] WebSocket 接收消息失败: \(error.localizedDescription)")
            throw error
        }
    }

    private func waitForTaskStarted() async throws {
        var receivedTaskStarted = false

        while !receivedTaskStarted {
            let received = try await receive()

            if let text = received.text {
                if let data = text.data(using: .utf8),
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let event = (json["header"] as? [String: Any])?["event"] as? String {
                    if event == "task-started" {
                        receivedTaskStarted = true
                        Log(message: "收到 task-started 事件")
                    } else if event == "task-failed" {
                        let errorMessage = (json["header"] as? [String: Any])?["error_message"] as? String ?? "Unknown error"
                        throw TTSError.serverError(errorMessage)
                    }
                }
            }
            // 忽略二进制消息（理论上不应该在 task-started 之前出现）
        }
    }

    private func closeConnectionInternal() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        urlSession?.invalidateAndCancel()
        urlSession = nil
        isConnected = false
        currentTaskId = nil
    }

    func closeConnection() {
        connectionLock.lock()
        defer { connectionLock.unlock() }

        closeConnectionInternal()
        Log(message: "WebSocket 连接已关闭")
    }

    func ping() {
        guard isConnected, let webSocketTask = webSocketTask else { return }
        webSocketTask.sendPing { error in
            if let error = error {
                Log(message: "Ping failed: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - 错误类型

enum TTSError: LocalizedError {
    case connectionError
    case invalidRequest
    case serverError(String)
    case noAudioData
    case timeout

    var errorDescription: String? {
        switch self {
        case .connectionError:
            return "无法连接到语音合成服务"
        case .invalidRequest:
            return "无效的请求参数"
        case .serverError(let message):
            return "服务器错误: \(message)"
        case .noAudioData:
            return "未收到音频数据"
        case .timeout:
            return "请求超时"
        }
    }
}

// MARK: - 便捷扩展

extension BailianTTSService {

    func synthesize(text: String, voice: String) async throws -> Data {
        return try await synthesize(
            text: text,
            voice: voice,
            rate: 1.0,
            volume: 100,
            sampleRate: 48000
        )
    }

    func synthesizeAndSave(
        text: String,
        voice: String,
        emotion: String? = nil,
        rate: Double = 1.0,
        volume: Double = 100,
        sampleRate: Int = 48000,
        nlInstruction: String? = nil,
        to url: URL
    ) async throws -> URL {
        let audioData = try await synthesize(
            text: text,
            voice: voice,
            emotion: emotion,
            rate: rate,
            volume: volume,
            sampleRate: sampleRate,
            nlInstruction: nlInstruction
        )

        try audioData.write(to: url)
        Log(message: "音频已保存到: \(url.path)")

        return url
    }
}
