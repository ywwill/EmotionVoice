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
                language: language,
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
        language: String,
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

        // DEBUG: 输出完整文本（>200 字符时截断显示）便于排查「多标签只生效一个」问题
        let preview: String
        if processedText.count > 200 {
            preview = String(processedText.prefix(200)) + "...（共 \(processedText.count) 字符）"
        } else {
            preview = processedText
        }
        Log(message: "发送 continue-task 事件，文本长度: \(processedText.count) 字符")
        Log(message: "  完整文本: \(preview)")

        // 关键修复：百炼 TTS 在单次请求中可能只识别第一个控制类标签和第一个富语言类标签，
        // 后续标签会被静默忽略。把文本按控制类标签拆成多个 segment，
        // 每个 segment 独立发送一次 continue-task，由 API 独立解析。
        let segments = splitTextByControlTags(processedText)
        Log(message: "  拆分为 \(segments.count) 个 segment:")
        for (idx, seg) in segments.enumerated() {
            Log(message: "    [\(idx+1)/\(segments.count)] \(seg)")
        }

        // 逐个发送 continue-task 事件
        for segment in segments {
            let continueTaskEvent = buildContinueTaskEvent(taskId: taskId, text: segment)
            try await sendMessage(continueTaskEvent)
        }

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
                                    // 记录每个句子如何被 API 切分，帮助排查标签未生效问题
                                    if let sentence = outputData["sentence"] as? [String: Any] {
                                        let originalText = sentence["original_text"] as? String ?? ""
                                        let textLen = originalText.count
                                        Log(message: "[API切分] sentence-begin: 长度=\(textLen), 前100字=\(String(originalText.prefix(100)))")
                                    } else {
                                        // 找不到 sentence/original_text 时，打印完整结构
                                        Log(message: "[API切分] sentence-begin: outputData keys=\(outputData.keys.sorted())")
                                    }
                                case "sentence-end":
                                    if let sentence = outputData["sentence"] as? [String: Any] {
                                        let originalText = sentence["original_text"] as? String ?? ""
                                        let textLen = originalText.count
                                        Log(message: "[API切分] sentence-end: 长度=\(textLen), 前100字=\(String(originalText.prefix(100)))")
                                    } else {
                                        Log(message: "[API切分] sentence-end: outputData keys=\(outputData.keys.sorted())")
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

    /// 例子：
    ///   输入: `[panicked]虽然…精简，[angry]其他…体验 [cough] [crying]几行…跑起来 [laughing]`
    ///   输出:
    ///     - "[panicked]虽然…精简，"
    ///     - "[angry]其他…体验 [cough]"
    ///     - "[crying]几行…跑起来 [laughing]"
    private func splitTextByControlTags(_ text: String) -> [String] {
        // 富语言类标签集合（用于区分控制 vs 富语言）
        let richLanguageSet: Set<String> = Set(Constants.richLanguageTags.map { $0.tag })

        struct Item {
            enum Kind { case control, rich, text }
            let kind: Kind
            let value: String
        }

        let pattern = "\\[([^\\]]+)\\]"
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return [text]
        }
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)

        // 1) 用正则把 text 切成 [tag] / 普通文本 两类 item
        var items: [Item] = []
        var cursor = 0

        for match in regex.matches(in: text, range: fullRange) {
            let openLoc = match.range.location
            let closeEnd = match.range.upperBound
            let labelRange = match.range(at: 1)
            guard let swiftRange = Range(labelRange, in: text) else { continue }
            let label = String(text[swiftRange])
            let tagStr = "[\(label)]"

            if openLoc > cursor {
                let textPart = nsText.substring(with: NSRange(location: cursor, length: openLoc - cursor))
                if !textPart.isEmpty {
                    items.append(Item(kind: .text, value: textPart))
                }
            }

            let kind: Item.Kind = richLanguageSet.contains(label) ? .rich : .control
            items.append(Item(kind: kind, value: tagStr))

            cursor = closeEnd
        }
        if cursor < nsText.length {
            let tail = nsText.substring(from: cursor)
            if !tail.isEmpty {
                items.append(Item(kind: .text, value: tail))
            }
        }

        // 2) 按控制类标签分组
        //    - 遇到 control: 提交当前 segment，开始新 segment
        //    - 遇到 rich/text: 累加到当前 segment 末尾
        var segments: [String] = []
        var currentControl: String? = nil
        var currentBody: String = ""

        func flush() {
            let combined = (currentControl ?? "") + currentBody
            let trimmed = combined.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                segments.append(combined)
            }
            currentControl = nil
            currentBody = ""
        }

        for item in items {
            switch item.kind {
            case .control:
                flush()
                currentControl = item.value
            case .rich, .text:
                currentBody.append(item.value)
            }
        }
        flush()

        return segments.isEmpty ? [text] : segments
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
