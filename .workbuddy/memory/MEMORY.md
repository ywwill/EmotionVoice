# EmotionVoice 长期约定（只留「禁令 / 根因 / 入口」）

实现细节见 `.workbuddy/memory/YYYY-MM-DD.md`；商店页版式/本地化细节见 `产品/商店页/iOS预览图-*.md`、`iOS预览图-iPad横屏-*.md`。

## 工程 / 构建
- target `Emora`(macOS) / `iOSEmora`(iOS 18.6)；SPM：SQLite.swift / supabase-swift / keychain-swift。iOS 独有 `View/iOS/`；复用 macOS 文件**原地加入 iOS target**，`#if canImport(AppKit)` 隔离。新增 iOS .swift 须改 pbxproj 4 处（ID `7B3A...`）→ **优先塞进已有文件，零 pbxproj 改动**。
- SQLite **永不迁移**：改 `createTables()` 就 bump `currentSchemaVersion`，不符 DROP 重建。
- 构建 `bash tools/ios_build.sh`（`mac` 回归双 target）；类型检查 `bash tools/ios_typecheck/typecheck.sh`（`Shims.swift` 须同步加桩）；workaround `IDEPackageSupportDisableManifestSandbox` / `-disable-sandbox` / `ONLY_ACTIVE_ARCH=YES`。
- ⚠️ 四配置默认 `SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor`：后台纯计算显式 `nonisolated`（**私有 helper 一起加**），静态非 Sendable 用 `nonisolated(unsafe)`。Swift 5 违规仅 warning，**验证须 grep 构建日志**。
- macOS 首屏 `.defaultSize(visibleFrame)` + `viewDidMoveToWindow()` 同步配置，禁 `DispatchQueue.main.async` 延迟 setFrame。

## TTS / 本地化
- 无密钥 `wss://<ref>.supabase.co/functions/v1/bailian-tts?region=CN|INTL`，单条 `{"action":"synthesize"}`；断线不可续传；Deno<2.5 用 `dialUpstream()`。
- `.localized()` 中文原文当 key；⚠️ 禁 `String(format:"…%@…".localized(), arg)`，须 `"…%@".localized(arg)`。
- 三语 zh-Hans/zh-HK/en；⚠️ 改中文 key 须**三份 strings + macOS/iOS 两端引用一起改**。仿音色文案在 `<lproj>/VoiceCatalog.strings`；繁体 OpenCC `s2t`+覆写，**别用 s2hk**。

## 音色 / 标签
- 唯一数据源 `Voices/basic_voices.json`(v4)，改后跑 `tools/gen_basic_voices.py`。
- 语气/拟声标签唯一来源 `Shared/Models/Constants.swift`：`emotions` 24 项、`richLanguageTags` **只有 7 个官方拟声**。⚠️ 商店图禁自造标签。
- 胶囊整条热区 `contentShape(Rectangle())`；刷新过渡用 `contentVisible`，`.id(scrollResetID)` 只管滚回顶部。
- 中断 API 不支持 → `toTTSAPIString()` 丢弃，生成走 `toTTSSegments()` + `AudioConcatenator.merge()`。
- ⚠️ iOS 分类筛选**只在进程内保留**（`VoiceLibraryFilterStore`）；禁读写 `AppState.voiceLibrary*`。
- ⚠️ `VoicesLibraryView`/`VoicePickerSheet` 的 `apply` **取消也要 `commit(fresh,total)`**（只跳过动画），否则永久空态；另配 `onAppear` 自愈。

## macOS 输入框 / 语气标签
- 入口 `View/macOS/VoiceStudioView/EmotionToken/EmotionTokenTextView.swift`（`toneCapsuleGeometries()` 自绘胶囊）+ `View/macOS/EmotionHighlightedTextEditor.swift`（旧版 NSTextView 高亮）。绘制与命中同源（`tokenHitRegions()`）。
- ⚠️ **纯空行必须过滤**：AppKit 把 `\n` 单独排成 line fragment，`location(forGlyphAt:)` 对它返回**行底**（lineSpacing=28 时 y=45，正文行 14），`baseline = lineRect.minY + location.y` 会把空行胶囊整体推到下一行正文位置、上下叠 14.5pt → 「空一行就背景框重叠」。枚举行片段时用 `capsuleInvisibleCharacters`（空白/换行/U+3000/U+FFFC）判空后 return。
- ⚠️ `boundingRect(forGlyphRange:in:)`：高度含 lineSpacing 不可信（胶囊 y 由 `baseline ± ascender/descender` 推）；宽度会把行尾换行 / 空白算到容器右边界，短行胶囊因此满宽。必须裁掉该行首尾空白（`capsuleTrimCharacters`，**不含 U+FFFC**，拟声 pill 要留在胶囊里）后 `glyphRange(forCharacterRange:)` 再取 br → 胶囊只包有字形部分 + 8pt 内边距。
- **视觉 v14 对齐商店页 01.html**：胶囊 = 实色底（`accent` 按 0.28 混进 `#15171B`，`accent = base.darkened(0.48)`）+ **顶部 2pt 亮线、四周不描边**、圆角 8；徽章 = accent 20% 底/50% 描边/近白字（⚠️ 半透明层下先铺不透明编辑器底色）。⚠️ 别退回 `base.withAlphaComponent` 直叠；选中光环仍用原始亮色 `base`。

## iOS UI / 编辑器
- `ScreenMetrics` 分档 <375 / 375–659 / **660–1023** / ≥1024；两栏 `width>=740 && isWide`；3 标签+各自导航栈；二级页隐藏 tabBar 由 `TabRouter.isTabBarHidden` 驱动；Sheet 统一 `SheetNavBar`；同层不挂两个 `.alert`。
- ⚠️ **iPad**：`isPadClass = width>=740 && height>=700`（别用 `sizeClass==.regular`）；两栏编辑卡高度**必须由 GeometryReader 实测** `geo.height-20`，`editorMinHeight` 只兜底、禁夹 520 上限；`wideLayout` 只加一层 `.padding(.horizontal,pageMargin)`，别和 `pagePadding()` 叠加。
- ⚠️ **iPadOS 18 标签栏在顶部**，底部无 tabBar：浮层用 `metrics.tabBarClearance`，禁硬写 58。
- ⚠️ **参数面板单一数据源**：`StudioParamSheet.swift` 的 `StudioParamContent` = 完整参数正文；iPad 侧栏直接铺（`sampleRateColumns:2`，高度**必须**钉 `editorHeight`），iPhone 走「摘要条 → Sheet」，侧栏宽 360。改控件只改 Content 一处。
- ⚠️ 打字不经过 SwiftUI：`TokenEditorStore`（`doc`/`marks` 非 @Published），三类标记各占 1 个 U+FFFC；accessory 只在 `isDark` 翻转重建；overlay 字段加相等判断才重绘。
- ⚠️ 光标高度 = 正文一行字高：`TokenTextEditor.swift` 的 `TokenCaretTextView` 重写 `caretRect(for:)` **只削 height、保留 super 的 origin**；`lineSpacing=26` 被算进 `lineFragmentUsedRect`，UIKit 会拿 45pt 整行片段画插入符。禁改 lineSpacing / typingAttributes 修光标（会连带胶囊与行距）；子类塞进已有文件零 pbxproj 改动，且必须 `usingTextLayoutManager:false`（TextKit 1）。
- 底部条不压 accessory：`onKeyboardTopChanged` 报 min(键盘, accessory) → `keyboardSeam`；容器 didSet 自改 frame、`safeAreaInsets=.zero`。

## 播放器 / 订阅隔离（关键）
- ⚠️ 播放器**按 target 拆两份同名 `AudioPreviewPlayer`**（API 逐字对齐）：macOS 版只挂 Emora、iOS 版只挂 iOSEmora；`typecheck.sh` 的 `MAC_ONLY` 与 `add_ios_target_files.py` 的 `REUSED` 必须排除 macOS 版。
- iOS：AVAudioSession `.playback` + `iOSEmora-Info.plist` 的 `UIBackgroundModes=[audio]`（⚠️ `INFOPLIST_KEY_UIBackgroundModes` 对数组键无效，须 `INFOPLIST_FILE` 模板 + `plutil -extract` 验产物）。⚠️ 封面 `makeArtwork` 全幅不透明渐变（`opaque=true`、禁 `addClip`）。
- ⚠️ **iOS 播放/切倍速 CPU 暴涨根因 = SwiftUI 订阅拓扑**：`PlaybackStatus` 只订阅单属性 publisher；高频显示只许 6 个小 View 各自 `@ObservedObject`；禁 `@StateObject player`；`ProjectsView.row(_:)` 禁把 progress 传给所有行。
- `playingKey` 存 identifier，跨 key 用 `reidentify(_:)`；⚠️ 并发闭包「外层 `guard let self` + `Task @MainActor`」。
- iOS `transportRow` 与 macOS `PlayerTransportView` 同构：±15s/±5s 走 `player.skip(by:)`；「从头播放」只在工具行。⚠️ 步长写字面量别抽常量。

## iOS 历史记录 / 列表（v2）
- `HistoryListViewModel` 一次全量 `fetchAllAudios()` 50/批；`Shared/HistoryViewModel` 属 macOS 保持原样。
- ⚠️ 收藏与软删绝不入库：`AudioFlagStore`（UserDefaults JSON，30 天），软删只打标，`purgeExpired()` 交 `ProjectService.deleteAudio`。
- 播放跨页保留；`identifier=item.fileName` 经 `NowPlayingStore`。浮层互斥链：撤销 Toast > 后台接收条 > mini player。
- ⚠️ `MiniPlayerView` 品牌渐变底+白字、**height=56**；`ProjectsView` 按 `miniPlayerVisible` 在 List 末尾插透明占位 Section。卡片进度条只 `scaleEffect(x:,anchor:.leading)`，**绝不自加 `.clipShape`**。
- ⚠️ `.plain` List 必须清零系统留白（`.listSectionSpacing(0)` + `defaultMinListHeaderHeight=0` + `.contentMargins(.top,0)`）；垂直节奏只由 chips 底 10pt + 组头 顶 13/底 7。时间分组**按自然日**（组头 `yyyy.MM.dd`）。

## 积分 / 生成弹窗
- 积分全链路 Double(≤2位)：`CreditPrecision.normalize`，计费 `字符数/100*rate`（普通2/复刻5），CJK 算 2 字符，云端 `numeric(10,2)`。
- `GenerationDialog` 完成态 `displayName = defaultAudioName(...)`；`commitName()` 清空须写 `displayName: nil`；`hasResult = generatedAudioURL != nil && !isGenerating`。
- ⚠️ `PackageCard` 副标题禁 `.lineLimit(1)`（英文译文被截）。

## 创作参数持久化（两端共用）
- `StudioParamValues`/`StudioParamStore` 在 **`Shared/ViewModels/VoiceStudioViewModel.swift`**（零 pbxproj 改动）。键 `studioParam.*`；两端 `onAppear` → `restoreIfNeeded`、4 个 `.onChange` → `save`。
- ⚠️ 禁把 `AppState.defaultFormat`/`defaultSampleRate` 当存储；⚠️「重置」两端只调 `reset(on: vm)`，禁传 `defaults`（否则重置回 WAV）——重置 = `.factory`（mp3/22050/1.0x/100%）。
- 默认值一律读 `Constants`/`.factory`；`defaultFormat` 已改 `mp3`，全链路（VM/`.factory`/`BailianTTSService`/云端 `bailian-tts/index.ts`）同步，且不覆盖已有存档；`VoiceStudioView.onAppear` 旧的「从设置页覆盖参数」已删，**别加回来**。

## 商店页 / ASO（Mac 与 iOS 两套独立索引）
- **Mac v4**：`商店页文案-多语言版本.md` + `素材/gen_previews.py` + `素材/html/{zh,en}/` + `素材/mac-2880x1800/{zh,en}/`，深色 16:10、6 张。01/02/03/06 真机图 `raw/<lang>/1-4.png`，04/05 设计页。
- ⚠️ **Mac 01 中英两端覆盖层**（v4.5）：`_studio_overlay(lang)` + `studio_overlay_zh/en()`，在 `.win` 内叠层，**raw 坐标 + 整体 transform scale**；先 wipe `#15171B`（y220→1380，卡片分隔线 ≈1450 别碰）再重绘。⚠️ **禁铺满**：`LINES_ZH` / `LINES_EN` 各排一整篇文稿（16 正文行 + 2 空行 = 18 显示行，行距 62 / 行高 42），行宽 = 文本自然宽度，**删掉全部 `letterSpacing` 拉伸 JS / 禁 justify**，短句与段落末行故意留白（Chrome `--dump-dom` 实测 zh 26%–86% / en 38%–86%，均 < 2121）。⚠️ **模拟正常输入**：连续文稿自然换行 + 段落空行；语气徽章只在语气切换首行的胶囊左上角（12 个），同色胶囊跨行延续不重复徽章；拟声 pill 5 个嵌在句子中途，**禁两个徽章并排**。依据 `EmotionToken/README.md` v13 + 用户 09:16 / 09:20 真机参考截图。标签取自 `Constants.swift`（24 情绪 + 7 官方拟声），**英文用词必须读 `en.lproj/Localizable.strings`**（Excited/…/Giggle），下方标签栏已是全量**禁再加**。
  - ⚠️ **两端缩放不同**：zh raw 3456×2062 → `2112/3456`；en raw 3442×2044 → **`2122/3442`**，套错会偏约 10px。`OV_CSS_EN` 换西文字体栈 + 剥掉 CSS 中文注释（英文 HTML 零 CJK），中文 `OV_CSS` 逐字节不动。
  - ⚠️ **计数/积分各一套**：zh `%d 字`（0.04/字，753→≈30.2）/ en `%d characters`（字符数/50，2053→≈41.1）；英文计数 wipe x2360 w275（"771 characters" 更长）、积分 wipe x3120 y178 h54、数字显示 x3126 y184，**别套中文 x3112**（会吃掉 `Estimated` 后的空格）。
  - 跑 `python3 gen_previews.py zh,en --only=01` → `python3 gen_previews.py en --export --only=01`（`--only` 须同时限制 build/export）。中文分支输出必须 md5 零回归。
- **iOS iPhone**：元数据 `iOS商店页元数据-6语言.md` + `ios-store-copy/`；预览图 `gen_ios_previews.py` + `ios-1320x2868/<locale>/`。
- 字段：名称/副标题 30 / 关键词 **100 字符含逗号、逗号后不加空格**；四英文区**名称副标题共用、关键词四套独立**（共享 9 词核心 + 地区变体），别改回零重复方案。
- ⚠️ iOS 端**没有声音复刻/克隆 UI**；⚠️ **字幕禁写具体能力数量**（`599`、「24 种语言」），`Constants.nlLanguages` 24 项只是语音指令目标语。
- 尺寸（2026-11-06 核官方）：6.9" `1320×2868`（1–10 张、**禁 alpha**）；iPad 13" 横屏 `2752×2064`（竖屏 2064×2752 **未做**）。
- iPhone 版式 v2.2 Aurora Pop：无品牌行/序号、H1 106px `top:36`、设备 1033×2240 `top:538`、dots `bottom:40`；Sheet `top:52px`+`zoom:1.22`（03 展开语言 1.08）。⚠️ 流程「HTML 确认构图 → 真机图覆盖 `raw/<locale>/` → **`--html-only --export`**」，漏 `--html-only` 会覆盖真机图。02 是真机、其余 5 张仍是设计稿样张，**不可直接提审**；en-GB/AU/CA 复用 en-US 一套图。
- iPhone 多本地化：`LOCALES`/`paths(locale)`/`PAGE_OVERRIDES`/`COPY`/`--locale`；英文靠 `EN_DICT`（优先取 App `en.lproj`）+`EN_RULES`，⚠️ 数字与单位是**分开的文本节点**；03 第一枚 chip 必须 `ALL[0]` 覆盖。
- ⚠️ **繁中不用纯 s2t**：`HANT_DICT` 运行时解析 App `zh-HK.lproj` 两份 strings + `HANT_OVERRIDE`，未命中走 OpenCC 单字兜底，`HANT_CHAR_FIX` 改「爲/衆/裏/啓/臺」→「為/眾/裡/啟/台」；字体必须 `PingFang TC`。DOM dump 校验简体残留 = 0。

### iPad 横屏（真机版 · 5 张 · 三语齐）
- 入口：`ios_previews_ipad/real/<locale>/` 用户真机图**只读** → `prepare_ipad_real.py` → `raw/` → `gen_ios_previews_ipad.py --locale <loc> --export`。`LOCALES=[zh-Hans,en-US,zh-Hant]`；⚠️ 缺真机图的语言**跳过**而非回退自绘。
- 5 张固定：01 创作参数态 / 02 音色库 / 03 创作指令态 / 04 播放 / 05 历史。**删 04 生成浮层**；创作页「输入框/参数/指令」是同一界面（左栏固定、右栏切换）。设备圆角吃状态栏 → `.screen img{transform:scale(.965)}`。
- ⚠️ **每批新截图必须拼索引图核对编号**：英文批次 `1=studio/2=voices/3=command/4=projects/5=player`；繁体批次 `1=studio/3=voices/2=command/5=player/4=projects`。`map_for(locale)`：zh-Hans 用旧编号 01/02/03/05/06，新语言 01–05。
- ⚠️ `prepare()` **三条独立分支**：`zh-Hans` 原路径 / `en-US → localize_en()` / `zh-Hant → localize_hant()`。**禁把 zh-Hant 塞进 `localize_en()`**。`render_cards()` 已参数化，简体默认参数逐字节不变。
- 通用数据优化：02 抹「599」重画箭头（简体 wipe x258、繁体 x260）；05 用 Chrome RGBA 覆盖层把 16 张重复卡换成 16 条不同记录（**只换数据**）。⚠️ 头像 = **音色名末字白色汉字**（英文用末字母小写）；覆盖层元素必须带 `.a`(`position:absolute`)。
- ⚠️ 03 与 01 重复：`fix_command()` 换无标签口播稿（253 字）+ 字数/积分同步 + 右栏真实指令；**必须用白色圆角矩形整块盖**（x65/y145/1340×1245/r24），只盖文字区会留旧胶囊残影；描述框手动 `<br>` 断句。
- ⚠️ **04 文稿卡必须左右铺满**：禁用 `nowrap` 手断短句。英文 `EN_PLAYER_TEXT` 整段 + `.pbody{left:100;width:1990;text-align:justify;text-align-last:justify}`，**526 字符是量过的硬约束**（±30 会短行或折第 4 行溢出）；繁体同理 154 字两行。⚠️ 只对短文案加 justify 会拉爆词距。简体 04 **别动**（md5 回归）。
- `localize_en()` 细节：状态栏中文日期 wipe 从 **x90** 起；文件名去掉「副本」，**别直译成 `- Copy`**；句数按 `.!?` 自动算。繁体状态栏保留不 wipe。三语 md5 回归：改一语另两语逐字节不变。
- 文档：`iOS预览图-iPad横屏-{中文,英文,繁体}版分镜.md`；v1 自绘稿 `UI/iOS/ipad-landscape-design.html` 仅作 `--force-redraw` 回退。
