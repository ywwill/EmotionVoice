# EmotionVoice 长期约定（禁令 / 入口）
只留「顺手改回去就会出事」的禁令；完整因果与验证见 `.workbuddy/memory/YYYY-MM-DD.md`、`产品/商店页/*.md`、代码注释。

## 工程 / 构建
- target `Emora`(mac)/`iOSEmora`(iOS18.6)；iOS 独有 `View/iOS/`，复用 macOS 文件加 target + `#if canImport(AppKit)`；新增 iOS .swift 改 pbxproj 4 处 → 优先塞已有文件。
- ⚠️ SQLite 永不迁移：改 `createTables()` 必 bump `currentSchemaVersion` → DROP 重建；只加注释/不动表结构别 bump。
- 构建 `bash tools/ios_build.sh mac`（先 iOS 再 mac）；`tools/ios_typecheck/typecheck.sh`（Shims 同步签名、MAC_ONLY 排除 mac 版 `AudioPreviewPlayer`）；workaround `IDEPackageSupportDisableManifestSandbox`/`-disable-sandbox`/`ONLY_ACTIVE_ARCH=YES`。
- ⚠️ 默认 MainActor：后台纯计算 `nonisolated`（helper 同加）、静态非 Sendable `nonisolated(unsafe)`；typecheck `-swift-version 5` + Shims 的 `VoiceService` 显式 @MainActor → 模型调它须显式 `@MainActor`，否则 `ActorIsolatedCall`。
- ⚠️ AlertToast SPM 已删；重引入须 `#if canImport(AlertToast)`。合并分支后查 `Package.resolved` 与冲突标记。
- macOS 首屏 `.defaultSize(visibleFrame)`+`viewDidMoveToWindow()`，禁 `DispatchQueue.main.async` setFrame；`Log()` 仅 DEBUG；mac 沙盒 Documents=`~/Library/Containers/<bundle>/Data/Documents`。

## TTS / 时间戳（详见 11-06~11-11 日志）
- 无密钥 WS `.../functions/v1/bailian-tts?region=CN|INTL`，单条 `{"action":"synthesize"}`；切段在边缘函数，断线不可续传；`BailianTTSService.receive()` 唯一接收点；`ttsPipeline` 串行互斥。
- ⚠️ 改 `supabase/functions/bailian-tts/index.ts` 必部署并核对 VERSION（`supabase functions deploy bailian-tts --project-ref dpyyhbqqmegencxekkcr` + `functions list`）。
- ⚠️ `language_hints`：`Constants.nlLanguages[].languageHint` 唯一映射源（16 官方语言，8 方言留空、禁映射 `zh`）→ `languageHint(forName:)` → `payload["language_hints"]=[hint]`（只 1 值、无值不写）→ 边缘函数白名单；试听 nil，降级重跑保留 hint。`payload["instruction"]` 非空才写、原样透传；UI `instructionLimit=1000`。
- 时间戳走 `sentence-end.words[]`；sidecar `<fileName>.timestamps.json`（禁改 SQLite/禁 DROP），段偏移按每段实际音频时长累加；任一段缺 words 整条不写、走静态原文，禁估时伪造对齐。
- ⚠️ 段时长按 MP3 帧累加（`AudioConcatenator.mp3DurationSeconds`），禁按字节估；末字>时长×1.2 退回静态原文；6% 漂移闸不过不写 sidecar。
- ⚠️ `[clears throat]` 会被劈成两个 word：`TranscriptTagMarkup` 整句拼字符流再扫（`owner[]` 回填）；阅读区不显示标签/徽标，`hasBody=false` 不占位，句数用 `transcriptSentenceCount`。
- ⚠️ `words[].text` 是 `normalized_text`（繁→简）；落盘前 `alignToOriginal(_:source:)` 重分配，首选 `segment.text`；逐字高亮拼 `word.text`。`remap` 三通道：①去空白字数相等→逐位；②`sliceByUnitEnds` 按占号字符数累计；③上游 index；末尾过 `previousEnd == unitVisible.count`。
- ⚠️ `begin_index/end_index` = 占号单元全文连续序号：占号=字母/数字/表意文字，标点/符号/emoji 不占号（`isSpokenUnit`，别退回 `!isPunctuation`）；别累加句长，英文 index 靠②兜底。v4 保留空白：`normalizeWhitespace()` 压空白后切片，禁「去空白数组+逐字回填」。
- ⚠️ 上游常把整段折成 1 个 `sentence-end`：`splitBySentenceEnding()` 只看 word 前导标点簇重切，`inQuote` 区分 `。"星`/`。"哥`，v5 兼容 `endsWithTerminal()`；切分只改 `text`，`beginMs/endMs` 不动。
- ⚠️ `AudioTimeline.currentVersion = 6`，对齐与切句共用、改任一条都 bump；`load` 低版本 `realign`、无原文 `regrade`；算法改动跑 `/tmp/ts_verify2.py`+`/tmp/ts_real.py`。逐字高亮禁 `.bold()`，颜色 `AppColor.blend`。

## 本地化 / 音色 / 参数
- `.localized()` 中文原文当 key；⚠️ 禁 `String(format:"…%@…".localized(), arg)`，须 `"…%@".localized(arg)`；改中文 key 须 8 份 Localizable.strings（en/zh-Hans/zh-HK/ru/ko/ja/fr/de）+ 两端引用一起改；繁体 OpenCC `s2t`+覆写、别用 s2hk。
- ⚠️ 五语言译文由 `tools/localization/build_localizable.py` + `translations/*.txt` 生成（禁手改 5 份 Localizable.strings）：以 en value 为源、中文 key 不动，逐行对齐，转义 `<NL>`/`<Q>`；`--check` + `plutil -lint`。
- ⚠️ VoiceCatalog 8 语种：法德日韩俄 5 份 `.strings` 由 `tools/localization/gen_voice_catalog.py` + `voice_catalog_data.py`（17 语义族）+ `voice_translations/*.tsv`（180 条）生成；禁手改。`tools/gen_basic_voices.py` 的 `CATALOG_LOCALES` 已扩到 8 份，两生成器共用 header、重跑幂等（禁改回扫描全部 `.lproj`、禁退回 3 份）；`SRC_JSON`=`Shared/Voices/basic_voices.json`。
- ⚠️ 读取链路：`AppLanguage.catalogLocale` 把 `Bundle.main.preferredLocalizations.first` 映射成 8 lproj（zh-Hant→zh-HK，未知→en）；`VoiceCatalog.interfaceLprojCandidates()` 返回 `[本地,"en"]`，`stringForInterface`/`localizedVoiceNameForInterface`/`localizedVoiceFeatureForInterface` 按界面语言取；`rowToVoice` 把 `nameEn`/`descEn` 烘焙成当前界面语言文案（字段名没改）；`orderedKeysWithoutSearch` 也用 ForInterface。⚠️ `VoiceLangCode` 只有 `.zh/.en`（音色语种 ≠ 界面语种）；切语言需重启。
- ⚠️ **11-13 用户最终决策：不动任何持久化，只在解析显示时按 `voice_key` 取名**。`DraftSnapshot.voiceName`/`Draft.voiceName`/`ConsumptionRecord.voiceName`/SQLite `voice_name` 列/`addConsumptionRecord(voiceName:voiceKey:...)` 签名/表结构全部保持原样（禁改成「落盘只存 key」或删列，改表结构会 DROP 重建丢账单）。唯一入口 `VoiceService.resolvedVoiceName(forKey:legacyName:)`，legacyName 仅兜底；`Draft.metaText`（`@MainActor`）、`CreditsService.fetchCreditRecords` 走它。⚠️ `tools/ios_typecheck/Shims.swift` 同步桩。⚠️ `nameCache`/`voiceCache` 键带 `AppLanguage.catalogLocale`（`cacheKey(for:)`，禁裸 key）；`matchesSearch` 同时匹配中文与界面语言两套文案。排序按当前语言名（刻意各语种字母序）。
- ⚠️ 音色命名：599 个（591 zh、8 en），中文三字诗意人名、各语种重新命名、繁体纯 s2t → 专名不能翻译；五语种意象名按 180 feature 归 17 语义族，同语种全唯一。唯一数据源 `Voices/basic_voices.json`(v4)（改后跑 `tools/gen_basic_voices.py`）；标签唯一来源 `Constants.swift`（24 语气/7 拟声）。
- ⚠️ `VoiceCatalog.string()` NSCache 禁去；`cachedOrderedKeys` 无搜索词走 `orderedKeysWithoutSearch`；iOS 分类筛选只在进程内 `VoiceLibraryFilterStore`，禁读写 `AppState.voiceLibrary*`，取消 apply 也要 `commit(fresh,total)`+`onAppear` 自愈。
- `toTTSAPIString()` 已弃（走 `toTTSSegments()`+`AudioConcatenator.merge()`）；胶囊整条热区 `contentShape(Rectangle())`。
- `StudioParamValues`/`Store` 在 `VoiceStudioViewModel.swift`，键 `studioParam.*`；⚠️ 禁把 `AppState.defaultFormat`/`defaultSampleRate` 当存储、禁 `VoiceStudioView.onAppear` 覆盖参数；「重置」只 `reset(on: vm)`=`.factory`。
- ⚠️ 语言 chip 与指令输入框完全解耦：`toggleLanguage()` 只切 `selectedLanguage`；`updateNLInstruction()` 只由 `applyPreset()` 调用、只写 `presetInstruction`。`composedNLInstruction` 禁止复活。草稿导出/恢复用 `legacyInstruction()` 归一化；拼接/导出/恢复三处一起改，写入指令必须 `.localized()`。

## UI / 播放器 / 切页
- ⚠️ U+FFFC 判空两端相反：macOS `capsuleInvisibleCharacters` 含、`capsuleTrimCharacters` 不含；iOS `TokenCapsuleOverlay.lineRects()` 不算空白。mac 胶囊 v14：实色底（`accent` 0.28 混进 `#15171B`）+ 顶部 2pt 亮线，禁退回 `base.withAlphaComponent`。
- iOS：`ScreenMetrics` 四档；iPad `isPadClass = width>=740 && height>=700`（别用 sizeClass）；浮层用 `metrics.tabBarClearance` 禁硬写 58；参数面板唯一数据源 `StudioParamContent`；`TokenEditorStore` 打字不经 SwiftUI；`TokenCaretTextView` 只削 height + TextKit 1；语言 chip 默认全展开（`ForEach(Constants.nlLanguages)`，禁加「展开全部」）。
- ⚠️ CPU 暴涨根因=订阅拓扑：`PlaybackStatus` 只订阅单属性 publisher；高频显示只许小 View 各自 `@ObservedObject`，禁 `@StateObject player`、禁 progress 传给所有行；macOS 音色库页面级只 `.onReceive($playingKey.removeDuplicates())`。
- ⚠️ 两份同名 `AudioPreviewPlayer` 按目标隔离。iOS 后台播放 `.playback`+`UIBackgroundModes=[audio]`；`playingKey` 存 identifier、跨 key `reidentify(_:)`；并发闭包「外层 `guard let self`+`Task @MainActor`」。
- ⚠️ iOS `AudioPreviewPlayer+iOS.swift`：`AVAudioSession.setCategory/setActive` 与 `AVAudioPlayer(contentsOf:)`/`prepareToPlay()` 必须在串行队列 `audioWorkQueue` 上；主线程只做 `delegate`/`play()`/状态发布；`playRequestSerial` 防竞态，`stop()`/`play(url:)` 都 `&+= 1`；`enableRate` 必须在 `prepareToPlay()` 前设。
- ⚠️ 阅读区播放底色两端都是「整篇唯一一块」（mac `PlayerTranscriptView.highlightLayer`/iOS `PlayerDetailControls.highlightLayer`，画在内容 VStack 的 `background`），行位置各走 fileprivate `TranscriptRowFrameKey`；禁改回每行各画一块；`highlightTravel`(0.34) 与 `scrollCurrent` 同值同曲线；`.animation(value:)` 只挂这一层。
- ⚠️ `ContentView.mainContent` ZStack 双层：访问过的 `.voiceStudio`/`.voices` 常驻只切 opacity，禁 `.id(renderedSection)` 重建、禁 `Color.clear` 门控；靠 `isActive` 补偿生命周期，禁失活时 cancel `loadTask`/重置 `voicesAppear`；`appState.voices` 变化须 `invalidateQueryCacheAndReload()`；首屏 `onAppear`→`Task.sleep(32ms)`→`vm.load()`（禁 `Task.yield()`）。

## 历史 / 积分 / 草稿 / 商店
- ⚠️ 收藏与软删绝不入库：`AudioFlagStore`（UserDefaults JSON，30 天），`purgeExpired()` 交 `ProjectService.deleteAudio`。`AudioItem.voice` 是 key、`NowPlayingStore.currentVoiceName` 是纯内存态。
- ⚠️ `.plain` List 清零留白（`listSectionSpacing(0)`+`defaultMinListHeaderHeight=0`+`contentMargins(.top,0)`）；macOS 分组类型须 `HistoryDay*` 前缀；`AudioRowItem` 第二行各字段 `fixedSize`+整行 `fixedSize(horizontal:true)`；进度条只 `scaleEffect(x:anchor:.leading)`、禁 `.clipShape`；`MiniPlayerView` h=56，List 末尾插透明占位 Section。
- 积分 Double(≤2位) `CreditPrecision.normalize`，计费 `字符数/100*rate`（普通2/复刻5，CJK 算 2 字符）；`GenerationDialog` 清空须 `displayName: nil`；`PackageCard` 副标题禁 `.lineLimit(1)`。
- ⚠️ 每次 App 打开弹评分，口径「每进程一次」`ReviewRequestGate`（`nonisolated(unsafe) static var`），禁 `@State` 标记、禁 `scenePhase != .active` 复位；两端入口不同、禁互相抄：iOS `requestReviewOnEveryOpen()` 挂 `iOSContentView`；macOS `AppDelegate.applicationDidFinishLaunching`→`LaunchReviewRequester`。
- ⚠️ 草稿：`DraftSnapshot`/`Draft`/`DraftStore` 在 `VoiceStudioViewModel.swift` 尾部，禁进 SQLite/`AudioFlagStore`；`Documents/Drafts/` 下 `index.json` 只元数据、正文 `<id>.json`，禁退回单文件 `drafts.v1.json`；`loadedItems` 不参与 Codable。恢复前 `stashBeforeRestore(_:)` 新建 manual 草稿（禁 `save(before,source:.auto)` 覆盖单槽位）；`Draft.isSameEditState` 只比 `voiceKey`；恢复统一 `vm.apply(_:appState:)`。
- ⚠️ 取快照前必须结算编辑器去抖（mac 0.35s）：View `commitEditor()`；⌘S `DraftStore.saveFromSharedVM()`→`PendingEditorCommit.flush()`；正文唯一格式 `[TTSContentItem]`，禁降纯文本；iOS 保存用 `TokenDocument.contentItems`。自动草稿标题落盘只存中文 key `Draft.autoTitleKey`，显示/搜索用 `draft.displayTitle`。
- ⚠️ 反馈通道两端各自实现、禁止共用类型/状态：iOS `IOSUIState.showToast`→`RootTabView` 顶部 `ToastHost`；macOS `MacUIState.showToast`（`MacToastMessage`+`MacToastHost` 在 `View/macOS/ContentView.swift`）→`ContentView` overlay，由 `WindowGroup` 注入 `.environmentObject`。两端 `duration` 1s，出现 `withAnimation(.spring)`+`.id`+`.transition`，消失 `.easeOut(0.25)`；禁自绘提示条/撤销按钮；打开 App 编辑区恒为空。外观刻意不同：iOS = Aurora 实色胶囊+白字+同色光晕；macOS = Cold Luxury 浮层（`bgElevated`+`borderMedium` 0.5 描边+中性黑投影、`AppRadius.medium`、高 42），状态色只给 24×24 图标方块。
- ⚠️ iOS `DraftSheet` 浮层必须 `.overlay {}` 挂内容 VStack；macOS 草稿列表=窗口内自绘 modal（`showDraftModal`+`DraftModalView`），禁 `.popover`；Dialog 一律 `presentDraftDialog(_:)`；`DraftModalView.focusable` 紧跟 `.focusEffectDisabled()`；⌘S 走 `KeyboardShortcuts.Name.saveDraft`+`DraftShortcutController`。
- 商店页尺寸 6.9" `1320×2868`(禁 alpha)/iPad 13" `2752×2064`/Mac `2880×1800`；iOS 无声音复刻 UI、字幕禁写能力数量；旧生成器未入 git，重做 01–04/06 只能改 tracked 的 `素材/html/*`；headless 底部 21px 白条靠 `html{background:#0B0C0F}`/`#F3EFFC` 兜底 + 导出后查底 6 行重渲。
- ⚠️ iPhone 真机图重建走**独立通道**、成片直接覆盖原文件名：05 = `素材/gen_ios_05_v2.py`→`05-shot-favorite.png`，02 = `素材/gen_ios_02.py`→`02-voices-1.png`，都是 `prepare→statusbar→html→export→sheet` + `--lang`（换图必须从 `prepare` 起跑）。屏幕像素 `.device`1033×2240−padding13×2=**1007×2214** 预缩放后 1:1 贴图；源图 885×1920 放大 1.153 后加 `UnsharpMask(1.2,50)` 补小字；Chrome **必须 `--no-sandbox`**。状态栏由墨迹高反解 SFNS Semibold 统一 9:41，刷底会连旁路「静音铃铛」一起擦掉（有意，全组只有时间/信号/WiFi/电量）。真机无灵动岛**禁贴假硬件**，与其余张的顶部差异原样保留。
