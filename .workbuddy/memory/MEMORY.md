# EmotionVoice 项目长期约定

## 技术栈
Swift + SwiftUI，两 target：`Emora`(macOS) / `iOSEmora`(iOS 18.6)。SPM：SQLite.swift、supabase-swift、keychain-swift。Supabase Edge Functions（Deno）在 `supabase/functions/`。
- iOS 独有代码放 `View/iOS/`；复用 macOS 文件原地加进 iOS target（不复制），靠 `#if canImport(AppKit)` 隔离。iOS 侧 `import SwiftUI` 不隐式导出 Combine → `@Published`/`ObservableObject` 要显式 `import Combine`。
- pbxproj 用 `tools/add_ios_target_files.py` 幂等维护。⚠️ PBXBuildFile ID ≠ XCSwiftPackageProductDependency ID（写错 Xcode 崩 `-[PBXBuildFile productName]`）。
- DB：SQLite（Documents/emotionvoice.sqlite3）。**永不迁移**：改 `createTables()` 就 bump `currentSchemaVersion`，不符 DROP 重建。

## TTS 链路（客户端 → Edge Function → 百炼）
- App 内**无百炼密钥**。端点 `wss://<ref>.supabase.co/functions/v1/bailian-tts?region=CN|INTL`；客户端只发一条 `{"action":"synthesize", text, voice, emotion?, rate, volume, sample_rate, format, instruction?}`，run-task/切段/continue/finish 全在 `bailian-tts/index.ts`。
- ⚠️ 断线无法重连续传，`receive()` 失败直接上抛。⚠️ 线上 Deno(<2.5) 不支持 `new WebSocket(url,{headers})` → `dialUpstream()` 两级拨号（原生 → `npm:ws@8`）；`upgradeWebSocket(req,{idleTimeout:0})` 后必须 `EdgeRuntime.waitUntil(closed)`。部署 `supabase/deploy.sh`。

## 本地化
- `.localized()` **用中文原文当 key**，找不到原样返回；动态拼接 `"%@ · 旗舰音色".localized(name)`。
- ⚠️ **禁止 `String(format: "…%@…".localized(), arg)`**（零参调用时 `%@` 已填 `(null)`）；定期扫 `grep -rn '\.localized()' --include=*.swift . | grep '%'`。
- 三语 zh-Hans / zh-HK / en 跟随系统；新增 lproj 要改 pbxproj `knownRegions` + PBXVariantGroup。
- 音色文案在 `<lproj>/VoiceCatalog.strings`。⚠️ 音色语种 ≠ 界面语言（中文音色永远中文名）；`VoiceCatalog.string` 用 `lprojCandidates(for:)`（繁体 `["zh-HK","zh-Hant","zh-Hans"]`）。
- 繁体按香港习惯（匯出/檔案/快取/目前/取樣率/位元率/增值），OpenCC `s2t` + 香港覆写（**别用 s2hk**）。手写 `.strings` 的 `\n` 必须是字面两字符；改完 `plutil -lint`。

## 音色目录 / 音色库筛选
- 唯一数据源 `Voices/basic_voices.json`（v4）。**JSON 只存语言无关 code + 稳定 key，文案外置 strings**；筛选基于 code 列（禁止中文字符串 WHERE）；搜索下沉内存（本地化名/特质/场景/语种 + 拼音）。改 JSON 后跑 `python3 tools/gen_basic_voices.py`。voices 表零文案列。
- 筛选七条规则（两端都不改）：① 分类单选互斥 ② 分类与收藏互斥 ③ 每行计数恒为全量 ④ 搜索忽略当前分类，全库匹配 ⑤ 搜索只命中 4 字段 ⑥ 排序固定「旗舰优先 → 名字典序」 ⑦ iOS 上拉追加替代 macOS 分页。
- ⚠️ `VoicesLibraryView` / `VoicePickerSheet` 两份筛选控件必须一致：整条胶囊全热区（外层 `contentShape(Rectangle())` + `onTapGesture`，不用内部 Button）；**选完分类不再出现 ×**（清除走分类列表里的「全部音色/重置」）。
- ⚠️ 分类列表进出场：`VoicePickerSheet` 是就地替换（无系统 Sheet 动画）→ 必须自己给 `panelTransition`（`move(edge:.bottom)`+`opacity`）+ `withAnimation` 包住 `categoryPresented` 翻转，else 分支要包一层 VStack 挂同一条 transition。`CategoryFilterSheet` 自身再补 14pt 上浮淡入（`appeared`，**必须 onDisappear 复位**，否则第二次打开没动画）。
- ⚠️ 列表刷新动画用「可动画属性」而非容器 transition：`.id(scrollResetID)` 只负责滚动复位，过渡靠 `contentVisible` 驱动 `opacity` + `offset(y:12)`（`.id` 重建触发的 `.transition` 不保证触发 → 硬切）。节奏：淡出 0.1s → 换数据 → 淡入 0.28s。分类 Sheet 是「点行即收起」→ 刷新必须**延迟 ~0.25s**（`onCommit(dismissing:)`），否则动画全程盖在 Sheet 背后。「重置」不收起 → 立即刷新。

## 标签体系（EmotionCategory 三类）
`.emotion`（语气：胶囊+徽章）/ `.richLanguage`（拟声：虚线 pill）/ `.interrupt`（不画胶囊，灰徽章，tag=`break`）。中断 API 不支持：`toTTSAPIString()` 丢弃；生成走 `Array.toTTSSegments()` 分段合成后 `AudioConcatenator.merge()`。
- macOS 语气胶囊 v13：同色胶囊（fill 13%、内描边 42%、圆角 9、内边距 8×6）+ 徽章压左上角，拟声 pill 嵌胶囊内。绘制顺序：胶囊 → 徽章 → `super.draw`（之后裁剪到 textContainer）；`drawsBackground=false`、`textContainerInset.height=28`、`lineSpacing=28`。
- marker cell 是 5×1 占位；陷阱：`boundingRect(forGlyphRange:)` 高度是整行高（只有 x/width 可信），同行判据用 `lineRect.minY`；空作用域补兜底胶囊。离屏测试 `debugToneCapsuleGeometry()`。

## iOS UI
- `ScreenMetrics` 按可视宽度分档（<375 / 375–659 / **660–1023** / ≥1024）。⚠️ **660**：iPhone Duo 展开态 669pt，阈值 700 会掉进 regular。全局**只用一次** GeometryReader（`ScreenMetricsReader`）。
- ⚠️ 两栏门槛 `usesTwoColumnStudio = width>=740 && isWide`；`contentMaxWidth` 两栏下返回 `nil`；`editorMinHeight` 宽屏 `max(260, min(height-190, 520))`。
- ⚠️ **键盘弹出时不能直接 push**：`TabRouter.push` 在 append 前 `resignFirstResponder()`，`StudioView` 另挂 `.onDisappear(finishEditing)`；否则返回后键盘避让失效、底栏被压到键盘下。
- 架构：3 标签 + 各自导航栈；购买 Sheet 挂 `RootTabView`。⚠️ **二级界面隐藏 TabBar**：用 `TabRouter.isTabBarHidden` Bool 驱动 `.toolbar(.hidden/.visible, for:.tabBar)` + `.animation(...value:)`，且 `push` 里 append 包 `withAnimation`；把 `.hidden` 挂死在 destination 上会瞬切无过渡。
- ⚠️ 编辑器撑满剩余高度要用 GeometryReader 显式给高；宽屏 ScrollView 里另加 `minHeight`。⚠️ **body 里的计算属性不许查库**（统一 `VoiceService.voice(forKey:)` NSCache）。⚠️ **同一层不要挂两个 `.alert`**。Sheet 统一 `SheetNavBar`（左 ✕ / 右「完成」）。

## iOS 编辑器（TokenTextEditor / TokenDocument / TokenCapsuleOverlay）
- ⚠️ 打字不经过 SwiftUI：内容放 `TokenEditorStore`（`doc`/`marks` 非 @Published，只有 `charCount`/`hasContent` 0.25s 合并 + `contentRevision`）；accessory 只在 `isDark` 翻转时重建；overlay 字段加相等判断才重绘。
- ⚠️ **三类标记都占 1 个 U+FFFC 占位**：语气/中断占 `toneSpacing=14pt` 空白（附件高 12，别超过正文字高否则撑高行）；拟声占 `pillWidth + 2×pillSpacing`；`capsulePadX=6` 由这段宽度支付。
  * ⚠️ 相邻两个标签之间只有一份 14pt，要同时付前一个右 pad 和后一个左 pad → 自然缝只剩 2pt（再被两条描边吃掉一半，肉眼 1pt「首尾重叠」）。故 `resolveSeams` 两支：`cutToneSeam`（撑到 `capsuleSeamGap=6`）、`cutPillSeam`（pill 不让，胶囊退到 pill 左沿 − `pillSeamGap 3`）。
  * ⚠️ `cutToneSeam` **必须带地板 `capsuleMinPad=3`**（早年无地板 → 为挤缝把 pad 吃到 0 → 复发「文字贴边」）。同标记的多个片段不参与收缝。
  * `TokenDocument.adjust` 只剩一条规则：占位符落在替换区间内 → 标记跟着没（区间在前则平移）。插/删占位符走 `Coordinator.insertPlaceholder`/`removeMark`（直接改 textStorage，不走 `shouldChangeTextIn`，必须手动 adjust 补 ±1）。插入后**光标必须跳到占位符之后**。
- ⚠️ overlay 是自绘层基准：`autoresizingMask=[.flexibleWidth,.flexibleHeight]`；文本变长要 `syncOverlayFrame(forceLayout:)`；空作用域只画徽章；**徽章统一排队**（按「行 → preferredX」推进游标，恒留 `badgeSeamGap=4`，中断也走这条队列画灰徽章）；绘制顺序：胶囊 → pill → 徽章；pill 不铺底、高 20 垂直居中。
- ⚠️ 空作用域回收唯一判据是「非空 → 空」翻转（**判据不许掺时序信息**）：`isBoundary`+`boundaryEmptiness` 只输出当前空/非空两组 id；`Coordinator` 持 `scopeHadText`+`pendingRemoval`，`refreshScopeStates()` 挂 `tvDidChangeContent` 最前。结果：从未有过内容的不回收，删光后停手 0.35s 回收。
- ⚠️ **底部条不能压到 accessory**：`onKeyboardTopChanged` 报「键盘+accessory 顶边」= `min(键盘框 minY, accessory 窗口框 minY)`（键盘框不在屏内就放弃，否则底部条凭空飘起）；`StudioView` 用 background GeometryReader 量内容底边，差值夹 0~260 得 `keyboardSeam` **再加固定 `keyboardSeamGap=10`**，加到 `generateBar` 底部 padding。⚠️ 只在 `onPreferenceChange` 里算。
- ⚠️ **accessory 高度由 SwiftUI 上报**（`background(GeometryReader)` + `AccessoryHeightKey` → Combine 写 `contentHeight`）；⚠️ 光 invalidate 不够：容器是手写 frame 建的 → `didSet` 里必须**自己改 frame** + `superview?.setNeedsLayout()`，否则永远停在初始高度、底部留死空白。⚠️ `safeAreaInsets` 覆写成 `.zero`；根视图 `.frame(maxHeight:.infinity, alignment:.top)` 顶对齐。高度常量在 `AccessoryMetrics`（6+42+38=86），三处共用。
- ⚠️ **「刚点了哪个标签」**：accessory 里刚点过的按钮给 `accentSoft` 底 + `accent` 实描边（`config.lastPickedTag`）。⚠️ **别弹临时浮层提示**（试过 1.3s 胶囊浮层挡编辑区，已删）。
- 「清空」两入口：标题行文字按钮 + accessory 🗑。「完成」在底部生成条与「生成音频」同行。`TokenEditorStore.hasContent` 门控清空。

## 生成弹窗 / 后台接收 / 播放器
- 开关 `AppState.showGenerationModal`；macOS 只有 `Views/GenerationOverlay.swift` 订阅 VM。⚠️ 完成态直接 `hasResult = generatedAudioURL != nil && !isGenerating` 推导。⚠️ 浮层 ZStack 要 `maxWidth/maxHeight:.infinity`；计时用自持 Timer(0.5s)，不用 `autoconnect()`。
- `DataReceiveGridView`（Canvas 自绘，`receive(n)` 是真实入口）：列数 `floor((可用宽+间距)/(格宽+间距))`，列间距 `(可用宽−n×格宽)/(n−1)`；`scrollTo` 锚点必须零宽；高亮环画在格外（`haloOutset=2`）；`onPreferenceChange(TailFrameKey)` 只在 `followTail` 翻转时写 @State。
- ⚠️ **必须用 `voice.audio` 找 Bundle 资源，不能用 `voice.key`**（key 带前缀 → 恒 nil），统一 `AudioPreviewPlayer.play(voice:)`。⚠️ `playingKey` 存 identifier 不是 URL：`isPlaying(url:)` 对自定义 identifier 恒 false，跨页统一 `playingKey == identifier`，跨 key 用 `reidentify(_:)`。

## iOS 列表 / 分页
- ⚠️ **上拉追加必须先写本地 `page` 再 `syncToVM()`**（反了追加恒为空）；空页回退 `page = max(1, next-1)`。
- ⚠️ 筛选/搜索变化后必须滚回顶部：用 `ScrollView.id(scrollResetID)` 自增整体重建（⚠️ 试过 `scrollTo` 顶部锚点：它按旧 contentSize 算偏移，行数变少时滚不动 → 一片空白）。
- 音色 Sheet 复用 `VoicesLibraryViewModel`；筛选是 Sheet 私有 @State，**不写回 `AppState.voiceLibrary*`**；分类列表就地替换内容区，不嵌第二层 `.sheet`。
- ⚠️ **搜索框回车**：`AuroraSearchField` 内 `.submitLabel(.search)` + `@FocusState`（`.onSubmit` 收键盘 + 回调），外层 `onSubmit: { commitSearch() }`（取消防抖 Task + 立即 `reload()`，不等 280ms）。
- ⚠️ **列表滚动收键盘**：`.scrollDismissesKeyboard(.immediately)` 必须挂在 **ScrollView 本身**；它依赖「内容能滚动」→ 无结果/不满一屏时滑不动，必须补 `simultaneousGesture(DragGesture(minimumDistance:12))` + `didResignOnDrag` 限一次拖拽一次。
- ⚠️ **`VoicesLibraryView.body` 的缩进是骗人的**（真正关闭 ScrollView 的 `}` 缩进 16 空格）。定层级用括号深度脚本，别看缩进，否则多一个 `}` → `extraneous '}' at top level`。
- ⚠️ 项目列表增删：**磁盘 IO 必须在动画事务之外**。⚠️ 左滑「复制」行先消失的根因是主线程被同步 IO 冻住 → `ProjectService.stageDuplicatedFile`（`nonisolated`，`Task.detached`）+ `finishDuplicate`（主线程写库）；副本插在被操作行下面。重命名用自绘 `RenameDialog`。
- ⚠️ `stageDuplicatedFile` / `Date.filenameTimestamp` / `generatedAudioDirectoryURL()` / `kGeneratedAudioSubdirectory` 都要 `nonisolated`（MainActor 默认隔离）。

## 快捷键 / 积分
- `PlaybackKeyboardShortcuts`：Carbon 热键吞事件 → 监听 `NSText.didBeginEditing/didEndEditing` → `KeyboardShortcuts.disable(all)/enable`。
- 积分全链路 Double（≤2 位）：权威 `CreditManager`，一律过 `CreditPrecision.normalize`（`(v*100).rounded()/100`），**禁止 `Int(ceil())`**；计费 `字符数/100*rate`（普通 2、复刻 5）；字符数 `TextSplitter.calculateCharCount`（CJK 算 2）；云端 `user_credits.credits` 必须 `numeric(10,2)`；展示 `formatCredits(_:)`。

## 构建与验证
- 真构建 `bash tools/ios_build.sh`（+ `mac`）；快速类型检查 `bash tools/ios_typecheck/typecheck.sh`。三个 workaround 均为沙箱问题：① `IDEPackageSupportDisableManifestSandbox` ② `OTHER_SWIFT_FLAGS='$(inherited) -disable-sandbox'`（**必须 $(inherited)**）③ `ONLY_ACTIVE_ARCH=YES`。
- ⚠️ `tools/ios_typecheck/Shims.swift` 有 `VoiceService`/`DatabaseManager`/`ProjectService` 等**业务替身**：给真实类加新方法必须同步加桩。
- 已知既有问题：`CreditsService.swift` 4 条 Swift6 actor 隔离报错；`PackageCardView.swift` 是未入 target 的孤儿文件；第三方 `swift-issue-reporting` 会挡住完整 build（与本项目无关）。
