# EmotionVoice 长期约定（禁令 / 根因 / 入口）
细节见 `.workbuddy/memory/YYYY-MM-DD.md`；商店页/预览图全部细节见 `产品/商店页/*.md`；代码内亦有同名注释。本文只留会被「顺手改回去」的禁令与根因。

## 工程 / 构建
- target `Emora`(mac)/`iOSEmora`(iOS 18.6)；iOS 独有 `View/iOS/`，复用 macOS 文件原地加 target + `#if canImport(AppKit)`；新增 iOS .swift 要改 pbxproj 4 处 → **优先塞进已有文件，零 pbxproj 改动**。
- SQLite 永不迁移：改 `createTables()` 就 bump `currentSchemaVersion`，不符 DROP 重建。
- 构建 `bash tools/ios_build.sh mac`；类型检查 `bash tools/ios_typecheck/typecheck.sh`（Shims.swift 须同步真实服务签名）；workaround `IDEPackageSupportDisableManifestSandbox` / `-disable-sandbox` / `ONLY_ACTIVE_ARCH=YES`。
- ⚠️ 四配置默认 MainActor：后台纯计算显式 `nonisolated`（私有 helper 同加），静态非 Sendable 用 `nonisolated(unsafe)`；Swift 5 只 warning，验证须 grep 构建日志。
- macOS 首屏 `.defaultSize(visibleFrame)` + `viewDidMoveToWindow()` 同步配置，禁 `DispatchQueue.main.async` 延迟 setFrame；SPM `unable to read tree` → `git fetch` 补缓存（含 DerivedData），别删目录。
- `Log()` 仅 `#if DEBUG` 生效。

## TTS / 本地化
- 无密钥 `wss://<ref>.supabase.co/functions/v1/bailian-tts?region=CN|INTL`，单条 `{"action":"synthesize"}`；run/continue/finish-task 与标签切段都在边缘函数，断线不可续传；Deno<2.5 用 `dialUpstream()`。
- `BailianTTSService.receive()` 是**唯一 WS 接收点**（waitForTaskStarted + 音频流循环共用），入站转储只改这里；`ttsPipeline` 串行互斥。
- 字级时间戳（`word_timestamp_enabled` → `result-generated`/`sentence-end` 的 `words[]`）：`word_timestamp_enabled` 是官方 `parameters` 字段（默认 false、仅流式可用，用户确认**当前所有音色都支持**，客户端早就发过、缺的只是边缘函数透传）；客户端走 `synthesizeWithTimeline()`，不支持时的降级重跑仅作兜底别当主路径。⚠️ 时间轴存 `<fileName>.timestamps.json` sidecar（禁改 SQLite/禁 DROP），段偏移必须按**每段实际音频时长**累加，任一段缺 words 整条不写、播放器走静态原文，**禁估时伪造对齐**。
- ⚠️ **改 `supabase/functions/bailian-tts/index.ts` 必须部署并核对版本**：`supabase functions deploy bailian-tts --project-ref dpyyhbqqmegencxekkcr`，再 `supabase functions list` 看 VERSION/UPDATED_AT 变了才算生效。曾因只在本地改、线上还是 11-06 的 v9，导致参数被静默丢弃、`words[]` 全空排查半天。旧客户端不传该字段 → `undefined !== true` → parameters 与改动前一致，不影响老用户。
- ⚠️ **`words[].begin_index/end_index` 不是原文字符位置**：它们是「非标点字符的连续序号」。实测原文 `"第一句话。\n\n第二句话，带标点。"`（16 字符）→ 11 个 word、max end_index = 11，按 index 切 `original_text` 有 7/11 个词错位。逐字高亮**必须拼 `word.text`**（`words.map(\.text).joined() === normalized_text`，标点已附着在相邻 word 上，拼接不丢标点，只丢 original_text 的换行）。`sentence-begin` 的 words 恒为空，只看 `sentence-end`。
- 边缘函数 `sentence-end` 诊断日志用 `previewSentence()` 截断到 80 字（`SENTENCE_PREVIEW_LENGTH`），**别用 `preview()`**：那里是 500 且受 `?debug=1` 影响，一句一条会让日志随文本线性膨胀（Supabase 日志按量计费）。
- ⚠️ 上游一个 `sentence-end` 常覆盖整段（273 字只回 1 个 idx=0），句卡粒度靠客户端 `TTSTimestampParser.splitBySentenceEnding()` 重切：**只看 word 的前导标点簇**（上游把标点粘在「后一个字」前面，`word.text.last` 永远是汉字，按行尾判断只会切出 1 句——已踩过）；切点落在簇内部，靠 `inQuote` 状态机区分 `。"星`（闭引号归前句）与 `。"哥`（开引号留给后句，整簇前移会让下一句丢引号）；只改 `text`、`beginMs/endMs` 一个不动。sidecar `version` 必须随切分规则 bump（现 `AudioTimeline.currentVersion = 2`），旧文件在 `AudioTimelineStore.load` 里自动重切回写；⚠️ v2 产物**禁止再跑 v2 切分**（标点已前移，重切会退化成一整段），将来改规则必须写专门的版本迁移。
- ⚠️ **上游把整段文本折成 1 个 `sentence-end`**（实测 43 字两句话只回 idx=0），所以落盘前必须 `TTSTimestampParser.splitBySentenceEnding()` 按 word 自带句末标点再切子句，否则句卡只有一张、点哪儿都 seek 到 0。切分**只动卡片边界，时间全取自 word**。
- ⚠️ 逐字高亮**禁给当前字加 `.bold()`**（字重变宽 → 整段重新折行、文字左右晃动）；颜色过渡靠 `AppColor.blend(hex,hex,t)` 按「字内进度」逐帧插值（当前字 未播→高亮、上一个字 高亮→已读，数值天然衔接），三档色在 `AppColor.WordTone`。
- `.localized()` 中文原文当 key；⚠️ 禁 `String(format:"…%@…".localized(), arg)`，须 `"…%@".localized(arg)`。
- 三语 zh-Hans/zh-HK/en：⚠️ 改中文 key 须三份 strings + 两端引用一起改；繁体 OpenCC `s2t`+覆写、别用 s2hk；仿音色文案在 `<lproj>/VoiceCatalog.strings`，繁中商店图按 `zh-HK.lproj` 用词 + `PingFang TC`。

## 音色 / 标签
- 唯一数据源 `Voices/basic_voices.json`(v4)（改后跑 `tools/gen_basic_voices.py`）；标签唯一来源 `Shared/Models/Constants.swift`（24 语气 / 7 官方拟声），⚠️ 商店图禁自造标签。
- ⚠️ `VoiceCatalog.string()` NSCache 禁去掉；`VoiceService.cachedOrderedKeys` 无搜索词走 `orderedKeysWithoutSearch`（不构造 Voice）。
- ⚠️ iOS 分类筛选只在进程内 `VoiceLibraryFilterStore`，禁读写 `AppState.voiceLibrary*`；`VoicesLibraryView`/`VoicePickerSheet` 的 apply 取消也要 `commit(fresh,total)` + `onAppear` 自愈，否则永久空态。
- 生成走 `toTTSSegments()` + `AudioConcatenator.merge()`；`toTTSAPIString()` 已弃（中断 API 不支持）；胶囊整条热区 `contentShape(Rectangle())`。

## UI / 编辑器
- ⚠️ U+FFFC 判空两端相反：macOS `capsuleInvisibleCharacters` **含** U+FFFC（空行过滤防双描边）、`capsuleTrimCharacters` **不含**（裁首尾空白防短行满宽）；iOS `TokenCapsuleOverlay.lineRects()` **U+FFFC 不算空白**，别互相抄。
- macOS 胶囊视觉 v14：实色底（`accent` 0.28 混进 `#15171B`，`accent = base.darkened(0.48)`）+ 顶部 2pt 亮线、不描边圆角 8；⚠️ 禁退回 `base.withAlphaComponent` 直叠。
- iOS：`ScreenMetrics` 四档；iPad `isPadClass = width>=740 && height>=700`（别用 sizeClass）、两栏卡高必须 GeometryReader 实测、iPadOS 18 浮层用 `metrics.tabBarClearance` 禁硬写 58；参数面板唯一数据源 `StudioParamContent`；`TokenEditorStore` 打字不经 SwiftUI；`TokenCaretTextView` 重写 `caretRect(for:)` 只削 height + TextKit 1。

## 播放器 / SwiftUI 订阅
- ⚠️ 两份同名 `AudioPreviewPlayer` 按 target 隔离（typecheck `MAC_ONLY` / `add_ios_target_files.py` 的 `REUSED` 须排除 macOS 版）。
- ⚠️ CPU 暴涨根因 = 订阅拓扑：`PlaybackStatus` 只订阅单属性 publisher；高频显示只许 6 个小 View 各自 `@ObservedObject`，禁 `@StateObject player`、禁把 progress 传给所有行；macOS 音色库页面级只 `.onReceive($playingKey.removeDuplicates())`。
- iOS 后台播放：AVAudioSession `.playback` + `iOSEmora-Info.plist` `UIBackgroundModes=[audio]`（数组键须 INFOPLIST_FILE 模板 + `plutil -extract` 验产物）；封面 `makeArtwork` 全幅不透明渐变。
- `playingKey` 存 identifier、跨 key `reidentify(_:)`；⚠️ 并发闭包「外层 `guard let self` + `Task @MainActor`」。

## macOS 切页 / 音色库首屏
- ⚠️ `ContentView.mainContent` ZStack 双层：访问过的 `.voiceStudio`/`.voices` 常驻只切 opacity，**禁 `.id(renderedSection)` 重建**（NSTextView + 全局 attachment + VM 全量重建 = 卡顿根因）；两页铺不透明 `bgPrimary` 盖住下层；隐藏时**保留整棵视图树，禁 `Color.clear` 门控**。
- ⚠️ 常驻页靠 `isActive` 补偿生命周期（关 sheet/popover、交出 firstResponder、停骨架扫光 + `persistAndPause()`）；**禁失活时 cancel `loadTask` / 重置 `voicesAppear`**（onAppear 不再触发 → 永久骨架）。
- ⚠️ VM 常驻后 `appState.voices` 变化须 `invalidateQueryCacheAndReload()`；首屏 `onAppear` → `Task.sleep(32ms)` 跨帧 → `vm.load()`，禁改回 `Task.yield()`；骨架扫光 `SkeletonShimmer` 一层。
- ⚠️ 首次进库仍卡 = 首次构建 + 首次全表加载 → 启动空闲期 `ContentView.warmUpVoicesLibrary()` 预热（数据预热与挂视图树分两帧、另开 `.task` 别挂更新检查那条）；首次进 `.voices` 的 100ms 延迟**已删除**。

## 历史 / 列表
- ⚠️ 收藏与软删绝不入库：`AudioFlagStore`（UserDefaults JSON，30 天），`purgeExpired()` 交 `ProjectService.deleteAudio`。
- ⚠️ `.plain` List 清零系统留白（`listSectionSpacing(0)` + `defaultMinListHeaderHeight=0` + `contentMargins(.top,0)`）；macOS 分组类型**必须 `HistoryDay*` 前缀**、保留 `displayedAudios`。
- ⚠️ `AudioRowItem` 第二行「音色名 · 时长 · 文件大小 · HH:mm」各字段 `fixedSize` + 整行 `fixedSize(horizontal:true)` 一行显示，禁时分单独右列 + `Spacer()`；卡片进度条只 `scaleEffect(x:anchor:.leading)`，**绝不自加 `.clipShape`**；`MiniPlayerView` height=56，List 末尾按 `miniPlayerVisible` 插透明占位 Section。

## 积分 / 参数 / 弹窗
- 积分全链路 Double(≤2位) `CreditPrecision.normalize`，计费 `字符数/100*rate`（普通2/复刻5，CJK 算 2 字符），云端 `numeric(10,2)`。
- `StudioParamValues`/`Store` 在 `Shared/ViewModels/VoiceStudioViewModel.swift`，键 `studioParam.*`；⚠️ 禁把 `AppState.defaultFormat`/`defaultSampleRate` 当存储，「重置」只调 `reset(on: vm)` = `.factory`(mp3/22050/1.0x/100%)；默认值读 `Constants`/`.factory`；`VoiceStudioView.onAppear` 从设置页覆盖参数**已删，别加回来**。
- `GenerationDialog` 清空须 `displayName: nil`，`hasResult = generatedAudioURL != nil && !isGenerating`；`PackageCard` 副标题禁 `.lineLimit(1)`。
- ⚠️ 用户明确要求「**每次 App 打开都弹评分弹窗**」（与 ASO 文档相反，以用户为准，别改回去）：`AppUpdateManager.requestReviewOnEveryOpen()` 两端根容器各挂一行，**不做本地节流**；StoreKit 365 天 3 次 / TestFlight 不弹是系统硬限制。

## 商店页 / ASO（细节全在 `产品/商店页/*.md`）
- 入口：Mac `素材/gen_previews.py` + `商店页文案-多语言版本.md`；iPhone `gen_ios_previews.py` + `iOS商店页元数据-6语言.md`；iPad `prepare_ipad_real.py` + `gen_ios_previews_ipad.py`。尺寸 6.9" `1320×2868`(禁 alpha) / iPad 13" `2752×2064` / Mac `2880×1800`；⚠️ `素材/raw/` 未被 git 追踪曾被清理。
- ⚠️ Mac 01 覆盖层 `.win` 内叠层、**禁铺满**，zh 缩放 `2112/3456` / en `2122/3442`，`--only=01` build/export 都带；改一语另一语 md5 零回归。
- ⚠️ 06 三语源图都是纯窗口须整幅缩放（禁套繁体 A 类 BOX），英文源高 1143 / 简繁 1145；半行字简体无、繁体已清理、**英文用户要求保留原样禁清理/禁贴字**；繁体 01/02/03/06 真机原生 UI `has_real_06()` 为真时跳过覆盖链、禁挂贴字层；禁全量跑主生成器 / 禁往 `raw/` 塞源图。
- ⚠️ iOS 端没有声音复刻 UI，字幕禁写具体能力数量；iPhone 流程须带 `--html-only --export`（漏了覆盖真机图）；`prepare()` 三分支禁把 zh-Hant 塞进 `localize_en()`；缺 iPad 真机图跳过而非回退自绘。
