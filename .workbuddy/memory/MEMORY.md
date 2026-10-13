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

## 构建与验证
- 本机 `xcodebuild` 会被沙箱挡住包解析（`sandbox-exec: Operation not permitted`）
- 替代方案：用 `swiftc -typecheck -disable-sandbox -swift-version 5 -target arm64-apple-macos14.0
  -sdk $(xcrun --sdk macosx --show-sdk-path) -I <DerivedData>/Build/Products/Debug @filelist`
  （`-disable-sandbox` 必须加，否则 SwiftUI 宏插件服务报错）
- 改代码前先对 HEAD 跑一次同样命令拿基线，再对比，避免被既有报错干扰
- 已知既有问题：`CreditsService.swift` 有 4 条 Swift6 actor 隔离报错；
  `PackageCardView.swift` 是未加入 target 的孤儿文件，`CreditsPackage` 类型不存在
