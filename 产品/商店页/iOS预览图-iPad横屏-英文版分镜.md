# Emora · iPad App Store 预览图（横屏 2752×2064 · 英文版 v1.1）分镜与本地化说明

> 与简体中文版同版式、同构图、同 5 张顺序。界面来自用户 2026-11-07 提供的 **英文 iPad 真机截图**
> （`素材/ios_previews_ipad/real/en-US/`，只读）。字幕逐字沿用 iPhone 英文组，两个尺寸槽在 ASC 里
> 分区展示但文案统一，做 A/B 时只剩画面这一个变量。

---

## 1. 成品规格

| 项 | 值 |
|---|---|
| 画布 | 2752 × 2064 px（iPad Pro 13″ 横屏，ASC 的 iPad 13″ 槽） |
| 色彩 | RGB、无 alpha |
| 张数 | 5 张（Apple 允许 1–10 张） |
| 版式 | H1 106px `top:58` 居中 → H2 42px → 设备 2117×1598 `top:412` → 5 个进度点 |
| 界面 | 真机 2224×1668，`transform:scale(.965)` 内缩（避免设备圆角吃掉状态栏时间） |
| 字体 | 字幕走西文字体栈 `-apple-system/Helvetica Neue`（PingFang 渲染拉丁字母偏宽，会把 H1 折成三行） |

产物：`素材/ios-2752x2064/en-US/01…05.png`
评审页：`素材/ios_previews_ipad/html/en-US/index.html`
总览：`素材/ios_previews_ipad/_5张总览-en.png`

---

## 2. 五张分镜与字幕

| # | H1 | H2 | 画面 |
|---|---|---|---|
| 01 | Give every line<br>**its own tone** | Tone tags change only the sentence they sit in | 创作页·参数侧栏：4 色情绪标签密布的 4110 字 AI 稿 + 音色/语速/音量/格式/采样率 |
| 02 | Hear it before<br>**you pick it** | Find a voice by name, trait or language | 音色库 5 列 × 4 行英文音色卡 |
| 03 | Don't tune it.<br>**Just say it.** | Pick a language and tone, then describe it | 创作页·语音指令侧栏：纯文本口播稿 + Language chips / Description Presets |
| 04 | Replay, speed up,<br>**and export** | Scrub the waveform, check speed, format and voice | 播放详情：波形、±15/±5s、时长/格式/积分/音色、正文、Rename/Duplicate/Delete |
| 05 | All your audio,<br>**kept for you** | Grouped by day, easy to search, replay and export | 历史记录：统计条 + chips + 16 条不同记录 |

对应简体组：iPad 5 条 = iPhone 组的 01/02/03/05/06（iPad 组没有独立的「参数页」字幕，
参数卖点由 01 画面承载）。

**四英文区（US / GB / AU / CA）共用这一套图**：文案刻意避开 favourite/favorite、colour/color、
voice-over 等拼写差异，一套可覆盖四个商店地区；但**关键词字段必须四套独立填写**，
Apple 索引按地区单独计算，截图共用不等于关键词可以合并。

---

## 3. 五处本地化处理（`prepare_ipad_real.py`）

英文真机图的界面本身已经英文化，实际只处理残留与数据质量，其余像素原样保留。

### ① 用户点名的「4」— 播放详情页

| 位置 | 原图 | 成片 |
|---|---|---|
| 顶部文件名 | 清晨，当你被手机闹钟 副本 | **A Morning with AI** |
| 元信息 | 130 Chars · 4 Sentences | **526 Chars · 4 Sentences**（随文稿重算） |
| 正文两行中文 | 清晨，当你被手机闹钟唤醒…AI 早已不是科幻电影中的遥远想象… | 一段完整英文文稿，自动折 3 行、**左右铺满卡片**：*Your phone wakes you at the best point…* |

> ASO 判断：真机文件名带「副本」，直译成 `- Copy` 会让商店图看起来像未整理的测试账号。
> 这是转化层面的负面信号，成片改用干净的自然文件名，不逐字直译。

**v1.1 优化：文稿卡左右填满。** 早期译文按 3 句手断成 3 行，英文字符比汉字窄得多，
每行只到 x≈1160、卡片右侧近 900px 全空（卡片右边界 x≈2120），缩略图里像稿子没写完。
现在改为**整段自然换行 + `text-align:justify` / `text-align-last:justify`**：
文本区 `left:100px; width:1990px`，526 字符恰好折成 3 行且第 3 行也接近满宽，
三行右端都精确到 x≈2087，词距只有几像素的微调，不会出现「字被拉开」的拉伸感。
⚠️ 字数不能随便改：少 30 字符第 3 行会短一大截，多 30 字符会折出第 4 行溢出卡片。
简体中文版 04 是真机原稿、两行本就接近满宽，**保持原像素不动**。

### ② 用户点名的「5」— 历史记录页

真机 16 张卡全是同一条中文标题「清晨，当你被手机…」。沿用简体版同口径处理：
换成 **16 条不同英文记录**（Waking up to your phone alarm / Unboxing: the portable speaker /
Bedtime story: The Bear's Moon …），音色名取自 02 真机里的英文名（Lynn / Lucas / Abigail / Ada …），
时长与大小沿用简体组，合计约 6.9 MB 与顶栏「6.81 MB」自洽。

- 头像规则按英文真机：**音色名末字母小写**（Lynn → `n`、Lucas → `s`），不是简体版的末字汉字。
- 统计条 / chips / 分组标题 / 底部标签栏保持真机英文原样，只换卡片数据。

> 转化理由：16 张一模一样的卡在缩略图里读作「占位数据」，会削弱「产品真的在被人用」的可信度。
> 这不是为了好看，是为了让第 5 格真的承担「历史可管理」的证明责任。

### ③ 02 抹掉具体数量

真机筛选行是「All Categories **599**」。按全组禁令（不写具体音色/语言数量），抹掉 599 并把
下拉箭头重画在文字右侧。右侧「♡ 2」收藏数保留。

### ④ 03 与 01 去重（沿用 v3.1 结论）

英文真机 01/03 左栏都是 4110 字 *What Is Artificial Intelligence?* 同一篇稿，连情绪标签都逐字相同，
缩略图里几乎像同图传两遍。03 按「另一次创作」处理：

| | 01 | 03 |
|---|---|---|
| 左栏 | 彩色情绪标签密布 | 16 行 *City Walks* 口播稿，**无标签** |
| 字数 / 积分 | 4110 characters · ≈ 82.2 | **712 characters · ≈ 14.2** |
| 右栏 | 参数滑块 | Language chips / Description Presets（真机原样） |

积分按真机比例 `字符数 / 100 × 2` 换算，与 App 计费口径一致。

> 英文真机 03 因 chip 文案更长，描述输入框被挤出屏幕（与简体版不同）。成片不造假补框，
> 右栏保持真机；「不用调参数」的信息由 Language chips 与 Description Presets 承载。

### ⑤ 全 5 张状态栏日期

真机状态栏仍是中文「11月7日周六」（用户只切了 App 语言）。统一换成 **Sat Nov 7**，
避免英文商店图里出现中文字符。⚠️ wipe 必须从 x≈90 起：中文日期从 x≈97 开始，
只盖 x≥114 会残留「11」并与新文字叠成 `1 Sat Nov 7`。

---

## 4. 实现方式

- `en_wipes()`：PIL 用区域众数底色抹掉中文 / 599 / 旧数字（保留波形、滑块、头像色块、按钮、图标）。
- `en_body()` + `overlay_png()`：Chrome headless `--default-background-color=00000000` 输出
  2224×1668 **RGBA 透明覆盖层**，`Image.alpha_composite` 贴回，没有矩形接缝。
- 卡片类区域（03 左栏、05 十六卡）用**与真机同形的白色圆角矩形整块覆盖**，不能只盖文字区，
  否则旧彩色胶囊的圆角边缘会露在两侧。
- 真机源 `real/en-US/` 只读，产物写 `raw/en-US/`；任何命令都不会覆盖用户原图。

---

## 5. 验收清单

- [x] 5 张均为 2752×2064 / RGB / 无 alpha
- [x] 每页 5 个进度点、当前页高亮正确
- [x] 英文 H1 全部两行，未折成三行；字幕与简体组逐字对应
- [x] 界面无中文字符残留（状态栏、04 标题/正文、05 卡片逐一放大复核）
- [x] 04 文稿三行左右铺满卡片、右侧无大片留白，无溢出、无字距拉伸（v1.1）
- [x] 02 无「599」，全组不写具体能力数量
- [x] 01 与 03 缩略图一眼可分
- [x] 05 十六张卡各不相同、头像为完整字母、无叠影与色块接缝
- [x] 状态栏时间（12:23 → 12:26）完整、日期统一 Sat Nov 7
- [x] **回归：zh-Hans 5 张 md5 逐字节不变**

---

## 6. 待办 / 下一步

### 香港繁体中文版（zh-Hant）— 已完成

5 张繁体真机截图已归档并出图，详见 `iOS预览图-iPad横屏-繁体版分镜.md`。
⚠️ 繁体**不能**复用本页的 `localize_en()`：那套覆盖层会把整页写成英文。
`prepare()` 已拆出 `zh-Hant → localize_hant()` 独立分支，繁体界面保留真机像素，
只处理用户内容里的简体稿与重复测试数据。

### 其他

- 04 播放详情下半屏约 30% 留白是产品真实状态，未造假填充；要更饱满需 App 侧补内容或换截图。
- 05 卡片时间用了具体时刻（19:53 → 09:12），真机显示的是 "Yesterday"；两套图保持一致更重要。
- iPad 竖屏 2064×2752 槽未做；ASC 同一尺寸槽只能传一组，横屏这一组已覆盖 iPad 13″ 展示位。
- 提审前建议用 Product Page Optimization 对 01 与 02 的首图顺序做一次 A/B，观测各地区的
  「展示 → 首次下载」转化率，而不是凭偏好定顺序。

---

**版本**：v1.1 · 2026-11-07（04 文稿卡左右填满）
**素材**：用户提供的 5 张英文 iPad 真机截图
**生成器**：`gen_ios_previews_ipad.py` v4 + `prepare_ipad_real.py`（04 排版 v4.1）
