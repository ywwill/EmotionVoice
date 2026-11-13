# EmotionVoice 长期禁令（细节见 .workbuddy/memory/YYYY-MM-DD.md 与代码注释）

## 工程 / 构建
- target `Emora`(mac)/`iOSEmora`(iOS18.6)；iOS 独有 `View/iOS/`；新增 iOS .swift 改 pbxproj 4 处→优先塞已有文件。
- ⚠️ SQLite 永不迁移：改 `createTables()` 必 bump `currentSchemaVersion`→DROP 重建。
- 构建 `bash tools/ios_build.sh mac`；`tools/ios_typecheck/typecheck.sh`（Shims 同步签名、MAC_ONLY 排除 mac 版 `AudioPreviewPlayer`）。
- ⚠️ 默认 MainActor：后台纯计算 `nonisolated`、静态非 Sendable `nonisolated(unsafe)`。
- ⚠️ AlertToast SPM 已删，重引入须 `#if canImport(AlertToast)`；合并分支后查 `Package.resolved`。
- macOS 首屏 `.defaultSize(visibleFrame)`+`viewDidMoveToWindow()`，禁 `DispatchQueue.main.async` setFrame；`Log()` 仅 DEBUG。

## TTS / 时间戳
- 无密钥 WS `.../functions/v1/bailian-tts?region=CN|INTL`；⚠️ 改边缘函数必部署并核对 VERSION；`BailianTTSService.receive()` 唯一接收点。
- `language_hints` 唯一映射源 `Constants.nlLanguages[].languageHint`（方言留空、禁映射 zh）；`instruction` 非空才传。
- 时间戳走 `sentence-end.words[]`；sidecar `<fileName>.timestamps.json`；任一段缺 words 整条不写，禁伪造对齐。
- ⚠️ 段时长按 MP3 帧累加（禁按字节估）；`AudioTimeline.currentVersion = 6`，对齐/切句任一改都 bump。
- ⚠️ 占号单元用 `isSpokenUnit`（字母/数字/表意文字）；`words[].text` 是 `normalized_text`，落盘前 `alignToOriginal` 重分配；`[clears throat]` 整句拼字符流再扫。
- 上游常把整段折成 1 个 `sentence-end`→`splitBySentenceEnding()` 重切，只改 text 不动时间。

## 本地化 / 音色
- `.localized()` 用中文原文当 key；禁 `String(format:"…%@…".localized(), arg)`；改 key 需 8 份 Localizable.strings 同步改。
- ⚠️ 5 语言译文由 `tools/localization/build_localizable.py` 生成；VoiceCatalog 法德日韩俄由 `gen_voice_catalog.py` 生成；禁手改生成物。
- ⚠️ 音色唯一数据源 `Voices/basic_voices.json`(v4)，改后跑 `tools/gen_basic_voices.py`；标签唯一来源 `Constants.swift`；`VoiceLangCode` 只有 zh/en。
- ⚠️ 持久化不动（11-13 决策）：只在显示时按 `voice_key` 取名，唯一入口 `VoiceService.resolvedVoiceName(forKey:legacyName:)`；名字缓存键带 `AppLanguage.catalogLocale`。
- 语言 chip 与指令框解耦：`toggleLanguage()` 只切语言、`updateNLInstruction()` 只由 `applyPreset()` 调；`composedNLInstruction` 禁复活。
- `StudioParamValues` 键 `studioParam.*`；禁把 `AppState.defaultFormat` 当存储、禁 `VoiceStudioView.onAppear` 覆盖参数。

## UI / 播放器
- ⚠️ CPU 暴涨根因=订阅拓扑：`PlaybackStatus` 只订阅单属性；高频显示只许小 View 各自 `@ObservedObject`，禁 `@StateObject player`。
- iOS 后台播放 `.playback`+`UIBackgroundModes=[audio]`；`AudioPreviewPlayer+iOS` 的 AVAudioSession/AVAudioPlayer 必须在串行队列，`playRequestSerial` 防竞态。
- ⚠️ 阅读区播放底色是「整篇唯一一块」（`highlightLayer` 画在内容 VStack 的 background），禁每行各画一块。
- ⚠️ `ContentView.mainContent` ZStack 双层常驻只切 opacity，禁 `.id()` 重建；首屏 `onAppear`→`Task.sleep(32ms)`→`vm.load()`。
- ⚠️ U+FFFC 判空两端相反（mac `capsuleInvisibleCharacters` 含、iOS `lineRects()` 不算空白），禁统一。

## 历史 / 积分 / 草稿 / 商店
- ⚠️ 收藏与软删绝不入库（`AudioFlagStore` UserDefaults 30 天）；`AudioItem.voice` 是 key。
- ⚠️ 评分：每打开 3 次 App 申请一次 → `ReviewRequestGate`（UserDefaults `review.launchCount`，每进程只判断一次、禁 `@State` 标记）；入口两端不同禁互抄：iOS `requestReviewOnEveryOpen()` 挂 `iOSContentView`，macOS `AppDelegate`→`LaunchReviewRequester`。
- 积分 `CreditPrecision.normalize`；计费 `字符数/100*rate`（CJK 算 2 字符）。
- ⚠️ 草稿禁入 SQLite：`Documents/Drafts/` 下 `index.json` 元数据 + `<id>.json` 正文；取快照前必结算编辑器去抖（mac 0.35s）。
- macOS 草稿列表用窗口内自绘 modal（`showDraftModal`），禁 `.popover`；反馈通道两端各自实现，禁共用类型。
- 商店页 6.9" 1320×2868（禁 alpha）/iPad 13" 2752×2064/Mac 2880×1800；iPhone 真机图走 `素材/gen_ios_05_v2.py`、`gen_ios_02.py` 独立通道。
