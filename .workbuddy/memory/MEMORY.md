# EmotionVoice 长期约定（禁令 / 根因 / 入口）
细节见 `.workbuddy/memory/YYYY-MM-DD.md`；商店页/预览图见 `产品/商店页/*.md`；代码内亦有同名注释。本文只留会被「顺手改回去」的禁令与根因。

## 工程 / 构建
- target `Emora`(mac)/`iOSEmora`(iOS 18.6)；iOS 独有 `View/iOS/`，复用 macOS 文件原地加 target + `#if canImport(AppKit)`；新增 iOS .swift 要改 pbxproj 4 处 → **优先塞进已有文件，零 pbxproj 改动**。
- SQLite 永不迁移：改 `createTables()` 就 bump `currentSchemaVersion`，不符 DROP 重建。
- 构建 `bash tools/ios_build.sh mac`；类型检查 `bash tools/ios_typecheck/typecheck.sh`（Shims.swift 须同步真实服务签名）；workaround `IDEPackageSupportDisableManifestSandbox` / `-disable-sandbox` / `ONLY_ACTIVE_ARCH=YES`。
- ⚠️ 四配置默认 MainActor：后台纯计算显式 `nonisolated`（私有 helper 同加），静态非 Sendable 用 `nonisolated(unsafe)`；Swift 5 只 warning，验证须 grep 构建日志。
- macOS 首屏 `.defaultSize(visibleFrame)` + `viewDidMoveToWindow()` 同步配置，禁 `DispatchQueue.main.async` 延迟 setFrame；SPM `unable to read tree` → `git fetch` 补缓存（含 DerivedData），别删目录。`Log()` 仅 `#if DEBUG` 生效。

## TTS / 时间戳 / 本地化
- 无密钥 `wss://<ref>.supabase.co/functions/v1/bailian-tts?region=CN|INTL`，单条 `{"action":"synthesize"}`；run/continue/finish-task 与标签切段都在边缘函数，断线不可续传；Deno<2.5 用 `dialUpstream()`。`BailianTTSService.receive()` 是**唯一 WS 接收点**（waitForTaskStarted + 音频流循环共用），入站转储只改这里；`ttsPipeline` 串行互斥。
- ⚠️ **`language_hints`（目标语言）是双端链路**：`Constants.nlLanguages[].languageHint` 是唯一映射源（16 种官方语言 zh/en/fr/de/ja/ko/ru/pt/th/id/vi/es/it/ms/fil/ar；**8 个中文方言留空、禁顺手映射 `zh`**）→ `Constants.languageHint(forName:)` → VM `synthesizeWithTimeline(languageHint:)` → `buildSynthesizeRequest` 写 `payload["language_hints"] = [hint]`（**array[string] 只放 1 个值，上游当前只处理第一个；无值不写字段 = 默认空**）→ 边缘函数 `ALLOWED_LANGUAGE_HINTS` 白名单校验后写进 `run-task.parameters`。试听路径传 nil，时间戳降级重跑须保留 hint。⚠️ 改 `index.ts` 后**必须部署并核对版本**（11-11 已部署 v14）；旧客户端不传字段不影响。
- 字级时间戳走 `word_timestamp_enabled` → `sentence-end` 的 `words[]`；客户端 `synthesizeWithTimeline()`。⚠️ **改 `supabase/functions/bailian-tts/index.ts` 必须部署并核对版本**：`supabase functions deploy bailian-tts --project-ref dpyyhbqqmegencxekkcr` + `functions list` 看 VERSION/UPDATED_AT。曾因只在本地改、线上还是 v9 导致参数被静默丢弃、`words[]` 全空。旧客户端不传字段 → `undefined !== true`，不影响老用户。
- 时间轴存 `<fileName>.timestamps.json` sidecar（禁改 SQLite/禁 DROP），段偏移按**每段实际音频时长**累加，任一段缺 words 整条不写、播放器走静态原文，**禁估时伪造对齐**。
- ⚠️ **`words[].text` 是 `normalized_text`（繁→简）不是用户原文**；v3 起落盘前 `TTSTimestampParser.alignToOriginal(_:source:)` 重分配文本，**对齐源首选自己发出去的 `segment.text`，上游 `original_text` 只作次选**（不保证等于用户原文，且只有单条 cue 才可能是整段）。禁止把 word.text 改回 normalized / 把 original_text 当唯一对齐源。
- `remap` 三条通道按精确度：① 去空白字数完全相等→逐位映射；② **按词内占号字符数累计**（`sliceByUnitEnds`，不看上游 index、只要求占号总数相同，带纯标点词/空洞/末尾补标点处理）；③ 上游 `begin_index/end_index`。末尾统一过 `previousEnd == unitVisible.count` 总量校验，对不上原样返回。`allowSurfaceMatch:false` 用于 v2+ sidecar 迁移。
- ⚠️ **`begin_index/end_index` 是「占号单元的全文连续序号」，不是原文字符位置**：占号 = 字母/数字/表意文字，标点/符号(`~ $ % =`)/emoji 不占号（判据 `isSpokenUnit`，**别退回 `!isPunctuation`**，那会把 `%` `$` 算成占号、含百分号原文整条失败）。阿里云文档「该字在整句中的开始位置」是**错的**（其示例 `阿里巴巴。达摩院。` 的 `达` index=4 证明跨句累加）；别真去累加句长。⚠️ **英文 index 口径不可信**（长文 `Default Mode Network` 按词编号 3 个 vs 我们按字母 18 个 → 通道③失效，靠②兜住）。逐字高亮**必须拼 `word.text`**（v4 起 === 用户原文，只折 `\n\n`；v2 及更早是 normalized）。`sentence-begin` 的 words 恒为空，只看 `sentence-end`。
- ⚠️ **v4 对齐必须保留空白**：早期 `filter { !$0.isWhitespace }` 去空白再逐字回填 → 英文粘成 `Today,AIIspoweredby…`。现 `normalizeWhitespace()` 压连续空白为一个空格后切片，计数按非空白、切片取归一后原文。**禁止「去空白数组 + 逐字回填」**。
- ⚠️ **上游常把整段折成 1 个 `sentence-end`**（43 字两句只回 idx=0；273 字 1 个），句卡粒度必须靠 `TTSTimestampParser.splitBySentenceEnding()` 按 word 自带标点重切，否则只有一张卡、点哪都 seek 0：**只看 word 的前导标点簇**（中文标点粘在下一个词开头，按行尾判断永远只切 1 句），切点落在簇内部靠 `inQuote` 状态机区分 `。"星`（闭引号归前句）/ `。"哥`（开引号留给后句）。**v5 兼容两种形态**：西文标点在词尾（`brain.`）→ `cut` 恒 -1，必须靠 `endsWithTerminal()`（跳过尾部空白/引号）单独判一次；补 tail 从 `punctStart` 起取（不能从 `chars[0]`，否则前导空白拼进上句末尾）。切分**只改 `text`，`beginMs/endMs` 一个不动**。v5 起两条通道都在，v2/v4 产物可安全 `regrade`。
- ⚠️ **`AudioTimeline.currentVersion = 6`**：文本对齐与切句规则共用版本号，改任一条（含通道数量/优先级）都必须 bump。`AudioTimelineStore.load` 带 `audio.text` 比对：`version == current && textMatches` 才原样返回；**版本低于当前一律 `realign`**（重排+重切，不看 textMatches，因为文本对不代表切分规则对）；无原文走 `regrade` 只重切。原文靠 `AudioItem.timeline` 传 `text`；缓存里存「结论」（失败也缓存，避免 10Hz 重绘反复读盘）。算法改动后跑 `/tmp/ts_verify2.py`（11 场景）+ `/tmp/ts_real.py`（1251 字真实长文）。
- ⚠️ 逐字高亮**禁给当前字加 `.bold()`**（字重变宽→整段重新折行晃动）；颜色过渡靠 `AppColor.blend(hex,hex,t)` 按字内进度逐帧插值，三档色在 `AppColor.WordTone`。边缘函数 `sentence-end` 诊断日志用 `previewSentence()`（80 字），**别用 `preview()`**（500 且受 `?debug=1` 影响，日志按量计费）。
- `.localized()` 中文原文当 key；⚠️ 禁 `String(format:"…%@…".localized(), arg)`，须 `"…%@".localized(arg)`。三语 zh-Hans/zh-HK/en：⚠️ 改中文 key 须三份 strings + 两端引用一起改；繁体 OpenCC `s2t`+覆写、别用 s2hk；仿音色文案在 `<lproj>/VoiceCatalog.strings`，繁中商店图按 `zh-HK.lproj` 用词 + `PingFang TC`。

## 音色 / 标签
- 唯一数据源 `Voices/basic_voices.json`(v4)（改后跑 `tools/gen_basic_voices.py`）；标签唯一来源 `Shared/Models/Constants.swift`（24 语气 / 7 官方拟声），⚠️ 商店图禁自造标签。
- ⚠️ `VoiceCatalog.string()` NSCache 禁去掉；`VoiceService.cachedOrderedKeys` 无搜索词走 `orderedKeysWithoutSearch`（不构造 Voice）。
- ⚠️ iOS 分类筛选只在进程内 `VoiceLibraryFilterStore`，禁读写 `AppState.voiceLibrary*`；`VoicesLibraryView`/`VoicePickerSheet` 的 apply 取消也要 `commit(fresh,total)` + `onAppear` 自愈，否则永久空态。
- 生成走 `toTTSSegments()` + `AudioConcatenator.merge()`；`toTTSAPIString()` 已弃（中断 API 不支持）；胶囊整条热区 `contentShape(Rectangle())`。

## UI / 编辑器
- ⚠️ U+FFFC 判空两端相反：macOS `capsuleInvisibleCharacters` **含** U+FFFC（空行过滤防双描边）、`capsuleTrimCharacters` **不含**（裁首尾空白防短行满宽）；iOS `TokenCapsuleOverlay.lineRects()` **U+FFFC 不算空白**，别互相抄。
- macOS 胶囊视觉 v14：实色底（`accent` 0.28 混进 `#15171B`，`accent = base.darkened(0.48)`）+ 顶部 2pt 亮线、不描边圆角 8；⚠️ 禁退回 `base.withAlphaComponent` 直叠。
- iOS：`ScreenMetrics` 四档；iPad `isPadClass = width>=740 && height>=700`（别用 sizeClass）、两栏卡高必须 GeometryReader 实测、iPadOS 18 浮层用 `metrics.tabBarClearance` 禁硬写 58；参数面板唯一数据源 `StudioParamContent`；`TokenEditorStore` 打字不经 SwiftUI；`TokenCaretTextView` 重写 `caretRect(for:)` 只削 height + TextKit 1。
- ⚠️ **iOS 参数面板语言 chip 默认全展开**（`ForEach(Constants.nlLanguages)`，与 macOS 一致），**禁再加「展开全部」按钮 / `languagesExpanded` 收起态**；`UI/iOS/emotionvoice-ios-design.html` 旧稿仍画收起态，仅作历史参考。

## 播放器 / SwiftUI 订阅
- ⚠️ 两份同名 `AudioPreviewPlayer` 按 target 隔离（typecheck `MAC_ONLY` / `add_ios_target_files.py` 的 `REUSED` 须排除 macOS 版）。
- ⚠️ CPU 暴涨根因 = 订阅拓扑：`PlaybackStatus` 只订阅单属性 publisher；高频显示只许 6 个小 View 各自 `@ObservedObject`，禁 `@StateObject player`、禁把 progress 传给所有行；macOS 音色库页面级只 `.onReceive($playingKey.removeDuplicates())`。
- iOS 后台播放：AVAudioSession `.playback` + `iOSEmora-Info.plist` `UIBackgroundModes=[audio]`（数组键须 INFOPLIST_FILE 模板 + `plutil -extract` 验产物）；封面 `makeArtwork` 全幅不透明渐变。
- `playingKey` 存 identifier、跨 key `reidentify(_:)`；⚠️ 并发闭包「外层 `guard let self` + `Task @MainActor`」。

## macOS 切页 / 音色库首屏
- ⚠️ `ContentView.mainContent` ZStack 双层：访问过的 `.voiceStudio`/`.voices` 常驻只切 opacity，**禁 `.id(renderedSection)` 重建**（NSTextView + 全局 attachment + VM 全量重建 = 卡顿根因）；两页铺不透明 `bgPrimary` 盖住下层；隐藏时**保留整棵视图树，禁 `Color.clear` 门控**。
- ⚠️ 常驻页靠 `isActive` 补偿生命周期（关 sheet/popover、交出 firstResponder、停骨架扫光 + `persistAndPause()`）；**禁失活时 cancel `loadTask` / 重置 `voicesAppear`**（onAppear 不再触发 → 永久骨架）。
- ⚠️ VM 常驻后 `appState.voices` 变化须 `invalidateQueryCacheAndReload()`；首屏 `onAppear` → `Task.sleep(32ms)` 跨帧 → `vm.load()`，禁改回 `Task.yield()`；骨架扫光 `SkeletonShimmer` 一层。首次进库仍卡 = 首次构建 + 首次全表加载 → 启动空闲期 `ContentView.warmUpVoicesLibrary()` 预热（数据预热与挂视图树分两帧、另开 `.task`）；首次进 `.voices` 的 100ms 延迟**已删除**。

## 历史 / 列表
- ⚠️ 收藏与软删绝不入库：`AudioFlagStore`（UserDefaults JSON，30 天），`purgeExpired()` 交 `ProjectService.deleteAudio`。
- ⚠️ `.plain` List 清零系统留白（`listSectionSpacing(0)` + `defaultMinListHeaderHeight=0` + `contentMargins(.top,0)`）；macOS 分组类型**必须 `HistoryDay*` 前缀**、保留 `displayedAudios`。
- ⚠️ `AudioRowItem` 第二行「音色名 · 时长 · 文件大小 · HH:mm」各字段 `fixedSize` + 整行 `fixedSize(horizontal:true)` 一行显示，禁时分单独右列 + `Spacer()`；卡片进度条只 `scaleEffect(x:anchor:.leading)`，**绝不自加 `.clipShape`**；`MiniPlayerView` height=56，List 末尾按 `miniPlayerVisible` 插透明占位 Section。

## 积分 / 参数 / 弹窗
- 积分全链路 Double(≤2位) `CreditPrecision.normalize`，计费 `字符数/100*rate`（普通2/复刻5，CJK 算 2 字符），云端 `numeric(10,2)`。
- `StudioParamValues`/`Store` 在 `Shared/ViewModels/VoiceStudioViewModel.swift`，键 `studioParam.*`；⚠️ 禁把 `AppState.defaultFormat`/`defaultSampleRate` 当存储，「重置」只调 `reset(on: vm)` = `.factory`(mp3/22050/1.0x/100%)；默认值读 `Constants`/`.factory`；`VoiceStudioView.onAppear` 从设置页覆盖参数**已删，别加回来**。
- ⚠️ **语音指令拼接必须 `.localized()`**：`updateNLInstruction()` 里 `nlLanguages.name` / `nlPresets.instruction` 都是中文原文兼本地化 key，三份 strings 已备齐 24 语言名 + 6 预设译文；**禁直接拼中文原文**（英文/繁中界面指令框会冒简体中文，11-11 实测）。iOS/macOS 共用此 VM，改一处两端生效，macOS 视图无独立拼接。分隔符中文 `,`、英文 `, `（`AppLanguage.isChinese`），中文沿用半角逗号零回归。
- `GenerationDialog` 清空须 `displayName: nil`，`hasResult = generatedAudioURL != nil && !isGenerating`；`PackageCard` 副标题禁 `.lineLimit(1)`。
- ⚠️ 用户明确要求「**每次 App 打开都弹评分弹窗**」（与 ASO 文档相反，以用户为准，别改回去）：`AppUpdateManager.requestReviewOnEveryOpen()` 两端根容器各挂一行，**不做本地节流**。⚠️ 评分口径是「**每个进程一次**」：`ReviewRequestGate`（`AppUpdateManager.swift` 内 `nonisolated(unsafe) static var`）只放行一次，退后台再回前台不再弹。**禁把一次性标记放回 `@State`、禁在 `scenePhase != .active` 时复位**——iOS 上评分面板/控制中心/来电都会让 scenePhase 走 `active→inactive→active`，复位即连环弹窗；iPad 多窗口/场景重建又会各持一份 `@State`。StoreKit 365 天 3 次 / TestFlight 不弹是系统硬限制。

## 商店页 / ASO（细节全在 `产品/商店页/*.md`）
- 入口：Mac `素材/gen_previews.py` + `商店页文案-多语言版本.md`；iPhone `gen_ios_previews.py` + `iOS商店页元数据-6语言.md`；iPad `prepare_ipad_real.py` + `gen_ios_previews_ipad.py`。尺寸 6.9" `1320×2868`(禁 alpha) / iPad 13" `2752×2064` / Mac `2880×1800`；⚠️ `素材/raw/` 未被 git 追踪曾被清理。
- ⚠️ Mac 01 覆盖层 `.win` 内叠层、**禁铺满**，zh 缩放 `2112/3456` / en `2122/3442`，`--only=01` build/export 都带；改一语另一语 md5 零回归。⚠️ 06 三语源图都是纯窗口须整幅缩放（禁套繁体 A 类 BOX）；半行字简体无、繁体已清理、**英文用户要求保留原样禁清理/禁贴字**；三语已于 11-10 全换成当前播放器窗口（`素材/gen_mac_06.py`，`--lang` 单语重做），`.win` 高度按各源图比例（简/英 2112×1255、繁 2112×1262）、文案不动。
- ⚠️ headless 截图偶发「视口最后 21px 没画完 → 底部纯白条」（1/4 概率、差 241/255），这就是同命令导出两次 md5 会变的真凶：加 `html{background:#0B0C0F}` 兜底 + 导出后校验底部 24px 亮度 >200 就重渲，别只靠比对 md5。
- ⚠️ iOS 端没有声音复刻 UI，字幕禁写具体能力数量；iPhone 流程须带 `--html-only --export`（漏了覆盖真机图）；`prepare()` 三分支禁把 zh-Hant 塞进 `localize_en()`；缺 iPad 真机图跳过而非回退自绘。
- ⚠️ **05 播放界面走独立通道** `素材/gen_ios_05_v2.py`（中间产物 `素材/ios-05v2/`，**成片直接覆盖** `ios-1320x2868/<lang>/05-shot-favorite.png`）：屏幕像素 1007×2214 预缩放后 1:1 贴图；Chrome **必须 `--no-sandbox`**（否则 SIGTRAP）；状态栏由实测墨迹框反解 SFNS Semibold 41 统一成 9:41；换图用 `--lang <zh-Hans|en-US|zh-Hant>`。细节见 `产品/商店页/iOS预览图-05播放界面-v2.md`。
- ⚠️ `gen_previews.py` / `gen_ios_previews.py` / `prepare_ipad_real.py` 等旧生成器**未被 git 追踪、已从工作区消失**，重做 01–04/06 只能改 `素材/html/*`（tracked）再 headless 截图；新脚本记得 commit。
