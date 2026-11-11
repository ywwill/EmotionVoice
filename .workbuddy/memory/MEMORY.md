# EmotionVoice 长期约定（禁令 / 根因 / 入口）
细节见 `.workbuddy/memory/YYYY-MM-DD.md`、`产品/商店页/*.md` 及代码同名注释。本文只留易被「顺手改回去」的禁令。

## 工程 / 构建
- target `Emora`(mac)/`iOSEmora`(iOS 18.6)；iOS 独有 `View/iOS/`，复用 macOS 文件原地加 target + `#if canImport(AppKit)`；新增 iOS .swift 要改 pbxproj 4 处 → 优先塞已有文件、零 pbxproj 改动。
- SQLite 永不迁移：改 `createTables()` 就 bump `currentSchemaVersion`，不符 DROP 重建。
- 构建 `bash tools/ios_build.sh mac`；类型检查 `tools/ios_typecheck/typecheck.sh`（Shims.swift 同步真实签名）；workaround `IDEPackageSupportDisableManifestSandbox`/`-disable-sandbox`/`ONLY_ACTIVE_ARCH=YES`。
- ⚠️ 四配置默认 MainActor：后台纯计算显式 `nonisolated`（私有 helper 同加），静态非 Sendable 用 `nonisolated(unsafe)`；Swift 5 仅 warning，须 grep 构建日志验证。
- macOS 首屏 `.defaultSize(visibleFrame)` + `viewDidMoveToWindow()` 同步配置，禁 `DispatchQueue.main.async` 延迟 setFrame；SPM `unable to read tree` → `git fetch` 补缓存（含 DerivedData），别删目录。`Log()` 仅 `#if DEBUG`。

## TTS 链路
- 无密钥 WS `wss://<ref>.supabase.co/functions/v1/bailian-tts?region=CN|INTL`，单条 `{"action":"synthesize"}`；run/continue/finish-task 与标签切段在边缘函数，断线不可续传；Deno<2.5 用 `dialUpstream()`。`BailianTTSService.receive()` 是唯一 WS 接收点（入站转储只改这里）；`ttsPipeline` 串行互斥。模型默认 `qwen-audio-3.0-tts-plus`（env `BAILIAN_TTS_MODEL`）。
- ⚠️ 改 `supabase/functions/bailian-tts/index.ts` 必须部署并核对版本：`supabase functions deploy bailian-tts --project-ref dpyyhbqqmegencxekkcr` + `functions list` 看 VERSION/UPDATED_AT（11-11 v14）。曾因线上仍是 v9 导致新参数被静默丢弃、words[] 全空；旧客户端不传字段不影响。
- ⚠️ `language_hints` 双端链路：`Constants.nlLanguages[].languageHint` 唯一映射源（16 种官方语言；8 个中文方言留空、禁映射 `zh`）→ `Constants.languageHint(forName:)` → VM `synthesizeWithTimeline(languageHint:)` → `buildSynthesizeRequest` 写 `payload["language_hints"]=[hint]`（array[string] 只 1 值；无值不写）→ 边缘函数白名单 `ALLOWED_LANGUAGE_HINTS` 校验后进 `run-task.parameters`。试听传 nil，降级重跑保留 hint。
- `payload["instruction"]`：自然语言指令（方言/情感/角色），客户端非空才写、边缘函数原样透传到 `parameters.instruction`，无语言/字数校验。官方 Qwen-Audio-TTS 无指令语种白名单，只要求「指令中指定的语种与 text 一致」；UI `instructionLimit=1000`。en/繁中指令（`.localized()` 后的译文）可用。
- 字级时间戳 `word_timestamp_enabled` → `sentence-end.words[]`；sidecar `<fileName>.timestamps.json`（禁改 SQLite/DROP），段偏移按每段实际音频时长累加；任一段缺 words 整条不写、播放器走静态原文，**禁估时伪造对齐**。

## 时间戳对齐 / 切句（详见 11-06~11-11 日志）
- ⚠️ `words[].text` 是 `normalized_text`（繁→简）非用户原文；v3 起落盘前 `alignToOriginal(_:source:)` 重分配，首选自己发出的 `segment.text`，上游 `original_text` 仅次选；禁退回 normalized / 把 original_text 当唯一源。
- `remap` 三通道：① 去空白字数相等→逐位；② 按词内占号字符数累计 `sliceByUnitEnds`（不看上游 index，含纯标点词/空洞/末尾补标点）；③ 上游 `begin_index/end_index`。末尾过 `previousEnd == unitVisible.count` 校验，对不上原样返回；`allowSurfaceMatch:false` 用于 v2+ 迁移。
- ⚠️ `begin_index/end_index` 是「占号单元全文连续序号」非字符位置：占号=字母/数字/表意文字；标点/符号(`~ $ % =`)/emoji 不占号（判据 `isSpokenUnit`，别退回 `!isPunctuation`）。阿里云文档「整句中的开始位置」是错的（示例 `阿里巴巴。达摩院。` 的 `达` index=4 证明跨句累加）；英文 index 按词编号不可信→靠②兜底。逐字高亮必须拼 `word.text`（v4 起===原文，只折 `\n\n`）；`sentence-begin.words` 恒空。
- ⚠️ v4 对齐必须保留空白：`normalizeWhitespace()` 压连续空白为单空格后切片（计数按非空白、切片取归一后原文），禁「去空白数组+逐字回填」（英文粘成 `Today,AIIspoweredby…`）。
- ⚠️ 上游常把整段折成 1 个 `sentence-end`：句卡靠 `splitBySentenceEnding()` 按 word 自带标点重切，只看词首前导标点簇，`inQuote` 状态机区分 `。"星`/`。"哥`；v5 兼容西文词尾标点（`brain.`）靠 `endsWithTerminal()`，补 tail 从 `punctStart` 取。切分只改 `text`，`beginMs/endMs` 不动；v2/v4 产物可安全 `regrade`。
- ⚠️ `AudioTimeline.currentVersion = 6`：对齐与切句共用版本号，改任一条都 bump。`AudioTimelineStore.load` 比 `audio.text`：`version==current && textMatches` 才原样返回；低于当前一律 `realign`；无原文走 `regrade`。原文靠 `AudioItem.timeline.text`；缓存存「结论」（失败也缓存）。算法改动跑 `/tmp/ts_verify2.py` + `/tmp/ts_real.py`。
- ⚠️ 逐字高亮禁给当前字 `.bold()`（折行晃动）；颜色用 `AppColor.blend(hex,hex,t)` 按字内进度插值，三档色 `AppColor.WordTone`。边缘函数 `sentence-end` 日志用 `previewSentence()`（80 字），别用 `preview()`。

## 本地化 / 音色 / 生成
- `.localized()` 中文原文当 key；⚠️ 禁 `String(format:"…%@…".localized(), arg)`，须 `"…%@".localized(arg)`。三语 zh-Hans/zh-HK/en：改中文 key 须三份 strings + 两端引用同步；繁体 OpenCC `s2t`+覆写、别用 s2hk；仿音色文案在 `<lproj>/VoiceCatalog.strings`，繁中商店图按 `zh-HK.lproj` 用词 + `PingFang TC`。
- 唯一数据源 `Voices/basic_voices.json`(v4)（改后跑 `tools/gen_basic_voices.py`）；标签唯一来源 `Shared/Models/Constants.swift`（24 语气/7 官方拟声），商店图禁自造标签。
- ⚠️ `VoiceCatalog.string()` NSCache 禁去；`VoiceService.cachedOrderedKeys` 无搜索词走 `orderedKeysWithoutSearch`；iOS 分类筛选只在进程内 `VoiceLibraryFilterStore`，禁读写 `AppState.voiceLibrary*`，取消 apply 也要 `commit(fresh,total)` + `onAppear` 自愈。
- 生成走 `toTTSSegments()` + `AudioConcatenator.merge()`；`toTTSAPIString()` 已弃；胶囊整条热区 `contentShape(Rectangle())`。

## UI / 编辑器
- ⚠️ U+FFFC 判空两端相反：macOS `capsuleInvisibleCharacters` 含、`capsuleTrimCharacters` 不含；iOS `TokenCapsuleOverlay.lineRects()` 不算空白，别互相抄。macOS 胶囊 v14：实色底（`accent` 0.28 混进 `#15171B`，`accent = base.darkened(0.48)`）+ 顶部 2pt 亮线、不描边圆角 8；禁退回 `base.withAlphaComponent` 直叠。
- iOS：`ScreenMetrics` 四档；iPad `isPadClass = width>=740 && height>=700`（别用 sizeClass）；两栏卡高 GeometryReader 实测；iPadOS 18 浮层用 `metrics.tabBarClearance` 禁硬写 58；参数面板唯一数据源 `StudioParamContent`；`TokenEditorStore` 打字不经 SwiftUI；`TokenCaretTextView` 重写 `caretRect(for:)` 只削 height + TextKit 1。
- ⚠️ iOS 参数面板语言 chip 默认全展开（`ForEach(Constants.nlLanguages)`），禁加「展开全部」/`languagesExpanded`；`UI/iOS/emotionvoice-ios-design.html` 旧稿仅历史参考。

## 播放器 / 订阅 / 切页
- ⚠️ 两份同名 `AudioPreviewPlayer` 按 target 隔离（typecheck `MAC_ONLY` / `add_ios_target_files.py` 的 `REUSED` 排除 macOS 版）。
- ⚠️ CPU 暴涨根因=订阅拓扑：`PlaybackStatus` 只订阅单属性 publisher；高频显示只许 6 个小 View 各自 `@ObservedObject`，禁 `@StateObject player`、禁把 progress 传给所有行；macOS 音色库页面级只 `.onReceive($playingKey.removeDuplicates())`。
- iOS 后台播放：AVAudioSession `.playback` + `UIBackgroundModes=[audio]`（INFOPLIST_FILE 模板 + `plutil -extract` 验产物）；封面 `makeArtwork` 全幅不透明渐变；`playingKey` 存 identifier、跨 key `reidentify(_:)`；⚠️ 并发闭包「外层 `guard let self` + `Task @MainActor`」。
- ⚠️ `ContentView.mainContent` ZStack 双层：访问过的 `.voiceStudio`/`.voices` 常驻只切 opacity，禁 `.id(renderedSection)` 重建；两页铺不透明 `bgPrimary`；隐藏保留整棵视图树，禁 `Color.clear` 门控。
- ⚠️ 常驻页靠 `isActive` 补偿生命周期（关 sheet/popover、交出 firstResponder、停骨架扫光 + `persistAndPause()`）；禁失活时 cancel `loadTask` / 重置 `voicesAppear`（onAppear 不再触发→永久骨架）。
- ⚠️ VM 常驻后 `appState.voices` 变化须 `invalidateQueryCacheAndReload()`；首屏 `onAppear` → `Task.sleep(32ms)` 跨帧 → `vm.load()`，禁改回 `Task.yield()`；骨架 `SkeletonShimmer` 一层；启动空闲期 `warmUpVoicesLibrary()` 预热（数据与挂树分两帧、另开 `.task`）；首次进 `.voices` 的 100ms 延迟已删。

## 历史 / 列表 / 积分 / 弹窗
- ⚠️ 收藏与软删绝不入库：`AudioFlagStore`（UserDefaults JSON，30 天），`purgeExpired()` 交 `ProjectService.deleteAudio`。
- ⚠️ `.plain` List 清零留白（`listSectionSpacing(0)` + `defaultMinListHeaderHeight=0` + `contentMargins(.top,0)`）；macOS 分组类型必须 `HistoryDay*` 前缀、保留 `displayedAudios`；`AudioRowItem` 第二行各字段 `fixedSize` + 整行 `fixedSize(horizontal:true)`，禁时分单独右列 + `Spacer()`；卡片进度条只 `scaleEffect(x:anchor:.leading)`、绝不自加 `.clipShape`；`MiniPlayerView` height=56，List 末尾按 `miniPlayerVisible` 插透明占位 Section。
- 积分全链路 Double(≤2位) `CreditPrecision.normalize`，计费 `字符数/100*rate`（普通2/复刻5，CJK 算 2 字符），云端 `numeric(10,2)`。
- `StudioParamValues`/`Store` 在 `Shared/ViewModels/VoiceStudioViewModel.swift`，键 `studioParam.*`；⚠️ 禁把 `AppState.defaultFormat`/`defaultSampleRate` 当存储；「重置」只 `reset(on: vm)` = `.factory`(mp3/22050/1.0x/100%)；`VoiceStudioView.onAppear` 从设置页覆盖参数已删。
- ⚠️ 语音指令拼接必须 `.localized()`（`updateNLInstruction()` 的 `nlLanguages.name`/`nlPresets.instruction` 均为中文 key，三份 strings 已备 24 语言名 + 6 预设译文），禁直接拼中文原文；iOS/macOS 共用此 VM；分隔符中文 `,`、英文 `, `（`AppLanguage.isChinese`）。
- `GenerationDialog` 清空须 `displayName: nil`，`hasResult = generatedAudioURL != nil && !isGenerating`；`PackageCard` 副标题禁 `.lineLimit(1)`。
- ⚠️ 用户要求每次 App 打开弹评分弹窗：`AppUpdateManager.requestReviewOnEveryOpen()` 两端根容器各一行、不做本地节流；口径是每进程一次 `ReviewRequestGate`（`nonisolated(unsafe) static var`），退后台再回前台不再弹。禁把标记放回 `@State`、禁 `scenePhase != .active` 复位（iOS 评分面板/控制中心/来电会 active→inactive→active → 连环弹窗）。StoreKit 365 天 3 次 / TestFlight 不弹是系统硬限制。

## 商店页 / ASO（细节全在 `产品/商店页/*.md`）
- 入口：Mac `素材/gen_previews.py`；iPhone `gen_ios_previews.py`；iPad `prepare_ipad_real.py` + `gen_ios_previews_ipad.py`。尺寸 6.9" `1320×2868`(禁 alpha)/iPad 13" `2752×2064`/Mac `2880×1800`；`素材/raw/` 未追踪曾被清理。
- ⚠️ Mac 01 覆盖层 `.win` 内叠层禁铺满，zh 缩放 `2112/3456`/en `2122/3442`，`--only=01` build/export 都带；06 三语源图纯窗口须整幅缩放（禁套繁体 A 类 BOX），英文半行字按用户要求保留原样；三语 11-10 换成当前播放器窗口（`素材/gen_mac_06.py --lang`），`.win` 高度按源图比例、文案不动。
- ⚠️ headless 截图偶发底部 21px 纯白条（1/4 概率、差 241/255）= 同命令两次导出 md5 不同的真凶：`html{background:#0B0C0F}` 兜底 + 导出后校验底部 24px 亮度 >200 重渲。
- ⚠️ iOS 端无声音复刻 UI，字幕禁写具体能力数量；iPhone 流程须带 `--html-only --export`；`prepare()` 三分支禁把 zh-Hant 塞进 `localize_en()`；缺 iPad 真机图跳过而非回退自绘。
- ⚠️ 05 播放界面独立通道 `素材/gen_ios_05_v2.py`（中间产物 `素材/ios-05v2/`，成片直接覆盖 `ios-1320x2868/<lang>/05-shot-favorite.png`）：屏幕 1007×2214 预缩放后 1:1 贴图；Chrome 必须 `--no-sandbox`；状态栏 SFNS Semibold 41 统一 9:41；`--lang` 换图。细节见 `产品/商店页/iOS预览图-05播放界面-v2.md`。
- ⚠️ `gen_previews.py`/`gen_ios_previews.py`/`prepare_ipad_real.py` 等旧生成器未被 git 追踪、已从工作区消失；重做 01–04/06 只能改 `素材/html/*`(tracked) 再 headless 截图；新脚本记得 commit。
