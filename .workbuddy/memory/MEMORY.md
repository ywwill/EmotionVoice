# EmotionVoice 长期约定（禁令 / 根因 / 入口）
只留「顺手改回去就会出事」的禁令；完整因果与验证过程见 `.workbuddy/memory/YYYY-MM-DD.md`、`产品/商店页/*.md`、代码注释。

## 工程 / 构建
- target `Emora`(mac)/`iOSEmora`(iOS18.6)；iOS 独有 `View/iOS/`，复用 macOS 文件加 target + `#if canImport(AppKit)`；新增 iOS .swift 改 pbxproj 4 处 → 优先塞已有文件。
- SQLite 永不迁移：改 `createTables()` 必 bump `currentSchemaVersion` → DROP 重建。
- `bash tools/ios_build.sh mac`；`tools/ios_typecheck/typecheck.sh`（Shims 同步签名、MAC_ONLY 排除 mac 版 `AudioPreviewPlayer`）；workaround `IDEPackageSupportDisableManifestSandbox`/`-disable-sandbox`/`ONLY_ACTIVE_ARCH=YES`。
- ⚠️ 默认 MainActor：后台纯计算 `nonisolated`（helper 同加）、静态非 Sendable `nonisolated(unsafe)`；Swift 5 仅 warning，grep 构建日志。
- ⚠️ AlertToast SPM 已删（pbxproj / Package.resolved / Shims）；重引入须 `#if canImport(AlertToast)`。
- ⚠️ 合并分支后必查 `Package.resolved` 与冲突标记（swift-asn1 版本回退、memory 内 `=======` 残留均已修）。
- macOS 首屏 `.defaultSize(visibleFrame)`+`viewDidMoveToWindow()`，禁 `DispatchQueue.main.async` setFrame；SPM `unable to read tree`→`git fetch`；`Log()` 仅 DEBUG；mac 沙盒 Documents=`~/Library/Containers/<bundle>/Data/Documents`。

## TTS 链路
- 无密钥 WS `.../functions/v1/bailian-tts?region=CN|INTL`，单条 `{"action":"synthesize"}`；run/continue/finish-task 与标签切段在边缘函数，断线不可续传；`BailianTTSService.receive()` 唯一接收点；`ttsPipeline` 串行互斥。
- ⚠️ 改 `supabase/functions/bailian-tts/index.ts` 必须部署并核对 VERSION（`supabase functions deploy bailian-tts --project-ref dpyyhbqqmegencxekkcr` + `functions list`）；曾只改本地、线上 v9 → 参数被静默丢弃、`words[]` 全空。
- ⚠️ `language_hints`：`Constants.nlLanguages[].languageHint` 唯一映射源（16 官方语言，**8 方言留空、禁映射 `zh`**）→ `languageHint(forName:)` → `synthesizeWithTimeline` → `payload["language_hints"]=[hint]`（只 1 值、无值不写）→ 边缘函数白名单；试听 nil，降级重跑保留 hint。
- `payload["instruction"]` 非空才写、原样透传；官方只要求「指令语种与 text 一致」；UI `instructionLimit=1000`。
- 时间戳走 `sentence-end.words[]`（`sentence-begin` 恒空）；sidecar `<fileName>.timestamps.json`（禁改 SQLite/禁 DROP），段偏移按**每段实际音频时长**累加；任一段缺 words 整条不写、走静态原文，**禁估时伪造对齐**。
- ⚠️ 段时长按 MP3 帧累加（`AudioConcatenator.mp3DurationSeconds`），写死 32kbps 按字节估会成倍偏大（211s→2114s）；末字>时长×1.2 退回静态原文；6% 漂移闸不通过不写 sidecar。
- ⚠️ `[clears throat]` 含空格标签会被劈成两个 word：`TranscriptTagMarkup` 必须整句拼字符流再扫（`owner[]` 回填）；阅读区**不显示标签、不画徽标**，`hasBody=false` 不占位，句数用 `transcriptSentenceCount`。

## 时间戳对齐 / 切句（详见 11-06~11-11 日志）
- ⚠️ `words[].text` 是 `normalized_text`（繁→简）；落盘前 `alignToOriginal(_:source:)` 重分配，首选发出的 `segment.text`；逐字高亮必须拼 `word.text`。
- `remap` 三通道：①去空白字数相等→逐位；②`sliceByUnitEnds` 按占号字符数累计；③上游 index；末尾过 `previousEnd == unitVisible.count`。
- ⚠️ `begin_index/end_index` = 占号单元全文连续序号：占号=字母/数字/表意文字，标点/符号/emoji 不占号（`isSpokenUnit`，**别退回 `!isPunctuation`**）；阿里云文档是错的、别累加句长；英文 index 不可信→靠②兜底。
- ⚠️ v4 对齐保留空白：`normalizeWhitespace()` 压空白后切片，禁「去空白数组+逐字回填」。
- ⚠️ 上游常把整段折成 1 个 `sentence-end`：`splitBySentenceEnding()` 只看 word 前导标点簇重切，`inQuote` 区分 `。"星`/`。"哥`，v5 兼容西文词尾 `endsWithTerminal()`；切分只改 `text`，`beginMs/endMs` 不动。
- ⚠️ `AudioTimeline.currentVersion = 6`，对齐与切句共用、改任一条都 bump；`load` 低版本 `realign`、无原文 `regrade`；算法改动跑 `/tmp/ts_verify2.py`+`/tmp/ts_real.py`。逐字高亮禁 `.bold()`，颜色 `AppColor.blend`。

## 本地化 / 音色 / 参数
- `.localized()` 中文原文当 key；⚠️ 禁 `String(format:"…%@…".localized(), arg)`，须 `"…%@".localized(arg)`；改中文 key 须 **8 份** Localizable.strings（en/zh-Hans/zh-HK/ru/ko/ja/fr/de）+ 两端引用一起改；繁体 OpenCC `s2t`+覆写、别用 s2hk。
- ⚠️ 五语言译文由 `tools/localization/build_localizable.py` + `translations/{ru,ko,ja,fr,de}.txt` 生成（**禁手改这 5 份 `.lproj/Localizable.strings`**）：以 en 的 value 为源、中文 key 不动，每行一条顺序对齐，转义 `<NL>`/`<Q>`，占位符顺序必须与英文一致；`--check` + `plutil -lint`。
- ⚠️ **11-13 起 VoiceCatalog 正式支持 8 语种界面**（用户决策，推翻 11-12「不要加新语种」的旧结论）：`4b61a21` 恢复的五份 `.strings` 由 `tools/localization/gen_voice_catalog.py` + `voice_catalog_data.py`（17 语义族意象词根 + 名尾）+ `voice_translations/{fr,de,ja,ko,ru}.tsv`（180 条特质译文）生成；**禁手改这 5 份 `.strings`**，改文案改词库/TSV 再重跑。`tools/gen_basic_voices.py` 的 `CATALOG_LOCALES` 已扩到 8 份，两个生成器共用同一份 header、产物逐字一致、重跑幂等（**禁改回扫描全部 `.lproj`、禁把白名单退回 3 份**）；`SRC_JSON` 正确路径 `Shared/Voices/basic_voices.json`。
- ⚠️ Swift 读取链路（`4b61a21` 时还只认 zh/en，现已接通）：`AppLanguage.catalogLocale` 把 `Bundle.main.preferredLocalizations.first` 映射成 8 个 lproj 名（zh-Hant→zh-HK，未知→en）；`VoiceCatalog.interfaceLprojCandidates()` 返回 `[本地, "en"]`（中文按简繁），`stringForInterface` / `localizedVoiceNameForInterface` / `localizedVoiceFeatureForInterface` 按界面语言取；`VoiceService.rowToVoice` 把 `nameEn`/`descEn` 烘焙成**当前界面语言的非中文文案**，字段名没改、`Voice.localizedName` 二值判断不用动；`orderedKeysWithoutSearch` 排序也改用 ForInterface。⚠️ `VoiceLangCode` 仍只有 `.zh/.en`（音色语种 ≠ 界面语种），`lprojCandidates(for:)` 保留给显式取中/英两套的场景。切语言需重启（无 App 内切换），`cacheGeneration()` 已含语言因子。
- ⚠️ 音色命名根因（仍成立）：599 个音色（591 `zh`、8 `en`），中文三字诗意人名、英文 599 个重新命名、繁体纯 s2t → 这类专名只能**按当地习惯重新命名**，不能翻译。新五语种是意象式本地名（日语 2 汉字、韩语固有词、德语日耳曼复合名、法语 -ine/-ette 派生、俄语 -ана / 连接元音 о + 斯拉夫成分），按 180 种 feature 归 17 语义族，同语种 599 个全唯一。⚠️ **仍未解决**：`DraftSnapshot.voiceName` / `ConsumptionRecord.voiceName` 落盘的是名字文本快照，`VoiceService.sortName` / `matchesSearch` / `Voice.sortKey` 都吃 `localizedName` → 切语言后草稿/账单名字定格在保存时语言、排序与搜索漂移；要根治得先改成存 key。
- 唯一数据源 `Voices/basic_voices.json`(v4)（改后跑 `tools/gen_basic_voices.py`）；标签唯一来源 `Constants.swift`（24 语气/7 拟声），商店图禁自造标签。
- ⚠️ `VoiceCatalog.string()` NSCache 禁去；`VoiceService.cachedOrderedKeys` 无搜索词走 `orderedKeysWithoutSearch`；iOS 分类筛选只在进程内 `VoiceLibraryFilterStore`，禁读写 `AppState.voiceLibrary*`，取消 apply 也要 `commit(fresh,total)`+`onAppear` 自愈。
- `toTTSAPIString()` 已弃（生成走 `toTTSSegments()`+`AudioConcatenator.merge()`）；胶囊整条热区 `contentShape(Rectangle())`。
- `StudioParamValues`/`Store` 在 `VoiceStudioViewModel.swift`，键 `studioParam.*`；⚠️ 禁把 `AppState.defaultFormat`/`defaultSampleRate` 当存储、禁 `VoiceStudioView.onAppear` 覆盖参数；「重置」只 `reset(on: vm)`=`.factory`。
- ⚠️ **语言 chip 与指令输入框完全解耦**（曾修、合并 dev-草稿 被旧 VM 覆盖回来）：`toggleLanguage()` 只切 `selectedLanguage`，唯一去处 = chip 选中态 / `language_hints` / 草稿语义值；`updateNLInstruction()` 只由 `applyPreset()` 调用、只写 `presetInstruction`。含 `selectedLanguage?.localized()` 的 `composedNLInstruction` **禁止复活**。草稿导出/恢复用 `legacyInstruction()` 归一化；拼接/导出/恢复三处一起改，两端共用此 VM，写入指令必须 `.localized()`。

## UI / 播放器 / 切页
- ⚠️ U+FFFC 判空两端相反：macOS `capsuleInvisibleCharacters` 含、`capsuleTrimCharacters` 不含；iOS `TokenCapsuleOverlay.lineRects()` 不算空白。mac 胶囊 v14：实色底（`accent` 0.28 混进 `#15171B`）+ 顶部 2pt 亮线，禁退回 `base.withAlphaComponent`。
- iOS：`ScreenMetrics` 四档；iPad `isPadClass = width>=740 && height>=700`（别用 sizeClass）；浮层用 `metrics.tabBarClearance` 禁硬写 58；参数面板唯一数据源 `StudioParamContent`；`TokenEditorStore` 打字不经 SwiftUI；`TokenCaretTextView` 只削 height + TextKit 1。
- ⚠️ iOS 参数面板语言 chip 默认全展开（`ForEach(Constants.nlLanguages)`），禁加「展开全部」/`languagesExpanded`。
- ⚠️ CPU 暴涨根因=订阅拓扑：`PlaybackStatus` 只订阅单属性 publisher；高频显示只许小 View 各自 `@ObservedObject`，禁 `@StateObject player`、禁 progress 传给所有行；macOS 音色库页面级只 `.onReceive($playingKey.removeDuplicates())`。
- ⚠️ 两份同名 `AudioPreviewPlayer` 按目标隔离。iOS 后台播放 `.playback`+`UIBackgroundModes=[audio]`；`playingKey` 存 identifier、跨 key `reidentify(_:)`；并发闭包「外层 `guard let self`+`Task @MainActor`」。
- ⚠️ iOS `AudioPreviewPlayer+iOS.swift`：所有 `AVAudioSession.setCategory/setActive` 与 `AVAudioPlayer(contentsOf:)`/`prepareToPlay()` 必须在串行队列 `audioWorkQueue` 上（Xcode 27 Hang Risk）；主线程只做 `delegate`/`play()`/状态发布；`playRequestSerial` 防竞态，`stop()`/`play(url:)` 都 `&+= 1`；`enableRate` 必须在 `prepareToPlay()` 前设。
- ⚠️ 阅读区播放底色两端都是「整篇唯一一块」（mac `PlayerTranscriptView.highlightLayer`/iOS `PlayerDetailControls.highlightLayer`，画在内容 VStack 的 `background`），行位置各走 fileprivate `TranscriptRowFrameKey`；**禁改回每行各画一块**；`highlightTravel`(0.34) 与 `scrollCurrent` 同值同曲线；`.animation(value:)` 只挂这一层。
- ⚠️ `ContentView.mainContent` ZStack 双层：访问过的 `.voiceStudio`/`.voices` 常驻只切 opacity，禁 `.id(renderedSection)` 重建、禁 `Color.clear` 门控；靠 `isActive` 补偿生命周期，禁失活时 cancel `loadTask`/重置 `voicesAppear`；`appState.voices` 变化须 `invalidateQueryCacheAndReload()`；首屏 `onAppear`→`Task.sleep(32ms)`→`vm.load()`（禁 `Task.yield()`）。

## 历史 / 列表 / 积分 / 弹窗
- ⚠️ 收藏与软删绝不入库：`AudioFlagStore`（UserDefaults JSON，30 天），`purgeExpired()` 交 `ProjectService.deleteAudio`。
- ⚠️ `.plain` List 清零留白（`listSectionSpacing(0)`+`defaultMinListHeaderHeight=0`+`contentMargins(.top,0)`）；macOS 分组类型须 `HistoryDay*` 前缀；`AudioRowItem` 第二行各字段 `fixedSize`+整行 `fixedSize(horizontal:true)`；进度条只 `scaleEffect(x:anchor:.leading)`、禁 `.clipShape`；`MiniPlayerView` h=56，List 末尾插透明占位 Section。
- 积分全链路 Double(≤2位) `CreditPrecision.normalize`，计费 `字符数/100*rate`（普通2/复刻5，CJK 算 2 字符）；`GenerationDialog` 清空须 `displayName: nil`；`PackageCard` 副标题禁 `.lineLimit(1)`。
- ⚠️ 每次 App 打开弹评分，口径「每进程一次」`ReviewRequestGate`（`nonisolated(unsafe) static var`），禁 `@State` 标记、禁 `scenePhase != .active` 复位；**两端入口不同、禁互相抄**：iOS `requestReviewOnEveryOpen()` 挂 `iOSContentView`；macOS `AppDelegate.applicationDidFinishLaunching`→`LaunchReviewRequester`。

## 草稿（详见 11-11 日志）
- `DraftSnapshot`/`Draft`/`DraftStore` 全在 `VoiceStudioViewModel.swift` 尾部，禁进 SQLite / `AudioFlagStore`；`Documents/Drafts/` 下 `index.json` 只元数据、正文 `<id>.json`，禁退回单文件 `drafts.v1.json`；`loadedItems` 不参与 Codable，正文缺失 `load` 返回 nil。
- ⚠️ 恢复前 `stashBeforeRestore(_:)` 新建 manual 草稿（禁 `save(before, source:.auto)` 覆盖单槽位）；`Draft.isSameEditState` 全同才跳过；恢复统一 `vm.apply(_:appState:)`（含 `StudioParamStore.save`）。
- ⚠️ 取快照前必须结算编辑器去抖（mac 0.35s）：View `commitEditor()`；⌘S `DraftStore.saveFromSharedVM()`→`PendingEditorCommit.flush()`；正文唯一格式 `[TTSContentItem]`，禁降纯文本；iOS 保存用 `TokenDocument.contentItems`。
- 反馈通道（**两端各自实现，禁止共用类型/状态**）：iOS `IOSUIState.showToast`→`RootTabView` 顶部 `ToastHost`；macOS `MacUIState.showToast`（`MacToastMessage`+`MacToastHost` 全在 `View/macOS/ContentView.swift`）→`ContentView` overlay，由 `WindowGroup` 注入 `.environmentObject`。⚠️ 两端 `duration` 统一 1s，出现 `withAnimation(.spring)`+`.id`+`.transition`，消失 `.easeOut(0.25)`；禁自绘提示条/撤销按钮；**打开 App 编辑区恒为空**。⚠️ 外观刻意不同：iOS = Aurora 实色胶囊+白字+同色光晕；macOS = Cold Luxury 浮层（`bgElevated`+`borderMedium` 0.5 描边+中性黑投影、`AppRadius.medium`、高 42），状态色只给 24×24 图标方块。
- ⚠️ 自动草稿标题**落盘只存中文 key** `Draft.autoTitleKey`；显示/搜索/重命名预填/复制用 `draft.displayTitle`。禁把 `.localized()` 结果写进草稿索引。
- ⚠️ iOS `DraftSheet` 浮层必须 `.overlay {}` 挂内容 VStack；macOS 草稿列表=窗口内自绘 modal（`showDraftModal`+`DraftModalView`），禁 `.popover`；Dialog 一律 `presentDraftDialog(_:)`；`DraftModalView.focusable` 紧跟 `.focusEffectDisabled()`；⌘S 走 `KeyboardShortcuts.Name.saveDraft`+`DraftShortcutController`。

## 商店页 / ASO（细节在 `产品/商店页/*.md`）
- 尺寸 6.9" `1320×2868`(禁 alpha)/iPad 13" `2752×2064`/Mac `2880×1800`；iOS 无声音复刻 UI、字幕禁写能力数量；⚠️ 旧生成器未被 git 追踪、已消失，重做 01–04/06 只能改 tracked 的 `素材/html/*`；headless 底部 21px 白条靠 `html{background:#0B0C0F}` 兜底 + 底部 24px 亮度校验重渲。
