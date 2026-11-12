# EmotionVoice 长期约定（禁令 / 根因 / 入口）
细节见 `.workbuddy/memory/YYYY-MM-DD.md`、`产品/商店页/*.md` 与代码注释；只留「顺手改回去就会出事」的禁令。

## 工程 / 构建
- target `Emora`(mac)/`iOSEmora`(iOS18.6)；iOS 独有 `View/iOS/`，复用 macOS 文件加 target + `#if canImport(AppKit)`；新增 iOS .swift 改 pbxproj 4 处 → 优先塞已有文件。
- SQLite 永不迁移：改 `createTables()` 必 bump `currentSchemaVersion` → DROP 重建。
- `bash tools/ios_build.sh mac` 构建；`tools/ios_typecheck/typecheck.sh`（Shims 同步签名、MAC_ONLY 排除 mac 版 `AudioPreviewPlayer`）；workaround `IDEPackageSupportDisableManifestSandbox`/`-disable-sandbox`/`ONLY_ACTIVE_ARCH=YES`。
- ⚠️ 默认 MainActor：后台纯计算 `nonisolated`（helper 同加）、静态非 Sendable `nonisolated(unsafe)`；Swift 5 仅 warning，grep 构建日志。
- ⚠️ 11-12 起 **AlertToast SPM 包已从工程删除**（pbxproj / Package.resolved 由用户清理）；iOS / macOS 两端都不再引用，`tools/ios_typecheck/Shims.swift` 里的 AlertToast 替身也已删。若以后重新引入，必须 `#if canImport(AlertToast)` 守卫，否则 typecheck `no such module`。
- ⚠️ 合并分支后必查 `Package.resolved` 与冲突标记：`a1ff280` 把 BASE/P1 的 swift-asn1 1.7.4 退回 P2 的 1.7.3（已修回），并在两份 memory 里留下 `=======` / `>>>>>>> dev-草稿` 残留（已清）。
- macOS 首屏 `.defaultSize(visibleFrame)`+`viewDidMoveToWindow()`，禁 `DispatchQueue.main.async` setFrame；SPM `unable to read tree`→`git fetch`；`Log()` 仅 DEBUG；mac 沙盒 Documents=`~/Library/Containers/<bundle>/Data/Documents`。

## TTS 链路
- 无密钥 WS `.../functions/v1/bailian-tts?region=CN|INTL`，单条 `{"action":"synthesize"}`；run/continue/finish-task 与标签切段在边缘函数，断线不可续传；`BailianTTSService.receive()` 唯一 WS 接收点；`ttsPipeline` 串行互斥。
- ⚠️ 改 `supabase/functions/bailian-tts/index.ts` 必须部署并核对 VERSION（`supabase functions deploy bailian-tts --project-ref dpyyhbqqmegencxekkcr` + `functions list`）；曾只改本地、线上 v9 → 参数被静默丢弃、`words[]` 全空。
- ⚠️ `language_hints` 双端链路：`Constants.nlLanguages[].languageHint` 唯一映射源（16 官方语言，**8 方言留空、禁映射 `zh`**）→ `languageHint(forName:)` → `synthesizeWithTimeline(languageHint:)` → `payload["language_hints"]=[hint]`（只 1 值、无值不写）→ 边缘函数白名单；试听 nil，降级重跑保留 hint。
- `payload["instruction"]` 非空才写、原样透传；官方只要求「指令语种与 text 一致」；UI `instructionLimit=1000`。
- 时间戳 `word_timestamp_enabled`→`sentence-end.words[]`（`sentence-begin` 恒空）；sidecar `<fileName>.timestamps.json`（禁改 SQLite/禁 DROP），段偏移按**每段实际音频时长**累加；任一段缺 words 整条不写、走静态原文，**禁估时伪造对齐**。
- ⚠️ 段时长按 MP3 帧累加（`AudioConcatenator.mp3DurationSeconds`），写死 32kbps 按字节估会成倍偏大（211s→2114s）；末字>时长×1.2 退回静态原文；6% 漂移闸不通过不写 sidecar。
- ⚠️ `[clears throat]` 含空格标签会被劈成两个 word：`TranscriptTagMarkup` 必须整句拼字符流再扫（`owner[]` 回填）；阅读区**不显示标签、不画徽标**，`hasBody=false` 不占位，句数用 `transcriptSentenceCount`，禁退回 `sentences.count`。

## 时间戳对齐 / 切句（详见 11-06~11-11 日志）
- ⚠️ `words[].text` 是 `normalized_text`（繁→简）；落盘前 `alignToOriginal(_:source:)` 重分配，首选自己发出的 `segment.text`；逐字高亮必须拼 `word.text`。
- `remap` 三通道：①去空白字数相等→逐位；②`sliceByUnitEnds` 按占号字符数累计；③上游 index；末尾过 `previousEnd == unitVisible.count`。
- ⚠️ `begin_index/end_index` = 占号单元全文连续序号：占号=字母/数字/表意文字，标点/符号/emoji 不占号（`isSpokenUnit`，**别退回 `!isPunctuation`**）；阿里云文档是错的、别累加句长；英文 index 按词编号不可信→靠②兜底。
- ⚠️ v4 对齐保留空白：`normalizeWhitespace()` 压空白后切片，禁「去空白数组+逐字回填」。
- ⚠️ 上游常把整段折成 1 个 `sentence-end`：`splitBySentenceEnding()` 只看 word 前导标点簇重切，`inQuote` 区分 `。"星`/`。"哥`，v5 兼容西文词尾 `endsWithTerminal()`；切分只改 `text`，`beginMs/endMs` 不动。
- ⚠️ `AudioTimeline.currentVersion = 6`，对齐与切句共用、改任一条都 bump；`load` 低版本 `realign`、无原文 `regrade`；算法改动跑 `/tmp/ts_verify2.py`+`/tmp/ts_real.py`。逐字高亮禁 `.bold()`（折行晃动），颜色 `AppColor.blend(hex,hex,t)`。

## 本地化 / 音色 / 参数 / 语言 chip
- `.localized()` 中文原文当 key；⚠️ 禁 `String(format:"…%@…".localized(), arg)`，须 `"…%@".localized(arg)`；改中文 key 须 **8 份** Localizable.strings（en/zh-Hans/zh-HK/ru/ko/ja/fr/de）+ 两端引用一起改；繁体 OpenCC `s2t`+覆写、别用 s2hk。
- ⚠️ 11-12 起五语言译文由 `tools/localization/build_localizable.py` + `translations/{ru,ko,ja,fr,de}.txt` 生成（**禁手改这 5 份 `.lproj/Localizable.strings`**，会被重建覆盖）：以 en 的 value 为翻译源、中文 key 不动，译文每行一条按顺序对齐，转义用 `<NL>`/`<Q>` 标记，占位符 `%@/%d` 顺序必须与英文一致（`String(format:)` 按序取参）；`--check` 校验 + `plutil -lint`。
- ⚠️ **`VoiceCatalog.strings` 不要翻译、也不要给新语言新增**：`VoiceLangCode` 只有 `.zh/.en`（音色语种≠界面语种），`VoiceCatalog.lprojCandidates()` 里 `guard language == .zh else { return ["en"] }`，运行时只打开 `zh-Hans`/`zh-HK`（繁体界面）与 `en` 两份；`VoiceService.rowToVoice` 只烘焙 `name/nameEn`、`desc/descEn`，`Voice.localizedName/localizedDesc` 按 `AppLanguage.isChinese` 二值切换，所有非中文界面统一显示英文名。ru/ko/ja/fr/de 五份英文副本是 `gen_basic_voices.py::discover_locales()` 扫描 `.lproj` 自动铺出来的死文件（白占 bundle ~260KB），**永不被读取**。要真本地化特质文案，得先改 `lprojCandidates` + `Voice` 模型 + `cachedOrderedKeys` 排序，不是改 `.lproj`。
- ⚠️ **音色名永远别加新语言版本，非中文界面统一用英文**：599 个音色里 591 个 `lang=zh`、仅 8 个 `lang=en`；中文名是三字诗意人名（龙安灵心 / 璨竹月 / 蓉芷荷），英文版是 599 个**重新命名**（Lynn / Abigail / Ada，非直译非拼音），「翻译」在这类专名上不成立。繁体版不是第三种命名：369 条有差异、字数 0 条不等，纯 s2t 字形转换。`DraftSnapshot.voiceName`、`ConsumptionRecord.voiceName` 落盘的是**文本快照**（不是 key），`VoiceService` 排序 `sortName` 与 `matchesSearch` 也都吃 `localizedName`；按语言切名字会让草稿/账单里的名字定格在保存时语言、排序与搜索结果随语言漂移。若某市场确要本地名，只能给少量主推音色单独命名，并先把落盘改为存 key。
- 唯一数据源 `Voices/basic_voices.json`(v4)（改后跑 `tools/gen_basic_voices.py`）；标签唯一来源 `Constants.swift`（24 语气/7 拟声），商店图禁自造标签。
- ⚠️ `VoiceCatalog.string()` NSCache 禁去；`VoiceService.cachedOrderedKeys` 无搜索词走 `orderedKeysWithoutSearch`；iOS 分类筛选只在进程内 `VoiceLibraryFilterStore`，禁读写 `AppState.voiceLibrary*`，取消 apply 也要 `commit(fresh,total)`+`onAppear` 自愈。
- `toTTSAPIString()` 已弃（生成走 `toTTSSegments()`+`AudioConcatenator.merge()`）；胶囊整条热区 `contentShape(Rectangle())`。
- `StudioParamValues`/`Store` 在 `VoiceStudioViewModel.swift`，键 `studioParam.*`；⚠️ 禁把 `AppState.defaultFormat`/`defaultSampleRate` 当存储、禁 `VoiceStudioView.onAppear` 覆盖参数；「重置」只 `reset(on: vm)`=`.factory`(mp3/22050/1.0x/100%)。
- ⚠️ **语言 chip 与指令输入框完全解耦**（11-12 曾修、合并 dev-草稿 被旧 VM 覆盖回来）：`toggleLanguage()` 只切 `selectedLanguage`，唯一去处 = chip 选中态 / `language_hints` / 草稿语义值；`updateNLInstruction()` 只由 `applyPreset()` 调用、只写 `presetInstruction`。含 `selectedLanguage?.localized()` 的 `composedNLInstruction` **禁止复活**（否则「先选语言再点预设」「恢复带语言的草稿」都会把语言名写进框）。草稿导出/恢复用 `legacyInstruction()` 归一化旧数据；拼接/导出/恢复三处必须一起改，iOS/macOS 共用此 VM，写入指令必须 `.localized()`。

## UI / 播放器 / 切页
- ⚠️ U+FFFC 判空两端相反：macOS `capsuleInvisibleCharacters` 含、`capsuleTrimCharacters` 不含；iOS `TokenCapsuleOverlay.lineRects()` 不算空白。mac 胶囊 v14：实色底（`accent` 0.28 混进 `#15171B`）+ 顶部 2pt 亮线，禁退回 `base.withAlphaComponent`。
- iOS：`ScreenMetrics` 四档；iPad `isPadClass = width>=740 && height>=700`（别用 sizeClass）；浮层用 `metrics.tabBarClearance` 禁硬写 58；参数面板唯一数据源 `StudioParamContent`；`TokenEditorStore` 打字不经 SwiftUI；`TokenCaretTextView` 只削 height + TextKit 1。
- ⚠️ iOS 参数面板语言 chip 默认全展开（`ForEach(Constants.nlLanguages)`），禁加「展开全部」/`languagesExpanded`。
- ⚠️ CPU 暴涨根因=订阅拓扑：`PlaybackStatus` 只订阅单属性 publisher；高频显示只许小 View 各自 `@ObservedObject`，禁 `@StateObject player`、禁 progress 传给所有行；macOS 音色库页面级只 `.onReceive($playingKey.removeDuplicates())`。
- ⚠️ 两份同名 `AudioPreviewPlayer` 按目标隔离。iOS 后台播放 `.playback`+`UIBackgroundModes=[audio]`（`plutil -extract` 验产物）；`playingKey` 存 identifier、跨 key `reidentify(_:)`；并发闭包「外层 `guard let self`+`Task @MainActor`」。
- ⚠️ iOS `AudioPreviewPlayer+iOS.swift`：**所有 `AVAudioSession.setCategory/setActive` 与 `AVAudioPlayer(contentsOf:)`/`prepareToPlay()` 必须在串行队列 `audioWorkQueue` 上跑**（Xcode 27 AVAudioSession Hang Risk）；Apple 建议的异步 activate/deactivate 是 iOS 27+，部署目标 17.6 用不了。主线程只做 `delegate`/`play()`/状态发布（delegate 回调依赖主线程 RunLoop）；`playRequestSerial` 防异步起播竞态，`stop()` 与 `play(url:)` 都要 `&+= 1`；`enableRate` 必须在 `prepareToPlay()` **之前**设，否则倍速失效。
- ⚠️ 阅读区播放底色两端都是「整篇唯一一块」（mac `PlayerTranscriptView.highlightLayer`/iOS `PlayerDetailControls.highlightLayer`，画在内容 VStack 的 `background`），行位置各走 fileprivate `TranscriptRowFrameKey`；**禁改回「每行各画一块」**（换行必闪）；`highlightTravel`(0.34) 须与 `scrollCurrent` 同值同曲线；`.animation(value:)` 只挂这一层。
- ⚠️ `ContentView.mainContent` ZStack 双层：访问过的 `.voiceStudio`/`.voices` 常驻只切 opacity，禁 `.id(renderedSection)` 重建、禁 `Color.clear` 门控；靠 `isActive` 补偿生命周期，禁失活时 cancel `loadTask`/重置 `voicesAppear`；`appState.voices` 变化须 `invalidateQueryCacheAndReload()`；首屏 `onAppear`→`Task.sleep(32ms)`→`vm.load()`（禁 `Task.yield()`）。

## 历史 / 列表 / 积分 / 弹窗
- ⚠️ 收藏与软删绝不入库：`AudioFlagStore`（UserDefaults JSON，30 天），`purgeExpired()` 交 `ProjectService.deleteAudio`。
- ⚠️ `.plain` List 清零留白（`listSectionSpacing(0)`+`defaultMinListHeaderHeight=0`+`contentMargins(.top,0)`）；macOS 分组类型须 `HistoryDay*` 前缀；`AudioRowItem` 第二行各字段 `fixedSize`+整行 `fixedSize(horizontal:true)`；进度条只 `scaleEffect(x:anchor:.leading)`、禁加 `.clipShape`；`MiniPlayerView` h=56，List 末尾插透明占位 Section。
- 积分全链路 Double(≤2位) `CreditPrecision.normalize`，计费 `字符数/100*rate`（普通2/复刻5，CJK 算 2 字符）；`GenerationDialog` 清空须 `displayName: nil`；`PackageCard` 副标题禁 `.lineLimit(1)`。
- ⚠️ 每次 App 打开弹评分，口径「每进程一次」`ReviewRequestGate`（`nonisolated(unsafe) static var`），禁 `@State` 标记、禁 `scenePhase != .active` 复位；**两端入口不同、禁互相抄**：iOS `requestReviewOnEveryOpen()` 挂 `iOSContentView`；macOS `AppDelegate.applicationDidFinishLaunching`→`LaunchReviewRequester`。

## 草稿（11-11，详见当日日志）
- `DraftSnapshot`/`Draft`/`DraftStore` 全在 `VoiceStudioViewModel.swift` 尾部，禁进 SQLite / `AudioFlagStore`；`Documents/Drafts/` 下 `index.json` 只元数据、正文 `<id>.json`，禁退回单文件 `drafts.v1.json`；`loadedItems` 不参与 Codable，正文缺失 `load` 返回 nil（不是空正文）。
- ⚠️ 恢复前 `stashBeforeRestore(_:)` 新建 manual 草稿（禁 `save(before, source:.auto)` 覆盖单槽位）；`Draft.isSameEditState`（正文+音色+四项参数+指令）全同才跳过；恢复统一 `vm.apply(_:appState:)`（含 `StudioParamStore.save` 写回）。
- ⚠️ 取快照前必须结算编辑器去抖（mac 0.35s）：View `commitEditor()`；⌘S `DraftStore.saveFromSharedVM()`→`PendingEditorCommit.flush()`；正文唯一格式 `[TTSContentItem]`，禁降纯文本；iOS 保存用 `TokenDocument.contentItems`。
- 反馈通道（11-12 起**两端各自实现，禁止共用类型/状态**）：iOS `IOSUIState.showToast` → `RootTabView` 顶部 `ToastHost`；macOS `MacUIState.showToast`（`MacToastMessage` + `MacToastHost` 全在 `View/macOS/ContentView.swift`）→ `ContentView` 顶部 overlay，由 `EmotionVoiceApp.WindowGroup` 注入 `.environmentObject(MacUIState.shared)`。⚠️ 两端 `duration` 统一 1s（默认参数 + 显式调用处都写 1），出现用 `withAnimation(.spring)` + `.id(message.id)` + `.transition`，消失用 `.easeOut(0.25)`；禁自绘提示条/撤销按钮；**打开 App 编辑区恒为空**（两端 `restoreLastEditIfNeeded()` 已删）。⚠️ 外观两端刻意不同：iOS = Aurora 实色胶囊 + 白字 + 同色光晕；macOS = Cold Luxury 浮层（`bgElevated` + `borderMedium` 0.5 描边 + 中性黑投影、`AppRadius.medium` 圆角矩形、高 42），状态色只给 24×24 图标方块、正文 `textPrimary`、info 用琥珀金 `accentPrimary`；禁把 iOS `ToastHost` 那套复制回 macOS。
- ⚠️ 自动草稿标题**落盘只存中文 key** `Draft.autoTitleKey`（`index.json`）；显示 / 搜索 / 重命名预填 / 复制一律用 `draft.displayTitle`（对历史值 `"上次编辑"/"上次編輯"/"Last Edit"` 也重新本地化）。禁把 `.localized()` 结果写进草稿索引，否则切语言后英文仍显示中文。
- ⚠️ iOS `DraftSheet` 浮层必须 `.overlay {}` 挂内容 VStack；macOS 草稿列表=窗口内自绘 modal（`showDraftModal`+`DraftModalView`，尺寸/字号以 `VoiceStudioDraft.swift` 为准），禁 `.popover`；Dialog 一律 `presentDraftDialog(_:)`，`draftDialog`/`showDraftModal` 都要参与 `EmotionTokenEditor(isInteractive:)`；`DraftModalView.focusable` 紧跟 `.focusEffectDisabled()`；⌘S 走 `KeyboardShortcuts.Name.saveDraft`+`DraftShortcutController`（禁设置页 `Recorder`）。

## 商店页 / ASO（细节全在 `产品/商店页/*.md`）
- 尺寸 6.9" `1320×2868`(禁 alpha)/iPad 13" `2752×2064`/Mac `2880×1800`；iOS 无声音复刻 UI、字幕禁写能力数量；⚠️ 旧生成器未被 git 追踪、已消失，重做 01–04/06 只能改 tracked 的 `素材/html/*`；headless 底部 21px 白条靠 `html{background:#0B0C0F}` 兜底 + 底部 24px 亮度校验重渲。
