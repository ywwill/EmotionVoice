# EmotionVoice 长期约定（只留「禁令 / 根因 / 入口」；实现细节见 `.workbuddy/memory/YYYY-MM-DD.md`）

## 工程 / 构建
- target `Emora`(macOS)/`iOSEmora`(iOS 18.6)；SPM: SQLite.swift / supabase-swift / keychain-swift。iOS 独有 `View/iOS/`；复用 macOS 文件**原地加入 iOS target**（不复制），`#if canImport(AppKit)` 隔离。
- 新增 iOS .swift 要手工改 pbxproj 4 处（FileRef/BuildFile/组 children/Sources，ID `7B3A...`）。⚠️ **优先把新类型塞进已有文件，零 pbxproj 改动**。
- SQLite **永不迁移**：改 `createTables()` 就 bump `currentSchemaVersion`，不符 DROP 重建。
- 构建 `bash tools/ios_build.sh`（`mac` 回归双 target）；类型检查 `bash tools/ios_typecheck/typecheck.sh`（`Shims.swift` 替身，真实类加方法须同步加桩）；workaround `IDEPackageSupportDisableManifestSandbox`／`-disable-sandbox`／`ONLY_ACTIVE_ARCH=YES`。
- ⚠️ 四配置默认 `SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor`（Swift 5.0）：后台纯计算须显式 `nonisolated`（**私有 helper 一起加**），静态非 Sendable 用 `nonisolated(unsafe)`。Swift 5 违规仅 warning，**验证须 grep 构建日志**。
- macOS 首屏 `.defaultSize(visibleFrame)` + `viewDidMoveToWindow()` 同步配置，禁 `DispatchQueue.main.async` 延迟 setFrame。

## TTS / 本地化
- 无密钥 `wss://<ref>.supabase.co/functions/v1/bailian-tts?region=CN|INTL`，单条 `{"action":"synthesize"}`；断线不可续传；Deno<2.5 用 `dialUpstream()`。
- `.localized()` 中文原文当 key；⚠️ 禁 `String(format:"…%@…".localized(), arg)`，须 `"…%@".localized(arg)`。
- 三语 zh-Hans/zh-HK/en；⚠️ 改中文 key 须**三份 strings + macOS/iOS 两端引用一起改**。仿音色文案在 `<lproj>/VoiceCatalog.strings`；繁体 OpenCC `s2t`+覆写，**别用 s2hk**。

## 音色 / 标签
- 唯一数据源 `Voices/basic_voices.json`(v4)，改后跑 `tools/gen_basic_voices.py`；七条筛选规则见日志。
- 胶囊整条热区 `contentShape(Rectangle())`；刷新过渡用 `contentVisible`，`.id(scrollResetID)` 只管滚回顶部。
- 中断 API 不支持 → `toTTSAPIString()` 丢弃，生成走 `toTTSSegments()` + `AudioConcatenator.merge()`。
- ⚠️ iOS 分类筛选**只在进程内保留**（`VoiceLibraryFilterStore` 纯内存单例）；禁读写 `AppState.voiceLibrary*`（属 macOS 语义）。
- ⚠️ `VoicesLibraryView`/`VoicePickerSheet` 的 `apply` **取消 ≠ 丢数据**：取消时也必须 `commit(fresh,total)`（只跳过动画），否则留下 `didLoad=true + voices=[]` 永久空态；另配 `onAppear` 自愈。

## iOS UI / 编辑器
- `ScreenMetrics` 分档 <375/375–659/**660–1023**/≥1024；两栏 `width>=740 && isWide`；3 标签+各自导航栈；二级页隐藏 tabBar 由 `TabRouter.isTabBarHidden` 驱动；Sheet 统一 `SheetNavBar`；同层不挂两个 `.alert`。
- ⚠️ **iPad 适配**：`isPadClass = width>=740 && height>=700`（隔开 Duo 横屏 669 与 iPad mini 横屏 744；别用 `sizeClass==.regular`，分屏也是 regular）。两栏编辑卡高度**必须由 GeometryReader 实测** `geo.height-20`，`editorMinHeight` 只兜底、**禁再夹 520 上限**；`wideLayout` 只加一层 `.padding(.horizontal,pageMargin)`，`pagePadding()` 与子视图内边距二选一，叠了会变 48pt。
- ⚠️ **iPadOS 18 TabView 的标签栏在顶部**（胶囊居中、toolbar 分列两侧），底部无 tabBar：浮层用 `metrics.tabBarClearance`（iPad 18 / iPhone 58），禁硬写 58；顶部更新横幅让位 +8pt。
- ⚠️ **参数面板单一数据源**：`StudioParamSheet.swift` 里 `StudioParamContent` = 完整参数正文（音色/音频控制/采样率/语音指令），`StudioParamSheet` 只包 `SheetNavBar`。iPad 侧栏直接铺 `StudioParamContent`（`sampleRateColumns: 2`，高度**必须**钉 `editorHeight`，否则内层 ScrollView 撑爆两栏）；iPhone 仍走「摘要条 → Sheet」；折叠屏横屏（非 `isPadClass`）保留 `voiceRow+paramsSummary`。侧栏宽 360。改参数控件只改 Content 一处。
- ⚠️ 打字不经过 SwiftUI：`TokenEditorStore`（`doc`/`marks` 非 @Published）；accessory 只在 `isDark` 翻转重建；overlay 字段加相等判断才重绘。三类标记各占 1 个 U+FFFC。
- 底部条不压 accessory：`onKeyboardTopChanged` 报 min(键盘, accessory) → `keyboardSeam`；容器 didSet 自改 frame、`safeAreaInsets=.zero`。

## 播放器 / 订阅隔离（关键）
- ⚠️ 播放器**按 target 拆两份同名 `AudioPreviewPlayer`**（API 逐字对齐）：macOS 版只挂 Emora、iOS 版只挂 iOSEmora；`typecheck.sh` 的 `MAC_ONLY` 与 `add_ios_target_files.py` 的 `REUSED` 必须排除 macOS 版。
- iOS：AVAudioSession `.playback` + `iOSEmora-Info.plist` 的 `UIBackgroundModes=[audio]`（⚠️ `INFOPLIST_KEY_UIBackgroundModes` 对数组键无效，须 `INFOPLIST_FILE` 模板 + `plutil -extract` 验产物）。⚠️ 封面 `makeArtwork` 必须全幅不透明渐变（`opaque = true`、禁 `addClip`）。
- ⚠️ **iOS 播放/切倍速 CPU 暴涨根因 = SwiftUI 订阅拓扑**：`PlaybackStatus` 只订阅 `$playingKey` 等单属性 publisher；高频显示只许 6 个小 View 各自 `@ObservedObject`（`RowProgressTrack`/`MiniPlayerView`/`ModalAudioPlayer`/`ElapsedTimeLabel`/`RemainingTimeLabel`/`WaveformScrubber`）。禁 `@StateObject player`；`ProjectsView.row(_:)` 禁把 progress 传给所有行。
- `playingKey` 存 identifier，跨 key 用 `reidentify(_:)`；⚠️ 并发闭包「外层 `guard let self` + `Task @MainActor`」。
- iOS `transportRow` 与 macOS `PlayerTransportView` 同构：±15s/±5s 走 `player.skip(by:)`；「从头播放」只在下方工具行。⚠️ 步长写字面量别抽常量。

## iOS 历史记录 / 列表（v2）
- `HistoryListViewModel` 一次全量 `fetchAllAudios()` 50/批；`Shared/HistoryViewModel` 属 macOS 保持原样。
- ⚠️ 收藏与软删绝不入库：`AudioFlagStore`（UserDefaults JSON，30 天），软删只打标，`purgeExpired()` 交 `ProjectService.deleteAudio`。
- 播放跨页保留（`PlayerDetailView` 不 `onDisappear{stop()}`）；`identifier=item.fileName` 经 `NowPlayingStore`。浮层互斥链：撤销 Toast > 后台接收条 > mini player。
- ⚠️ `MiniPlayerView` 品牌渐变底+白字（**别退回白底**），`height = 56`；`ProjectsView` 按 `miniPlayerVisible` 在 List 末尾插透明占位 Section。⚠️ 卡片进度条只 `scaleEffect(x:,anchor:.leading)`，**绝不自加 `.clipShape`**。
- ⚠️ `.plain` List 必须清零系统留白（`.listSectionSpacing(0)`+`defaultMinListHeaderHeight=0`+`.contentMargins(.top,0)`）；垂直节奏只由 chips 底 10pt + 组头 顶 13/底 7 决定，别用负 `listRowInsets`。
- 时间分组**按自然日**（今天/昨天/其余每日一组，组头 `yyyy.MM.dd`，POSIX+公历+本地时区）。

## 积分 / 生成弹窗
- 积分全链路 Double(≤2位)：`CreditPrecision.normalize`，计费 `字符数/100*rate`（普通2/复刻5），CJK 算 2 字符，云端 `numeric(10,2)`。
- `GenerationDialog` 完成态 `displayName = defaultAudioName(...)`；`commitName()` 清空须写 `displayName: nil`；`hasResult = generatedAudioURL != nil && !isGenerating`。
- ⚠️ `PackageCard` 副标题**禁 `.lineLimit(1)`**（英文译文被截）。

## 创作参数持久化（两端共用）
- `StudioParamValues`/`StudioParamStore` 定义在 **`Shared/ViewModels/VoiceStudioViewModel.swift`**（零 pbxproj 改动）。键 `studioParam.*`；两端 `onAppear` → `restoreIfNeeded`（进程内一次）、4 个 `.onChange` → `save`。
- ⚠️ **禁把 `AppState.defaultFormat`/`defaultSampleRate` 当存储**；⚠️ **「重置」两端都只调 `reset(on: vm)`，禁传 `defaults`**（否则重置回 WAV）——重置 = 出厂 `.factory`（mp3/22050/1.0x/100%）。
- 默认值一律读 `Constants`/`.factory`；`defaultFormat` 已改 `mp3`，全链路（VM/`.factory`/`BailianTTSService`/云端 `bailian-tts/index.ts`）须同步。「默认 mp3」**不覆盖已有存档**；`VoiceStudioView.onAppear` 旧的「从设置页覆盖参数」已删，**别加回来**。

## 商店页 / ASO（iOS 与 Mac 两套独立索引）
- **Mac v4**：`商店页文案-多语言版本.md` + `gen_previews.py` + `mac-2880x1800/{zh,en}`，深色 16:10。
- **iOS**：元数据 `iOS商店页元数据-6语言.md` + `ios-store-copy/{ios-copy.json,validate.py}`；预览图 `gen_ios_previews.py` + `ios-1320x2868/<locale>/`，分镜 `iOS预览图-{中文,英文,繁体}版分镜.md`。
- 字段：名称 30 / 副标题 30 / 关键词 **100 字符含逗号、逗号后不加空格**（项目既定，不按字节；另备 97 字节安全版）；名称副标题已有词不进关键词。四英文区**名称副标题共用、关键词四套独立**（共享 9 词核心 + 地区变体），**别改回零重复方案**。
- ⚠️ iOS 端**没有声音复刻/克隆 UI**，相关词禁进元数据与图上字幕。
- 尺寸（2026-11-06 核官方）：6.9" 取最高档 `1320×2868`（也接受 1260×2736/1290×2796），1–10 张、**禁 alpha**；⚠️ 支持 iPadOS 必出 iPad 13" `2064×2752`（**未做**）。
- 版式 v2.2 Aurora Pop：**无品牌行/序号**、H1 106px `top:36`、设备 1033×2240 `top:538`、dots `bottom:40`；Sheet `top:52px`+`zoom:1.22`（03 展开语言后 1.08）；灵动岛用界面自带。
- ⚠️ **字幕禁写具体能力数量**：02 不写 `599`（界面计数也去掉，收藏数可留）；03 不写「24 种语言」。`Constants.nlLanguages` 24 项只是**语音指令的可选目标语**，非产品支持语言数。
- 界面来源：`emotionvoice-ios-design.html`（01/03/04）+ `history-redesign.html` 的 `shot-favorite`(05)/`shot-default`(06) + 02 真机图。⚠️ 真机音色库**没有独立语种筛选行**；03 必须全量重建 24 chip（`slice(5)` 追加会重复「东北话」）；01 用 `.asc-fill` 撑满 + 7 段/4 色脚本，⚠️ `space-between` 下须 `.badge{top:0}` 且隐藏 `.sfx .x`。
- ⚠️ 流程「HTML 确认构图 → 真机图覆盖 `raw/<locale>/` → **`--html-only --export`**」，**必须带 `--html-only`**，否则会重新提取并覆盖真机图。**02 是真机、其余 5 张仍是设计稿样张，不可直接提审**；zh-Hant/en-US 的 02 也是样张；en-GB/AU/CA 复用 en-US 一套图。
- 多本地化：`LOCALES`/`paths(locale)`/`PAGE_OVERRIDES`/`COPY`/`--locale`。英文靠 `EN_DICT`（优先取 App `en.lproj`）+`EN_RULES`；⚠️ 数字与单位是**分开的文本节点**（「条音频」「条本月」须单列）；03 第一枚 chip 必须 `ALL[0]` 覆盖。
- **繁中 v1**：⚠️ 界面文案**不能用纯 s2t**：`HANT_DICT` 运行时解析 App `zh-HK.lproj` 两份 strings（設定/專案/匯出/檔案/取樣率/搜尋/載入/預設），叠 `HANT_OVERRIDE`（样张文案），未命中走 OpenCC 单字兜底，`HANT_CHAR_FIX` 把「爲/衆/裏/啓/臺」改回「為/眾/裡/啟/台」；界面须 `--font:"PingFang TC"`（默认 PingFang SC 会让繁体走简体字形）。Chrome DOM dump 校验简体残留 = 0。
