# EmotionVoice 项目长期约定

> 精简索引；完整踩坑过程与数值推导见 `.workbuddy/memory/YYYY-MM-DD.md` 日志。

## 工程
Swift + SwiftUI，两 target `Emora`(macOS) / `iOSEmora`(iOS 18.6)。SPM：SQLite.swift / supabase-swift / keychain-swift；Edge Functions 在 `supabase/functions/`。
- iOS 独有 `View/iOS/`；复用 macOS 文件原地加进 iOS target（不复制），`#if canImport(AppKit)` 隔离；iOS `import SwiftUI` 不导出 Combine → `@Published` 需显式 `import Combine`。
- pbxproj：`tools/add_ios_target_files.py` 幂等维护 REUSED/Frameworks/Resources；⚠️ `IOS_DIR` 指向不存在的顶层 `iOS/` → 新增 iOS .swift 必须手工 4 步（FileRef + BuildFile + 叶子 group children + iOSEmora Sources），新 ID 用 `7B3A...` 序列。⚠️ PBXBuildFile ID ≠ XCSwiftPackageProductDependency ID（写错 Xcode 崩）。
- DB SQLite（Documents/emotionvoice.sqlite3）**永不迁移**：改 `createTables()` 就 bump `currentSchemaVersion`，不符 DROP 重建。

## TTS / 本地化
App 无密钥。`wss://<ref>.supabase.co/functions/v1/bailian-tts?region=CN|INTL`，客户端一条 `{"action":"synthesize",...}`，run-task/切段/continue/finish 在 `bailian-tts/index.ts`；部署 `supabase/deploy.sh`。⚠️ 断线无法重连续传，`receive()` 失败上抛；Deno(<2.5) 不支持 `new WebSocket(url,{headers})` → `dialUpstream()` 两级拨号（原生 → `npm:ws@8`）；`upgradeWebSocket(req,{idleTimeout:0})` 后 `EdgeRuntime.waitUntil(closed)`。
- `.localized()` 中文原文当 key，找不到原样返回；⚠️ 禁止 `String(format: "…%@…".localized(), arg)`（零参 `%@` 已填 `(null)`）。三语 zh-Hans/zh-HK/en 跟随系统；新增 lproj 改 pbxproj `knownRegions`+PBXVariantGroup；`plutil -lint`；手写 `.strings` 的 `\n` 字面两字符。
- 音色文案 `<lproj>/VoiceCatalog.strings`（音色语种 ≠ 界面语言），`VoiceCatalog.string` 用 `lprojCandidates(for:)`（繁体 `["zh-HK","zh-Hant","zh-Hans"]`）；繁体按香港习惯（匯出/檔案/快取/目前/取樣率/位元率/增值），OpenCC `s2t` + 香港覆写，**别用 s2hk**。

## 音色目录 / 筛选
- 唯一数据源 `Voices/basic_voices.json`(v4)：语言无关 code + 稳定 key，文案外置 strings；筛选基于 code 列，搜索下沉内存；改 JSON 跑 `python3 tools/gen_basic_voices.py`；voices 表零文案列。
- 七规则：① 分类单选互斥 ② 分类与收藏互斥 ③ 每行计数恒为全量 ④ 搜索忽略当前分类、全库匹配 ⑤ 只命中 4 字段 ⑥ 排序「旗舰优先→名字典序」 ⑦ iOS 上拉追加替代 macOS 分页。
- ⚠️ `VoicesLibraryView`/`VoicePickerSheet` 筛选控件一致：整条胶囊全热区（`contentShape(Rectangle())`+`onTapGesture`），选完分类不出现 ×；分类列表就地替换 → `panelTransition`+`withAnimation` 包 `categoryPresented`，else 分支 VStack 挂同一 transition，`CategoryFilterSheet` 14pt 上浮淡入（`appeared` onDisappear 复位）。
- ⚠️ 列表刷新用可动画属性：`.id(scrollResetID)` 只管滚动复位，过渡靠 `contentVisible` 驱动 `opacity`+`offset(y:12)`；分类 Sheet 点行即收起延迟 ~0.25s（`onCommit(dismissing:)`），「重置」立即。

## 标签体系
`.emotion`（语气：胶囊+徽章）/`.richLanguage`（拟声：虚线 pill）/`.interrupt`（灰徽章，tag=`break`）。中断 API 不支持 → `toTTSAPIString()` 丢弃；生成走 `Array.toTTSSegments()` 分段合成后 `AudioConcatenator.merge()`。macOS 语气胶囊 v13：同色胶囊（fill 13%/内描边 42%/圆角 9/8×6）+ 徽章压左上角、拟声 pill 嵌内，顺序 胶囊→徽章→`super.draw`，`drawsBackground=false`、`textContainerInset.height=28`、`lineSpacing=28`；marker cell 5×1，`boundingRect` 只有 x/width 可信，同行判据 `lineRect.minY`。

## iOS UI
- `ScreenMetrics` 分档（<375 / 375–659 / **660–1023** / ≥1024），全局一次 GeometryReader（`ScreenMetricsReader`）；⚠️ 660 为 iPhone Duo 669pt，阈值 700 掉 regular。
- ⚠️ 两栏 `width>=740 && isWide`；`contentMaxWidth` 两栏下 nil；`editorMinHeight` 宽屏 `max(260, min(height-190, 520))`。键盘弹出不能直接 push：`TabRouter.push` append 前 `resignFirstResponder()`，`StudioView.onDisappear(finishEditing)`。
- 3 标签 + 各自导航栈；购买 Sheet 挂 `RootTabView`。⚠️ 二级界面隐藏 TabBar 用 `TabRouter.isTabBarHidden` 驱动 `.toolbar(.hidden/.visible, for:.tabBar)`+`.animation(...value:)`，push 的 append 包 `withAnimation`。
- ⚠️ 编辑器撑满剩余高度用 GeometryReader 显式给高；body 计算属性不许查库（`VoiceService.voice(forKey:)` NSCache）；同层不挂两个 `.alert`；Sheet 统一 `SheetNavBar`。

## iOS 编辑器（TokenTextEditor / TokenDocument / TokenCapsuleOverlay）
- ⚠️ 打字不经过 SwiftUI：`TokenEditorStore`（`doc`/`marks` 非 @Published，只有 `charCount`/`hasContent` 0.25s 合并 + `contentRevision`）；accessory 只在 `isDark` 翻转时重建；overlay 字段加相等判断才重绘。
- ⚠️ 三类标记各占 1 个 U+FFFC：语气/中断 `toneSpacing=14pt` 空白（附件高 12），拟声 `pillWidth+2×pillSpacing`；`capsulePadX=6` 由这段宽度支付。`resolveSeams`：`cutToneSeam`（撑到 `capsuleSeamGap=6`，地板 `capsuleMinPad=3`）、`cutPillSeam`（胶囊退到 pill 左沿 −`pillSeamGap=3`），同标记多片段不参与收缝。
- `TokenDocument.adjust` 一条规则：占位符落在替换区间内 → 标记跟着没（区间在前平移）；插/删占位符走 `insertPlaceholder`/`removeMark`（直接改 textStorage，手动 adjust 补 ±1），插入后光标跳到占位符之后。
- ⚠️ overlay 自绘层 `autoresizingMask=[.flexibleWidth,.flexibleHeight]`；文本变长 `syncOverlayFrame(forceLayout:)`；徽章排队（行→preferredX，恒留 `badgeSeamGap=4`），顺序 胶囊→pill→徽章，pill 不铺底高 20 居中。空作用域回收唯一判据「非空→空」翻转（`isBoundary`+`boundaryEmptiness`；`Coordinator` 持 `scopeHadText`+`pendingRemoval`，`refreshScopeStates()` 挂 `tvDidChangeContent` 最前 → 删光停手 0.35s 回收）。
- ⚠️ 底部条不压 accessory：`onKeyboardTopChanged` 报 `min(键盘框 minY, accessory 窗口框 minY)`；`StudioView` background GeometryReader 量内容底边，差值夹 0~260 得 `keyboardSeam`+`keyboardSeamGap=10`，只在 `onPreferenceChange` 算。accessory 高度 SwiftUI 上报（`background(GeometryReader)`+`AccessoryHeightKey`→Combine 写 `contentHeight`）；容器手写 frame → `didSet` 自己改 frame+`superview?.setNeedsLayout()`，`safeAreaInsets` 覆写 `.zero`，`AccessoryMetrics`(86) 三处共用。
- ⚠️ 刚点过的标签按钮 `accentSoft` 底+`accent` 实描边（`config.lastPickedTag`）；「清空」两入口；`hasContent` 门控清空。

## 生成弹窗 / 后台接收 / 播放器
- `GenerationDialog` 完成态名称框不再空着：`prepare()` 里 `displayName = Self.defaultAudioName(from: vm.plainText)`，规则与 macOS `generateDefaultAudioName()` 一致（折行→截 40→`sanitizeFileName`→取前 10；空则本地化时间戳 key `"音频_%@"`）。行内 × 一键清空（复用 `RenameDialog` 样式，非空才出现，`.animation` 只绑 `isEmpty`）。⚠️ `commitName()` 清空时写 `displayName: nil` 而不是跳过，列表才回退到时间戳文件名；时间戳兜底必须 `"…%@".localized(arg)`，不能 `String(format: "…%@…".localized(), arg)`。
- `AppState.showGenerationModal`；macOS 只有 `Views/GenerationOverlay.swift` 订阅 VM。⚠️ 完成态 `hasResult = generatedAudioURL != nil && !isGenerating`；浮层 ZStack `maxWidth/maxHeight:.infinity`；自持 Timer(0.5s)，不用 `autoconnect()`。`DataReceiveGridView` 是 Canvas 自绘（`receive(n)` 真实入口，列数 `floor((可用宽+间距)/(格宽+间距))`，高亮环画格外 `haloOutset=2`，`TailFrameKey` 只在 `followTail` 翻转时写 @State）。
- ⚠️ 用 `voice.audio` 找 Bundle 资源（不是 `voice.key`）；`playingKey` 存 identifier 不是 URL，`isPlaying(url:)` 对自定义 identifier 恒 false，跨页统一 `playingKey == identifier`，跨 key 用 `reidentify(_:)`。
- ⚠️ **iOS 详情页频谱静态假数据**：`StaticWaveformBars` 写死 `amplitudes` 常量循环铺满、零计算；参数不含 progress + `.equatable()` → 10Hz 刷新不重绘 Canvas。进度只用「已播色层裁剪宽度」+ 播放头 offset。⚠️ 别引入按 seed 计算包络（切倍速 CPU 暴涨）。`sentenceCount` @State + onAppear 缓存一次。
- ⚠️ `AudioPreviewPlayer` 保持 HEAD 原状（换 AVPlayer+timeDomain 用户验证无效已回退，**勿再改共享播放器**）；倍速 `AVAudioPlayer.enableRate`。macOS + iOS 共用同一类/单例（iOS 专用 `IOSAudioPlayer` 封装已按用户要求撤销）。
- ⚠️ **iOS 播放 / 切倍速 CPU 暴涨根因 = SwiftUI 订阅拓扑**（macOS 同一播放器不暴涨）：macOS 早做过「订阅隔离」——`View/macOS/HistoryView/AudioPlayerDetailView.swift:16-20`、`VoiceStudioView/AudioGenerationModal.swift:270-275`、`VoiceStudioView/VoiceStudioView.swift:970-976` 注释明写「宿主别用 @ObservedObject 持播放器，10Hz 进度会拖整页重算」。iOS history v2 却把订阅放在 `RootTabView`（根容器）、`ProjectsView`（列表宿主，且把 `player.progress` 传给**每一行**）、整页 `PlayerDetailView`、整个 `GenerationDialog` → 一次 `objectWillChange` 放大成「全 App 视图树 × N 行」。静态化波形 / 缓存 sentenceCount 只挡单个 Canvas；换引擎无效反证根因不在音频重采样。
- **修复（对齐 macOS）**：`PlaybackStatus`（在 `View/iOS/Views/Projects/AudioFlagStore.swift`）只订阅 `$playingKey` 等**单属性 publisher**（progress/currentTime 变化不发值）；大视图订阅它或用 `let player` 非观察。高频显示下沉到 6 个各自 `@ObservedObject player` 的小 View：`RowProgressTrack`（只有正在播放那一行挂）、`MiniPlayerView`、`ModalAudioPlayer`、`ElapsedTimeLabel`、`RemainingTimeLabel`、`WaveformScrubber`。⚠️ 新增视图禁止 `@StateObject player = AudioPreviewPlayer.shared`；`ProjectsView.row(_:)` 禁止把 progress 传给所有行。
- ⚠️ 并发闭包用「外层 `guard let self`+`Task @MainActor`」，别 `[weak self]`+`self?.` 进 Task（Swift6 `SendableClosureCaptures`）。

## iOS 列表 / 分页
- ⚠️ 上拉追加先写本地 `page` 再 `syncToVM()`（反了追加恒空），空页回退 `page=max(1,next-1)`；筛选/搜索滚回顶部用 `ScrollView.id(scrollResetID)` 自增整体重建。
- 音色 Sheet 复用 `VoicesLibraryViewModel`；筛选是 Sheet 私有 @State，不写回 `AppState.voiceLibrary*`；分类列表就地替换，不嵌第二层 `.sheet`。
- ⚠️ 搜索回车：`AuroraSearchField` `.submitLabel(.search)`+`@FocusState`，外层 `onSubmit: { commitSearch() }`（取消防抖 + 立即 `reload()`）；列表收键盘 `.scrollDismissesKeyboard(.immediately)` 挂 ScrollView 本身，不满一屏补 `simultaneousGesture(DragGesture(minimumDistance:12))`+`didResignOnDrag`。
- ⚠️ `VoicesLibraryView.body` 缩进骗人（关闭 ScrollView 的 `}` 缩进 16 空格），定层级用括号深度脚本；项目增删磁盘 IO 必须在动画事务之外，`ProjectService.stageDuplicatedFile`（`nonisolated`，`Task.detached`）+ `finishDuplicate`（主线程写库），副本插在被操作行下面，重命名用自绘 `RenameDialog`；`stageDuplicatedFile`/`Date.filenameTimestamp`/`generatedAudioDirectoryURL()`/`kGeneratedAudioSubdirectory` 都 `nonisolated`。

## 快捷键 / 积分 / 构建
- `PlaybackKeyboardShortcuts`：Carbon 热键吞事件 → 监听 `NSText.didBeginEditing/didEndEditing` → `KeyboardShortcuts.disable(all)/enable`。积分全链路 Double(≤2 位)：`CreditManager`+`CreditPrecision.normalize`（`(v*100).rounded()/100`），禁止 `Int(ceil())`；计费 `字符数/100*rate`（普通 2、复刻 5），`TextSplitter.calculateCharCount`（CJK 算 2），云端 `user_credits.credits` 必须 `numeric(10,2)`，展示 `formatCredits(_:)`。
- 真构建 `bash tools/ios_build.sh`；类型检查 `bash tools/ios_typecheck/typecheck.sh`。三 workaround：① `IDEPackageSupportDisableManifestSandbox` ② `OTHER_SWIFT_FLAGS='$(inherited) -disable-sandbox'`（必须 $(inherited)）③ `ONLY_ACTIVE_ARCH=YES`。⚠️ `tools/ios_typecheck/Shims.swift` 有 `VoiceService`/`DatabaseManager`/`ProjectService` 等替身：给真实类加新方法必须同步加桩。
- 既有问题：`CreditsService.swift` 4 条 Swift6 actor 隔离报错；`PackageCardView.swift` 未入 target 孤儿文件；第三方 `swift-issue-reporting` 挡完整 build（无关）。⚠️ `ios_build.sh mac` 会失败：`Launch Screen.storyboard` 同时挂两 target → `iOS storyboards do not support target device type "mac"`，与改动无关；只跑 iOS 验收。

## iOS 历史记录 / 播放链路（history-redesign v2）
- ⚠️ iOS 项目页用独立 `HistoryListViewModel`（`View/iOS/Views/Projects/`），`Shared/HistoryViewModel` 是 macOS 共用分页模型保持原样；新 VM 一次 `fetchAllAudios()` 全量，默认 50 条一批。
- ⚠️ 收藏与软删绝不入库：`audio_items` 无 `is_favorite`/`deleted_at`，永不迁移 → `AudioFlagStore`（UserDefaults JSON，按 audio id，30 天）。软删只打标；`purgeExpired()` 返回过期 id 交 `ProjectService.deleteAudio` 清理；撤销 = 清标记 + `vm.load()`。
- ⚠️ 播放跨页保留：`PlayerDetailView` 不再 `.onDisappear { stop() }`；列表/详情一律 `identifier=item.fileName` 起播（`NowPlayingStore.toggle/start`），判定 `playingKey == fileName`。底部浮层互斥链（`RootTabView.bottomDock`）：撤销 Toast > 后台接收浮条 > mini player；键盘弹起后两者隐藏，多选时 `uiState.hideMiniPlayer = true`；mini player 数据来自 `NowPlayingStore.currentItem/currentVoiceName`（body 不许查库）。
- 删除统一「移入最近删除」：列表左滑/多选/详情页共用 `flags.markDeleted`+`uiState.showUndoToast`；`RecentlyDeletedView` 从 ⋯ 菜单 push（`.recentlyDeleted`），一个 `.alert(item:)` 互斥处理清空/单条删除。⚠️ 撤销后刷新必须 `uiState.requestHistoryReload()` → `ProjectsView.onChange(historyReloadSignal) → vm.load()`。
- 详情页三按钮用 `.safeAreaInset(edge:.bottom)` 固定底栏；卡片需 `.clipShape` 才有底部圆角。
- ⚠️ `MiniPlayerView` 是全局浮层：品牌渐变底 + 白字 + 半透明白描边 + 彩色投影，**别再退回和列表行卡同款白底**（分不清）。整卡 `.contentShape` + `.onTapGesture(onExpand)`，内部播放/关闭 Button 命中优先级更高。`static let height = 56` 供列表占位复用。
- ⚠️ mini player 不参与 List 的 safe area → `ProjectsView` 必须按 `miniPlayerVisible`（`!hideMiniPlayer && activePath.isEmpty && currentItem != nil && playingKey != nil`）在 List 末尾插一个透明占位 Section，高度 `MiniPlayerView.height + 28`，否则最后一行滚到底仍被盖住。
- ⚠️ **卡片底部进度条统一模式**（`HistoryRow` / `UndoToastView` / `MiniPlayerView`）：进度条本身只写 `Rectangle.fill().frame(height:2).scaleEffect(x:...,anchor:.leading)`，**绝不加自己的 `.clipShape`**；圆角只由整卡唯一一层 `.clipShape(RoundedRectangle)` 统一裁。2pt 高的条套 16pt 连续圆角，裁剪路径会向左右溢出卡片。
