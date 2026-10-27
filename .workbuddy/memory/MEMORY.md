# EmotionVoice 项目长期约定

## 技术栈
macOS 原生 App，Swift + SwiftUI（Swift 5）。依赖 SQLite.swift、supabase-swift、keychain-swift（SPM）。
服务端 Supabase Edge Functions（Deno），代码在仓库根 `supabase/functions/`。

## TTS 链路（2026-10-18 起：客户端 → Supabase Edge Function → 阿里云百炼）
- App 内**无百炼密钥**：`RegionConfig.swift` 只剩区域判断（`edgeRegionCode` → CN/INTL），Key/Workspace/模型名都在 function secrets。
- 端点 `Services/TTSEndpoint.swift`：`wss://<ref>.supabase.co/functions/v1/bailian-tts?region=CN|INTL`，
  握手头 `Authorization`/`apikey`（publishable key）+ `x-app-secret`（`kSupabaseAppSecret` ↔ 函数 `APP_SECRET`，也可 `?secret=`）。
- 客户端只发一条消息：`{"action":"synthesize", text, voice, emotion?, rate, volume, sample_rate, format, instruction?}`；
  run-task/切段/continue-task/finish-task 全在 `supabase/functions/bailian-tts/index.ts`。
- 上游 JSON 事件（task-started/result-generated/task-finished/task-failed）与二进制音频帧**原样转发**，客户端收包逻辑与直连一致。
- ⚠️ 服务端断开后无法"重连续传"，`receive()` 失败必须直接上抛（别加重连）。
- ⚠️ Supabase 线上 Deno(<2.5) **不支持** `new WebSocket(url, { headers })`（报 `Invalid protocol value`）；
  函数用 `dialUpstream()` 两级拨号：先原生 `{headers}`，异常回退 `npm:ws@8`；`?ws=npm` 强制回退，日志打印"拨号方式"。
- `Deno.upgradeWebSocket(req,{idleTimeout:0})` 后必须 `EdgeRuntime.waitUntil(closed)`。
- 部署 `supabase/deploy.sh`（本机 CLI 无权访问该项目 + 无 Docker，需用户自己跑）。
- DB：SQLite，文件在用户 Documents `emotionvoice.sqlite3`。

## 生成弹窗与后台接收（2026-10-21：全局承载）
- 开关在 `AppState.showGenerationModal`（不放 VoiceStudioView 的 @State：关弹窗后接收继续跑；ContentView 用 `.id(renderedSection)` 会销毁重建子视图）。
- `Views/GenerationOverlay.swift` 是唯一订阅 `VoiceStudioViewModel` 的全局浮层（弹窗 + 后台接收卡片 + `.alert`），挂 ContentView 上；ContentView 本体不订阅 VM（否则 NSTextView 每次输入牵动整窗重建）。
- 后台接收卡片锚在情感面板「拟声效果」区块右下角（该 VStack `.overlay(alignment:.bottomTrailing)`）；全局浮层只留弹窗/失败 alert/完成信号。
- ⚠️ 浮层定位两坑：① `ZStack` 尺寸=子视图并集，不撑满父级 → 卡片被摆到正中，必须 `.frame(maxWidth:.infinity,maxHeight:.infinity)`；② 固定尺寸小浮层**不要用 GeometryReader**（贪婪吃满空间），用常量（`CardLayout`）。
- 计时用自持 Timer（0.5s），**不能用 `Timer.publish().autoconnect()`**（视图被 10Hz stats 重建 → 订阅断连，速率停在 0）。
- VM：`generationCompletedSignal`（自增计数，onChange 触发"完成后自动重开弹窗"）、`generationStartedAt`。
- ⚠️ **完成态判定不要用「本地 Bool + onChange」中转**（2026-10-26 起）：VM 的 `generatedAudioURL` /
  `generatedAudioDuration` / `isGenerating` 是在同一个 `MainActor.run` 里连续赋值的，因此直接用
  `hasResult = generatedAudioURL != nil && !isGenerating` 推导能在一次 view 更新里切到位；
  若改成 `@State isCompleted` 在 `onChange` 里翻（onChange 跑在 body 求值之后），就会先渲染一帧
  「已完成内容 + 未完成装饰」，下一次事务再带动画跳一次 —— 表现就是"切换时卡顿一下"。
  同理，派生展示值（时长等）直接读 VM，别在 onChange 里拷一份 @State（会晚一帧闪默认值）。

## 本地化
- `.localized()`（`Extension/String+Extension.swift`）**用中文原文当 key**，找不到原样返回；动态拼接必须用格式占位符：`"%@ · 旗舰音色".localized(name)`。
- 三语：zh-Hans / zh-HK（繁体，2026-10-21）/ en，跟随系统。新增 lproj 要改 pbxproj `knownRegions` + PBXVariantGroup。
- 音色文案在 `<lproj>/VoiceCatalog.strings`（key `voice.<stem>.name`/`.feature`，stem = key 去 `qwen-audio-3.0-tts-plus-` 前缀）。
- ⚠️ 音色语种（zh/en）≠ 界面语言：中文音色永远中文名，字形跟界面走。`VoiceCatalog.string` 用 `lprojCandidates(for:)`：繁体 `["zh-HK","zh-Hant","zh-Hans"]`，其余 `["zh-Hans"]`，靠 `AppLanguage.prefersTraditionalChinese`；别写死 `zh-Hans`。
- 繁体用香港习惯（匯出/檔案/快取/目前/取樣率/位元率/增值；台不写臺、神秘不写神祕、為不写爲）。同步可用 OpenCC `s2t` + 香港覆写（**别用 `s2hk`**：漏转 温→温、說→説）。

## 标签体系（v14 三类家族）
- `EmotionCategory`: `.emotion`（语气，胶囊+徽章）/ `.richLanguage`（拟声，虚线 pill，按情感着色，未命中走确定性色相哈希回退）/ `.interrupt`（不画胶囊，灰徽章，tag=`break`）。
- **中断标签 API 不支持**：`toTTSAPIString()` 丢弃；生成走 `Array.toTTSSegments()` 按中断标记切多请求（中断段 emotion=nil），逐段 `synthesizeStream` 后 `AudioConcatenator.merge()` 拼接（WAV 重写 header 总长，mp3 字节拼）。
- ⚠️ 段落样式取自段落首字符：attachment 不带段落样式，落在段首会塌回默认 → 必须设 `defaultParagraphStyle` + `typingAttributes`。

## EmotionTokenEditor 标签 UI（语气胶囊版 v13，已取代 10-14 下划线版）
- 语气 = 整段同色胶囊（fill 13%、1px 内描边 42%、圆角 9、内边距 8×6）+ emoji/名称徽章压左上角（10.5pt 粗体、底色=编辑器背景、仅首块）；
  拟声 = 虚线 pill（12pt、圆角 6、内边距 7×1.5、悬停正中浮 ×），嵌在胶囊内不打断语气。
- **绘制顺序铁律**：胶囊 → **徽章** → `super.draw`。徽章必须提前（super.draw 后裁剪收窄到 textContainer，容器上沿外的徽章会被裁）。配套 `tokenView.drawsBackground = false`；`textContainerInset.height = 28`、`bodyAttributes.lineSpacing = 28`。
- 语气 marker cell 是 5×1 不可见占位（`toneMarkerWidth`）：这 5pt 是相邻作用域唯一物理间距，靠 `resolveCapsuleSeams` 切出 `capsuleSeamGap = 2`。几何见 `toneCapsuleGeometries()`（绘制与命中共用）；拟声 pill 左右内缩 `soundEdgeInset = 3`。
- 悬停区 = 字形 ∪ × ∪ 徽章 ∪ 胶囊；小手光标不含胶囊（正文保持 I 型）。× 仅可编辑时绘制（悬停/选中实心，空闲 alpha 0.35）。
- 外观感知配色：`nonisolated(unsafe) var kEmotionAttachmentIdentity` + `EmotionTokenStyle.resolved(for:dark:)` 读 `effectiveAppearance` 解析暗/亮；`EmotionTokenStyle.default` 只描述几何。
- 几何陷阱：`boundingRect(forGlyphRange:)` 高度是整行高（只有 x/width 可信）；同行判据用 `lineRect.minY`；行首尾要夹进容器；空作用域补兜底胶囊。
- 离屏测试用 internal `debugToneCapsuleGeometry()`。

## 音色目录
- 唯一数据源 `EmotionVoice/EmotionVoice/Voices/basic_voices.json`（v4 schema）。**铁律：JSON 只存语言无关 code + 稳定 key，文案外置 strings**。
  字段 `idx`(旗舰 1/2、基础 3 起，DB 主键)、`key`、`tier`(premium|basic)、`lang`(zh|en)、`gender`(female|male|unknown)、`age`、`scene`、`audio`。
  scene 取值：daily|companion|reading|customer_service|social|anime|news|live_stream|classic_audiobook|sports|audiobook|radio|knowledge|comedy|business|assistant|speech。
- 筛选基于 code 列（`tier`/`lang_code`/`scene_key`/`age`/`gender_code`），禁止中文字符串 WHERE；搜索下沉内存（本地化名/特质/场景/语种，支持拼音）。
- 改 JSON 后跑 `python3 tools/gen_basic_voices.py`（幂等）。加语言只需新增 `.lproj/VoiceCatalog.strings`。
- `DatabaseManager` voices 表零文案列。
- **DB 策略：不做迁移，永久"结构版本不符就 DROP 全表重建"**（`resetDatabaseIfSchemaChanged`：改 `createTables()` 就 bump `currentSchemaVersion`，启动比对 UserDefaults，不符删 audio_items/voices/consumption_records/purchaseRecords 重建）。用户明确不需要迁移，接受清空本地数据（前提：这些表要么可再生缓存、要么有服务端兜底）。`currentFingerprintVersion` + `voiceCountKey` 只管 voices 内容刷新，重建时一并清掉。

## 快捷键（KeyboardShortcuts 包）
- `Views/HistoryView/PlaybackKeyboardShortcuts.swift`：`@MainActor` 单例 `PlaybackShortcutsController` + 7 个 `Name`（空格/←/→/⇧←/⇧→/Home/End）。
- ⚠️ 该包用 Carbon 热键（`RegisterEventHotKey`）**会吞事件**，"回调里再判断"救不回输入框。挡输入框要反向做：监听 `NSText.didBeginEditing/didEndEditing` → `KeyboardShortcuts.disable(all)`/`enable`。
- 没在播（`player.playingKey == nil`）时 disable ←→/Home/End，把方向键还给列表。
- 包回调已在主线程，但从非隔离闭包调 @MainActor 方法仍需 `MainActor.assumeIsolated`。

## 积分体系（全链路 Double，最多 2 位小数）
- 权威 `CreditManager`（`balance` 走 UserDefaults + Supabase）；`CreditsService` 是门面，`CreditService` 旧校验封装。
- 精度：一律过 `CreditPrecision.normalize`（`(v*100).rounded()/100`），比较加 1e-9 容差。**禁止 `Int(ceil())` 向上取整**。
- 计费 `字符数/100*rate`（普通 2、复刻 5），无起扣门槛；字符数用 `TextSplitter.calculateCharCount`（CJK 算 2）。
- 云端 `user_credits.credits` 必须 `numeric(10,2)`。展示统一 `formatCredits(_:)`。

## 数据接收网格（Views/DataReceiveGridView.swift）
- 用 `Canvas` 自绘（几百个 View 会拖垮布局）； `DataReceiveGridModel.receive(n)` 真实接收入口，
  `clock` 只在落地动画 + 余晖期间跑，播完自停。`rows`/`cellSize` 由调用方给。
- ⚠️ **横向铺满铁律**：列步进与行步进必须拆开 —— 列数取 `floor((可用宽+期望间距)/(格宽+期望间距))`
  （保证真实列间距 ≥ 期望值），列间距 = (可用宽 − n×格宽)/(n−1)，做到首列贴左、末列贴右；
  超宽时画布宽 = n×列步进 − 列间距。早年用 `ceil(宽度/步进)` 会让最右一列被容器切掉一角。
- ⚠️ 自动跟随的 `scrollTo` 锚点 View **必须零宽**（`.frame(width: 0)`）：占 1pt 就会让内容永远比可视区宽，
  跟随时整块内容被往左拽，左边第一格被切。
- ⚠️ 「最新一格」的高亮环画在格子**外面**（外扩 1pt + 线宽一半 0.6pt ≈ 1.6pt），所以画布四周必须预留
  `haloOutset = 2`：排列方块的可用宽度 = 可视宽 − 2×2，画布高 = 网格高 + 2×2，否则落在顶行 / 最右一列的
  最新格子上边或右边的白环会被画布裁掉。改动 `haloRingInset` 或描边 `lineWidth` 都要同步看这个值。
- 生成弹窗里挂的是 **rows=6**（2026-10-26）/ cellSize=11 / spacing=4（可用宽 498 → 33 列 ≈ 198 空槽），
  一格代表的字节数由 `prepareGrid()` 按本次文本（字数 → 时长 → 字节 → ÷ `gridTargetCells`）算出来，不写死常数。
  ⚠️ 改行数必须同步改 `gridTargetCells`（≈ 空槽数 × 0.82，即每格字节数跟着变），否则一批到底时要么铺不满要么滚太远。
- ⚠️ 网格面板（`receiveGridBox`）挂在 `header` / `footer` 之间的**公共层**，不在 `generatingContent` 里：
  生成完成后这组格子要留着当接收留痕。新一轮生成靠 `stats.receivedBytes` 掉回 0 触发 `prepareGrid()` 清盘。
- ⚠️ `onPreferenceChange(TailFrameKey)` 里**只在 `followTail` 真正翻转时才写 @State**：`tailMinX` 每帧都可能变
  （上层任何布局动画都会让它逐帧漂移），无条件写会把 GeometryReader+Canvas+ScrollView 整个 body 每帧重算一遍。
- ⚠️ 底槽绘制要攒成一条 `Path` 一次 `fill`，别逐格 fill（5 行 × 33 列 = 165 次绘制调用 × 每帧）。

## iOS 版（iOSEmora target，2026-10-27 起）
- 同工程两个 target：`Emora`(macOS) / `iOSEmora`(iOS, bundle id com.emotion.voice.ios, 部署 18.6, device family 1,2)。
- iOS **独有代码统一放仓库根 `iOS/`**（App / DesignSystem / Layout / Views/{Studio,Library,Projects,Generation,Settings}）；
  复用的 macOS 逻辑文件原地加进 iOSEmora target（不复制），靠 `#if canImport(AppKit)` / `#if os(macOS)` 做平台隔离。
- 信息架构：macOS 220pt 侧边栏 6 分区 → iOS 3 标签（创作/音色库/项目）+ 导航栈；「积分中心」并入设置页，
  设置入口 = 三个标签导航栏右上齿轮 push 进当前标签栈。桌面专属项（主题/语言/导出目录/缓存/设备标识）全部删除。
- iPhone Duo 适配 = 折叠屏展开态宽屏：`iOS/Layout/ScreenMetrics.swift` 按可视宽度分档（<375 / 375–699 / 700–1023 / ≥1024）
  派生 pageMargin、contentMaxWidth、voiceGridColumns(2/2/3/4)、metaColumns、usesTwoColumnStudio、dialogWidth=min(w-61,420)。
  全局**只用一次** GeometryReader（`ScreenMetricsReader`），向下注入 `\.screenMetrics`。
- iOS 无 `NSTextAttachmentCell`：情感标签走「纯文本 + 位置标记 + U+FFFC 占位附件 + 自绘 overlay」（`TokenCapsuleOverlay`）。
- pbxproj 用 `tools/add_ios_target_files.py` 幂等维护（新增 24 + 复用 36 = 66 sources，8 SPM product，603 resources）。
  ⚠️ PBXBuildFile ID ≠ XCSwiftPackageProductDependency ID（相邻但不同），写错 Xcode 会在算依赖图时崩
  `-[PBXBuildFile productName]`；脚本已改为从 Emora 的 Frameworks 阶段动态反查 productRef。
- ⚠️ iOS 侧 `import SwiftUI` **不隐式导出 Combine**：用 `@Published`/`ObservableObject` 的文件必须显式 `import Combine`。

## 构建与验证
- 真构建：`bash tools/ios_build.sh`（+ `mac` 参数顺带回归 macOS）—— 三个 workaround 都是受限 shell 的沙箱问题，
  Xcode GUI 直接 Build 不需要：① `IDEPackageSupportDisableManifestSandbox`（SwiftPM manifest 沙箱，脚本写入并在退出时恢复）
  ② `OTHER_SWIFT_FLAGS='$(inherited) -disable-sandbox'`（宏插件服务；**必须 $(inherited)**，否则覆盖 SPM 包的
  `-package-name`，supabase-swift 报 ambiguous implicit access level）③ `ONLY_ACTIVE_ARCH=YES`。
  当前状态：iOSEmora 与 Emora 均 BUILD SUCCEEDED，iOS 代码 0 error / 0 warning。
- 快速类型检查（不依赖 SPM 真包）：`bash tools/ios_typecheck/typecheck.sh`（`swiftc -typecheck -disable-sandbox`，
  SPM 服务用 `Shims.swift` 同签名替身）。
- macOS 侧的同类命令：`swiftc -typecheck -disable-sandbox -swift-version 5 -target arm64-apple-macos14.0 -sdk $(xcrun --sdk macosx --show-sdk-path) -I <DerivedData>/Build/Products/Debug @filelist`。
- 改代码前先对 HEAD 跑一次同命令拿基线。
- 已知既有问题：`CreditsService.swift` 4 条 Swift6 actor 隔离报错；`PackageCardView.swift` 是未入 target 的孤儿文件（`CreditsPackage` 不存在）。
