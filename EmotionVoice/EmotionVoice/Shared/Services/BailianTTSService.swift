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

    /// NSLock 的 lock()/unlock() 在 Swift 6 里不允许出现在 async 函数体中
    /// （跨 await 持锁可能死锁）。把所有加锁收敛到这个同步 scoped helper，
    /// async 调用方只传一个不跨 await 的闭包。
    private func withConnectionLock<T>(_ body: () throws -> T) rethrows -> T {
        connectionLock.lock()
        defer { connectionLock.unlock() }
        return try body()
    }

    private init() {}

    // MARK: - 公开接口

    // ⚠️ 下面两个入口的默认实参一律读 `Constants`：默认音频格式 / 采样率的
    // 唯一数据源在 `Constants.defaultFormat` / `Constants.defaultSampleRate`
    // （当前为 mp3 / 22050Hz）。别在这里写死 "wav" / 48000 —— 设置页与工作台
    // 都已经跟随常量，写死会让「省略参数」的调用路径悄悄用回旧默认值。
    // 正常生成流程会把 vm 里的四项显式传进来，默认实参只是兜底。

    /// 语音合成（流式接收）
    func synthesize(
        text: String,
        voice: String,
        emotion: String? = nil,
        rate: Double = 1.0,
        volume: Double = 100,
        sampleRate: Int = Constants.defaultSampleRate,
        format: String = Constants.defaultFormat,
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

    /// 一次合成的完整结果（音频 + 上游返回的字级时间戳）
    ///
    /// `sentences` 里的时间是**本次请求音频内的绝对毫秒**，已经过时钟重启归一化；
    /// 若整段文本被切多次请求，调用方（VoiceStudioViewModel）须按每段音频实际
    /// 时长累加段偏移，再落进 sidecar。
    struct TTSGeneration {
        let audioData: Data
        let sentences: [AudioSentenceCue]
    }

    /// 正式生成入口：开启 `word_timestamp_enabled` 并收集 sentence-end 的 words[]。
    ///
    /// 只有部分音色支持字级时间戳；上游明确拒绝时自动**降级重跑一次**（不带该参数），
    /// 返回空 sentences，播放器会走「静态原文」降级态，绝不让整次生成失败。
    func synthesizeWithTimeline(
        text: String,
        voice: String,
        emotion: String? = nil,
        rate: Double = 1.0,
        volume: Double = 100,
        sampleRate: Int = Constants.defaultSampleRate,
        format: String = Constants.defaultFormat,
        nlInstruction: String? = nil,
        /// 选中语言对应的 language_hints 单个取值（如 "en"）；nil = 不下发。
        languageHint: String? = nil,
        onAudio: ((Data) -> Void)? = nil,
        /// 同一段文本的「用户原文」形态（不含 `[emotion]` 前缀），仅用于给字级字幕
        /// 重新分配文本；传 nil 时退回上游 `original_text`。
        displaySource: String? = nil
    ) async throws -> TTSGeneration {
        do {
            return try await runSynthesize(
                text: text, voice: voice, emotion: emotion, rate: rate,
                volume: volume, sampleRate: sampleRate, format: format,
                nlInstruction: nlInstruction, languageHint: languageHint, onAudio: onAudio,
                wordTimestampEnabled: true, displaySource: displaySource
            )
        } catch let error as TTSError {
            guard case .timestampUnsupported = error else { throw error }
            Log(message: "当前音色不支持字级时间戳，降级为普通合成重试一次")
            return try await runSynthesize(
                text: text, voice: voice, emotion: emotion, rate: rate,
                volume: volume, sampleRate: sampleRate, format: format,
                nlInstruction: nlInstruction, languageHint: languageHint, onAudio: onAudio,
                wordTimestampEnabled: false, displaySource: displaySource
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
        sampleRate: Int = Constants.defaultSampleRate,
        format: String = Constants.defaultFormat,
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

    /// 异步语音合成（试听 / 旧调用点：不开时间戳，只取音频）
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
        try await runSynthesize(
            text: text, voice: voice, emotion: emotion, rate: rate,
            volume: volume, sampleRate: sampleRate, format: format,
            nlInstruction: nlInstruction, languageHint: nil, onAudio: onAudio,
            wordTimestampEnabled: false
        ).audioData
    }

    /// 所有合成路径的唯一入口：先抢 ttsPipeline 串行权限，再跑一次完整任务。
    private func runSynthesize(
        text: String,
        voice: String,
        emotion: String?,
        rate: Double,
        volume: Double,
        sampleRate: Int,
        format: String,
        nlInstruction: String?,
        languageHint: String?,
        onAudio: ((Data) -> Void)?,
        wordTimestampEnabled: Bool,
        displaySource: String? = nil
    ) async throws -> TTSGeneration {
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
                languageHint: languageHint,
                onAudio: onAudio,
                wordTimestampEnabled: wordTimestampEnabled,
                displaySource: displaySource
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
        languageHint: String?,
        onAudio: ((Data) -> Void)?,
        wordTimestampEnabled: Bool,
        displaySource: String? = nil
    ) async throws -> TTSGeneration {
        // 生成任务 ID（仅同步修改本地状态，无需长持锁）
        let taskId = UUID().uuidString
        withConnectionLock { currentTaskId = taskId }

        // 成功 / 失败 / 降级重试前都必须断开：边缘函数在 task-failed 后会关连接，
        // 留着这条已死的 socket 会让下一次 ensureConnection() 误判「可复用」。
        defer { closeConnectionInternal() }

        var completeAudioData = Data()
        /// 上游按句子推送的 sentence-end，稍后统一归一化成段内绝对时间
        var sentenceEnds: [AudioSentenceCue] = []

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
            instruction: nlInstruction,
            languageHint: languageHint,
            wordTimestampEnabled: wordTimestampEnabled
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

        // 「建连 → 发 run-task → 等 task-started」是整条链路最脆的一段：
        // 日志里那种 `-1200 / errSSLClosedNoNotify / ECONNRESET with incomplete TLS handshake`
        // 就是 TCP 在 TLS 握手途中被对端或中间设备关掉，纯瞬时的网络抖动，
        // 跟参数、音色、时间戳都无关。
        // 此刻上游还没建任务、本地也没有任何音频，所以整段重来一次是安全的 ——
        // 比直接把「TLS错误导致安全连接失败」弹给用户要好得多。
        var connectionAttempt = 0
        while true {
            do {
                try await startTask(request: request, wordTimestampEnabled: wordTimestampEnabled)
                break
            } catch let error where connectionAttempt == 0 && Self.isTransientNetworkError(error) {
                connectionAttempt += 1
                Log(message: "WS 建连失败（\(error.localizedDescription)），500ms 后重连重试一次")
                closeConnectionInternal()
                try await Task.sleep(nanoseconds: 500_000_000)
                try Task.checkCancellation()
            } catch let error as URLError {
                // 重试后仍然失败：换成可读的文案，原始 TLS/网络细节留在日志里
                Log(message: "WS 建连最终失败: \(error.code.rawValue) / \(error.localizedDescription)")
                throw TTSError.networkError(error.localizedDescription)
            }
        }
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
                            if wordTimestampEnabled && Self.isTimestampRejection(errorCode, errorMessage) {
                                throw TTSError.timestampUnsupported
                            }
                            throw TTSError.serverError("[\(errorCode)] \(errorMessage)")

                        case "result-generated":
                            // 上游只在 sentence-end 带 words[]；sentence-begin / sentence-synthesis
                            // 的 sentence.words 是空数组，解析器会直接返回 nil。
                            if wordTimestampEnabled,
                               let cue = TTSTimestampParser.sentenceEnd(from: jsonText) {
                                sentenceEnds.append(cue)
                                Log(message: "收到 sentence-end: words=\(cue.words.count) text=\(cue.text.prefix(40))")
                            }

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
                // 已经收到部分音频时断流：绝不静默存一条被截断的音频
                // （音频半截 + 时间轴半截 = 两处错误，还查不出原因）。
                if Self.isTransientNetworkError(error) {
                    throw TTSError.networkError(error.localizedDescription)
                }
                isTaskFinished = true
            }
        }

        if completeAudioData.isEmpty {
            throw TTSError.noAudioData
        }

        // 连接由开头的 defer 统一断开（正常完成 / 失败 / 降级重试都覆盖）。

        // 诊断：音频头是否正常（WAV 以 RIFF 开头；合并多段时最容易在这里出错）
        let hasRIFFHeader = completeAudioData.count >= 4 &&
            completeAudioData[0] == 0x52 && // R
            completeAudioData[1] == 0x49 && // I
            completeAudioData[2] == 0x46 && // F
            completeAudioData[3] == 0x46    // F
        Log(message: "音频生成完成: \(completeAudioData.count) bytes, hasRIFFHeader=\(hasRIFFHeader)，已断开 WebSocket 连接")

        // 上游 words[].text 是 normalized_text（可能被转成另一套字形），落盘前必须换回
        // 用户原文里的字符片段；对齐源优先用我们自己发出去的文本，其次才是 original_text。
        let aligned = TTSTimestampParser.alignToOriginal(sentenceEnds, source: displaySource)
        if wordTimestampEnabled {
            let anchors = aligned.reduce(0) { $0 + $1.words.count }
            let after = aligned.flatMap(\.words).map(\.text).joined().filter { !$0.isWhitespace }
            if let displaySource, !displaySource.isEmpty {
                let target = displaySource.filter { !$0.isWhitespace }
                Log(message: after == target
                    ? "字级时间轴文本对齐: 成功，\(anchors) 个锚点已换成用户原文"
                    : "⚠️ 字级时间轴文本对齐: 失败（字数对不上 / 数字或英文被读法展开），保留上游文本")
            } else {
                Log(message: "字级时间轴文本对齐: 无原文可依（调用方未传 displaySource），保留上游文本，\(anchors) 个锚点")
            }
            // 上游 original_text 与发送文本不一致时留痕：这正是「字幕不是我的原文」的根因
            if let displaySource,
               let upstream = sentenceEnds.map(\.text).max(by: { $0.count < $1.count }),
               !displaySource.isEmpty, !upstream.isEmpty,
               displaySource.filter({ !$0.isWhitespace }) != upstream.filter({ !$0.isWhitespace }) {
                Log(message: "⚠️ 上游 original_text 与发送文本不一致，字幕按发送文本显示。发送: \(displaySource.prefix(30)) / 上游: \(upstream.prefix(30))")
            }
        }

        // 上游会把整段文本折成一个 sentence-end（实测 43 字的两句话只回 1 句），
        // 直接落盘会让阅读区只有一张句卡。这里按句末标点再切成子句，
        // 时间仍取自每个 word，不发明任何时间点。
        let normalized = TTSTimestampParser.splitBySentenceEnding(
            TTSTimestampParser.normalize(aligned)
        )
        if wordTimestampEnabled {
            Log(message: "字级时间戳: \(normalized.count) 句 / \(normalized.reduce(0) { $0 + $1.words.count }) 锚点")
        }
        return TTSGeneration(audioData: completeAudioData, sentences: normalized)
    }

    /// 上游拒绝字级时间戳的判定（音色不支持 / 参数不合法时才会提到该参数名）。
    /// 其它错误一律按 serverError 正常上报，不做无意义的重试。
    private nonisolated static func isTimestampRejection(_ code: String, _ message: String) -> Bool {
        let text = (code + " " + message).lowercased()
        guard text.contains("timestamp") else { return false }
        return text.contains("word_timestamp")
            || text.contains("support")
            || text.contains("invalid")
            || text.contains("not allow")
    }

    /// 判断是否为「重连一次就能好」的瞬时网络错误。
    ///
    /// -1200 `secureConnectionFailed`：TLS 握手被中途关闭（`errSSLClosedNoNotify`），
    ///   日志里最常见的那个；-1005 `networkConnectionLost`、-1009 `notConnectedToInternet`
    ///   （WiFi ↔ 蜂窝切换 / 刚唤醒）、-1001 `timedOut`、-1004/-1003 也属于同类。
    /// 参数错误、鉴权失败、上游 4xx 一律不在此列，绝不能重试。
    private nonisolated static func isTransientNetworkError(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        switch urlError.code {
        case .secureConnectionFailed,
             .networkConnectionLost,
             .notConnectedToInternet,
             .timedOut,
             .cannotConnectToHost,
             .cannotFindHost,
             .dnsLookupFailed,
             .badServerResponse:
            return true
        default:
            return false
        }
    }

    /// 建连 → 发 run-task → 等 task-started。
    ///
    /// 单独抽出来，是为了让调用方能在「上游还没建任务」的阶段安全地整段重试
    /// （见 `performSynthesize` 里的重连循环）。
    private func startTask(request: String, wordTimestampEnabled: Bool) async throws {
        try await ensureConnection()
        try await sendMessage(request)
        try await waitForTaskStarted(wordTimestampEnabled: wordTimestampEnabled)
        Log(message: "字级时间戳: \(wordTimestampEnabled ? "开启" : "关闭")")
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
        instruction: String?,
        languageHint: String?,
        wordTimestampEnabled: Bool
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

        // 只有正式生成才带；音色试听不带，避免触发上游的音色支持限制。
        if wordTimestampEnabled {
            payload["word_timestamp_enabled"] = true
        }

        if let emotion = emotion, !emotion.isEmpty {
            payload["emotion"] = emotion
        }
        if let instruction = instruction, !instruction.isEmpty {
            payload["instruction"] = instruction
        }
        // 百炼 run-task 的 parameters.language_hints 是 array[string]，当前版本
        // 只处理第一个元素，所以只放一个值。未选语言 / 中文方言时不带该字段（默认空）。
        // 边缘函数会校验白名单后原样透传，改这里记得同步 index.ts。
        if let hint = languageHint, !hint.isEmpty {
            payload["language_hints"] = [hint]
        }

        Log(message: "参数发送: \(payload)")
        
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

        // ⚠️ 会话必须复用：一次生成会按 [break] / 控制标签切成多次请求，
        // 如果每段都 new 一个 URLSession，就等于每段都重做一次冷 TLS 握手。
        // 对 Cloudflare 边缘尤其脆（日志里的 -1200 / errSSLClosedNoNotify 就出在这一步），
        // 复用之后第二段起直接走同一条 keep-alive 连接，握手次数从「段数」降到 1。
        if urlSession == nil {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 60
            config.timeoutIntervalForResource = 300
            #if os(iOS)
            // 后台接收（配合 GenerationBackgroundKeeper 的 beginBackgroundTask）：
            // WiFi ↔ 蜂窝等短暂切换时等连通，而不是直接把 receive 判失败。
            // ⚠️ 两点别踩坑：
            //    ① URLSessionWebSocketTask 不支持 background URLSessionConfiguration，
            //       WebSocket 只能跑在 default session 上；
            //    ② `shouldUseExtendedBackgroundIdleMode` 自 iOS 18.4 起已被标记
            //       "Not supported"，不要再靠它保 socket。后台能继续收流的唯一保证是
            //       `UIApplication.beginBackgroundTask` 提供的那段执行时间。
            config.waitsForConnectivity = true
            #endif
            urlSession = URLSession(configuration: config)
        }

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

    // MARK: - WebSocket 接收报文转储（DEBUG）

#if DEBUG
    /// 接收序号。所有接收都经过 `receive()`，且被 `ttsPipeline` 串行化，直接自增即可。
    private var receivedMessageIndex = 0
    /// 二进制音频分片是否输出**完整** hex。
    /// 一段语音会有上百个分片、合计几百 KB，默认只打长度 + 前 64 字节；
    /// 需要逐字节排查某个分片时改成 `true`。
    private let dumpFullBinaryPayload = false
    /// 单条日志的文本长度上限；超长按此长度分多条打印，内容不截断。
    private let wsLogChunkSize = 2000

    /// 打印**每一条**收到的 WebSocket 帧。
    ///
    /// `waitForTaskStarted()` 与 `performSynthesize()` 的接收全部走 `receive()`，
    /// 所以只在这里打一次即可覆盖全部入站数据，包括被上层 switch 忽略的中间事件、
    /// `task-started` 之前的帧、空帧以及音频二进制分片。
    /// - 文本帧：原样完整输出（超长自动分片，不省略、不截断）
    /// - 二进制帧：字节数 + hex（`dumpFullBinaryPayload` 控制全量 / 头部 64 字节）
    private func logReceivedMessage(_ message: URLSessionWebSocketTask.Message) {
        receivedMessageIndex += 1
        let n = receivedMessageIndex

        switch message {
        case .string(let text):
            Log(message: "[WS RECV #\(n)][text][\(text.utf8.count) bytes]")
            if text.isEmpty {
                Log(message: "[WS RECV #\(n)] <empty>")
                return
            }
            var start = text.startIndex
            var part = 0
            while start < text.endIndex {
                let end = text.index(start, offsetBy: wsLogChunkSize, limitedBy: text.endIndex) ?? text.endIndex
                part += 1
                Log(message: "[WS RECV #\(n)][text \(part)] \(text[start..<end])")
                start = end
            }

        case .data(let data):
            let byteCount = data.count
//            Log(message: "[WS RECV #\(n)][binary][\(byteCount) bytes]")
            let shown: Data = dumpFullBinaryPayload ? data : Data(data.prefix(64))
            let hex = shown.map { String(format: "%02x", Int($0)) }.joined(separator: " ")
//            Log(message: "[WS RECV #\(n)][hex\(dumpFullBinaryPayload ? " full" : " head")] \(hex)")
            if !dumpFullBinaryPayload && byteCount > 64 {
//                Log(message: "[WS RECV #\(n)] …余 \(byteCount - 64) bytes 未展开（dumpFullBinaryPayload = true 可全量打印）")
            }

        @unknown default:
            Log(message: "[WS RECV #\(n)][unknown frame]")
        }
    }
#endif

    private func receive() async throws -> ReceivedMessage {
        guard let webSocketTask = webSocketTask else {
            throw TTSError.connectionError
        }

        do {
            let message = try await webSocketTask.receive()

            #if DEBUG
            logReceivedMessage(message)
            #endif

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

    private func waitForTaskStarted(wordTimestampEnabled: Bool) async throws {
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
                        let header = json["header"] as? [String: Any] ?? [:]
                        let errorMessage = header["error_message"] as? String ?? "Unknown error"
                        let errorCode = header["error_code"] as? String ?? "Unknown"
                        // 参数不合法时上游可能在 task-started 之前就直接 task-failed，
                        // 这里也要能触发「不带时间戳重跑一次」的降级。
                        if wordTimestampEnabled && Self.isTimestampRejection(errorCode, errorMessage) {
                            throw TTSError.timestampUnsupported
                        }
                        throw TTSError.serverError(errorMessage)
                    }
                }
            }
            // 忽略二进制消息（理论上不应该在 task-started 之前出现）
        }
    }

    /// 只断开当前任务，**保留 URLSession**。
    ///
    /// 保留会话是为了让下一次连接复用同一条 keep-alive / TLS 连接：
    /// 一次生成有 N 段就 N 次 connect，销毁会话会让每次都重做冷握手，
    /// 而冷握手正是最容易被打断的一步（-1200 / errSSLClosedNoNotify）。
    private func closeConnectionInternal() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        isConnected = false
        currentTaskId = nil
    }

    /// 真正销毁会话（退出登录 / 内存压力 / 用户手动断开时用）。
    private func destroySessionInternal() {
        closeConnectionInternal()
        urlSession?.invalidateAndCancel()
        urlSession = nil
    }

    func closeConnection() {
        withConnectionLock {
            destroySessionInternal()
            Log(message: "WebSocket 连接已关闭")
        }
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
    /// 当前音色不支持 word_timestamp_enabled；内部用于触发一次无时间戳降级重试
    case timestampUnsupported
    /// 网络层失败（TLS 握手被打断 / 断网 / 超时）。原始细节放进关联值，日志里能看到。
    case networkError(String)

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
        case .timestampUnsupported:
            return "当前音色不支持字级时间戳"
        case .networkError(let detail):
            return "网络连接失败，请检查网络后重试（\(detail)）"
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
