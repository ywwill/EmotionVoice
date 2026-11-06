# Emora · iOS App Store 预览图（英文版 v1）分镜与排版说明

> 日期：2026-11-06　平台：**iOS / iPadOS App Store**　本地化：**en-US**（一套覆盖 en-US / en-GB / en-AU / en-CA）
> 配套：`iOS商店页元数据-6语言.md`（名称 / 副标题 / 关键词）、`iOS预览图-中文版分镜.md`（中文版 v2.3 版式基准）
> 生成器：`素材/gen_ios_previews.py`　成品：`素材/ios-1320x2868/en-US/01…06.png`
> **与中文版的关系**：同构图、同尺寸、同 6 张顺序、同设备框与进度点。只换**字幕层**与**界面语言**，不重排构图。中文版成品在生成器重写后经 md5 校验**逐字节不变**。

---

## 0. 适用范围与一句话结论

| 项目 | 口径 |
|---|---|
| 画幅 | **1320 × 2868 px 竖版**、PNG / RGB 无 alpha、6 张（与中文版完全一致） |
| 覆盖本地化 | **en-US / en-GB / en-AU / en-CA 共用这一套**；见 §2 |
| 界面语言 | **全英文**，DOM 校验后可见中文文本节点 = **0** |
| 界面来源 | ⚠️ **英文设计稿样张，不是真机截图**；详见 §3、§6 |

⚠️ **最重要的一条**：英文商店页不能放中文界面截图（元数据审核 + 转化双重风险），所以这一版把 6 张界面的可见文案全部翻成英文。但它仍是**从高保真设计稿渲染出来的样张**，正式提审前必须换成英文真机截图，尤其是 02。

---

## 1. 六张英文字幕（逐字，可直接对照 ASC）

H1 两行（第二行渐变强调），H2 一行。括号为字符数，用于复核 106 px / 42 px 字号下的行宽。

| # | H1 第一行 | H1 第二行（强调） | H2 | 对应中文版 |
|---|---|---|---|---|
| **01** | `Give every line` (15) | `its own tone` (12) | `Tone tags change only the sentence they sit in` (46) | 按句加情绪，文字才读得像人 |
| **02** | `Hear it before` (14) | `you pick it` (11) | `Find a voice by name, trait or language` (39) | 海量音色，先听再选 |
| **03** | `Don't tune it.` (14) | `Just say it.` (12) | `Pick a language and tone, then describe it` (42) | 不会调参数？说出来就行 |
| **04** | `Fine-tune every` (15) | `little detail` (13) | `Speed, volume, MP3 / WAV and 6 sample rates` (43) | 想细调，也随时能细调 |
| **05** | `Replay, speed up,` (17) | `and export` (10) | `Scrub the waveform, check speed, format and voice` (49) | 回听、倍速、导出，都在一屏 |
| **06** | `All your audio,` (15) | `kept for you` (12) | `Grouped by day, easy to search, replay and export` (49) | 生成过的，都给你留着 |

**行宽约束**：H1 每行 ≤ 17 个西文字母（106 px 字号、1080 px 可用宽）；H2 ≤ 49 字符（42 px 字号）。实测六张 H1 恰好两行、H2 全部一行，320 px 缩略图下 H1 仍清晰。

**文案取舍**：

- 01 沿用 Mac v4 已验证的 `Give every line its own tone`，把「按句加情绪」这个唯一差异点放在首图；H2 解释「标签只影响所在句」而不是泛泛说「情感配音」。
- 02 用 `Hear it before you pick it`（先听再选）承载卖点，**H1 与 H2 都不写音色数量**；中文版 v2.2/v2.3 的「不写具体能力数量」口径原样沿用。H2 只描述真机搜索框真实支持的字段（名字 / 特质 / 语种），不承诺画面里不存在的筛选器。
- 03 用 `Don't tune it. Just say it.` 对应「说出来就行」。**不写 `24 languages`** —— `Constants.nlLanguages` 的 24 项是语音指令模块的可选目标语言/方言，不是产品支持语言总数，界面底部还写着「Commands accept Chinese and English only」，写成数量会自相矛盾。
- 04/05/06 全部是「动作 + 收益」句式，不含数字能力宣称、不含价格、不含竞品名、不含 iOS 端未实现的声音复刻/克隆。

---

## 2. 为什么一套能覆盖四个英文区

| 依据 | 说明 |
|---|---|
| 元数据既定口径 | `iOS商店页元数据-6语言.md` 里四英文区**名称与副标题共用**，只有关键词字段四套独立；截图不参与关键词索引，所以没有做地区差异的必要 |
| 文案刻意避歧 | 全组字幕**避开** `favorite/favourite`、`color/colour`、`voiceover/voice-over`、`organize/organise`、`center/centre` 等英美拼写差异词；`MP3 / WAV`、`00:24` 之类是格式/时间，各区写法一致 |
| 界面文案同理 | 界面用 `Studio / Voices / Projects / Saved / Size` 等中性词；`Saved` 而非 `Favorites`，避免美英拼写分歧 |
| 上传方式 | App Store Connect 里 en-US / en-GB / en-AU / en-CA 各自上传**同一批 6 张 PNG** 即可；若想按目录管理，复制 `ios-1320x2868/en-US/` 到另外三个 locale 目录（见 §附 命令） |

⚠️ 这不等于四个地区可以共用一套**关键词**：关键词仍按元数据文档里的四套独立填写，别把「共享核心 9 词 + 地区变体」改回零重复方案。

---

## 3. 界面英文化怎么做的

生成器把 6 张界面的可见文本节点按 **精确字典 `EN_DICT` + 数字单位正则 `EN_RULES`** 替换，译文优先取 App 自己的 `en.lproj/Localizable.strings` 与 `en.lproj/VoiceCatalog.strings`（音色名如 `龙安灵心 → Lynn`、`龙安鲁风 → Lucas`），设计稿特有的展示文案按同一口径补齐。

| 处理 | 原因 / 结果 |
|---|---|
| 界面层走西文字体栈 | `Helvetica Neue`，避免 PingFang 渲染拉丁字母偏宽把 H1 折成三行 |
| 01 编辑区 7 段脚本翻成英文 | 保留 **4 种情绪色胶囊 + 2 个拟声 + 2 段无色默认语气对照**，首图仍能一眼读出「同一段文字里不同句子颜色不同」；字数标签由 `100 字` 改为按英文正文重算的 `215 characters`（与 App 英文文案 `"%d 字" = "%d characters"` 一致） |
| 03 的 24 个语言 chip 按 `LANGS_EN` 生成 | 用短名（Chongqing / Sichuan / Dongbei / Malay / Filipino …），并把 Sheet 缩放由 `1.08` 降到 `0.98`，保证 24 个 chip 一屏放得下；第一枚 `Chinese` 保持选中态 |
| 05 的积分字段 | 中文版处理链是「积分 → 大小」，英文版再翻成 `Size`，值 `412 KB`；不出现积分/价格类数字 |
| 06 统计条 | 「128 条音频 / 18 条本月」→ `128 clips` / `18 this month`；数字与单位在设计稿里是**分开的文本节点**，所以字典里要单独放 `条音频` / `条本月`，光靠带数字的正则会漏 |
| 02（en-US 专用） | **暂无英文真机截图**，退回 `emotionvoice-ios-design.html` 的音色库界面：结构与中文真机一致（**只有「All Categories」一行筛选、没有独立语种 chips 行**），语种只写在搜索框 `Search name, trait, scene or language`；剥掉 `599`、结果行改 `Flagship first, then by name`、补 4 张英文音色卡填满下半屏、移除「上拉加载更多」 |

⚠️ 02 的 4 张英文卡与「♡ 12」是设计稿样张数据，不是真机状态（中文真机版是「♡ 3」）；**提审前必须换成英文真机截图**。

**界面语言校验**：用 Chrome `--dump-dom` 遍历可见文本节点、过滤含 CJK 的节点，6 张界面残留均为 **0**。这个校验应在每次改字典后重跑。

---

## 4. 版式规范

与 `iOS预览图-中文版分镜.md` §3（v2.3）**完全一致**：

- H1 106 px / 800 / `top:36` 贴画布最顶部；H2 42 px / 距 H1 24 px；无品牌行、无序号
- 设备 1033 × 2240、`top:538`、圆角 112；屏幕内圆角 99；6 点进度指示 `bottom:40`
- 浅雾紫 Aurora Pop 背景，深色标题 + 紫→玫红渐变强调词
- 灵动岛由界面素材自带，母版不另画
- 唯一差异：`CSS_EN` 把字体栈换成西文并去掉 H2 字距（`.sub{letter-spacing:0}`）

**缩放自检**：`素材/ios_previews/_320px自检-en.png` 已通过 —— H1 清晰、H2 可辨、情绪色块可见、顶部干净。

---

## 5. 文案承诺 ↔ 画面兑现核对

| 承诺 | 由哪张兑现 | 状态 |
|---|---|---|
| 按句插情绪标签 | 01（7 段英文脚本、4 色胶囊 + 拟声、2 段无色对照） | ✅ |
| 音色丰富、可搜索可试听 | 02（搜索框 + All Categories + 8 张英文卡 + 试听态，不写数量） | ✅ |
| 一句话下指令 + 6 个预设 | 03（指令输入框 + 6 个英文预设 + 24 个语言 chip） | ✅ |
| 语速 / 音量 / MP3·WAV / 采样率可调 | 04（Speed / Volume / Format / Sample Rate + 6 档） | ✅ |
| 回听、倍速、导出 | 05（波形 + ±15/±5 + 1.0x + Copy Audio）+ 06（列表 + mini player） | ✅ |
| 按日分组、搜索、收藏 | 06（Today / Yesterday / All / Saved / 搜索栏） | ✅ |
| 不写具体能力数量 | 全组字幕无数字；02 无 `599`、03 无「展开全部 24」 | ✅ |
| 界面语言与商店页本地化一致 | 6 张界面全英文，可见中文文本节点 0 | ✅ |
| 图上无价格、无积分、无未实现功能 | 全组无 | ✅ |

---

## 6. 待办与风险

| 优先级 | 待办 | 说明 |
|---|---|---|
| **P0** | **02 的英文真机截图** | 在英文系统的真机/模拟器上截音色库，同名覆盖 `raw/en-US/voices-1.png` 后跑 `--html-only --export`。真机自带「All Categories 599」，换图后要按「不写具体数量」口径复查；真机没有独立语种行是**正确**的，别为了对齐旧样张去改 App |
| **P0** | 其余 5 张英文真机截图 | 同上，同名覆盖 `raw/en-US/`；换图后重跑界面中文残留校验不再适用（真机本来就是英文），改为人工看图 |
| P1 | 四英文区上传 | 同一批 6 张分别上传到 en-US / en-GB / en-AU / en-CA；关键词仍按四套独立填 |
| P1 | iPad 13" `2064×2752` | App 支持 iPadOS，必须另出一套，不能用 iPhone 图拉伸 |
| P2 | zh-Hant 套图 | 同构图 + 繁中界面截图 + 繁中字幕；字幕沿用「不写具体数量」口径 |
| P2 | 首图 A/B | 见中文版 §1 PPO：换成「编辑中」上半部特写，一次只改一个变量，只看产品页转化率 |

⚠️ **不能直接提审**：这一版和中文版一样是设计稿样张。App Review 要求截图反映真实 App 界面；把带设计稿假数据的样张传上去，也可能因「界面与实际不符」被要求补正。

---

## 7. 验收清单

- [x] 6 张 `1320×2868 / PNG / RGB 无 alpha`，逐张 PIL 断言
- [x] 六张 H1 恰好两行、H2 一行、全部贴顶无裁切；六张字体/设备框/灵动岛/进度点统一
- [x] 界面可见中文文本节点 = 0（Chrome DOM dump 校验）
- [x] 02 无独立语种筛选行、无 `599`；03 无「24 languages」类表述
- [x] 字幕无英美拼写差异词，一套可覆盖四个英文区
- [x] 320 px 缩略可读性自检通过；评审入口 `index.html` 渲染 6 卡无破图
- [x] 中文版成品在生成器重写后 md5 **逐字节不变**（回归验证）
- [ ] 逐图与当前英文版实机对比：界面功能在 App 里点得出来
- [ ] 真机英文截图替换完成后重跑 `--html-only --export` 并删除样张
- [ ] 四英文区分别上传；关键词字段按四套独立填
- [ ] iPad 13" 套图补齐
- [ ] 提审前以 ASC 上传页实时尺寸提示复核一次

---

## 附：文件清单与命令

| 路径 | 内容 |
|---|---|
| `素材/ios-1320x2868/en-US/01…06.png` | 英文版 6 张成品 |
| `素材/ios_previews/html/en-US/01…06.html` | 1:1 HTML 母版；`index.html` 为评审入口 |
| `素材/ios_previews/raw/en-US/*.png` | 6 张英文界面素材（换真机截图即覆盖这里，同名） |
| `素材/ios_previews/_6张总览-en.png` | 英文六图拼版 |
| `素材/ios_previews/_320px自检-en.png` | 英文首图 320 px 缩略自检 |
| `素材/gen_ios_previews.py` | 多本地化生成器（`LOCALES = ["zh-Hans", "en-US"]`） |

```bash
cd 产品/商店页/素材

# 只重出英文（界面 + HTML + PNG）
python3 gen_ios_previews.py --locale en-US --export

# 两套一起重出（默认行为）
python3 gen_ios_previews.py --export

# ⚠️ 换真机截图后：必须带 --html-only，否则会重新从设计稿提取并覆盖掉新截图
python3 gen_ios_previews.py --locale en-US --html-only --export

# 一套英文图复制到另外三个英文区目录（可选，方便 ASC 分别上传）
for loc in en-GB en-AU en-CA; do
  mkdir -p "ios-1320x2868/$loc" && cp ios-1320x2868/en-US/*.png "ios-1320x2868/$loc/"
done
```

**注**：以上给的是构图、信息分配与验证方法，不对转化率、排名或下载量做任何承诺。
