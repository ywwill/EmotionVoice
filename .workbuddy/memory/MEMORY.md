# EmotionVoice 项目长期约定

## 技术栈
Swift + SwiftUI，两 target：`Emora`(macOS) / `iOSEmora`(iOS 18.6)。SPM：SQLite.swift、supabase-swift、keychain-swift。服务端 Supabase Edge Functions（Deno）在 `supabase/functions/`。
- iOS 独有代码放 `EmotionVoice/View/iOS/`；复用 macOS 文件原地加进 iOS target（不复制），靠 `#if canImport(AppKit)` 隔离。
- iOS 侧 `import SwiftUI` 不隐式导出 Combine：`@Published`/`ObservableObject` 必须显式 `import Combine`。
- pbxproj 用 `tools/add_ios_target_files.py` 幂等维护。⚠️ PBXBuildFile ID ≠ XCSwiftPackageProductDependency ID，写错 Xcode 崩溃 `-[PBXBuildFile productName]`。
- DB：SQLite（Documents/emotionvoice.sqlite3）。**永不迁移**：改 `createTables()` 就 bump `currentSchemaVersion`，不符 DROP 重建。

## TTS 链路（客户端 → Edge Function → 百炼）
- App 内**无百炼密钥**（都在 function secrets）。`TTSEndpoint`：`wss://<ref>.supabase.co/functions/v1/bailian-tts?region=CN|INTL`；客户端只发一条 `{"action":"synthesize", text, voice, emotion?, rate, volume, sample_rate, format, instruction?}`，run-task/切段/continue/finish 全在 `bailian-tts/index.ts`。
- ⚠️ 断线无法重连续传，`receive()` 失败直接上抛。⚠️ 线上 Deno(<2.5) 不支持 `new WebSocket(url,{headers})` → `dialUpstream()` 两级拨号（原生 → `npm:ws@8`）；`upgradeWebSocket(req,{idleTimeout:0})` 后必须 `EdgeRuntime.waitUntil(closed)`。部署 `supabase/deploy.sh`。

## 本地化
- `.localized()` **用中文原文当 key**，找不到原样返回；动态拼接 `"%@ · 旗舰音色".localized(name)`。
- ⚠️ **禁止 `String(format: "…%@…".localized(), arg)`**（零参调用时 `%@` 已填 `(null)`）。参数一律直接传 `.localized(...)`。定期扫 `grep -rn '\.localized()' --include=*.swift . | grep '%'`。
- 三语 zh-Hans / zh-HK（繁体）/ en 跟随系统；新增 lproj 要改 pbxproj `knownRegions` + PBXVariantGroup。
- 音色文案在 `<lproj>/VoiceCatalog.strings`。⚠️ 音色语种 ≠ 界面语言（中文音色永远中文名）；`VoiceCatalog.string` 用 `lprojCandidates(for:)`（繁体 `["zh-HK","zh-Hant","zh-Hans"]`）。
- 繁体按香港习惯（匯出/檔案/快取/目前/取樣率/位元率/增值），OpenCC `s2t` + 香港覆写（**别用 s2hk**）。手写 `.strings` 的 `\n` 必须是字面两字符；改完 `plutil -lint`。

## 音色目录
- 唯一数据源 `Voices/basic_voices.json`（v4）。**JSON 只存语言无关 code + 稳定 key，文案外置 strings**。筛选基于 code 列（禁止中文字符串 WHERE）；搜索下沉内存（本地化名/特质/场景/语种 + 拼音）。改 JSON 后跑 `python3 tools/gen_basic_voices.py`。voices 表零文案列。

## 标签体系（EmotionCategory 三类）
`.emotion`（语气：胶囊+徽章）/ `.richLanguage`（拟声：虚线 pill）/ `.interrupt`（不画胶囊，灰徽章，tag=`break`）。中断 API 不支持：`toTTSAPIString()` 丢弃，生成走 `Array.toTTSSegments()` 切多请求逐段合成后 `AudioConcatenator.merge()`。
- macOS（语气胶囊 v13）：整段同色胶囊（fill 13%、内描边 42%、圆角 9、内边距 8×6）+ 徽章压左上角，拟声 pill 嵌胶囊内。
  - **绘制顺序**：胶囊 → **徽章** → `super.draw`（之后裁剪到 textContainer）。`drawsBackground=false`、`textContainerInset.height=28`、`lineSpacing=28`。
  - marker cell 是 **5×1 占位**（iOS 同，见下），相邻作用域靠 `resolveCapsuleSeams` 切 2pt 缝；几何集中 `toneCapsuleGeometries()`。
  - 陷阱：`boundingRect(forGlyphRange:)` 高度是整行高（只有 x/width 可信）；同行判据用 `lineRect.minY`；空作用域补兜底胶囊。离屏测试 `debugToneCapsuleGeometry()`。

## iOS UI
- `ScreenMetrics` 按可视宽度分档（<375 / 375–659 / **660–1023** / ≥1024）。⚠️ **660**：iPhone Duo 展开态 669pt，阈值 700 会掉进 `regular`。全局**只用一次** GeometryReader（`ScreenMetricsReader`）。
- ⚠️ 两栏门槛 `usesTwoColumnStudio = width>=740 && isWide`（侧栏 300pt，669pt 只剩 ~305pt）→ Duo 展开走单列 + wide 红利；⚠️ `contentMaxWidth` 在两栏下返回 `nil`；`editorMinHeight` 宽屏 `max(260, min(height-190, 520))`。
- ⚠️ **键盘弹出时不能直接 push**：`TabRouter.push` 统一在 append 前 `resignFirstResponder()`（`UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder)…)`），`StudioView` 另挂 `.onDisappear(perform: finishEditing)` 兜住切标签。否则返回后 SwiftUI 键盘避让失效，底部 `generateBar` 被压到键盘底下（看着是「生成/完成按钮没了」）。收键盘后 `textViewDidEndEditing` 会把 `isEditingText` 复位。
- 架构：3 标签 + 各自导航栈；购买 Sheet 挂 `RootTabView`（`IOSUIState.purchaseSheetPresented`）。⚠️ **二级界面隐藏底部 TabBar**：必须用 `TabRouter.isTabBarHidden`（`!activePath.isEmpty`）这个 Bool 驱动 `.toolbar(hidden ? .hidden : .visible, for: .tabBar)` + `.animation(TabRouter.tabBarAnimation, value:)`，且 `TabRouter.push` 里 append 要包 `withAnimation(Self.tabBarAnimation)` —— 把 `.hidden` 直接挂死在 destination 上会**瞬切、没有过渡**。后台浮条底距随之切（`activePath.isEmpty ? 58 : 18`）。
- ⚠️ 编辑器撑满剩余高度要用 GeometryReader 显式给高；宽屏 ScrollView 里另加 `minHeight`。⚠️ **body 里的计算属性不许查库**（统一 `VoiceService.voice(forKey:)` NSCache）。
- ⚠️ **同一层不要挂两个 `.alert`**（互相覆盖）：`StudioView` 根视图有 `.alert(item:)`，生成二次确认挂 `generateBar`。Sheet 统一 `SheetNavBar`（左 ✕ / 右「完成」）；设置页「默认格式 / 采样率」就地 sheet（`OptionPickerSheet` + `SettingsOptionKind: Identifiable`）。

## iOS 编辑器（TokenTextEditor / TokenDocument / TokenCapsuleOverlay）
- ⚠️ 打字不经过 SwiftUI：内容放 `TokenEditorStore`（`doc`/`marks` 非 @Published，只有 `charCount`/`hasContent` 0.25s 合并 + `contentRevision`）；accessory 只在 `isDark` 翻转时重建；overlay 字段加相等判断才重绘。
- ⚠️ **三类标记都占 1 个 U+FFFC 占位**（2026-10-31 起；此前语气/中断是零宽的），等价于 macOS 的 5×1 可见占位：
  * 语气/中断占 `toneSpacing = 14pt` 空白（附件高 12，别超过正文字高否则 TextKit 撑高行）；拟声占 `pillWidth + 2×pillSpacing`。
  * `capsulePadX = 6` 由这段宽度支付 → 文字距胶囊左右各 6pt。
  * ⚠️ **相邻两个标签之间只有一份 14pt**，要同时付前一个的右 pad 和后一个的左 pad，自然缝只剩 2pt（再被两条 1pt 描边吃掉一半 → 肉眼 1pt，「两个标签首尾重叠」）。所以 `resolveSeams` 仍留**两支**：`cutToneSeam`（不同标记的胶囊，把可见缝撑到 `capsuleSeamGap = 6`）与 `cutPillSeam`（pill 实心不让，胶囊退到 `pill 左沿 − pillSeamGap 3`）。
    - ⚠️ `cutToneSeam` **必须带地板 `capsuleMinPad = 3`**：每侧最多让到「文字距边还剩 3pt」为止。早年没地板，为挤出缝隙把 pad 一路吃到 0/负数 → 每修一次「标签之间要有缝」就复发一次「文字紧贴边缘」。实测让位后接缝 6pt、两侧 pad 6→4，单个标签（左右是裸文本）完全不被切。
    - 同标记的多个片段（被 pill 切开）不参与收缝。
  * `TokenDocument.adjust` 只剩一条规则：占位符落在替换区间内 → 标记跟着没（区间在前则平移）。插入/删除占位符都走 `Coordinator.insertPlaceholder` / `removeMark`（直接改 `textStorage` 不走 `shouldChangeTextIn`，必须手动 adjust 补 ±1）。
  * 插入后**光标必须跳到占位符之后**，否则打字落在作用域之外。
- ⚠️ overlay 是自绘层的基準：`autoresizingMask=[.flexibleWidth,.flexibleHeight]`，文本变长要 `syncOverlayFrame(forceLayout:)`；空作用域只画徽章不铺胶囊；**徽章统一排队**（`drawBadges` 按「行 → preferredX」推进游标，恒留 `badgeSeamGap=4`，中断也走这条队列画灰徽章）；绘制顺序：胶囊 → pill → 徽章；pill 不铺底色、高 20 垂直居中，文本用 `boundingRect` 量行盒后纵向居中。
- ⚠️ 空作用域回收唯一判据是「非空 → 空」翻转：`isBoundary` + `boundaryEmptiness` 只输出当前空/非空两组 id；`Coordinator` 持 `scopeHadText`+`pendingRemoval`，`refreshScopeStates()` 挂在 `tvDidChangeContent` 最前面（打字/插/删/清空同一路径）。**判据不许掺时序信息**。结果：从未有过内容的标签永不回收，删光后停手 0.35s 回收，期间恢复文本撤回。
- ⚠️ **底部条不能压到 accessory**：SwiftUI 的键盘避让**不一定含 `inputAccessoryView` 那截**（通知里的键盘框有时只有键盘本身），差值还随生命周期变 → 必须实测不能写死。`TokenTextEditor.onKeyboardTopChanged` 报「键盘+accessory 顶边」= `min(键盘框 minY, accessory 窗口框 minY)`（键盘框不在屏内就放弃：收起过程中 accessory 会短暂挂在键盘窗口里，只认它 → 底部条凭空飘起来）；`StudioView` 用 background 里的 `GeometryReader` 量内容底边（`geo.frame(in: .global).maxY - geo.safeAreaInsets.bottom`），差值就是 `keyboardSeam`（夹 0~260）**再加固定间隙 `keyboardSeamGap = 10`**（贴着 accessory 上沿看着像长在键盘上，间隙不参与 max(0) 截断），加在 `generateBar` 的底部 padding 上。⚠️ 只在 `onPreferenceChange`（布局量完）里算：拿键盘升起前的旧底边去减会算出天价。
- ⚠️ **accessory 高度**：容器 `AccessoryContainerView` 高度**由 SwiftUI 上报**（`background(GeometryReader)` + `AccessoryHeightKey` → `config.$contentHeight` → Combine sink 写 `contentHeight`，setter 里 `invalidateIntrinsicContentSize`）；写死常量会把多出的几 pt 裁掉。⚠️ 根视图 `.frame(maxHeight:.infinity, alignment:.top)` 顶对齐（默认居中会把内容顶出容器）。
  - ⚠️ **光 invalidate 不够**：容器是手写 frame 建的（autoresizing 把 frame 翻成宽/高约束），键盘只在弹出那一刻量一次 → `contentHeight.didSet` 里必须**自己改 frame** + `superview?.setNeedsLayout()`，否则 accessory 永远停在初始高度、内容顶对齐 → 底部留一条死空白（2026-10-31 的 30pt 空白就是这么来的）。
  - ⚠️ `AccessoryContainerView.safeAreaInsets` 覆写成 `.zero`：键盘窗口的 bottom inset 会渗给 SwiftUI，内容被顶上去也是同一个症状。
  - 高度常量在 `AccessoryMetrics`（顶部 6 + 控制行 42 + 标签行 38 = 86），`config.contentHeight` 初值 / 容器 init frame / `makeUIView` 的 frame 三处共用；副行不在 body 里就不许算进 baseHeight。
- ⚠️ **「刚点了哪个标签」零成本提示**：accessory 里刚点过的按钮给 `accentSoft` 底 + `accent` 实描边（`config.lastPickedTag`，切分段/中断/清空复位）。⚠️ **别再弹临时浮层提示**（2026-10-31 试过 `onMarkInserted` + `.overlay` 弹 1.3s 胶囊，挡在编辑区正上方，体验差，已全删）。
- 「清空」两入口：文本卡标题行文字按钮 + accessory 🗑（键盘弹出时标题行收成 0 高）。「完成」在底部生成条与「生成音频」同行（完成描边、生成渐变实心）。`TokenEditorStore.hasContent` 门控清空（只看 `charCount` 判不了只插标签）。

## 生成弹窗 / 后台接收 / 播放器
- 开关在 `AppState.showGenerationModal`；macOS 只有 `Views/GenerationOverlay.swift` 订阅 VM（ContentView 本体不订阅）。⚠️ 完成态直接 `hasResult = generatedAudioURL != nil && !isGenerating` 推导，不要 Bool + onChange 中转。⚠️ 浮层 `ZStack` 要 `.frame(maxWidth:.infinity,maxHeight:.infinity)`；计时用自持 Timer(0.5s)，不用 `autoconnect()`。
- `DataReceiveGridView`（Canvas 自绘，`receive(n)` 是真实入口）：列数 `floor((可用宽+间距)/(格宽+间距))`，列间距 `(可用宽−n×格宽)/(n−1)`；跟随 `scrollTo` 的锚点必须零宽；高亮环画在格外（`haloOutset=2`）；`onPreferenceChange(TailFrameKey)` 只在 `followTail` 翻转时写 @State。
- ⚠️ **必须用 `voice.audio` 找 Bundle 资源，不能用 `voice.key`**（key 带前缀 → 恒 nil），统一 `AudioPreviewPlayer.play(voice:)`。⚠️ `playingKey` 存的是 identifier 不是 URL：`isPlaying(url:)` 对自定义 identifier 恒 false，跨页统一用 `playingKey == identifier`，跨 key 用 `reidentify(_:)`。

## iOS 列表 / 分页
- ⚠️ **上拉追加必须先写本地 `page` 再 `syncToVM()`**（反了追加恒为空）；`VoicesLibraryView` 与 `VoicePickerSheet` 两份一致；空页回退 `page = max(1, next-1)`。
- ⚠️ 筛选/搜索变化后必须滚回顶部（`ScrollViewReader` + 顶部 0 高锚点），否则内容变短偏移仍在原处 → 一片空白。
- 音色 Sheet 复用 `VoicesLibraryViewModel`；筛选是 Sheet 私有 @State，**不写回 `AppState.voiceLibrary*`**；分类列表就地替换内容区，不嵌第二层 `.sheet`。
- ⚠️ 项目列表增删：**磁盘 IO 必须在动画事务之外**（`deleteAudio` 拆成磁盘部分 + `removeAudioItem` 纯内存，后者才包 `withAnimation`）。
- ⚠️ 左滑「复制」当前行先消失的根因是主线程被同步 IO 冻住 → 拆 `ProjectService.stageDuplicatedFile`（`nonisolated`，`Task.detached`）+ `finishDuplicate`（主线程写库）；副本插在被操作行**下面**（`insertAudioItem(_:after:)`），`scrollTo` 不带 anchor。
- ⚠️ `stageDuplicatedFile` / `Date.filenameTimestamp` / `generatedAudioDirectoryURL()` / `kGeneratedAudioSubdirectory` 都要 `nonisolated`（MainActor 默认隔离）。重命名用自绘 `RenameDialog`（overlay，非系统 `.alert`）。

## 快捷键 / 积分
- `PlaybackKeyboardShortcuts`：Carbon 热键吞事件 → 监听 `NSText.didBeginEditing/didEndEditing` → `KeyboardShortcuts.disable(all)/enable`。
- 积分全链路 Double（≤2 位）：权威 `CreditManager`，一律过 `CreditPrecision.normalize`（`(v*100).rounded()/100`），**禁止 `Int(ceil())`**；计费 `字符数/100*rate`（普通 2、复刻 5），字符数 `TextSplitter.calculateCharCount`（CJK 算 2）；云端 `user_credits.credits` 必须 `numeric(10,2)`；展示 `formatCredits(_:)`。

## 构建与验证
- 真构建 `bash tools/ios_build.sh`（+ `mac`）；快速类型检查 `bash tools/ios_typecheck/typecheck.sh`。三个 workaround 均为沙箱问题：① `IDEPackageSupportDisableManifestSandbox` ② `OTHER_SWIFT_FLAGS='$(inherited) -disable-sandbox'`（**必须 $(inherited)**）③ `ONLY_ACTIVE_ARCH=YES`。
- ⚠️ `Shims.swift` 有 `VoiceService`/`DatabaseManager`/`ProjectService` 等**业务替身**：给真实类加新方法必须同步加桩。
- 已知既有问题：`CreditsService.swift` 4 条 Swift6 actor 隔离报错；`PackageCardView.swift` 是未入 target 的孤儿文件。
