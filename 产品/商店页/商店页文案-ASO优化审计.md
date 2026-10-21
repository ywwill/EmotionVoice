# Emora 商店页 ASO 优化审计

> ⚠️ **本文件已过期（v2/v3），仅供变更记录，不要照抄。** 当前有效版本见 `商店页文案-多语言版本.md`（v4）。
审计对象：Mac App Store 当前定稿（v2）　审计日期：2026-10-21
结论：**8 项里有 6 项值得改**，其中 3 项是「把零搜索价值的词换掉」，收益最直接。

---

## 1. 问题清单（按优先级）

| 优先级 | 位置 | 现状问题 | 优化动作 |
|---|---|---|---|
| **P0** | 英文主标题 | `Emotion` 搜索量极低，`TTS` 缩写流量也低于全拼；最高流量词 **text to speech** 没进标题 | 换成 `Emora AI Voice, Text to Speech` |
| **P0** | 英文副标题 | `Emotion per line, live preview` 是生造短语，用户不会这样搜；`live preview` 零搜索 | 换成 `Audiobook, Podcast & Voiceover` |
| **P0** | 中文副标题 | 整条是功能罗列，没有一个搜索词；`MP3` `WAV` 没人搜 | 换成场景词：有声书 / 播客 / 视频解说 / 课件配音 |
| **P1** | 中文主标题 | 27/30 未用满；`拟声` `标签` 占 5 字符却几乎零搜索；缺 `语音合成` `朗读` 两个高流量品类词 | 换词并填满 30 |
| **P1** | 中文关键词 | 25 词里约 30 字符与标题重复（语音合成 / 方言 / 朗读 / AI / 有声书 / 播客 / 课件 / 情绪 / 解说） | 去重，换成配音软件、讲故事、听书、视频旁白、声音定制、有声制作 |
| **P1** | 英文关键词 | `tts` 与标题 `TTS` 重复；缺 cantonese / chinese / read aloud / story | 补进 4 个高意向词 |
| P2 | 中文描述 | 结尾停在"界面支持…"，没有行动号召；首句未带 `配音软件` | 结尾加 CTA，首句带品类词 |
| P2 | 英文描述 | 同上；另缺 `read aloud` | 同上 |

**判定口径**：Apple 对 App 名称的索引权重 > 副标题 > 关键词字段 > 描述。所以标题里放低搜索价值的词，是整页最大的浪费。

---

## 2. 逐项对比

### 中文主标题

| | 文本 | 字数 |
|---|---|---|
| 现状 | Emora AI 情感配音：文字转语音、方言与拟声标签 | 27/30 |
| **优化** | Emora AI 情感配音：文字转语音、语音合成、方言与朗读 | **30/30** |

变化：删掉零搜索的「拟声标签」，补进 `语音合成`、`朗读` 两个真实品类词，同时用满 30 字符。

### 中文副标题

| | 文本 | 字数 |
|---|---|---|
| 现状 | 按句插情感与拟声标签，边写边听，一键导出 MP3 或 WAV | 30/30 |
| **优化** | 有声书、播客、视频解说与课件配音，按句调情绪，边写边听边导出 | **30/30** |

变化：副标题的任务不是复述功能（那是描述的事），而是**补标题装不下的搜索词**。「有声书」「播客」「视频解说」「课件配音」都是目标用户的真实搜法。

### 英文主标题

| | 文本 | 字数 |
|---|---|---|
| 现状 | Emora: AI Voices & Emotion TTS | 30/30 |
| **优化** | Emora AI Voice, Text to Speech | **30/30** |

变化：`Emotion` 换成 `Text to Speech`（英文区该品类最高流量词），`TTS` 缩写退到关键词字段。

### 英文副标题

| | 文本 | 字数 |
|---|---|---|
| 现状 | Emotion per line, live preview | 30/30 |
| **优化** | Audiobook, Podcast & Voiceover | **30/30** |

---

## 3. 优化版全文（可直接复制）

### 中文 · 主标题

```text
Emora AI 情感配音：文字转语音、语音合成、方言与朗读
```

### 中文 · 副标题

```text
有声书、播客、视频解说与课件配音，按句调情绪，边写边听边导出
```

### 中文 · 推广文本 · 74/170

```text
写一句「温柔女声，语速适中」，Emora 就照这句话念。按句插入情绪与拟声标签，边写边听，一键导出 MP3 或 WAV；中文、英文与多种方言都能用。
```

### 中文 · 描述 · 502/4000

```text
Emora 是一款为长内容而生的 AI 配音软件（TTS）：贴入稿件，按句标注情绪、挑音色、边写边听，导出成片。

■ 一句话定语气
丰富的语气标签与拟声标签，插在哪一句就只影响哪一句。旁白保持平静，对话带上笑意，结尾留一声叹息。

■ 音色挑得出来
599 个音色，按语言、性别、年龄、场景筛选，支持名称搜索；每个都能先试听再定，常用的收进收藏夹。

■ 不会调参数，就把它说出来
一句话下指令——「知性沉稳的讲述风格，富有感染力」，或从温柔女声、新闻播报、有声书等 6 种预设起步；语速、音量、采样率按需微调。

■ 边写边听，听完就导出
流式合成，边生成边播放；一键导出 MP3 或 WAV；生成记录自动留存，随时回听与重新导出。

适合有声制作：播客主播、有声书与有声小说、电子书朗读、视频配音与解说、课件与广告配音、口播与角色对话、儿童故事与有声读物；也适合睡前讲故事、通勤听书、视频旁白与声音定制。支持中文、英文等多语言，以及粤语、四川话、东北话等方言。

按字数计费，随用随充，不绑定订阅。界面支持简体中文与英文，跟随系统语言。

下载 Emora，把下一篇稿子读成你想要的样子。
```

### 中文 · 关键词 · 92/100 字符

```text
旁白,主播,口播,角色,广告配音,视频配音,粤语,四川话,东北话,儿童故事,有声读物,电子书,有声小说,音色,拟声,TTS,多语言,配音软件,讲故事,听书,有声制作,视频旁白,声音定制
```

### 英文 · App Name

```text
Emora AI Voice, Text to Speech
```

### 英文 · Subtitle

```text
Audiobook, Podcast & Voiceover
```

### 英文 · Promotional Text · 155/170

```text
Write "a warm female voice" and Emora reads it that way. Tag emotion per line, preview as it generates, export MP3 or WAV — Mandarin, English and dialects.
```

### 英文 · Description · 1321/4000

```text
Emora is an AI voice generator — text to speech (TTS) built for long-form scripts: paste your text, tag the emotion line by line, pick a voice, listen as you go, and export the finished audio.

■ Emotion, one line at a time
Dozens of tone and sound tags; a tag only affects the sentence it sits in. Keep the narration calm, let the dialogue smile, end on a sigh.

■ Voices you can actually find
599 voices, filterable by language, gender, age and use case, each previewable before you commit, with favorites one click away.

■ Say it instead of tuning it
Give an instruction in plain words — "a calm, warm storytelling voice" — or start from 6 presets including newscast, audiobook and ad voiceover. Fine-tune speed, volume and sample rate when you need to.

■ Hear it as it writes
Streaming synthesis plays while it generates. Export MP3 or WAV in one click, and every generation stays in history for replay and re-export.

Made for podcast hosts, dubbing, audiobooks, video narration and course material, ad voiceover and character dialogue — or simply read aloud a long article. Supports Mandarin, English and dialects including Cantonese and Sichuanese.

Pay by character, top up as you go — no subscription. Interface in Simplified Chinese and English.

Download Emora and hear your next script the way you meant it.
```

### 英文 · Keywords · 99/100 字符

```text
tts,voice generator,audiobook,narration,dubbing,dialect,mandarin,cantonese,chinese,read aloud,story
```

---

## 4. 校验结果（优化版）

```
copy-optimized.json   zh: name 30/30  subtitle 30/30  promo 74/170  desc 502/4000
                      en: name 30/30  subtitle 30/30  promo 155/170 desc 1321/4000
                      0 硬问题（4 条 margin 告警均为标题用满 30 的余量提示）

keywords-optimized-zh 23 个词，23 个在文案中落地     0 硬问题
keywords-optimized-en 11 个词，11 个在文案中落地     0 硬问题
```

---

## 5. 上线后的测试路线（Product Page Optimization）

App Store Connect 支持自定义产品页，**一次只改一个变量**，否则无法归因。

| 轮次 | 测试变量 | 对照组 | 处理组 | 观察周期 |
|---|---|---|---|---|
| 第 1 轮 | 首图 | 工作台全貌 | 情绪标签特写（按句插标签那一下） | 至少 2–4 周，看够样本再下结论 |
| 第 2 轮 | 中文副标题 | 场景词版 | 差异点版（按句调情绪） | 同上 |
| 第 3 轮 | 英文主标题 | `Emora AI Voice, Text to Speech` | `Emora: AI Voices & Emotion TTS` | 同上 |

判读规则：只看**产品页转化率**（展示 → 下载）和**搜索带来的下载占比**两个指标，不要拿绝对下载量下结论（受曝光波动影响大）。样本不足时不要提前换方案。

---

## 6. 追踪指标与口径

| 指标 | 在哪看 | 用途 |
|---|---|---|
| 产品页转化率 | App Store Connect → 分析与报告 | 判断文案与截图是否有效 |
| 来源分布（搜索 / 浏览） | 同上 | 判断 ASO 是否起效 |
| 分语言转化率 | 按地区筛选 | 决定先修哪一版 |
| 关键词排名 | 第三方工具（AppTweak / Sensor Tower 等） | Mac 品类样本稀疏，趋势比绝对值可信 |
| 评分与评价 | App Store Connect → 评分与评价 | 新 App 无评分会明显压制转化 |

**关于评分**：建议在用户**成功导出第一条音频之后**再请求评分（此时体验峰值），不要在启动时弹——早期弹窗换来的低分对转化的伤害大于收益。

---

## 7. 文案之外更大的杠杆（提一句）

文案能改的空间已经不大了，剩下的转化差距主要在视觉资产：

- **首图**是单个最大的转化杠杆——搜索结果里直接展示前 1–3 张，决定是否点进详情页
- Mac 产品页支持最多 **10 张截图 + 3 个 App 预览**（每个 ≤30 秒）
- 图标要在 16×16 尺寸下仍可辨识，且与「声音 / 情感」这个品类语义挂钩

需要的话，我可以接着出一份**截图顺序与首图分镜方案**（每张图传达什么信息、字幕文案、竖横版差异）。

---

**注**：以上给的是做法、口径与验证方法，不对排名、下载量做任何承诺。
