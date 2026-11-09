# EmotionVoice 长期约定（只留「禁令 / 根因 / 入口」）

细节见 `.workbuddy/memory/YYYY-MM-DD.md`；商店页/预览图版式、本地化、坐标等细节全部见 `产品/商店页/*.md`（本文只留索引）。

## 工程 / 构建
- target `Emora`(macOS) / `iOSEmora`(iOS 18.6)；iOS 独有 `View/iOS/`；复用 macOS 文件**原地加入 iOS target**，`#if canImport(AppKit)` 隔离。新增 iOS .swift 须改 pbxproj 4 处 → **优先塞进已有文件，零 pbxproj 改动**。
- SQLite **永不迁移**：改 `createTables()` 就 bump `currentSchemaVersion`，不符 DROP 重建。
- 构建 `bash tools/ios_build.sh`（`mac` 回归双 target）；类型检查 `bash tools/ios_typecheck/typecheck.sh`（`Shims.swift` 须加桩）；workaround `IDEPackageSupportDisableManifestSandbox`/`-disable-sandbox`/`ONLY_ACTIVE_ARCH=YES`。
- ⚠️ 四配置默认 `SWIFT_DEFAULT_ACTOR_ISOLATION=MainActor`：后台纯计算显式 `nonisolated`（私有 helper 一起加），静态非 Sendable 用 `nonisolated(unsafe)`。Swift 5 违规仅 warning，**验证须 grep 构建日志**。
- macOS 首屏 `.defaultSize(visibleFrame)` + `viewDidMoveToWindow()` 同步配置，禁 `DispatchQueue.main.async` 延迟 setFrame。SPM 缓存报 `unable to read tree` → `git fetch` 补缓存（含 DerivedData 那份），别删目录。

## TTS / 本地化
- 无密钥 `wss://<ref>.supabase.co/functions/v1/bailian-tts?region=CN|INTL`，单条 `{"action":"synthesize"}`；断线不可续传；Deno<2.5 用 `dialUpstream()`。
- `.localized()` 中文原文当 key；⚠️ 禁 `String(format:"…%@…".localized(), arg)`，须 `"…%@".localized(arg)`。
- 三语 zh-Hans/zh-HK/en；⚠️ 改中文 key 须**三份 strings + 两端引用一起改**。仿音色文案在 `<lproj>/VoiceCatalog.strings`；繁体 OpenCC `s2t`+覆写，**别用 s2hk**；繁中商店图按 `zh-HK.lproj` 实际用词、字体 `PingFang TC`。

## 音色 / 标签
- 唯一数据源 `Voices/basic_voices.json`(v4)，改后跑 `tools/gen_basic_voices.py`。语气/拟声标签唯一来源 `Shared/Models/Constants.swift`（`emotions` 24 项、`richLanguageTags` 7 个官方拟声）；⚠️ 商店图禁自造标签。
- 胶囊整条热区 `contentShape(Rectangle())`；刷新过渡用 `contentVisible`，`.id(scrollResetID)` 只管滚回顶部。中断 API 不支持 → `toTTSAPIString()` 丢弃，生成走 `toTTSSegments()` + `AudioConcatenator.merge()`。
- ⚠️ iOS 分类筛选只在进程内保留（`VoiceLibraryFilterStore`），禁读写 `AppState.voiceLibrary*`；⚠️ `VoicesLibraryView`/`VoicePickerSheet` 的 `apply` 取消也要 `commit(fresh,total)`，否则永久空态；另配 `onAppear` 自愈。

## macOS 输入框 / 语气标签
- 入口 `View/macOS/VoiceStudioView/EmotionToken/EmotionTokenTextView.swift`（`toneCapsuleGeometries()` 自绘胶囊）+ `View/macOS/EmotionHighlightedTextEditor.swift`（旧版）；绘制与命中同源（`tokenHitRegions()`）。
- ⚠️ 纯空行必须过滤：AppKit 把 `\n` 单独排成 line fragment，`location(forGlyphAt:)` 返回行底 → 空行胶囊叠出双描边。用 `capsuleInvisibleCharacters`（空白/换行/U+3000/**U+FFFC**）判空后 return，`rects/textRects/lineKeys` 一起跳。
- ⚠️ `boundingRect(forGlyphRange:in:)` 把行尾换行算到容器右边界 → 短行胶囊满宽。须裁掉首尾空白（`capsuleTrimCharacters`，⚠️ 不含 U+FFFC）后 `glyphRange(forCharacterRange:)` 再取 br，只包字形 + 8pt 内边距。
- 视觉 v14（商店页 01.html）：胶囊实色底（`accent` 按 0.28 混进 `#15171B`，`accent = base.darkened(0.48)`）+ 顶部 2pt 亮线、四周不描边、圆角 8；徽章 accent 20% 底/50% 描边/近白字（⚠️ 半透明层下先铺不透明编辑器底色）。⚠️ 别退回 `base.withAlphaComponent` 直叠；选中光环仍用 `base`。

## iOS UI / 编辑器
- `ScreenMetrics` 分档 <375 / 375–659 / 660–1023 / ≥1024；两栏 `width>=740 && isWide`；3 标签+各自导航栈；二级页隐藏 tabBar 由 `TabRouter.isTabBarHidden` 驱动；Sheet 统一 `SheetNavBar`；同层不挂两个 `.alert`。
- ⚠️ iPad：`isPadClass = width>=740 && height>=700`（别用 `sizeClass==.regular`）；两栏编辑卡高度**必须由 GeometryReader 实测** `geo.height-20`，`editorMinHeight` 只兜底；`wideLayout` 只加一层 `.padding(.horizontal,pageMargin)`。
- ⚠️ iPadOS 18 标签栏在顶部、底部无 tabBar：浮层用 `metrics.tabBarClearance`，禁硬写 58。
- ⚠️ 参数面板单一数据源 = `StudioParamSheet.swift` 的 `StudioParamContent`；iPad 侧栏直接铺（高度**必须**钉 `editorHeight`，`sampleRateColumns:2`）、iPhone 走「摘要条 → Sheet」，侧栏宽 360。改控件只改 Content 一处。
- ⚠️ 打字不经过 SwiftUI：`TokenEditorStore`（`doc`/`marks` 非 @Published），三类标记各占 1 个 U+FFFC；accessory 只在 `isDark` 翻转重建；overlay 字段加相等判断才重绘。
- ⚠️ 光标高度 = 正文一行字高：`TokenTextEditor.swift` 的 `TokenCaretTextView` 重写 `caretRect(for:)` 只削 height、保留 super 的 origin；禁改 lineSpacing/typingAttributes 修光标；必须 `usingTextLayoutManager:false`(TextKit 1)。
- ⚠️ iOS `TokenCapsuleOverlay.lineRects()` 判空集合里 **U+FFFC 不算空白**（与 macOS 相反），别互相抄；别改 1pt 宽度兜底。底部条不压 accessory：`onKeyboardTopChanged` 报 min(键盘, accessory) → `keyboardSeam`。

## 播放器 / 订阅隔离（关键）
- ⚠️ 播放器按 target 拆两份同名 `AudioPreviewPlayer`（API 逐字对齐）：macOS 版只挂 Emora、iOS 版只挂 iOSEmora；`typecheck.sh` 的 `MAC_ONLY` 与 `add_ios_target_files.py` 的 `REUSED` 必须排除 macOS 版。
- iOS：AVAudioSession `.playback` + `iOSEmora-Info.plist` 的 `UIBackgroundModes=[audio]`（⚠️ `INFOPLIST_KEY_UIBackgroundModes` 对数组键无效，须 `INFOPLIST_FILE` 模板 + `plutil -extract` 验产物）。⚠️ 封面 `makeArtwork` 全幅不透明渐变（`opaque=true`、禁 `addClip`）。
- ⚠️ iOS 播放/切倍速 CPU 暴涨根因 = SwiftUI 订阅拓扑：`PlaybackStatus` 只订阅单属性 publisher；高频显示只许 6 个小 View 各自 `@ObservedObject`；禁 `@StateObject player`；`ProjectsView.row(_:)` 禁把 progress 传给所有行。
- `playingKey` 存 identifier，跨 key 用 `reidentify(_:)`；⚠️ 并发闭包「外层 `guard let self` + `Task @MainActor`」。iOS `transportRow` 与 macOS `PlayerTransportView` 同构：±15s/±5s 走 `player.skip(by:)`；「从头播放」只在工具行，步长写字面量别抽常量。

## 历史记录 / 列表
- `HistoryListViewModel`(iOS) 一次全量 `fetchAllAudios()` 50/批；`Shared/HistoryViewModel` 属 macOS。
- ⚠️ 收藏与软删绝不入库：`AudioFlagStore`（UserDefaults JSON，30 天），软删只打标，`purgeExpired()` 交 `ProjectService.deleteAudio`。
- 播放跨页保留；`identifier=item.fileName` 经 `NowPlayingStore`。浮层互斥链：撤销 Toast > 后台接收条 > mini player。
- ⚠️ `MiniPlayerView` 品牌渐变底+白字、height=56；`ProjectsView` 按 `miniPlayerVisible` 在 List 末尾插透明占位 Section。卡片进度条只 `scaleEffect(x:,anchor:.leading)`，**绝不自加 `.clipShape`**。
- ⚠️ `.plain` List 必须清零系统留白（`.listSectionSpacing(0)` + `defaultMinListHeaderHeight=0` + `.contentMargins(.top,0)`）；垂直节奏只由 chips 底 10pt + 组头 顶 13/底 7。时间分组按自然日（组头 `yyyy.MM.dd`）。
- **macOS 分组**：全在 `View/macOS/HistoryView/HistoryView.swift` 文件内（`daySections` + `HistoryDaySection`/`HistoryDaySectionHeader`），`LazyVStack(pinnedViews:[.sectionHeaders])` + `Section`，算法照抄 iOS `makeSections`。⚠️ 类型**必须 `HistoryDay*` 前缀**（iOS 已有 `HistorySection`/`HistorySectionHeader`，别放进双 target 共用的 Shared）；⚠️ 保留 `displayedAudios`（批量操作 4 处依赖），VM 零改动；⚠️ 加载更多 ProgressView 只在所有 Section 之后一处；组头用 `AppColor`（iOS 的 `.aurora`/`.screenMetrics` macOS 编译不到）且背景须不透明。⚠️ 组头**不显示「%d 条」计数**（用户要求；三份 strings 的 key 保留给 iOS）。⚠️ `AudioRowItem` **已移除头像**（用户要求腾宽度），名称行右侧放「更多」按钮，第二行「音色名 · 时长 · 文件大小 · HH:mm」**必须一行完整显示**：各字段 `fixedSize` + 整行 `fixedSize(horizontal:true)`；左栏固定 340pt，⚠️ 禁把时分单独放右列 + `Spacer()`（文字列会被压到 ~138pt）。

## 积分 / 生成弹窗 / 参数持久化
- 积分全链路 Double(≤2位)：`CreditPrecision.normalize`，计费 `字符数/100*rate`（普通2/复刻5），CJK 算 2 字符，云端 `numeric(10,2)`。
- `GenerationDialog` 完成态 `displayName = defaultAudioName(...)`；`commitName()` 清空须写 `displayName: nil`；`hasResult = generatedAudioURL != nil && !isGenerating`。⚠️ `PackageCard` 副标题禁 `.lineLimit(1)`。
- `StudioParamValues`/`StudioParamStore` 在 **`Shared/ViewModels/VoiceStudioViewModel.swift`**（零 pbxproj 改动）。键 `studioParam.*`；两端 `onAppear` → `restoreIfNeeded`、4 个 `.onChange` → `save`。
- ⚠️ 禁把 `AppState.defaultFormat`/`defaultSampleRate` 当存储；「重置」两端只调 `reset(on: vm)`，禁传 `defaults` —— 重置 = `.factory`(mp3/22050/1.0x/100%)。默认值一律读 `Constants`/`.factory`；`defaultFormat` 已改 `mp3`，全链路（VM/`BailianTTSService`/云端 `bailian-tts/index.ts`）同步且不覆盖已有存档；`VoiceStudioView.onAppear` 旧的「从设置页覆盖参数」已删，**别加回来**。

## 评分弹窗
- ⚠️ 用户明确要求「**每次 App 打开都弹评分弹窗**」，与 ASO 审计文档「不要在启动时弹」相反，**以用户要求为准，别改回去**。实现在 `Shared/Services/AppUpdateManager.swift` 的 `requestReviewOnEveryOpen()`（共享 ViewModifier，两端根容器各挂一行），**不做任何本地节流**。⚠️ StoreKit 正式版每设备 365 天最多 3 次 / TestFlight 不弹是系统硬限制，代码绕不过。

## 商店页 / ASO（细节全在 `产品/商店页/*.md`）
- Mac：`商店页文案-多语言版本.md` + `素材/gen_previews.py` + `素材/html/{zh,en}/` + `素材/mac-2880x1800/{zh,en}/`，深色 16:10、6 张。⚠️ `素材/raw/` 未被 git 追踪曾被清理，重跑 build 缺源图；可从成片裁 `.win` 区作底图。
- ⚠️ Mac 01 覆盖层 v4.5：`.win` 内叠层、raw 坐标 + 整体 transform scale；**禁铺满**（连续文稿自然换行、删光 letterSpacing/禁 justify），语气徽章只在切换首行、拟声 pill 嵌句中。两端缩放不同：zh `2112/3456` / en **`2122/3442`**；计数积分 wipe 坐标各一套。`--only=01` build/export 都要带；改一语另一语 md5 零回归。
- **Mac 繁体 v3**：入口 `素材/prepare_mac_hant_real.py`（真机源 `mac_hant_real/*.jpg` 只读 → `html/zh-Hant/win-*.png`）+ `gen_mac_hant.py`；细节全在 `Mac预览图-香港繁体中文版分镜.md`。主生成器零改动、中英 12 张零回归。⚠️ 01/02/03/06 四窗全是繁体真机原生 UI，`has_real_06()` 为真时跳过整条覆盖链，`BLOCKS`/`ensure_clean_06`/`detail_fix_overlay` 只作缺图回退，**禁挂贴字层**（双层字）。⚠️ 两种裁法：4 张 1920×1191 带画布用 `(58,39)-(1862,1114)`；`06-projects.jpg` 是 **1920×1145 纯窗口**须整幅缩放（`BOX_BY_SRC`），套 BOX 会裁掉交通灯/左栏/状态栏。01 仍叠 v4.5 `LINES_HANT`，wipe 底色须 `sample_bg()` 动态采样 + 3 处坐标修正（1160→1220 / cr wipe 左移加宽 / credit 左移）。06 半行字清理用整块 `paste` 纯底色条带 y886..908→y963..984，⚠️ 按列取色出竖条纹、铺单色出色带。⚠️ `dominant()` 收 `(x,y,w,h)` 不是 roi、只取暗色；禁无条件注入 `UI_CSS`。⚠️ 全量 export 偶发 04/05 底部 21px 最大 18/255 色差（Chrome 视口边缘，视觉无影响，别 hack CSS）。用词读 `zh-HK.lproj`，s2t 对港式「台/只/才/吃/游/注」误报别改。
- **Mac 简英 06（当前真机 UI）**：简体 `prepare_mac_zh_real.py`（源 `mac_zh_real/06-projects.jpg` 只读 → `html/zh/win-06.png` + 同份 `4.png`）+ `gen_mac_zh06.py --export`；英文 `prepare_mac_en_real.py`（`mac_en_real/06-projects.jpg` → `html/en/win-06.png`）+ `gen_mac_en06.py --export`（`cfg_lang="en"`）。均复用 gp 的 CSS/page_image/export + `only={"06"}`，主生成器零改动、其余 17 张 md5 零回归。文档 `Mac预览图-{简体中文,英文}06真机图更新.md`。⚠️ 三语源图都是**纯窗口须整幅缩放**，禁套繁体 A 类 `(58,39)-(1862,1114)` BOX；英文源高 **1143**（简繁 1145），别为凑数拉伸/补边。⚠️ **半行字处理三语不同**：简体图无半行字、繁体图已清理（y886..908→963..984）、**英文图用户明确要求保留原样，禁清理/禁贴字**（别抄繁体 `clean_card_bottom()`）。⚠️ 禁全量跑主生成器 / 禁往 `raw/` 塞源图；英文 `.win` 已从 2104 统一 2112。旧成片带橙色头像属早期 UI，别恢复。
- iOS iPhone：元数据 `iOS商店页元数据-6语言.md` + `ios-store-copy/`；预览图 `gen_ios_previews.py` + `ios-1320x2868/<locale>/`。名称/副标题 30 / 关键词 100 字符含逗号、逗号后不加空格；四英文区名称副标题共用、关键词四套独立。
- ⚠️ iOS 端没有声音复刻/克隆 UI；字幕禁写具体能力数量。尺寸：6.9" `1320×2868`(禁 alpha) / iPad 13" 横屏 `2752×2064`(竖屏未做) / Mac `2880×1800`。iPhone 版式 v2.2 Aurora Pop（Sheet `zoom:1.22`）；⚠️ 流程须带 **`--html-only --export`**，漏了会覆盖真机图；02 是真机、其余 5 张设计稿不可提审；en-GB/AU/CA 复用 en-US。多本地化 `EN_DICT`/`HANT_DICT` 运行时解析 App strings，数字与单位是分开的文本节点。
- ⚠️ iPad 横屏真机版：入口 `ios_previews_ipad/real/<locale>/`(只读) → `prepare_ipad_real.py` → `gen_ios_previews_ipad.py --locale --export`，三语，缺真机图**跳过**而非回退自绘。5 张固定（创作参数/音色库/创作指令/播放/历史），创作页三态同界面。⚠️ 每批新截图必须拼索引图核对编号；`prepare()` 三条独立分支（zh-Hans 原路径 / en-US `localize_en()` / zh-Hant `localize_hant()`），**禁把 zh-Hant 塞进 `localize_en()`**；`render_cards()` 简体默认参数逐字节不变，改一语另两语 md5 零回归。
