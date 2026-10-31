# EmotionVoice 项目长期约定

## 技术栈
Swift + SwiftUI（Swift 5），单工程两 target：`Emora`(macOS) / `iOSEmora`(iOS, com.emotion.voice.ios, 18.6)。
依赖 SQLite.swift、supabase-swift、keychain-swift（SPM）。服务端 Supabase Edge Functions（Deno），代码在 `supabase/functions/`。
- **iOS 独有代码放 `EmotionVoice/EmotionVoice/View/iOS/`**（App / DesignSystem / Layout / Views/{Studio,Library,Projects,Generation,Settings}）；复用的 macOS 文件原地加进 iOS target（不复制），靠 `#if canImport(AppKit)` 隔离。
- iOS 侧 `import SwiftUI` **不隐式导出 Combine**：用 `@Published`/`ObservableObject` 必须显式 `import Combine`。
- pbxproj 用 `tools/add_ios_target_files.py` 幂等维护。⚠️ PBXBuildFile ID ≠ XCSwiftPackageProductDependency ID，写错 Xcode 依赖图崩溃 `-[PBXBuildFile productName]`。

## TTS 链路（客户端 → Supabase Edge Function → 阿里云百炼）
- App 内**无百炼密钥**：`RegionConfig.swift` 只剩区域判断，Key/Workspace/模型在 function secrets。
- 端点 `Services/TTSEndpoint.swift`：`wss://<ref>.supabase.co/functions/v1/bailian-tts?region=CN|INTL`，握手头 Authorization/apikey + `x-app-secret`。
- 客户端只发一条 `{"action":"synthesize", text, voice, emotion?, rate, volume, sample_rate, format, instruction?}`；run-task/切段/continue/finish 全在 `supabase/functions/bailian-tts/index.ts`。上游 JSON 事件与二进制音频帧**原样转发**。
- ⚠️ 服务端断开后无法重连续传，`receive()` 失败必须直接上抛。
- ⚠️ Supabase 线上 Deno(<2.5) 不支持 `new WebSocket(url,{headers})`；`dialUpstream()` 两级拨号：原生 → 回退 `npm:ws@8`。
- `Deno.upgradeWebSocket(req,{idleTimeout:0})` 后必须 `EdgeRuntime.waitUntil(closed)`。部署 `supabase/deploy.sh`（需用户自己跑）。
- DB：SQLite，文件在用户 Documents `emotionvoice.sqlite3`。
- **DB 策略：永远不做迁移** —— `resetDatabaseIfSchemaChanged`：改 `createTables()` 就 bump `currentSchemaVersion`，启动比对 UserDefaults，不符就 DROP 重建。

## 本地化
- `.localized()`（`Extension/String+Extension.swift`）**用中文原文当 key**，找不到原样返回；动态拼接用格式占位符：`"%@ · 旗舰音色".localized(name)`。
- ⚠️ **绝不能写 `String(format: "…%@…".localized(), arg)`**：`.localized()` 内部就是 `String(format: 原文, arguments: args)`，零参调用时 `%@` 已被填成 `(null)`、`%d` 填成 `0`。参数一律直接传给 `.localized(...)`。定期扫：`grep -rn '\.localized()' --include=*.swift . | grep '%'`。
- 三语 zh-Hans / zh-HK（繁体）/ en，跟随系统。新增 lproj 要改 pbxproj `knownRegions` + PBXVariantGroup。
- 音色文案在 `<lproj>/VoiceCatalog.strings`（`voice.<stem>.name`/`.feature`）。⚠️ 音色语种 ≠ 界面语言：中文音色永远中文名。`VoiceCatalog.string` 用 `lprojCandidates(for:)`（繁体 `["zh-HK","zh-Hant","zh-Hans"]`），别写死 `zh-Hans`。
- 繁体用香港习惯（匯出/檔案/快取/目前/取樣率/位元率/增值）。同步用 OpenCC `s2t` + 香港覆写（**别用 `s2hk`**）。
- ⚠️ 手写 `.strings` 时 `\n` 必须是**字面两字符**；改完跑 `plutil -lint <lproj>/Localizable.strings`。

## 标签体系（EmotionCategory 三类家族）
- `.emotion`（语气：胶囊+徽章）/ `.richLanguage`（拟声：虚线 pill，情感着色）/ `.interrupt`（不画胶囊，灰徽章，tag=`break`）。
- **中断 API 不支持**：`toTTSAPIString()` 丢弃；生成走 `Array.toTTSSegments()` 切多请求，逐段 `synthesizeStream` 后 `AudioConcatenator.merge()`。
- macOS UI（语气胶囊版 v13）：语气 = 整段同色胶囊（fill 13%、内描边 42%、圆角 9、内边距 8×6）+ emoji/名称徽章压左上角；拟声 pill 嵌在胶囊内。
  - **绘制顺序铁律**：胶囊 → **徽章** → `super.draw`（super.draw 后裁剪到 textContainer，容器上沿外的徽章会被裁）。`tokenView.drawsBackground = false`、`textContainerInset.height = 28`、`lineSpacing = 28`。
  - 语气 marker cell 是 5×1 不可见占位，相邻作用域靠 `resolveCapsuleSeams` 切 2pt 缝。几何集中 `toneCapsuleGeometries()`。
  - 陷阱：`boundingRect(forGlyphRange:)` 高度是整行高（只有 x/width 可信）；同行判据用 `lineRect.minY`；空作用域补兜底胶囊。离屏测试 `debugToneCapsuleGeometry()`。

## 音色目录
- 唯一数据源 `EmotionVoice/EmotionVoice/Voices/basic_voices.json`（v4）。**铁律：JSON 只存语言无关 code + 稳定 key，文案外置 strings**。字段 `idx`/`key`/`tier`/`lang`/`gender`/`age`/`scene`/`audio`。
- 筛选基于 code 列（禁止中文字符串 WHERE）；搜索下沉内存（本地化名/特质/场景/语种，支持拼音）。
- 改 JSON 后跑 `python3 tools/gen_basic_voices.py`。`DatabaseManager` voices 表零文案列。

## 生成弹窗 / 后台接收 / 数据接收网格
- 开关在 `AppState.showGenerationModal`（不能放子视图 @State）。
- macOS：`Views/GenerationOverlay.swift` 是唯一订阅 `VoiceStudioViewModel` 的全局浮层（ContentView 本体不订阅 VM，否则 NSTextView 每次输入牵动整窗重建）。后台卡片锚在情感面板「拟声效果」区块右下角。
- ⚠️ 完成态**不要用「本地 Bool + onChange」中转**（onChange 跑在 body 求值之后 → 多渲染一帧 + 动画跳一次 = 卡顿）。直接 `hasResult = generatedAudioURL != nil && !isGenerating` 推导。
- ⚠️ 浮层定位：`ZStack` 必须 `.frame(maxWidth:.infinity,maxHeight:.infinity)`；固定尺寸小浮层**不要用 GeometryReader**。
- 计时用自持 Timer（0.5s），**不能用 `Timer.publish().autoconnect()`**。
- 网格 `Views/DataReceiveGridView.swift`：`Canvas` 自绘；`receive(n)` 是真实接收入口。
  - **横向铺满铁律**：列数 `floor((可用宽+间距)/(格宽+间距))`，列间距 `(可用宽−n×格宽)/(n−1)`。
  - 跟随 `scrollTo` 的锚点 View **必须零宽**。「最新一格」高亮环画在格子外，预留 `haloOutset = 2`。
  - `onPreferenceChange(TailFrameKey)` **只在 `followTail` 真正翻转时才写 @State**。

## 音色试听 / 播放器
- ⚠️ **必须用 `voice.audio` 找 Bundle 资源，不能用 `voice.key`**：基础音色 key 带 `qwen-audio-3.0-tts-plus-` 前缀，按 key 找一律 nil。统一走 `AudioPreviewPlayer.play(voice:)` / `.toggle(voice:)`（identifier 仍用 `voice.key`）。
- ⚠️ **`playingKey` 存的是 `play(url:identifier:)` 传进来的 identifier，不是 URL**。用 `isPlaying(url:)`（比 `url.path`）去判「是不是这条在播」，只要调用方传了自定义 identifier 就**恒为 false**（表现：播放按钮图标不变、点暂停从头重播）。跨页 / 带 identifier 的场景统一用 `playingKey == identifier` 判定（播放器内已有 `togglePlayback(url:identifier:)`）。列表页与详情页用不同 key 时用 `reidentify(_:)` 衔接，避免 push 时从头重播。

## iOS 编辑器标签 / 清空
- ⚠️ 语气 / 中断标记的**空作用域回收**：唯一判据是 **「非空 → 空」的翻转**（2026-10-31 第二轮重写：`pruneEmptyScopes` → `boundaryEmptiness` → 现在的状态机；中间那版「删除前快照 + 0.4s 后结算」仍会被真实操作打穿）。
  * `TokenDocument.isBoundary`（`nonisolated static`）+ `boundaryEmptiness` 只输出**当前**的空 / 非空两组 id；
  * `Coordinator` 持 `scopeHadText: [UUID: Bool]` + `pendingRemoval: Set<UUID>`，`refreshScopeStates()` 挂在 `tvDidChangeContent` **最前面** —— 打字 / 插标签 / 删标签 / 清空**每条路径都跑同一遍**判定；
  * **判据里不许掺时序信息**（「这次删没删东西」、延迟后才采的快照…）：同一段操作在快 / 慢两种节奏下会跑出不同结果；
  * 结果：从未有过内容的标签**永不自动回收**；内容被删光必然翻转一次 → 停手 0.35s 后回收，期间恢复文本则撤回。拟声（占字符）始终交给 `adjust`。
- 「清空」有两个入口：`StudioView.cardHeader` 的文字按钮 + accessory 的 🗑 —— 键盘弹出时标题行会收成 0 高，那时只剩 accessory 可达。「完成」（收键盘）不在 accessory，在底部生成条、与「生成音频」同一行（完成 = 描边无填充，生成音频 = 渐变实心，必须拉开差异）。`TokenEditorStore.hasContent` 用于清空按钮的门控（只看 `charCount` 判不了：只插标签时字数是 0）。

## iOS 弹窗
- ⚠️ **同一层不要挂两个 `.alert`**：会互相覆盖。`StudioView` 根视图已有 `.alert(item:)`，「生成音频」二次确认挂在 **`generateBar` 子视图**上。

## 快捷键 / 积分
- `Views/HistoryView/PlaybackKeyboardShortcuts.swift`：Carbon 热键**会吞事件** → 监听 `NSText.didBeginEditing/didEndEditing` → `KeyboardShortcuts.disable(all)/enable`。
- 积分全链路 Double（最多 2 位）：权威 `CreditManager`；一律过 `CreditPrecision.normalize`（`(v*100).rounded()/100`），**禁止 `Int(ceil())`**。计费 `字符数/100*rate`（普通 2、复刻 5），字符数用 `TextSplitter.calculateCharCount`（CJK 算 2）。云端 `user_credits.credits` 必须 `numeric(10,2)`。展示统一 `formatCredits(_:)`。

## iOS UI 要点
- iPhone Duo 适配 = 折叠屏展开宽屏：`iOS/Layout/ScreenMetrics.swift` 按可视宽度分档（<375 / 375–659 / **660–1023** / ≥1024）派生 pageMargin、contentMaxWidth、voiceGridColumns、metaColumns、`usesTwoColumnStudio`、dialogWidth。⚠️ **660 这一刀**：iPhone Duo 展开态是 **669pt**，老阈值 700 会让它掉进 `regular` 单列档（展开只是拉宽手机布局）；660 卡在「手机横屏最大值」与「Duo 展开宽度」之间。全局**只用一次** GeometryReader（`ScreenMetricsReader`）。
- ⚠️ **两栏工作台门槛 `usesTwoColumnStudio = width >= 740 && isWide`**：侧栏固定 300pt，669pt（Duo 展开态）留给编辑区只剩 ~305pt（比手机 361pt 还窄）→ Duo 展开态走**单列 + wide 红利**（3 列网格 / 24pt 边距）。两栏只在 iPad 横屏 / Duo 横屏(951pt) 生效。
- ⚠️ **`contentMaxWidth` 在两栏布局返回 `nil`**：否则 951×669 横屏两栏会被 720 cap 夹住，两侧各留 ~115pt 空白。单列 wide 档 cap=720 / extraWide=820（均 >660 最小档宽，不会一进来就被夹）。`editorMinHeight` 宽屏下 `max(260, min(height-190, 520))`（Duo 横屏只有 669pt 高，按 260 会给下面留一大截）。
- 信息架构：3 标签（创作/音色库/项目）+ 各自导航栈；购买 Sheet 挂 `RootTabView`（`IOSUIState.purchaseSheetPresented`），全局还有生成弹窗 / 后台浮条 / Toast。
- iOS 无 `NSTextAttachmentCell`：标签走「纯文本 + 位置标记 + U+FFFC 占位附件 + 自绘 overlay」（`TokenCapsuleOverlay`）。
- ⚠️ **TokenTextEditor 打字不经过 SwiftUI**：内容放 `TokenEditorStore`（`doc`/`marks` 非 @Published，只有 `charCount`/`hasContent` 0.25s 合并 + `contentRevision`）。accessory 只在 `isDark` 翻转时重建；overlay 字段加相等判断才重绘。
- ⚠️ `TokenCapsuleOverlay` 必须设 `autoresizingMask = [.flexibleWidth,.flexibleHeight]`；文本变长还要显式 `syncOverlayFrame(forceLayout:)`。
- **空作用域只画徽章、不铺胶囊**。
- ⚠️ **徽章统一排队**：`drawBadges(_:minX:maxX:)` 按「行 → `preferredX`」排序，同行从左到右推进游标，恒留 `badgeSeamGap = 4`；中断标记也走这条队列，画**灰徽章**。绘制顺序：胶囊 → pill → 徽章。
- 直接改 `textStorage` 不走 `shouldChangeTextIn`，必须手动 `TokenDocument.adjust()` 补 ±1。
- ⚠️ `TokenDocument.adjust` 里**零宽标记（语气/中断）与占位标记（拟声）规则相反**：零宽标记 `location <= editedRange.location` 就**原地不动**，落在替换区间内部**夹回区间起点**而不是删除；拟声占 1 个 U+FFFC，随字符消失。
- 拟声 pill：**不铺底色**，高度固定 20 并垂直居中（不能拿行高当高度）。
- ⚠️ 胶囊**接缝收敛**：左右 `capsulePadX = 8` 会让相邻两段重叠 16pt，按「行 → x」排序两两收敛 ——
  ① pill 参与：拟声 pill 是 `isSolid` **不让位**，胶囊单方面让 `pillSeamGap`；
  ② 语气↔语气：**两侧一起收到重叠区中点**；
  ③ **中断**处的断开由 `applyInterruptGaps(_:anchors:gap:)` 在收敛**之前**独立跑（两者都只收不放）。
  ⚠️ 必须用**几何**判定（中断锚点 x 是否落在某盒 `textRect` 左/右端点 ±1.5pt 内）。两侧都有胶囊 → 各让 `interruptSeamGap/2`；**只有一侧 → 只把那侧内边距收到 0**。
  ⚠️ 不能照抄 macOS 的「各让 `gap/2` + 每侧留 `minPad`」：iOS 语气标记**不占字符位**，两段文本严丝合缝，`minPad` 地板会顶过中线。
  配套 `orderedMarks`（位置序，同位置按插入序 —— Swift 的 `sorted` 不稳定）、`scopeEnd(at:in:)`、`scopePieces`、`clampX(minX:maxX:)`。
- ⚠️ 三道缝隙收敛按「先粗后细」依次跑：`applyNeighborGaps`（**另一侧没有底色**的邻居 → `uncoveredSeamGap 3` / `uncoveredMaxCut 3`）→ `applyInterruptGaps` → `resolveSeams`。
  ⚠️ `applyNeighborGaps` 补的是 macOS 天然有、iOS 没有的物理空隙：iOS 语气标记不占字符位，相邻两段严丝合缝，胶囊的 `capsulePadX = 8` 会盖到**不属于任何胶囊**的前一段字上 —— 「中断（不画胶囊）→ 输入一段字 → 再插语气标签」必现。只对「邻居没底色」那一支让位（用 `SeamBox.charRange` 找邻居、`isCovered` 排除已经有底色的），另一侧有底色的照旧交给 `resolveSeams`；为此 `lineRects` 改成 `linePieces`（多返回一个**字符区间**）。
- 拟声 pill 文本要**两个方向都居中**：`draw(with:options:)` 是左上角对齐的，把 pill 高直接当 rect 高塞进去 → 12pt 文本顶在虚线框上沿、下面空一截。先 `boundingRect` 量行盒，再横向（左内边距 ~ × 之间）与纵向（pill 中线）居中。
- ⚠️ 编辑器要撑满剩余高度时，高度必须用 **GeometryReader** 显式给；宽屏在 ScrollView 里要另加 `minHeight`。
- ⚠️ **SwiftUI body 里的计算属性不许查库**。统一走 `VoiceService.voice(forKey:)`（NSCache）。

## iOS 列表 / 分页
- ⚠️ **上拉追加（`loadMore`）必须先写本地 `page` 再 `syncToVM()`**：`syncToVM()` 会把本地 `page` 灌回 `vm.currentPage`，顺序反了新页码被旧页码覆盖 → 追加恒为空。`VoicesLibraryView` 与 `VoicePickerSheet` 两份都要一致。空页回退 `page = max(1, next-1)`。
- ⚠️ **筛选/搜索变化后必须把 ScrollView 滚回顶部**（`ScrollViewReader` + 顶部 0 高锚点）：否则内容变短而偏移仍停在原处，看到的就是一片空白（「滚动后点收藏没反应」）。
- 音色选择 Sheet（`Views/Studio/VoicePickerSheet.swift`）复用 `VoicesLibraryViewModel`。⚠️ 筛选状态是 Sheet 私有 @State，**不写回 `AppState.voiceLibrary*`**。⚠️ 分类列表**就地替换内容区**，不要嵌第二层 `.sheet`。
- ⚠️ **项目列表的增删：磁盘 IO 必须在动画事务之外**。`HistoryViewModel` 已拆成 `deleteAudio`（磁盘 + 库）与 `removeAudioItem`（纯内存），调用方先在外面删干净，再把 `removeAudioItem` 包进 `withAnimation`。早年 `HistoryViewModel.deleteAudio` 只改 UI 数组，`ProjectService.deleteAudio` 全工程 0 调用 —— 行看着消失、数据和文件都还在，重进页面又整排回来（2026-10-31 修）。
- ⚠️ **左滑「复制」的「当前行先消失」根因是主线程被同步 IO 冻住**，不是「动画事务里夹 IO」：复制几 MB 音频的 `FileManager.copyItem` 卡住主线程时，左滑菜单的回弹动画还没跑完，那一帧行内容仍停在滑开的位置。复制已拆成 `ProjectService.stageDuplicatedFile`（`nonisolated static`，在 `Task.detached` 里跑）+ `finishDuplicate`（写库留在主线程）。
- ⚠️ 副本插在被操作行的**下面**（`insertAudioItem(_:after:)`），不是列表顶部：顶部插入会把整列往下推一格，再 `scrollTo(anchor: .top)` 就等于「刚操作的行被顶出视野」。`scrollTo` **不带 anchor**（最小位移），副本在视野里就一步都不走。
- ⚠️ `ProjectService.stageDuplicatedFile` / `Date.filenameTimestamp` / `generatedAudioDirectoryURL()` / `kGeneratedAudioSubdirectory` 都要标 `nonisolated`：工程开了 **MainActor 默认隔离**，后台线程调用它们会出 actor 隔离告警（改完跑一遍 `ios_build.sh` 看 warning 是否回升）。
- 重命名用自绘 `RenameDialog`（overlay，非系统 `.alert`）：系统 Alert 的 TextField 没有清空按钮、槽位也塞不进自定义视图。

## 构建与验证
- 真构建：`bash tools/ios_build.sh`（+ `mac` 回归 macOS）—— 三个 workaround 都是受限 shell 沙箱问题：① `IDEPackageSupportDisableManifestSandbox` ② `OTHER_SWIFT_FLAGS='$(inherited) -disable-sandbox'`（**必须 $(inherited)**）③ `ONLY_ACTIVE_ARCH=YES`。
- 快速类型检查：`bash tools/ios_typecheck/typecheck.sh`。⚠️ `Shims.swift` 里有 `VoiceService`/`DatabaseManager` 等**业务替身**：给真实类加新方法必须同步加桩；这些文件不参与 typecheck 编译，改动要用 `swiftc -parse` 兜语法。
- 已知既有问题：`CreditsService.swift` 4 条 Swift6 actor 隔离报错；`PackageCardView.swift` 是未入 target 的孤儿文件。
