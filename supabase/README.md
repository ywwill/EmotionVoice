# Supabase Edge Function：bailian-tts

把阿里云百炼 `qwen-audio-3.0-tts-plus` 的语音合成搬到 Supabase 边缘函数上，
**API Key / WorkspaceId / 模型协议全部收进 function secrets**，客户端（macOS App）里不再出现任何厂商密钥。

## 架构

```
macOS App                      Supabase Edge Function              阿里云百炼
BailianTTSService  ──wss──▶  functions/v1/bailian-tts  ──wss──▶  *.maas.aliyuncs.com
  只发一条 synthesize            1) 注入 Authorization: Bearer <key>
  收二进制音频分片                2) run-task → 等 task-started
                                3) 按控制类标签切段 → 逐段 continue-task
                                4) finish-task
                                5) 上游 JSON 事件原样转发 + 二进制音频透传
```

- 客户端：`EmotionVoice/EmotionVoice/EmotionVoice/Services/BailianTTSService.swift`
  + `TTSEndpoint.swift`（拼 `wss://<ref>.supabase.co/functions/v1/bailian-tts?region=CN`）
- 服务端：`functions/bailian-tts/index.ts`

## 客户端协议（只有一条消息）

握手：`wss://dpyyhbqqmegencxekkcr.supabase.co/functions/v1/bailian-tts?region=CN|INTL`

请求头：

| header | 值 |
| --- | --- |
| `Authorization` | `Bearer <publishable key>` |
| `apikey` | `<publishable key>` |
| `x-app-secret` | 与 `APP_SECRET` 一致（也可用 query `?secret=`） |

连接成功后**只发一条** JSON：

```json
{
  "action": "synthesize",
  "text": "[happy]今天天气真好。 [laughing]",
  "voice": "longanlingxin",
  "emotion": null,
  "rate": 1.0,
  "volume": 100,
  "sample_rate": 48000,
  "format": "wav",
  "instruction": null
}
```

下游回来的都是上游原样事件（`task-started` / `result-generated` / `task-finished` /
`task-failed`）+ 二进制音频帧，客户端的收包逻辑与直连时完全一致。

## Secrets

| 名称 | 说明 |
| --- | --- |
| `BAILIAN_API_KEY_CN` | 中国区（北京）API Key |
| `BAILIAN_API_KEY_INTL` | 国际区（新加坡）API Key |
| `BAILIAN_WS_URL_CN` | 可选，默认北京 workspace |
| `BAILIAN_WS_URL_INTL` | 可选，默认新加坡 workspace |
| `BAILIAN_TTS_MODEL` | 可选，默认 `qwen-audio-3.0-tts-plus` |
| `APP_SECRET` | 应用级 secret，对应客户端 `kSupabaseAppSecret`；不设置则不校验 |

## 部署

```bash
cp functions/bailian-tts/.env.example functions/.env   # 填入真实值
./deploy.sh
```

或手动：

```bash
supabase link --project-ref dpyyhbqqmegencxekkcr
supabase secrets set --project-ref dpyyhbqqmegencxekkcr --env-file supabase/functions/.env
supabase functions deploy bailian-tts --project-ref dpyyhbqqmegencxekkcr
```

`functions/.env` 已在根目录 `.gitignore` 中，**不要提交**。

## 本地验证

`supabase functions serve` 需要 Docker。没有 Docker 时可以直接用 deno 跑：

```bash
cd supabase/functions/bailian-tts
deno run --allow-net --allow-env --env-file ../../functions/.env index.ts   # 监听 :8000
```

然后用一个 WebSocket 客户端连 `ws://127.0.0.1:8000?region=CN&secret=<APP_SECRET>`，
发上面那条 synthesize 请求即可（本机有 HTTP 代理时记得 `NO_PROXY=127.0.0.1`）。

已验证结果：两段标签 `[happy]…[sad]…[laughing]` 各自独立合成，`task-started →
sentence-begin/end → task-finished` 事件齐全，音频 534 KB / 13 个分片流式到达。

## 日志 / 调试

函数默认会打印三组信息（Supabase Dashboard → Edge Functions → Logs）：

1. **握手参数**：path、query（`secret`/`jwt`/`token` 打码）、请求头（`authorization`/`apikey`/`x-app-secret` 打码）
2. **客户端参数**：原始报文长度 + 报文预览，然后逐字段
   `action / task_id / voice / emotion / rate / volume / sample_rate / format / instruction / text`
3. **交给上游**：task_id、上游地址、补 `emotion` 后的文本、`run-task` 完整报文、切段结果逐条

`text` 与 `instruction` 默认只打前 500 字，加 `?debug=1` 打印全文。

## 出站 WebSocket 的拨号方式（重要）

百炼要求握手时带 `Authorization` 头，而标准 `WebSocket` 构造函数不允许带 header。
函数里做了两级拨号，日志会打印实际走了哪条（`[bailian-tts] 拨号方式: …`）：

1. `deno-native` —— Deno ≥ 2.5 的非标准扩展 `new WebSocket(url, { headers })`
2. `npm:ws` —— 更老的运行时会把第二个参数当 subprotocol 校验，对象被转成
   `"[object Object]"` 后抛 **`Invalid protocol value`**；捕获这个异常后自动回退
   （Supabase 线上目前就走这条）

> 2026-10-18 实测：线上运行时不支持第 1 种，客户端报
> `服务器错误: Invalid protocol value`，因此加入了 `npm:ws` 回退。

`?ws=npm` 可强制走第 2 条（排查握手问题时用）。

## 已知风险与兜底
- `APP_SECRET` 只是"拿到 publishable key 就能白嫖"的最低门槛，不是真正的用户鉴权。
  后续要收紧的话，在函数里校验 Supabase JWT（`--no-verify-jwt` 部署 + 函数内
  `supabase.auth.getUser(jwt)`），或按 device_id 做配额。
- 单次文本上限 20000 字，上游连接超时 15s。
