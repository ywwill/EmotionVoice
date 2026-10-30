# EmotionVoice 项目长期约定

## 技术栈
Swift + SwiftUI（Swift 5），单工程两个 target：`Emora`(macOS) / `iOSEmora`(iOS, com.emotion.voice.ios, 18.6)。
依赖 SQLite.swift、supabase-swift、keychain-swift（SPM）。服务端 Supabase Edge Functions（Deno），代码在 `supabase/functions/`。
- **iOS 独有代码放 `EmotionVoice/iOSEmora/`**（App / DesignSystem / Layout / Views/{Studio,Library,Projects,Generation,Settings}）；复用的 macOS 文件原地加进 iOS target（不复制），靠 `#if canImport(AppKit)` 隔离。
- iOS 侧 `import SwiftUI` **不隐式导出 Combine**：用 `@Published`/`ObservableObject` 必须显式 `import Combine`。
- pbxproj 用 `tools/add_ios_target_files.py` 幂等维护。⚠️ PBXBuildFile ID ≠ XCSwiftPackageProductDependency ID，写错 Xcode 依赖图崩溃 `-[PBXBuildFile productName]`。

## TTS 链路（客户端 → Supabase Edge Function → 阿里云百炼）
- App 内**无百炼密钥**：`RegionConfig.swift` 只剩区域判断，Key/Workspace/模型在 function secrets。
- 端点 `Services/TTSEndpoint.swift`：`wss://<ref>.supabase.co/functions/v1/bailian-tts?region=CN|INTL`，握手头 Authorization/apikey + `x-app-secret`。
- 客户端只发一条 `{"action":"synthesize", text, voice, emotion?, rate, volume, sample_rate, format, instruction?}`；run-task/切段/continue/finish 全在 `supabase/functions/bailian-tts/index.ts`。上游 JSON 事件与二进制音频帧**原样转发**。
- ⚠️ 服务端断开后无法重连续传，`receive()` 失败必须直接上抛。
- ⚠️ Supabase 线上 Deno(<2.5) 不支持 `new WebSocket(url,{headers})`（`Invalid protocol value`）；`dialUpstream()` 两级拨号：原生 → 回退 `npm:ws@8`。
- `Deno.upgradeWebSocket(req,{idleTimeout:0})` 后必须 `EdgeRuntime.waitUntil(closed)`。部署 `supabase/deploy.sh`（需用户自己跑）。
- DB：SQLite，文件在用户 Documents `emotionvoice.sqlite3`。
- **DB 策略：永远不做迁移** —— `resetDatabaseIfSchemaChanged`：改 `createTables()` 就 bump `currentSchemaVersion`，启动比对 UserDefaults，不符就 DROP audio_items/voices/consumption_records/purchaseRecords 重建。用户接受清空本地数据。

## 本地化
- `.localized()`（`Extension/String+Extension.swift`）**用中文原文当 key**，找不到原样返回；动态拼接用格式占位符：`"%@ · 旗舰音色".localized(name)`。
- 三语 zh-Hans / zh-HK（繁体）/ en，跟随系统。新增 lproj 要改 pbxproj `knownRegions` + PBXVariantGroup。
- 音色文案在 `<lproj>/VoiceCatalog.strings`（`voice.<stem>.name`/`.feature`）。⚠️ 音色语种 ≠ 界面语言：中文音色永远中文名。`VoiceCatalog.string` 用 `lprojCandidates(for:)`（繁体 `["zh-HK","zh-Hant","zh-Hans"]`），别写死 `zh-Hans`。
- 繁体用香港习惯（匯出/檔案/快取/目前/取樣率/位元率/增值）。同步用 OpenCC `s2t` + 香港覆写（**别用 `s2hk`**）。

## 标签体系（EmotionCategory 三类家族）
- `.emotion`（语气：胶囊+徽章）/ `.richLanguage`（拟声：虚线 pill，情感着色，未命中走确定性色相哈希）/ `.interrupt`（不画胶囊，灰徽章，tag=`break`）。
- **中断 API 不支持**：`toTTSAPIString()` 丢弃；生成走 `Array.toTTSSegments()` 切多请求（中断段 emotion=nil），逐段 `synthesizeStream` 后 `AudioConcatenator.merge()`（WAV 重写 header，mp3 字节拼）。
- macOS UI（语气胶囊版 v13）：语气 = 整段同色胶囊（fill 13%、内描边 42%、圆角 9、内边距 8×6）+ emoji/名称徽章压左上角；拟声 pill 嵌在胶囊内（12pt、圆角 6、内边距 7×1.5）。
  - **绘制顺序铁律**：胶囊 → **徽章** → `super.draw`（super.draw 后裁剪到 textContainer，容器上沿外的徽章会被裁）。`tokenView.drawsBackground = false`、`textContainerInset.height = 28`、`lineSpacing = 28`。
  - 语气 marker cell 是 5×1 不可见占位，相邻作用域靠 `resolveCapsuleSeams` 切 2pt 缝。几何集中 `toneCapsuleGeometries()`（绘制与命中共用）。
  - 悬停区 = 字形 ∪ × ∪ 徽章 ∪ 胶囊；× 仅可编辑时绘制。配色：`kEmotionAttachmentIdentity` + `EmotionTokenStyle.resolved(for:dark:)`。
  - 陷阱：`boundingRect(forGlyphRange:)` 高度是整行高（只有 x/width 可信）；同行判据用 `lineRect.minY`；空作用域补兜底胶囊。离屏测试 `debugToneCapsuleGeometry()`。

## 音色目录
- 唯一数据源 `EmotionVoice/EmotionVoice/Voices/basic_voices.json`（v4）。**铁律：JSON 只存语言无关 code + 稳定 key，文案外置 strings**。
  字段 `idx`(旗舰 1/2、基础 3 起)、`key`、`tier`、`lang`、`gender`、`age`、`scene`、`audio`。
- 筛选基于 code 列（禁止中文字符串 WHERE）；搜索下沉内存（本地化名/特质/场景/语种，支持拼音）。
- 改 JSON 后跑 `python3 tools/gen_basic_voices.py`（幂等）。`DatabaseManager` voices 表零文案列。

## 生成弹窗 / 后台接收 / 数据接收网格
- 开关在 `AppState.showGenerationModal`（不能放子视图 @State：关弹窗后接收仍要继续）。
- macOS：`Views/GenerationOverlay.swift` 是唯一订阅 `VoiceStudioViewModel` 的全局浮层（ContentView 本体不订阅 VM，否则 NSTextView 每次输入牵动整窗重建）。后台卡片锚在情感面板「拟声效果」区块右下角。
- ⚠️ 完成态**不要用「本地 Bool + onChange」中转**（onChange 跑在 body 求值之后 → 多渲染一帧+动画跳一次 = 卡顿）。直接 `hasResult = generatedAudioURL != nil && !isGenerating` 推导；派生展示值也直接读 VM。
- ⚠️ 浮层定位：`ZStack` 不撑满父级 → 必须 `.frame(maxWidth:.infinity,maxHeight:.infinity)`；固定尺寸小浮层**不要用 GeometryReader**。
- 计时用自持 Timer（0.5s），**不能用 `Timer.publish().autoconnect()`**（视图被 10Hz stats 重建会断连）。
- 网格 `Views/DataReceiveGridView.swift`：`Canvas` 自绘（几百个 View 会拖垮布局）；`receive(n)` 是真实接收入口，`clock` 播完自停。
  - **横向铺满铁律**：列数 `floor((可用宽+间距)/(格宽+间距))`，列间距 `(可用宽−n×格宽)/(n−1)` —— 早年用 `ceil` 会让最右列被切。
  - 跟随 `scrollTo` 的锚点 View **必须零宽**（占 1pt 就永远比可视区宽）。
  - 「最新一格」高亮环画在格子外，画布四周预留 `haloOutset = 2`，否则边角被裁。
  - 底槽攒成一条 `Path` 一次 `fill`。
  - `onPreferenceChange(TailFrameKey)` **只在 `followTail` 真正翻转时才写 @State**（tailMinX 每帧变 → 逐帧重算整块）。
  - 面板挂在 header/footer 之间的公共层（生成完留接收痕迹）；新一轮靠 `stats.receivedBytes` 掉回 0 触发 `prepareGrid()`。

## 快捷键 / 积分
- `Views/HistoryView/PlaybackKeyboardShortcuts.swift`：Carbon 热键**会吞事件** → 挡输入框要反向做：监听 `NSText.didBeginEditing/didEndEditing` → `KeyboardShortcuts.disable(all)/enable`。没在播时 disable 方向键还给列表。非隔离闭包调 @MainActor 需 `MainActor.assumeIsolated`。
- 积分全链路 Double（最多 2 位）：权威 `CreditManager`；一律过 `CreditPrecision.normalize`（`(v*100).rounded()/100`），**禁止 `Int(ceil())`**。计费 `字符数/100*rate`（普通 2、复刻 5），字符数用 `TextSplitter.calculateCharCount`（CJK 算 2）。云端 `user_credits.credits` 必须 `numeric(10,2)`。展示统一 `formatCredits(_:)`。

## iOS UI 要点
- iPhone Duo 适配 = 折叠屏展开宽屏：`iOS/Layout/ScreenMetrics.swift` 按可视宽度分档（<375 / 375–699 / 700–1023 / ≥1024）派生 pageMargin、contentMaxWidth、voiceGridColumns、metaColumns、`usesTwoColumnStudio`、dialogWidth=min(w-61,420)。全局**只用一次** GeometryReader（`ScreenMetricsReader`）。
- 信息架构：3 标签（创作/音色库/项目）+ 各自导航栈；齿轮 push 设置页（感知当前标签）；购买 Sheet 挂 `RootTabView`（`IOSUIState.purchaseSheetPresented`），全局还有生成弹窗 / 后台浮条 / Toast。
- iOS 无 `NSTextAttachmentCell`：标签走「纯文本 + 位置标记 + U+FFFC 占位附件 + 自绘 overlay」（`TokenCapsuleOverlay`）。
- ⚠️ **TokenTextEditor 打字不经过 SwiftUI**：内容放 `TokenEditorStore`（`doc`/`marks` 非 @Published，只有 `charCount` 0.25s 合并 + `contentRevision`）。早期每键击写 @Binding → 整页重算 → `updateUIView` → 重建 accessory SwiftUI 树 → 输入卡死。accessory 只在 `isDark` 翻转时重建；overlay 字段加相等判断才重绘。
- ⚠️ `TokenCapsuleOverlay` 必须设 `autoresizingMask = [.flexibleWidth,.flexibleHeight]`（否则 frame 恒 0，一个胶囊都画不出）；文本变长还要显式 `syncOverlayFrame(forceLayout:)`。
- 空作用域必须画 `emptyScopeWidth` 兜底胶囊，锚点取**前一个字符右边缘**。直接改 `textStorage` 不走 `shouldChangeTextIn`，必须手动 `TokenDocument.adjust()` 补 ±1。
- ⚠️ `TokenDocument.adjust` 里**零宽标记（语气/中断）与占位标记（拟声）规则相反**：零宽标记 `location <= editedRange.location` 就**原地不动**（新输入归它管），落在替换区间内部**夹回区间起点**而不是删除；否则每敲一字标记就被推后一格 → 作用域恒为空 → 「选完标签一输入就消失」。拟声占 1 个 U+FFFC，随字符消失。
- 拟声 pill：**不铺底色**（会在文字后面压出背景块），高度固定 20 并垂直居中 —— 不能拿行高当高度（`lineSpacing = 26` 会把行片段撑到 45pt）。
- ⚠️ 胶囊**接缝收敛**（移植 macOS `resolveCapsuleSeams`）：左右 `capsulePadX = 8` 会让相邻两段重叠 16pt。
  按「行 → x」排序两两收敛，`capsuleSeamGap = 2` / `capsuleSeamMinPadding = 3`；拟声 pill 是 `isSolid` **不让位**，
  所以胶囊背景在 pill 处断开。配套 `TokenDocument.orderedMarks`（位置序，同位置按插入序 —— Swift 的 `sorted` 不稳定）、
  `scopeEnd(at:in:)`（取位置序里的下一个边界，同位置标记不能漏）、`scopePieces`（按拟声占位切段）、`clampX(minX:maxX:)`。
- ⚠️ 编辑器要撑满剩余高度时，高度必须用 **GeometryReader** 显式给：`.frame(maxHeight:.infinity)` 顶 `UIViewRepresentable`
  会因为 UITextView 没有 intrinsicContentSize 而压成 0 高。宽屏在 ScrollView 里要另加 `minHeight` 兜底。
- ⚠️ **SwiftUI body 里的计算属性不许查库**：`VoiceStudioViewModel.voice` 曾是 `fetchAll().first(where:)`，一次 body 求值被调 5 次 = 5 次全表扫描，是切标签/打字卡顿的真因。统一走 `VoiceService.voice(forKey:)`（NSCache），失效点 = `toggleFavorite` + `DatabaseManager.rebuildVoices`（post `Notification.Name.voicesDidReload`）。

- 音色选择 Sheet（`Views/Studio/VoicePickerSheet.swift`）结构与音色库对齐：搜索（280ms 防抖）+ 分类/收藏筛选行 + 结果行 + `VoiceCardGrid` 网格（末卡 onAppear 追加，`pageSize = 列数 × 4`），复用 `VoicesLibraryViewModel`。⚠️ 筛选状态是 Sheet 私有 @State，**不写回 `AppState.voiceLibrary*`**。⚠️ 分类列表**就地替换内容区**，不要嵌第二层 `.sheet`（两层 detent 手势打架）。选中 = 卡片空白 `onTapGesture`（内层按钮优先吃掉自己的点击）或右下角箭头 → 设 key + toast + dismiss。

## 构建与验证
- 真构建：`bash tools/ios_build.sh`（+ `mac` 顺带回归 macOS）—— 三个 workaround 都是受限 shell 沙箱问题，Xcode GUI 不需要：① `IDEPackageSupportDisableManifestSandbox` ② `OTHER_SWIFT_FLAGS='$(inherited) -disable-sandbox'`（**必须 $(inherited)**，否则丢 SPM 的 `-package-name`，supabase-swift 报 ambiguous implicit access level）③ `ONLY_ACTIVE_ARCH=YES`。当前两个 target 均 BUILD SUCCEEDED、iOS 0 error/0 warning。
- 快速类型检查：`bash tools/ios_typecheck/typecheck.sh`（`swiftc -typecheck -disable-sandbox`，SPM 包用 `Shims.swift` 同签名替身）。改代码前先对 HEAD 跑基线。
  ⚠️ `Shims.swift` 里还有 `VoiceService`/`DatabaseManager` 等**业务替身**：给真实类加新方法必须同步在 Shims 加桩，否则报 "has no member"；反过来这些文件**不参与 typecheck 编译**，改动要用 `swiftc -parse` 另兜语法。
- 已知既有问题：`CreditsService.swift` 4 条 Swift6 actor 隔离报错；`PackageCardView.swift` 是未入 target 的孤儿文件。
