//
//  BailianTTSService.swift
//  EmotionVoice
//
//  阿里云百炼语音合成服务 - 流式版本
//  使用 URLSessionWebSocketTask，支持连接复用
//

import Foundation
import AVFoundation

// MARK: - 常量定义

/// 阿里云百炼 TTS 服务
final class BailianTTSService {

    static let shared = BailianTTSService()

    // MARK: - 配置
    private let model = "qwen-audio-3.0-tts-plus"

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
        language: String = "mandarin",
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
                language: language,
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
        language: String = "mandarin",
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
                    language: language,
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
        language: String,
        nlInstruction: String?,
        onAudio: ((Data) -> Void)?
    ) async throws -> Data {
        connectionLock.lock()
        defer { connectionLock.unlock() }

        // 生成任务 ID
        let taskId = UUID().uuidString
        currentTaskId = taskId

        var completeAudioData = Data()

        // 确保 WebSocket 连接
        try await ensureConnection()

        // 构建 run-task 事件
        let runTaskEvent = buildRunTaskEvent(
            taskId: taskId,
            voice: voice,
            rate: rate,
            volume: volume,
            sampleRate: sampleRate,
            instruction: nlInstruction
        )

        Log(message: "发送 run-task 事件，task_id: \(taskId)")

        // 发送 run-task
        try await sendMessage(runTaskEvent)

        // 等待 task-started 事件
        try await waitForTaskStarted()

        // 准备待合成的文本（添加情感标签）
        let processedText = processTextWithEmotion(text: text, emotion: emotion)

        Log(message: "发送 continue-task 事件，文本长度: \(processedText.count) 字符")

        // 发送 continue-task 事件
        let continueTaskEvent = buildContinueTaskEvent(taskId: taskId, text: processedText)
        try await sendMessage(continueTaskEvent)

        // 发送 finish-task 事件
        Log(message: "发送 finish-task 事件")
        let finishTaskEvent = buildFinishTaskEvent(taskId: taskId)
        try await sendMessage(finishTaskEvent)

        // 接收音频流
        var isTaskFinished = false

        while !isTaskFinished {
            do {
                // 直接接收消息，根据类型处理
                let message = try await receive()

                if let jsonText = message.text {
                    // JSON 文本消息
                    if let json = try? JSONSerialization.jsonObject(with: jsonText.data(using: .utf8)!) as? [String: Any],
                       let event = (json["header"] as? [String: Any])?["event"] as? String {
                        
                        switch event {
                        case "task-finished":
                            isTaskFinished = true
                            if let usage = json["payload"] as? [String: Any],
                               let usageInfo = usage["usage"] as? [String: Any],
                               let chars = usageInfo["characters"] as? Int {
                                Log(message: "任务完成，累计字符数: \(chars)")
                            }

                        case "result-generated":
                            if let output = json["payload"] as? [String: Any],
                               let outputData = output["output"] as? [String: Any],
                               let type = outputData["type"] as? String {
                                switch type {
                                case "sentence-begin":
                                    if let sentence = outputData["sentence"] as? [String: Any],
                                       let originalText = sentence["original_text"] as? String {
                                        Log(message: "句子开始: \(originalText.prefix(20))...")
                                    }
                                case "sentence-end":
                                    if let sentence = outputData["sentence"] as? [String: Any],
                                       let originalText = sentence["original_text"] as? String {
                                        Log(message: "句子结束: \(originalText.prefix(20))...")
                                    }
                                case "sentence-synthesis":
                                    // 音频通过 binary 通道接收
                                    break
                                default:
                                    break
                                }
                            }

                        case "task-failed":
                            isTaskFinished = true
                            let errorCode = (json["header"] as? [String: Any])?["error_code"] as? String ?? "Unknown"
                            let errorMessage = (json["header"] as? [String: Any])?["error_message"] as? String ?? "Unknown error"
                            throw TTSError.serverError("[\(errorCode)] \(errorMessage)")

                        default:
                            Log(message: "收到未知事件: \(event)")
                            break
                        }
                    }
                } else if let binaryData = message.binaryData {
                    // 二进制音频数据
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

        Log(message: "收到音频数据: \(completeAudioData.count) bytes")
        return completeAudioData
    }

    // MARK: - 消息接收结果

    private struct ReceivedMessage {
        var text: String?
        var binaryData: Data?
    }

    // MARK: - 文本处理

    /// 处理文本，添加情感标签
    private func processTextWithEmotion(text: String, emotion: String?) -> String {
        // 如果已有 [emotion] 格式的标签，直接返回
        if text.contains("[") && text.contains("]") {
            return text
        }

        // 如果有情感标签，在开头添加
        if let emotion = emotion, !emotion.isEmpty {
            return "[\(emotion)]\(text)"
        }

        return text
    }

    // MARK: - 事件构建

    private func buildRunTaskEvent(
        taskId: String,
        voice: String,
        rate: Double,
        volume: Double,
        sampleRate: Int,
        instruction: String?
    ) -> String {
        var parameters: [String: Any] = [
            "text_type": "PlainText",
            "voice": voice,
            "format": "wav",
            "sample_rate": sampleRate,
            "volume": Int(volume),
            "rate": rate,
            "pitch": 1.0,
            "enable_ssml": false
        ]

        if let instruction = instruction, !instruction.isEmpty {
            parameters["instruction"] = instruction
        }

        let event: [String: Any] = [
            "header": [
                "action": "run-task",
                "task_id": taskId,
                "streaming": "duplex"
            ],
            "payload": [
                "task_group": "audio",
                "task": "tts",
                "function": "SpeechSynthesizer",
                "model": model,
                "parameters": parameters,
                "input": [:] as [String: Any]
            ]
        ]

        return serializeToJson(event)
    }

    private func buildContinueTaskEvent(taskId: String, text: String) -> String {
        let event: [String: Any] = [
            "header": [
                "action": "continue-task",
                "task_id": taskId,
                "streaming": "duplex"
            ],
            "payload": [
                "input": [
                    "text": text
                ]
            ]
        ]

        return serializeToJson(event)
    }

    private func buildFinishTaskEvent(taskId: String) -> String {
        let event: [String: Any] = [
            "header": [
                "action": "finish-task",
                "task_id": taskId,
                "streaming": "duplex"
            ],
            "payload": [
                "input": [:] as [String: Any]
            ]
        ]

        return serializeToJson(event)
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

        let wsUrl = RegionManager.shared.wsUrl
        Log(message: "建立 WebSocket 连接: \(wsUrl)")

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 300

        urlSession = URLSession(configuration: config)
        guard let url = URL(string: wsUrl) else {
            throw TTSError.connectionError
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(RegionManager.shared.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        webSocketTask = urlSession?.webSocketTask(with: request)
        webSocketTask?.resume()

        isConnected = true
    }

    private func sendMessage(_ message: String) async throws {
        guard let webSocketTask = webSocketTask else {
            throw TTSError.connectionError
        }

        let wsMessage = URLSessionWebSocketTask.Message.string(message)
        try await webSocketTask.send(wsMessage)
    }

    private func receive() async throws -> ReceivedMessage {
        guard let webSocketTask = webSocketTask else {
            throw TTSError.connectionError
        }

        let message = try await webSocketTask.receive()

        switch message {
        case .string(let text):
            return ReceivedMessage(text: text, binaryData: nil)

        case .data(let data):
            return ReceivedMessage(text: nil, binaryData: data)

        @unknown default:
            return ReceivedMessage(text: nil, binaryData: nil)
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
            sampleRate: 48000,
            language: "mandarin"
        )
    }

    func synthesizeAndSave(
        text: String,
        voice: String,
        emotion: String? = nil,
        rate: Double = 1.0,
        volume: Double = 100,
        sampleRate: Int = 48000,
        language: String = "mandarin",
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
            language: language,
            nlInstruction: nlInstruction
        )

        try audioData.write(to: url)
        Log(message: "音频已保存到: \(url.path)")

        return url
    }
}
