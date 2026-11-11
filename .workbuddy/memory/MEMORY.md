# EmotionVoice 长期约定（禁令 / 根因 / 入口）
细节见 `.workbuddy/memory/YYYY-MM-DD.md`、`产品/商店页/*.md` 与代码注释。本文只留易被「顺手改回去」的禁令。

## 工程 / 构建
- target `Emora`(mac) / `iOSEmora`(iOS 18.6)；iOS 独有放 `View/iOS/`；复用 macOS 文件原地加 target + `#if canImport(AppKit)`；新增 iOS .swift 要改 pbxproj 4 处 → **优先塞已有文件**。
- SQLite 永不迁移：改 `createTables()` 必 bump `currentSchemaVersion`，不符 DROP 重建。
- 构建 `bash tools/ios_build.sh mac`（不带参数只编 iOS）；类型检查 `tools/ios_typecheck/typecheck.sh`（`Shims.swift` 同步真实签名）；workaround：`IDEPackageSupportDisableManifestSandbox` / `-disable-sandbox` / `ONLY_ACTIVE_ARCH=YES`。
- ⚠️ 四配置默认 MainActor：后台纯计算显式 `nonisolated`（私有 helper 同加），静态非 Sendable 用 `nonisolated(unsafe)`；Swift 5 仅 warning，须 grep 构建日志。
- macOS 首屏 `.defaultSize(visibleFrame)` + `viewDidMoveToWindow()` 同步，禁 `DispatchQueue.main.async` 延迟 setFrame；SPM `unable to read tree` → `git fetch` 补缓存，别删目录；`Log()` 仅 `#if DEBUG`。
- mac 产物**是沙盒**，`.documentDirectory` = `~/Library/Containers/<bundle>/Data/Documents`。

## TTS 链路
- 无密钥 WS `wss://<ref>.supabase.co/functions/v1/bailian-tts?region=CN|INTL`，单条 `{"action":"synthesize"}`；run/continue/finish-task 与标签切段都在边缘函数，断线不可续传（Deno<2.5 用 `dialUpstream()`）。`BailianTTSService.receive()` 是唯一 WS 接收点；`ttsPipeline` 串行互斥；模型 `qwen-audio-3.0-tts-plus`(env `BAILIAN_TTS_MODEL`)。
- ⚠️ 改 `supabase/functions/bailian-tts/index.ts` 必须部署并核对版本（`supabase functions deploy bailian-tts --project-ref dpyyhbqqmegencxekkcr` + `functions list` 看 VERSION）；曾因线上旧版导致新参数被静默丢弃、`words[]` 全空。
- ⚠️ `language_hints`：`Constants.nlLanguages[].languageHint` 唯一映射源（16 官方语言，8 方言留空、禁映射 `zh`）→ `languageHint(forName:)` → VM `synthesizeWithTimeline(languageHint:)` → `buildSynthesizeRequest` 写 `payload["language_hints"]=[hint]`（只 1 值，无值不写）→ 边缘函数 `ALLOWED_LANGUAGE_HINTS`。试听传 nil。
- `payload["instruction"]`：客户端非空才写、边缘函数原样透传到 `parameters.instruction`，无语言/字数校验；官方只要求「指令语种与 text 一致」；UI `instructionLimit=1000`。
- 字级时间戳 `word_timestamp_enabled` → `sentence-end.words[]`；sidecar `<fileName>.timestamps.json`（禁改 SQLite），段偏移按各段实际音频时长累加；任一段缺 words 整条不写、播放器走静态原文，**禁估时伪造对齐**。

## 时间戳对齐 / 切句（详见 11-06~11-11 日志）
- ⚠️ `words[].text` 是 `normalized_text`（繁→简）非原文；v3 起落盘前 `alignToOriginal(_:source:)` 重分配，首选自己发出的 `segment.text`，上游 `original_text` 仅次选。逐字高亮必须拼 `word.text`；`sentence-begin.words` 恒空。
- ⚠️ `remap` 三通道：① 去空白字数相等→逐位；② 按词内占号字符数累计 `sliceByUnitEnds`（不看上游 index）；③ 上游 `begin_index/end_index`。末尾须过 `previousEnd == unitVisible.count`；`allowSurfaceMatch:false` 用于 v2+ 迁移。
- ⚠️ `begin_index/end_index` 是「占号单元全文连续序号」非字符位置：占号=字母/数字/表意文字，标点/符号/emoji 不占号（判据 `isSpokenUnit`，别退回 `!isPunctuation`）；阿里云文档「整句中的开始位置」是错的，英文 index 按词编号不可信→靠②兜底。
- ⚠️ v4 对齐必须保留空白：`normalizeWhitespace()` 压连续空白后切片（计数按非空白），禁「去空白数组+逐字回填」（英文会粘成 `Today,AIIspoweredby…`）。
- ⚠️ 上游常把整段折成 1 个 `sentence-end`：句卡靠 `splitBySentenceEnding()` 按 word 自带标点重切，只看词首前导标点簇，`inQuote` 区分 `。"星`/`。"哥`；v5 兼容西文词尾标点靠 `endsWithTerminal()`。切分只改 `text`，`beginMs/endMs` 不动。
- ⚠️ `AudioTimeline.currentVersion = 6`：对齐与切句共用版本号，改任一条都 bump。`load` 比 `audio.text`：`version==current && textMatches` 才原样返回，低于当前 `realign`，无原文 `regrade`；缓存存「结论」；算法改动跑 `/tmp/ts_verify2.py` + `/tmp/ts_real.py`。
- ⚠️ 逐字高亮禁给当前字 `.bold()`（折行晃动）；颜色用 `AppColor.blend(hex,hex,t)` 按字内进度插值，三档 `AppColor.WordTone`。

## 本地化 / 音色 / 生成
- `.localized()` 用中文原文当 key；⚠️ 禁 `String(format:"…%@…".localized(), arg)`，须 `"…%@".localized(arg)`。三语 zh-Hans/zh-HK/en 同步；繁体 OpenCC `s2t`+覆写、别用 s2hk；仿音色文案在 `<lproj>/VoiceCatalog.strings`。
- 唯一数据源 `Voices/basic_voices.json`(v4)（改后跑 `tools/gen_basic_voices.py`）；标签唯一来源 `Shared/Models/Constants.swift`（24 语气/7 官方拟声），商店图禁自造标签。
- ⚠️ `VoiceCatalog.string()` NSCache 禁去；`VoiceService.cachedOrderedKeys` 无搜索词走 `orderedKeysWithoutSearch`；iOS 分类筛选只在进程内 `VoiceLibraryFilterStore`，禁读写 `AppState.voiceLibrary*`，取消 apply 也要 `commit(fresh,total)` + `onAppear` 自愈。
- `toTTSAPIString()` 已弃（生成走 `toTTSSegments()`+`AudioConcatenator.merge()`）；胶囊整条热区 `contentShape(Rectangle())`。

## UI / 编辑器
- ⚠️ U+FFFC 判空两端相反：macOS `capsuleInvisibleCharacters` 含、`capsuleTrimCharacters` 不含；iOS `TokenCapsuleOverlay.lineRects()` 不算空白，别互相抄。macOS 胶囊 v14：实色底（`accent` 0.28 混进 `#15171B`，`accent = base.darkened(0.48)`）+ 顶部 2pt 亮线、不描边圆角 8；禁退回 `base.withAlphaComponent` 直叠。
- iOS：`ScreenMetrics` 四档；iPad `isPadClass = width>=740 && height>=700`（别用 sizeClass）；两栏卡高 GeometryReader 实测；iPadOS 18 浮层用 `metrics.tabBarClearance` 禁硬写 58；参数面板唯一数据源 `StudioParamContent`；`TokenEditorStore` 打字不经 SwiftUI；`TokenCaretTextView` 重写 `caretRect(for:)` 只削 height + TextKit 1。
- ⚠️ iOS 参数面板语言 chip 默认全展开（`ForEach(Constants.nlLanguages)`），禁加「展开全部」/`languagesExpanded`。

## 播放器 / 订阅 / 切页
- ⚠️ CPU 暴涨根因=订阅拓扑：`PlaybackStatus` 只订阅单属性 publisher；高频显示只许小 View 各自 `@ObservedObject`，禁 `@StateObject player`、禁把 progress 传给所有行；macOS 音色库页面级只 `.onReceive($playingKey.removeDuplicates())`。
- iOS 后台播放：AVAudioSession `.playback` + `UIBackgroundModes=[audio]`（INFOPLIST_FILE 模板 + `plutil -extract` 验产物）；封面 `makeArtwork` 全幅不透明渐变；`playingKey` 存 identifier、跨 key `reidentify(_:)`；⚠️ 并发闭包「外层 `guard let self` + `Task @MainActor`」。
- ⚠️ `ContentView.mainContent` ZStack 双层：访问过的 `.voiceStudio`/`.voices` 常驻只切 opacity，禁 `.id(renderedSection)` 重建；两页铺不透明 `bgPrimary`；禁 `Color.clear` 门控。
- ⚠️ 常驻页靠 `isActive` 补偿生命周期（关 sheet/popover、交出 firstResponder、停骨架扫光 + `persistAndPause()`）；禁失活时 cancel `loadTask` / 重置 `voicesAppear`。`appState.voices` 变化须 `invalidateQueryCacheAndReload()`；首屏 `onAppear` → `Task.sleep(32ms)` 跨帧 → `vm.load()`（禁 `Task.yield()`）。

## 历史 / 列表 / 积分 / 弹窗
- ⚠️ 收藏与软删绝不入库：`AudioFlagStore`（UserDefaults JSON，30 天），`purgeExpired()` 交 `ProjectService.deleteAudio`。
- ⚠️ `.plain` List 清零留白（`listSectionSpacing(0)`+`defaultMinListHeaderHeight=0`+`contentMargins(.top,0)`）；macOS 分组类型须 `HistoryDay*` 前缀；`AudioRowItem` 第二行各字段 `fixedSize`、整行 `fixedSize(horizontal:true)`，禁时分右列+`Spacer()`；进度条只 `scaleEffect(x:anchor:.leading)`、禁加 `.clipShape`；`MiniPlayerView` h=56，List 末尾按 `miniPlayerVisible` 插透明占位 Section。
- iOS 列表左滑统一「删除 `trash.fill` destructive / 复制 `square.on.square` `c.info` / 重命名 `square.and.pencil` `c.success`」+ `RenameDialog`（自动聚焦 + 清空按钮），草稿列表照抄这套。
- 积分全链路 Double(≤2位) `CreditPrecision.normalize`，计费 `字符数/100*rate`（普通2/复刻5，CJK 算 2 字符），云端 `numeric(10,2)`。
- `StudioParamValues`/`Store` 在 `Shared/ViewModels/VoiceStudioViewModel.swift`，键 `studioParam.*`；⚠️ 禁把 `AppState.defaultFormat`/`defaultSampleRate` 当存储；「重置」只 `reset(on: vm)` = `.factory`(mp3/22050/1.0x/100%)。
- ⚠️ 语音指令拼接必须 `.localized()`（`nlLanguages.name`/`nlPresets.instruction` 均为中文 key），禁拼中文原文；分隔符中文 `,`、英文 `, `（`AppLanguage.isChinese`）。
- ⚠️ 每次 App 打开弹评分：`AppUpdateManager.requestReviewOnEveryOpen()` 两端根容器各一行、不做本地节流；每进程一次 `ReviewRequestGate`（`nonisolated(unsafe) static var`）。禁把标记放回 `@State`、禁 `scenePhase != .active` 复位（会连环弹窗）。

## 商店页 / ASO
- 细节全在 `产品/商店页/*.md`；硬约束：6.9" `1320×2868`(禁 alpha) / iPad 13" `2752×2064` / Mac `2880×1800`，iOS 无声音复刻 UI、字幕禁写能力数量；headless 截图底部 21px 白条靠 `html{background:#0B0C0F}` 兜底。

## 草稿功能（11-11 落地，细节见当日日志）
- 数据层全在 `Shared/ViewModels/VoiceStudioViewModel.swift` 尾部：`DraftSnapshot` / `Draft` / `DraftStore`，**禁进 SQLite、禁混 `AudioFlagStore`**；解码失败留 corrupt 备份，30 天清 `generatedAt`。
- ⚠️ 存储 = `Documents/Drafts/`（`kDraftsSubdirectory`）：`index.json` 只元数据（启动/列表/角标只读它）、正文单独 `<id>.json`。**禁退回单文件整库 `drafts.v1.json`**（写放大 + 单点损坏 + 启动全量解码）；旧库由 `migrateLegacyStoreIfNeeded()` 搬走改名 `.migrated.json`。
- ⚠️ `Draft.loadedItems` 不参与 Codable（索引必须 KB 级）：索引条目 `hasBody == false`、`items` 空，恢复/复制一律先 `DraftStore.load(id:)`；正文缺失/损坏时 `load` 返回 nil（**不是空正文**），禁拿它覆盖编辑器。
- ⚠️ 恢复前兜底走 `stashBeforeRestore(_:)`：新建 manual 草稿（禁 `save(before, source:.auto)` 覆盖单槽位，连切会丢中间内容）；跟「编辑中」/「上次编辑」**编辑态全同**才跳过（`Draft.isSameEditState` = 正文+音色+四项参数+指令），禁退回只比 `items`（恢复后只调参数再切走会误判重复、参数白调）；恢复后 `restore(full.id)`。
- ⚠️ 保存/恢复取快照前必须结算编辑器去抖（macOS 0.35s）：View 内 `commitEditor()`；⌘S/文件菜单走 `DraftStore.saveFromSharedVM()` → `PendingEditorCommit.flush()`（编辑器注册钩子：macOS `commitPendingChangesNow`、iOS `editor.flush()`）。漏了会存上一版正文，且迟到回调在 `vm.apply` 后把旧内容写回。
- ⚠️ 正文唯一格式 = `[TTSContentItem]`（双 target 共用 + Codable），**禁降成纯文本**；iOS 保存须用 `TokenDocument.contentItems` 覆盖（打字期 `vm.ttsItems` 是旧的），恢复用 `TokenDocument.make` + `editor.replace`。
- ⚠️ 恢复统一走 `vm.apply(_:appState:)`：内含 `StudioParamStore.save` 双向写回 + 音色下架回落；语音指令只存语义值（`exportNLInstruction`/`restoreNLInstruction`），禁落盘拼好的句子。
- ⚠️ 列表行：标题=首行前 30 字、副标题取「首行之后」（单行从 `title.count` 往后接），**禁再截全文**；元信息只 `字数 · 音色`（不显示标签数）；`Draft.timeText` 一律「日期+时间」，禁「今天/昨天」。
- ⚠️ 反馈（Mac/iOS）统一 `AlertToast` `.toast(...)` + `.hud`（顶部居中、1.5s、`.complete`），文案只「草稿已保存 / 草稿已恢复」；**禁自绘提示条、禁撤销按钮 / 撤销窗口**。iOS 保存须先 `draftsPresented=false` 收 Sheet 再弹；`import AlertToast` 走 `#if canImport`（裸 import 会让 typecheck 报 no such module）。
- ⚠️ **打开 App 编辑区恒为空**：两端 `restoreLastEditIfNeeded()` 已删，禁再加冷启动自动回填；上次内容只在草稿列表「自动保存」那条。
- ⚠️ iOS `.hud` 不认宿主：中线钉死在全局 `alertRect.height`（≈33pt）被导航栏压住，必须传 `offsetY`（见 `StudioView.draftToastOffsetY`，含 navBarClearance(44) 与 iPad 8），禁去掉。
- ⚠️ iOS `DraftSheet` 恢复确认 / 删除浮层**必须 `.overlay {}` 挂在内容 VStack 上**，禁当外层 `ZStack` 兄弟（高度提案 nil → `c.scrim` 只剩一条）；浮层卡片必须自带 `c.surface` 底色 + 阴影，否则叠字。
- ⚠️ iOS 草稿左滑 / 长按菜单 = 删除、复制、重命名；重命名必须 `RenameDialog`，禁自绘 TextField。
- macOS「清空」与「存为草稿」同排，动作 `clearEditor()` = `resignTextEditor()`+`vm.clearText()`+`markEditing(nil)`，无二次确认。
- ⚠️ 草稿浮层都不变 key window：Dialog 一律走 `presentDraftDialog(_:)`（含 `resignTextEditor()`），`draftDialog != nil` 与 `showDraftModal` 都要参与 `EmotionTokenEditor(isInteractive:)`，否则打字仍落进正文；`resignTextEditor()` 须**先 `mainWindow` 再 `keyWindow`**。
- ⚠️ 草稿列表 = 窗口内自绘 modal（`showDraftModal` + `DraftModalView`：遮罩 + 440 中心卡），**禁退回 `.popover`**；它的 overlay 写在 `draftDialog` 之前（先=下层），确认层才能压在列表上；`isKeyboardActive: draftDialog == nil` 让出键盘（否则 ⏎ 在确认框底下再跑一次恢复），恢复成功由 `performRestore` 收起。
- ⚠️ `DraftModalView` 的 `.focusable` 挂在整层 ZStack 上（接 ↑↓/⏎/Esc），必须紧跟 `.focusEffectDisabled()`：否则 AppKit 沿整个工作台画系统 focus ring（一圈很大的蓝色描边）。
- ⚠️ `setContent` 改 `-> Bool`：程序化装载（恢复/切页）不问 `shouldChangeText`；失败时禁更新 `lastExportedFromView`（否则判已同步、永不重试）。
- ⚠️ macOS 保存快捷键固定 ⌘S，走 `KeyboardShortcuts.Name.saveDraft` + `DraftShortcutController`（`View/macOS/EmotionVoiceApp.swift`），**禁在设置页加 `Recorder`**；Carbon 热键必须随 `didBecomeActive/didResignActive` enable/disable；`.commands` 的 `.saveItem` 只作显示/兜底。
