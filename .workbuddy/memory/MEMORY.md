# EmotionVoice 长期约定（索引；细节见 `.workbuddy/memory/YYYY-MM-DD.md`）

## 工程 / 构建
Swift+SwiftUI，target `Emora`(macOS)/`iOSEmora`(iOS 18.6)；SPM: SQLite.swift / supabase-swift / keychain-swift。
- iOS 独有 `View/iOS/`；复用 macOS 文件原地加入 iOS target（不复制），`#if canImport(AppKit)` 隔离；`@Published` 须显式 `import Combine`。
- 新增 iOS .swift 手工改 pbxproj 4 处（FileRef + BuildFile + 叶子 group children + iOSEmora Sources）；新 ID `7B3A...`；`tools/add_ios_target_files.py` 的 `IOS_DIR` 指向不存在的顶层 `iOS/`，不可靠；PBXBuildFile ID ≠ XCSwiftPackageProductDependency ID。
- `View/iOS/Views/` 已按职责拆分：`HistoryComponents`（统计条/筛选/分组头/空态）、`HistoryRowViews`（行卡片）、`HistoryOverlays`（mini player/菜单/Toast）、`ProjectsOverlays`（重命名/呼吸条）、`PlayerDetailControls`、`GenerationDialogControls`、`Services/AudioFileSupport`（波形提取/导出/ShareSheet，跨页共用放 Services）。单一 View 只是 body 长的（`StudioView`）和 UITextView 强耦合的（`TokenTextEditor`/`TokenCapsuleOverlay`）不拆。
- SQLite（Documents/emotionvoice.sqlite3）**永不迁移**：改 `createTables()` 就 bump `currentSchemaVersion`，不符 DROP 重建。
- 真构建 `bash tools/ios_build.sh`（`mac` 可回归双 target）；类型检查 `bash tools/ios_typecheck/typecheck.sh`（`Shims.swift` 替身，给真实类加方法须同步加桩）。三 workaround：`IDEPackageSupportDisableManifestSandbox`／`OTHER_SWIFT_FLAGS='$(inherited) -disable-sandbox'`／`ONLY_ACTIVE_ARCH=YES`。既有问题：`CreditsService.swift` 4 条 Swift6 报错、`PackageCardView.swift` 孤儿文件。

## TTS / 本地化
- 无密钥 `wss://<ref>.supabase.co/functions/v1/bailian-tts?region=CN|INTL`，单条 `{"action":"synthesize"}`，其余在 `bailian-tts/index.ts`；断线不可续传；Deno<2.5 用 `dialUpstream()` 两级拨号。
- `.localized()` 中文原文当 key；⚠️ 禁 `String(format:"…%@…".localized(), arg)`（零参已填 `(null)`），须 `"…%@".localized(arg)`。三语 zh-Hans/zh-HK/en；新增 lproj 改 pbxproj `knownRegions`+PBXVariantGroup，`plutil -lint`。
- 音色文案 `<lproj>/VoiceCatalog.strings` + `lprojCandidates(for:)`；繁体按香港习惯（OpenCC `s2t`+覆写，**别用 s2hk**）。

## 音色 / 标签
- 唯一数据源 `Voices/basic_voices.json`(v4)，语言无关 code+稳定 key，改后跑 `tools/gen_basic_voices.py`；筛选基于 code，搜索下沉内存。七规则：分类单选互斥／分类与收藏互斥／计数恒全量／搜索忽略分类全库匹配／只命中 4 字段／旗舰优先→名字典序／iOS 上拉追加。
- 胶囊整条热区 `contentShape(Rectangle())`+`onTapGesture`；分类列表就地替换（`panelTransition`+`withAnimation`）；刷新过渡用 `contentVisible` 驱动 opacity/offset，`.id(scrollResetID)` 只管滚回顶部。
- `.emotion` 胶囊+徽章／`.richLanguage` 虚线 pill／`.interrupt` 灰徽章；中断 API 不支持 → `toTTSAPIString()` 丢弃，生成走 `toTTSSegments()` 分段 + `AudioConcatenator.merge()`。
- ⚠️ iOS 分类筛选**只在当前进程内保留**：`VoiceLibraryFilterStore`（定义在 `View/iOS/App/IOSUIState.swift` 内的纯内存单例，定义在已有文件里避免改 pbxproj）；切 tab／跳转／View 重建不丢，**重启回「全部音色」**。禁再读写 `AppState.voiceLibrary*`（那 4 个属性带 UserDefaults 落盘，属 macOS 语义）。筛选变化用 `.onChange` 即时落 store；Sheet 的 0.25s 延迟刷新若遇 `onDisappear`，须取消并 `reload(animated:false)` 同步落地，否则「按钮是分类 A、列表还是全部音色」。

## iOS UI / 编辑器
- `ScreenMetrics` 分档 <375/375–659/**660–1023**/≥1024；两栏 `width>=740 && isWide`；3 标签+各自导航栈；二级页 `.toolbar(.hidden,for:.tabBar)` 由 `TabRouter.isTabBarHidden` 驱动；push 前 `resignFirstResponder()`；Sheet 统一 `SheetNavBar`；同层不挂两个 `.alert`；body 计算属性不查库。
- ⚠️ 打字不经过 SwiftUI：`TokenEditorStore`（`doc`/`marks` 非 @Published）；accessory 只在 `isDark` 翻转重建；overlay 字段加相等判断才重绘。三类标记各占 1 个 U+FFFC；`TokenDocument.adjust` 只一条规则（占位符落替换区则标记跟着没）；空作用域回收判据「非空→空」翻转。
- 底部条不压 accessory：`onKeyboardTopChanged` 报 min(键盘, accessory) → `keyboardSeam`；accessory 高度 SwiftUI 上报+Combine 写 `contentHeight`，容器 didSet 自改 frame、`safeAreaInsets=.zero`。

## 播放器 / 订阅隔离（关键）
- ⚠️ 播放器**按 target 拆两份同名 `AudioPreviewPlayer`**（公开 API 逐字对齐）：macOS `Shared/Services/AudioPreviewPlayer.swift` 只挂 Emora（逻辑原样），iOS `View/iOS/Services/AudioPreviewPlayer+iOS.swift` 只挂 iOSEmora。`typecheck.sh` 的 `MAC_ONLY` 与 `add_ios_target_files.py` 的 `REUSED` 必须排除 macOS 版，否则 invalid redeclaration。引擎仍 AVAudioPlayer + `enableRate`（换 AVPlayer 无效已回退）。
- iOS 版：AVAudioSession `.playback` + `iOSEmora-Info.plist` 的 `UIBackgroundModes=[audio]`（⚠️ `INFOPLIST_KEY_UIBackgroundModes` 对数组键无效、产物里没这个键，必须用 `INFOPLIST_FILE` 模板 + `plutil -extract` 验产物）；`NowPlayingStore.attach` 起播前调 `setNowPlayingMetadata`（title=shownName / artist=音色 / 封面=`VoiceAvatar.gradient(seed:)`+末字重绘）；远程命令 play/pause/进度/±15s；锁屏进度每秒同步。⚠️ 封面 `makeArtwork` 必须全幅不透明渐变（`format.opaque = true`、禁 `addClip` 自绘圆角）：透明角在锁屏被合成成白色楔形，圆角交系统裁。
- ⚠️ **iOS 播放/切倍速 CPU 暴涨根因 = SwiftUI 订阅拓扑**（非音频引擎）。`PlaybackStatus`（`AudioFlagStore.swift`）只订阅 `$playingKey` 等单属性 publisher；大视图订阅它或 `let player` 非观察。高频显示只许 6 个小 View 各自 `@ObservedObject`：`RowProgressTrack`/`MiniPlayerView`/`ModalAudioPlayer`/`ElapsedTimeLabel`/`RemainingTimeLabel`/`WaveformScrubber`。新增视图禁 `@StateObject player`；`ProjectsView.row(_:)` 禁把 progress 传给所有行。
- `StaticWaveformBars` 静态假数据+`.equatable()`；用 `voice.audio` 找 Bundle 资源（非 `voice.key`）；`playingKey` 存 identifier，`isPlaying(url:)` 对自定义 id 恒 false，统一 `playingKey == identifier`，跨 key 用 `reidentify(_:)`。⚠️ 并发闭包「外层 `guard let self` + `Task @MainActor`」。
- iOS `PlayerDetailView.transportRow` 与 macOS `PlayerTransportView` 同构：`gobackward.15 / .5` → 播放 → `goforward.5 / .15`，全走 `player.skip(by: ±15/±5)`；不再有「跳到开头/结尾」两端按钮，「从头播放」只在下方工具行；热区统一 44pt、图标 32/24（macOS 34/24），四个按钮都带 `.localized()` 的 accessibilityLabel。⚠️ 步长**直接写字面量、别抽 View 私有常量**：SF Symbol 名已自带 5/15，抽常量只是把重复搬位置且易与图标不同步；锁屏远程命令的 15 在 `AudioPreviewPlayer+iOS.swift` 另有三处硬编码，真要统一须上移到 player 层共用。

## iOS 历史记录 / 列表（v2）
- 独立 `HistoryListViewModel` 一次全量 `fetchAllAudios()` 默认 50/批；`Shared/HistoryViewModel` 属 macOS 保持原样。
- ⚠️ 收藏与软删绝不入库：`AudioFlagStore`（UserDefaults JSON，30 天），软删只打标，`purgeExpired()` 交 `ProjectService.deleteAudio`；撤销=清标记+`vm.load()`。
- 播放跨页保留：`PlayerDetailView` 不 `onDisappear{stop()}`；一律 `identifier=item.fileName` 经 `NowPlayingStore.toggle/start`。底部浮层互斥链（撤销 Toast > 后台接收条 > mini player）。删除统一「移入最近删除」，撤销后 `uiState.requestHistoryReload()` → `vm.load()`。
- ⚠️ `MiniPlayerView` 全局浮层品牌渐变底+白字（**别退回白底**），`static let height = 56`；`ProjectsView` 按 `miniPlayerVisible` 在 List 末尾插透明占位 Section（height+28）。⚠️ 卡片底部进度条只 `scaleEffect(x:,anchor:.leading)`，**绝不自加 `.clipShape`**。
- 上拉追加先写本地 `page` 再 `syncToVM()`；项目增删磁盘 IO 必须在动画事务外（`stageDuplicatedFile` nonisolated + `finishDuplicate`）。

## 积分 / 生成弹窗
- 积分全链路 Double(≤2位)：`CreditPrecision.normalize`，计费 `字符数/100*rate`（普通2/复刻5），`TextSplitter.calculateCharCount`（CJK 算2），云端 `numeric(10,2)`。
- `GenerationDialog` 完成态 `displayName = defaultAudioName(from: vm.plainText)`；`commitName()` 清空必须写 `displayName: nil` 才回退时间戳；`hasResult = generatedAudioURL != nil && !isGenerating`；macOS 只 `Views/GenerationOverlay.swift` 订阅 VM。
