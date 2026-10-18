// Supabase Edge Function: bailian-tts
//
// 阿里云百炼 qwen-audio-3.0-tts-plus 语音合成的 WebSocket 代理。
//
// 目的：把 API Key / WorkspaceId / 模型协议全部收进 Supabase 的 function secrets，
// 客户端（macOS App）只持有 publishable key + 一个应用级 secret，不再出现任何厂商密钥。
//
// 业务逻辑与 BailianTTSService.swift 一一对应：
//   run-task -> 等 task-started -> 按控制类标签切段 -> 逐段 continue-task -> finish-task
//   期间把上游的 JSON 事件**原样转发**给客户端，二进制帧直接透传（音频流式到达）。
//
// 需要的 secrets（supabase secrets set）：
//   BAILIAN_API_KEY_CN    中国区（北京）API Key
//   BAILIAN_API_KEY_INTL  国际区（新加坡）API Key
//   BAILIAN_WS_URL_CN     可选，默认北京 workspace
//   BAILIAN_WS_URL_INTL   可选，默认新加坡 workspace
//   BAILIAN_TTS_MODEL     可选，默认 qwen-audio-3.0-tts-plus
//   APP_SECRET            可选，与客户端 kSupabaseAppSecret 一致；未设置时不校验
//
// ⚠️ 出站 WebSocket 必须带 `Authorization` 头。标准 WebSocket 构造函数不允许带 header，
// 所以：Deno ≥ 2.5 用非标准扩展 `new WebSocket(url, { headers })`；
// 更老的运行时会把 options 当成 subprotocol 校验并抛 `Invalid protocol value`，
// 此时自动回退到 `npm:ws`（Supabase 线上运行时目前走的就是这条）。

// @ts-ignore ws 不带类型声明
import NodeWebSocket from "npm:ws@8";

const MODEL = Deno.env.get("BAILIAN_TTS_MODEL") ?? "qwen-audio-3.0-tts-plus";
const APP_SECRET = Deno.env.get("APP_SECRET") ?? "";

/// 单次请求允许的最大文本长度（超出直接拒绝，避免被刷）
const MAX_TEXT_LENGTH = 20_000;

/// 上游连接建立超时（毫秒）
const UPSTREAM_TIMEOUT_MS = 15_000;

/// 日志里 text / instruction 的预览长度；加 `?debug=1` 会完整打印
const TEXT_PREVIEW_LENGTH = 500;

/// 富语言类标签（与 Constants.richLanguageTags 保持一致）。
/// 它们不是"语气"，不切段，只作为当前控制类标签作用域内的附加修饰。
const RICH_LANGUAGE_TAGS = new Set([
  "laughing",
  "giggles",
  "sighing",
  "gasp",
  "clears throat",
  "cough",
  "snorts",
]);

// MARK: - 调试日志

/// 敏感值打码：只留前 4 位
function mask(value: string): string {
  if (!value) return "(empty)";
  return value.length <= 8 ? "****" : `${value.slice(0, 4)}****(${value.length})`;
}

/// 长文本预览
function preview(value: string | null | undefined, full: boolean): string {
  if (value === null || value === undefined) return "(nil)";
  if (full || value.length <= TEXT_PREVIEW_LENGTH) return value;
  return `${value.slice(0, TEXT_PREVIEW_LENGTH)}…(共 ${value.length} 字)`;
}

/// 握手阶段：打印 URL 上的所有 query 参数与请求头（密钥打码）
function logHandshake(url: URL, req: Request): void {
  const query: Record<string, string> = {};
  for (const [k, v] of url.searchParams.entries()) {
    query[k] = (k === "secret" || k === "jwt" || k === "token") ? mask(v) : v;
  }

  const headers: Record<string, string> = {};
  for (const [k, v] of req.headers.entries()) {
    headers[k] = (k === "authorization" || k === "apikey" || k === "x-app-secret")
      ? mask(v)
      : v;
  }

  console.log("[bailian-tts] === 握手参数 ===");
  console.log("[bailian-tts] path:", url.pathname);
  console.log("[bailian-tts] query:", JSON.stringify(query));
  console.log("[bailian-tts] headers:", JSON.stringify(headers));
  console.log("[bailian-tts] upgrade:", req.headers.get("upgrade"));
}

/// 收到 synthesize 请求：先打原始 JSON，再逐字段打印
function logRequest(raw: string, req: TTSRequest, full: boolean): void {
  console.log("[bailian-tts] === 客户端参数 ===");
  console.log("[bailian-tts] 原始报文长度:", raw.length, "字节");
  console.log("[bailian-tts] 原始报文:", full ? raw : preview(raw, false));
  console.log("[bailian-tts] 逐字段:");
  console.log("  action      =", req.action ?? "(nil)");
  console.log("  task_id     =", req.task_id ?? "(nil)");
  console.log("  voice       =", req.voice ?? "(nil)");
  console.log("  emotion     =", req.emotion ?? "(nil)");
  console.log("  rate        =", req.rate ?? "(nil)");
  console.log("  volume      =", req.volume ?? "(nil)");
  console.log("  sample_rate =", req.sample_rate ?? "(nil)");
  console.log("  format      =", req.format ?? "(nil)");
  console.log("  instruction =", preview(req.instruction, full));
  console.log("  text        =", preview(req.text, full));
  console.log("  text.length =", (req.text ?? "").length);
}

// MARK: - 上游配置

interface UpstreamConfig {
  wsUrl: string;
  apiKey: string;
}

function upstreamConfig(region: string): UpstreamConfig {
  const isCN = region.toUpperCase() === "CN";
  if (isCN) {
    return {
      wsUrl:
        Deno.env.get("BAILIAN_WS_URL_CN") ??
        "wss://llm-quamnoopzri4mr6r.cn-beijing.maas.aliyuncs.com/api-ws/v1/inference",
      apiKey: Deno.env.get("BAILIAN_API_KEY_CN") ?? "",
    };
  }
  return {
    wsUrl:
      Deno.env.get("BAILIAN_WS_URL_INTL") ??
      "wss://llm-4z5f5e3xl478r32c.ap-southeast-1.maas.aliyuncs.com/api-ws/v1/inference",
    apiKey: Deno.env.get("BAILIAN_API_KEY_INTL") ?? "",
  };
}

// MARK: - 请求 / 事件

interface TTSRequest {
  action?: string;
  task_id?: string;
  text?: string;
  voice?: string;
  emotion?: string | null;
  rate?: number;
  volume?: number;
  sample_rate?: number;
  format?: string;
  instruction?: string | null;
}

function buildRunTaskEvent(
  taskId: string,
  req: TTSRequest,
): string {
  const parameters: Record<string, unknown> = {
    text_type: "PlainText",
    voice: req.voice ?? "",
    format: (req.format ?? "wav").toLowerCase(),
    sample_rate: req.sample_rate ?? 48000,
    volume: Math.trunc(req.volume ?? 100),
    rate: req.rate ?? 1.0,
    pitch: 1.0,
    enable_ssml: false,
  };
  const instruction = req.instruction;
  if (typeof instruction === "string" && instruction.length > 0) {
    parameters["instruction"] = instruction;
  }

  return JSON.stringify({
    header: { action: "run-task", task_id: taskId, streaming: "duplex" },
    payload: {
      task_group: "audio",
      task: "tts",
      function: "SpeechSynthesizer",
      model: MODEL,
      parameters,
      input: {},
    },
  });
}

function buildContinueTaskEvent(taskId: string, text: string): string {
  return JSON.stringify({
    header: { action: "continue-task", task_id: taskId, streaming: "duplex" },
    payload: { input: { text } },
  });
}

function buildFinishTaskEvent(taskId: string): string {
  return JSON.stringify({
    header: { action: "finish-task", task_id: taskId, streaming: "duplex" },
    payload: { input: {} },
  });
}

/// 客户端侧统一的失败事件（结构与上游 task-failed 一致，客户端无需区分来源）
function buildFailedEvent(code: string, message: string): string {
  return JSON.stringify({
    header: {
      event: "task-failed",
      error_code: code,
      error_message: message,
    },
  });
}

// MARK: - 文本处理

/// 无标签时，把 emotion 作为整段的控制标签补在开头
function processTextWithEmotion(text: string, emotion?: string | null): string {
  if (text.includes("[") && text.includes("]")) return text;
  if (emotion && emotion.length > 0) return `[${emotion}]${text}`;
  return text;
}

/// 按控制类标签把文本切成多段。
///
/// 百炼 TTS 单次请求只会识别第一个控制类标签和第一个富语言类标签，后续标签被静默忽略。
/// 因此遇到新的控制类标签就开一段，让 API 独立解析每一段。
///
/// 例：`[panicked]虽然…精简，[angry]其他…体验 [cough]`
///   -> ["[panicked]虽然…精简，", "[angry]其他…体验 [cough]"]
function splitTextByControlTags(text: string): string[] {
  const re = /\[([^\]]+)\]/g;
  type Item = { kind: "control" | "rich" | "text"; value: string };
  const items: Item[] = [];

  let cursor = 0;
  let m: RegExpExecArray | null;
  while ((m = re.exec(text)) !== null) {
    const openLoc = m.index;
    const closeEnd = m.index + m[0].length;
    const label = m[1];
    const tagStr = `[${label}]`;

    if (openLoc > cursor) {
      const part = text.slice(cursor, openLoc);
      if (part.length > 0) items.push({ kind: "text", value: part });
    }
    items.push({ kind: RICH_LANGUAGE_TAGS.has(label) ? "rich" : "control", value: tagStr });
    cursor = closeEnd;
  }
  if (cursor < text.length) {
    const tail = text.slice(cursor);
    if (tail.length > 0) items.push({ kind: "text", value: tail });
  }

  const segments: string[] = [];
  let currentControl: string | null = null;
  let currentBody = "";

  const flush = () => {
    const combined = (currentControl ?? "") + currentBody;
    if (combined.trim().length > 0) segments.push(combined);
    currentControl = null;
    currentBody = "";
  };

  for (const item of items) {
    if (item.kind === "control") {
      flush();
      currentControl = item.value;
    } else {
      currentBody += item.value;
    }
  }
  flush();

  return segments.length > 0 ? segments : [text];
}

// MARK: - 入口

Deno.serve(async (req: Request): Promise<Response> => {
  const upgrade = req.headers.get("upgrade") ?? "";
  if (upgrade.toLowerCase() !== "websocket") {
    return Response.json(
      { error: "request isn't trying to upgrade to WebSocket." },
      { status: 400 },
    );
  }

  // 轻量鉴权：publishable key 是公开的，真正拦住滥用的是这个应用级 secret。
  // 浏览器 WebSocket 发不了自定义 header，所以同时接受 query param。
  if (APP_SECRET) {
    const url0 = new URL(req.url);
    const provided =
      req.headers.get("x-app-secret") ?? url0.searchParams.get("secret") ?? "";
    if (provided !== APP_SECRET) {
      console.warn("[bailian-tts] rejected: bad app secret");
      return new Response("Unauthorized", { status: 401 });
    }
  }

  const url = new URL(req.url);
  const region = url.searchParams.get("region") ?? "";
  const up = upstreamConfig(region);
  if (!up.apiKey) {
    console.error(`[bailian-tts] missing API key for region=${region}`);
    return new Response("TTS provider is not configured", { status: 500 });
  }

  logHandshake(url, req);

  // ?debug=1 时完整打印文本（默认只打前 500 字）
  const fullText = url.searchParams.get("debug") === "1";
  // ?ws=native | ?ws=npm 可强制指定拨上游的方式（排查握手问题用）
  const rawMode = url.searchParams.get("ws");
  const mode: DialMode = rawMode === "native" || rawMode === "npm" ? rawMode : "auto";

  const { socket, response } = Deno.upgradeWebSocket(req, { idleTimeout: 0 });
  socket.binaryType = "arraybuffer";

  // 保持 worker 存活：upgrade 返回后 HTTP 请求即算完成，
  // 不挂一个 pending promise 的话 worker 会被提前回收。
  let resolveClosed: () => void;
  const closed = new Promise<void>((r) => (resolveClosed = r));
  const edgeRuntime = (globalThis as { EdgeRuntime?: { waitUntil(p: Promise<unknown>): void } })
    .EdgeRuntime;
  edgeRuntime?.waitUntil(closed);

  let handled = false;

  socket.onmessage = (event: MessageEvent) => {
    if (handled) return; // 协议里客户端只发一次 synthesize 请求
    if (typeof event.data !== "string") return;
    handled = true;

    let req: TTSRequest;
    try {
      req = JSON.parse(event.data) as TTSRequest;
    } catch {
      console.error("[bailian-tts] 请求不是合法 JSON:", String(event.data).slice(0, 300));
      safeSend(socket, buildFailedEvent("InvalidRequest", "请求不是合法 JSON"));
      safeClose(socket);
      return;
    }

    logRequest(event.data, req, fullText);

    runJob(socket, req, up, mode).catch((err) => {
      console.error("[bailian-tts] job failed:", err);
      safeSend(socket, buildFailedEvent("InternalError", String(err?.message ?? err)));
      safeClose(socket);
    });
  };

  socket.onclose = () => resolveClosed();
  socket.onerror = (e) =>
    console.error("[bailian-tts] client socket error:", (e as ErrorEvent).message ?? e.type);

  return response;
});

// MARK: - 拨上游（带 Authorization 头）

interface UpstreamHandlers {
  onOpen(): void;
  onMessage(data: string | Uint8Array): void;
  onError(): void;
  onClose(): void;
}

interface UpstreamConn {
  /// 实际用的拨号方式（日志用）
  kind: string;
  send(data: string): void;
  close(): void;
}

/// 拨号方式。默认 `auto`：按运行时能力选；`?ws=native|npm` 可强制指定。
type DialMode = "auto" | "native" | "npm";

/// 原生 `new WebSocket(url, { headers })` 是 Deno 2.5 才有的非标准扩展。
/// 更老的运行时会把第二个参数当 subprotocol 校验，
/// options 对象被转成 "[object Object]" 后抛 `Invalid protocol value`。
function nativeSupportsHeaders(): boolean {
  const [major, minor] = Deno.version.deno.split(".").map((p) => Number(p) || 0);
  return major > 2 || (major === 2 && minor >= 5);
}

/// 拨一条到百炼的 WebSocket，握手时带上 Authorization。
///
/// `auto` 下先判断运行时能力，不支持就直接走 `npm:ws`，
/// 不再"先抛异常再捕获"（那样日志里会留下一条容易误判的 Invalid protocol value）。
function dialUpstream(
  wsUrl: string,
  apiKey: string,
  mode: DialMode,
  h: UpstreamHandlers,
): UpstreamConn {
  const headers = {
    Authorization: `Bearer ${apiKey}`,
    "Content-Type": "application/json",
  };

  const useNative = mode === "auto" ? nativeSupportsHeaders() : mode === "native";
  if (!useNative) return dialViaNpmWs(wsUrl, headers, h);

  // deno-lint-ignore no-explicit-any
  const native = new (WebSocket as any)(wsUrl, { headers }) as WebSocket;
  native.binaryType = "arraybuffer";
  native.onopen = () => h.onOpen();
  native.onmessage = (event: MessageEvent) =>
    h.onMessage(
      typeof event.data === "string"
        ? event.data
        : new Uint8Array(event.data as ArrayBuffer),
    );
  native.onerror = () => h.onError();
  native.onclose = () => h.onClose();
  return {
    kind: "deno-native",
    send: (data) => native.send(data),
    close: () => safeClose(native),
  };
}

/// 老运行时的兜底：用 `npm:ws` 拨上游（它的客户端支持 `{ headers }`）
function dialViaNpmWs(
  wsUrl: string,
  headers: Record<string, string>,
  h: UpstreamHandlers,
): UpstreamConn {
  const node = new NodeWebSocket(wsUrl, { headers });
  node.on("open", () => h.onOpen());
  node.on("message", (data: Buffer | string, isBinary: boolean) => {
    if (isBinary) {
      const buf = data as Buffer;
      h.onMessage(new Uint8Array(buf.buffer, buf.byteOffset, buf.byteLength));
    } else {
      h.onMessage(typeof data === "string" ? data : data.toString("utf8"));
    }
  });
  node.on("error", () => h.onError());
  node.on("close", () => h.onClose());
  return {
    kind: "npm:ws",
    send: (data) => node.send(data),
    close: () => {
      try {
        node.close();
      } catch {
        /* ignore */
      }
    },
  };
}

// MARK: - 一次合成任务

async function runJob(
  socket: WebSocket,
  req: TTSRequest,
  up: UpstreamConfig,
  mode: DialMode,
): Promise<void> {
  const text = processTextWithEmotion(req.text ?? "", req.emotion);
  if (!text.trim()) {
    safeSend(socket, buildFailedEvent("EmptyText", "文本为空"));
    safeClose(socket);
    return;
  }
  if (text.length > MAX_TEXT_LENGTH) {
    safeSend(
      socket,
      buildFailedEvent("TextTooLong", `文本超过 ${MAX_TEXT_LENGTH} 字`),
    );
    safeClose(socket);
    return;
  }
  if (!req.voice) {
    safeSend(socket, buildFailedEvent("MissingVoice", "缺少 voice 参数"));
    safeClose(socket);
    return;
  }

  const taskId = crypto.randomUUID();
  console.log("[bailian-tts] === 交给上游 ===");
  console.log(`[bailian-tts] task=${taskId}`);
  console.log("[bailian-tts] Deno 版本:", Deno.version.deno, "· 拨号模式:", mode);
  console.log("[bailian-tts] 上游地址:", up.wsUrl);
  console.log("[bailian-tts] 补 emotion 后的文本:", text);
  console.log("[bailian-tts] run-task:", buildRunTaskEvent(taskId, req));

  let started = false;
  let finished = false;
  let opened = false;
  let conn: UpstreamConn | undefined;

  await new Promise<void>((resolve, reject) => {
    const timer = setTimeout(() => {
      if (!opened) reject(new Error("连接上游超时"));
    }, UPSTREAM_TIMEOUT_MS);
    const settle = (err?: Error) => {
      clearTimeout(timer);
      if (err) reject(err);
      else resolve();
    };

    conn = dialUpstream(up.wsUrl, up.apiKey, mode, {
      onOpen: () => {
        opened = true;
        settle();
      },
      onError: () => {
        if (!opened) {
          settle(new Error("无法连接语音合成服务"));
          return;
        }
        safeSend(socket, buildFailedEvent("UpstreamError", "语音服务连接异常"));
        safeClose(socket);
      },
      onClose: () => {
        if (!opened) {
          settle(new Error("上游连接已关闭"));
          return;
        }
        if (!finished) {
          console.warn(`[bailian-tts] task=${taskId} upstream closed unexpectedly`);
          safeSend(socket, buildFailedEvent("UpstreamClosed", "语音服务连接已断开"));
        }
        safeClose(socket);
      },
      onMessage: (data) => {
        // 二进制 = 音频分片，直接透传
        if (typeof data !== "string") {
          safeSend(socket, data);
          return;
        }

        // 原样转发上游事件（task-started / result-generated / task-finished / task-failed ...）
        safeSend(socket, data);

        let parsed: { header?: { event?: string } } | null = null;
        try {
          parsed = JSON.parse(data);
        } catch {
          parsed = null;
        }
        const ev = parsed?.header?.event;

        if (ev === "task-started" && !started) {
          started = true;
          const segments = splitTextByControlTags(text);
          console.log(`[bailian-tts] task=${taskId} segments=${segments.length}`);
          segments.forEach((seg, i) => {
            console.log(`[bailian-tts]   [${i + 1}/${segments.length}] ${seg}`);
          });
          for (const seg of segments) {
            conn?.send(buildContinueTaskEvent(taskId, seg));
          }
          conn?.send(buildFinishTaskEvent(taskId));
        } else if (ev === "task-finished" || ev === "task-failed") {
          finished = true;
          conn?.close();
          safeClose(socket);
        }
      },
    });

    console.log(`[bailian-tts] 拨号方式: ${conn?.kind}`);
  });

  conn?.send(buildRunTaskEvent(taskId, req));
}

// MARK: - 工具

function safeSend(socket: WebSocket, data: string | ArrayBuffer | Uint8Array) {
  try {
    if (socket.readyState === WebSocket.OPEN) socket.send(data);
  } catch (err) {
    console.error("[bailian-tts] send failed:", err);
  }
}

function safeClose(socket: WebSocket) {
  try {
    if (socket.readyState === WebSocket.OPEN || socket.readyState === WebSocket.CONNECTING) {
      socket.close();
    }
  } catch {
    /* ignore */
  }
}
