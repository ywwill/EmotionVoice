# EmotionVoice 项目长期约定

## 技术栈
- macOS 原生 App，Swift + SwiftUI + Swift 5
- 依赖：SQLite.swift、supabase-swift、keychain-swift（SPM）
- 数据库：SQLite，文件放在用户 Documents 目录 `emotionvoice.sqlite3`（方便调试）
- 本地化：`zh-Hans.lproj` / `en.lproj` 各一份 `Localizable.strings`，跟随系统语言，无 App 内切换

## 本地化约定
- `.localized()` 扩展（`Extension/String+Extension.swift`）：**用中文原文当 key**，
  找不到 key 时 `NSLocalizedString` 原样返回，所以中文界面天然是兜底
- 动态拼接必须用格式化占位符，不要拼好整串再 `.localized()`：
  ✅ `"%@ · 旗舰音色".localized(name)`　❌ `"\(name) · 旗舰音色".localized()`
- 音色名/特质文案在 `zh-Hans.lproj` / `en.lproj` 的 **`VoiceCatalog.strings`**
  （已通过 PBXVariantGroup 加入 target）：key 为 `voice.<stem>.name` / `voice.<stem>.feature`，
  `<stem>` = 音色 key 去掉 `qwen-audio-3.0-tts-plus-` 前缀（= audio 文件名去扩展名）。
  代码侧用 `VoiceCatalog.localizedVoiceName/Feature(stem:language:)` 强制按语种读取。

## 音色目录（Voice Catalog）
- 唯一数据源：`EmotionVoice/EmotionVoice/Voices/basic_voices.json`（**v4 schema**）
- **铁律：JSON 只存语言无关的语义 code 与稳定 key，任何文案（名/特质）外置到 `VoiceCatalog.strings`**
  - 数据字段：`idx`(便捷整数 id，旗舰 1/2、基础 3 起；也是 DB 主键)、`key`、`tier`、`lang`、
    `gender`、`age`、`scene`、`audio`
  - 本地化 key：`voice.<stem>.name` / `voice.<stem>.feature`，stem = `key` 去 `qwen-audio-3.0-tts-plus-`
    前缀（= audio 文件名去扩展名）
  - `tier`: premium|basic　`lang`: zh|en　`gender`: female|male|unknown
  - `scene`: daily|companion|reading|customer_service|social|anime|news|live_stream|
    classic_audiobook|sports|audiobook|radio|knowledge|comedy|business|assistant|speech
- 筛选一律基于 code 列（`tier`/`lang_code`/`scene_key`/`age`/`gender_code`），
  禁止用中文字符串做 WHERE 匹配——否则切语言就失效；**搜索下沉内存**
  （按本地化名/特质/场景名/语种名匹配，顺带支持拼音搜索）
- 改了 JSON 后跑 `python3 tools/gen_basic_voices.py`（幂等，文案来自已提交 strings）；
  加新语言只需新增一个 `.lproj/VoiceCatalog.strings`，JSON / DB 都不用动
- `DatabaseManager`：voices 表**零文案列**（`idx` 主键、`key` 唯一 + 6 个 code 列 + `audio` + `is_favorite`）
- **数据库策略：不做真正迁移，永久采用「结构版本不符就 DROP 全部表重建」**
  （`resetDatabaseIfSchemaChanged`：改了 `createTables()` 任何列就把 `currentSchemaVersion` +1，
  启动时比对 `UserDefaults` 存的版本，不符则删 audio_items/voices/consumption_records/purchaseRecords 四表重建）
  - 用户明确**不需要迁移**；接受上线后 bump 版本会清空本地全部表数据——
    隐含前提：audio_items / consumption_records / purchaseRecords 要么是本地可再生缓存，
    要么有服务端兜底，而非唯一真相源
  - 与音色数据同步正交：`currentFingerprintVersion` + `voiceCountKey`（UserDefaults）只管
    `voices` 表内容是否需从 `basic_voices.json` 刷新；结构重建时会一并清掉这两个键强制重刷

## 快捷键（KeyboardShortcuts 包）
- 播放快捷键用 `sindresorhus/KeyboardShortcuts`（SPM），代码在
  `Views/HistoryView/PlaybackKeyboardShortcuts.swift`：
  `@MainActor` 单例 `PlaybackShortcutsController` + 7 个 `KeyboardShortcuts.Name`
  （空格 / ← / → / ⇧← / ⇧→ / Home / End，`initial:` 给默认值）
- **该包用 Carbon 热键（`RegisterEventHotKey`），不是 NSEvent monitor，会吞掉按键事件**：
  事件在派发到 App 之前就被截走，所以"在回调里判断一下再决定做不做"救不回输入框
  （等回调跑起来空格已被吃掉，搜索框打不出空格）。
  挡输入框必须**反向做**：监听 `NSText.didBeginEditingNotification`/`didEndEditingNotification`，
  开始编辑 → `KeyboardShortcuts.disable(all)`，结束 → `enable` 回来。
- 同理：没在播（`player.playingKey == nil`）时 disable 掉 ←→/Home/End，把方向键还给列表滚动/行导航。
- 包回调本身已在主线程（包内部自己 `MainActor.assumeIsolated`），但从非隔离闭包调 @MainActor 方法
  仍要在闭包边界再套一层 `MainActor.assumeIsolated` 才能过编译。
- 热键是 App 内全局（`GetEventDispatcherTarget()`），不会抢别的应用的键。

## 积分体系（2026-10-16 起：全链路 Double，最多 2 位小数）
- **记账单位**：`CreditManager` 是唯一权威（`balance` 走 UserDefaults + Supabase 同步），
  `CreditsService`（Services）是门面，`CreditService`（Store）是旧校验封装。
- **精度铁律**：所有余额/消耗都过 `CreditPrecision.normalize`（`(v*100).rounded()/100`）；
  浮点比较统一加 `1e-9` 容差。**禁止再引入 `Int(ceil(...))` 这类向上取整**——
  用户明确要求按实际消耗计费，短文本就是零点几分。
- **计费公式**：`字符数 / 100 * rate`（普通 rate=2，复刻 rate=5），**没有起扣门槛**。
  字符数用 `TextSplitter.calculateCharCount`（CJK 一个字算 2）。
- **云端约束**：`user_credits.credits` 必须是 `numeric(10,2)`，否则小数写不进去。
- 展示统一用全局 `formatCredits(_: Double)`（整数不给小数位，否则最多 2 位）。

## 构建与验证
- 本机 `xcodebuild` 会被沙箱挡住包解析（`sandbox-exec: Operation not permitted`）
- 替代方案：用 `swiftc -typecheck -disable-sandbox -swift-version 5 -target arm64-apple-macos14.0
  -sdk $(xcrun --sdk macosx --show-sdk-path) -I <DerivedData>/Build/Products/Debug @filelist`
  （`-disable-sandbox` 必须加，否则 SwiftUI 宏插件服务报错）
- 改代码前先对 HEAD 跑一次同样命令拿基线，再对比，避免被既有报错干扰
- 已知既有问题：`CreditsService.swift` 有 4 条 Swift6 actor 隔离报错；
  `PackageCardView.swift` 是未加入 target 的孤儿文件，`CreditsPackage` 类型不存在

## EmotionTokenEditor 标签 UI（2026-10-16 起：语气胶囊版 v13，已取代 10-14 的下划线版）
- 语气标签 = **作用域整段同色胶囊**（fill 13%、1px 内描边 42%、圆角 9、内边距 8×6）
  + **emoji/名称徽章压在胶囊左上角**（10.5pt 粗体、底色取编辑器背景、只在首块出现）；
  拟声 = 虚线 pill（12pt、圆角 6、内边距 7×1.5、悬停正中浮 ×），嵌在胶囊内不打断语气。
- **绘制顺序铁律**（`EmotionTokenTextView.draw(_:)`）：胶囊 → **徽章** → `super.draw`。
  ⚠️ 徽章必须在 `super.draw` **之前**：实测 super.draw 返回后裁剪被收窄到文本容器区域
  （container origin 起），徽章画在容器上沿之外（container y 为负）会整块被裁掉。
  徽章提前画是安全的——它不与任何字形相交（底边比首行字形顶端还高 1.5pt）。
  配套：`tokenView.drawsBackground = false`（NSTextView 默认背景会盖掉胶囊）。
  `textContainerInset.height = 28`、`bodyAttributes.lineSpacing = 28`。
- 语气标记 cell 是 **5×1 的不可见占位**（`toneMarkerWidth = 5`）：这 5pt 是相邻两个语气作用域
  之间唯一的物理间距，靠它 `resolveCapsuleSeams` 才切得出 `capsuleSeamGap = 2` 的净间隙。
  胶囊/徽章全由文本视图自绘（几何见 `toneCapsuleGeometries()`，绘制与命中同一份）。
  拟声 pill 绘制时左右各内缩 `soundEdgeInset = 3`（advance 不变），给胶囊留收尾空间。
- 悬停区 = 字形 ∪ × ∪ 徽章 ∪ 整段胶囊；小手光标**不含**胶囊（正文要保持 I 型）。
- 几何陷阱：`boundingRect(forGlyphRange:)` 高度是整行高，只有 x/width 可信；
  同一行判据用 `lineRect.minY`（不是 rect.minY，胶囊 28.5 vs pill 17 差 7pt）；
  行首/行尾片段要夹进容器边界；空作用域要补兜底胶囊。详见该目录 README。
- 离屏几何测试可调 internal `EmotionTokenTextView.debugToneCapsuleGeometry()`。

## EmotionTokenEditor 标签 UI（2026-10-14 优化）
- 插入的标签（EmotionToken）**按情感着色**：基础色来自 `EmotionTokenStyle.colorMap`
  （英文 tag → NSColor，对齐 Constants 的 emotions/richLanguageTags 与 AppColor 情感色）；
  未命中的 tag 走「确定性色相回退」`NSColor(hue:saturation:brightness:)`，色相由字符串哈希算出，**进程稳定**（不用 Swift 随机化 hash）。
- **标签家族** `EmotionCategory`（emotion / richLanguage）贯穿：
  `EmotionToken.category` → `EmotionTokenEditor.insertTokenCategory` → `EmotionTokenTextView`。
  `richLanguage`（拟声类）用**虚线描边**与「语气类」实线区分。
- **外观感知配色**：文件级 `nonisolated(unsafe) var kEmotionAttachmentIdentity`（基础色+家族），
  绘制时由 `EmotionTokenStyle.resolved(for:dark:)` 结合 `controlView.effectiveAppearance`
  实时解析出暗/亮两套配色，**解决了 README 里 light mode 待改进**（不再写死单一琥珀色）。
- `EmotionTokenStyle.default` 只描述**几何**，绘制用 `resolved` 沿用其几何只覆盖颜色——保证 `cellSize()` 与 `drawPill()` 尺寸一致。
- **× 删除按钮交互（第二波优化，已接入 hover tracking）**：
  - 文件级 `nonisolated(unsafe) var kEmotionAttachmentHovered: NSTextAttachment?`（单例悬停指针，替代原未生效的 `kEmotionAttachmentDeleteHoverStates` 字典）。
  - `EmotionTokenTextView` 在 `isEditable` 时加 `NSTrackingArea(.mouseMoved, .activeInActiveApp, .inVisibleRect)`，override `mouseMoved/mouseExited` 做命中测试（`textContainerOrigin` 修正坐标）+ 设 `kEmotionAttachmentHovered` + 指针手型光标（悬停 tag 用 pointingHand，否则 iBeam）。
  - cell 行为：`×` **仅在可编辑时绘制**；悬停/选中时实心高亮，空闲时 alpha 0.35 弱提示；pill 在悬停/选中时抬升填充；选中态描边加粗到 1.5。只读（预览）场景不加追踪区、不画 ×，标签完全静止。
- `EmotionTokenPayload` 已含 `category` 字段（Codable 默认 .emotion，向后兼容旧附件）。
