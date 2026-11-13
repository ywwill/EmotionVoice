//
//  AppUpdateManager.swift
//  EmotionVoice
//
//  App 检查更新（iOS / macOS 共用）
//
//  数据源：Supabase `app_updates` 表（一个平台一行，见 supabase/sql/app_updates.sql）。
//  两条入口、两套 UI：
//    - `checkForUpdateAtLaunch()`  启动静默检查 → `availableUpdate` → 顶部横幅（**只有这条**会出横幅）
//    - `checkForUpdateManually()`  设置页手动检查 → `manualResult` / `presentedUpdate` → 弹窗（不出横幅）
//  `force_update = true` 时：启动即弹、关不掉（`presentedUpdate`），并且**不出横幅**；
//  界面上不出现「强制更新」之类的文案，只靠「弹窗没有出口」表达。
//
//  ⚠️ 只依赖 publishable key + anon select 策略，不需要用户登录。
//

import Foundation
import Combine
import SwiftUI
import StoreKit

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

// MARK: - App Store 链接

/// ⚠️ 跳转 URL 只用 `https://apps.apple.com/app/id<id>`：
/// - **不能带 storefront**（`/cn/app/...`）：实测带 storefront 会跳不到对应 App；
/// - **不能带 `?mt=12`**：macOS 的旧写法，iOS 会落到错误页面。
/// 而且这个坑 `curl` 验证不出来 —— 无 UA + CN 出口 IP 会被 302 到 `/cn` 首页，
/// 看起来「正常」，真机却跳不到。所以别再往 URL 上拼任何多余参数。
enum AppStoreLink {

#if os(macOS)
    /// macOS（Emora for Mac）
    static let appID = "6814391961"
#else
    /// iOS（Emora）
    static let appID = "6829576429"
#endif

    static var url: URL {
        URL(string: "https://apps.apple.com/app/id\(appID)")!
    }

    static func open() {
#if os(macOS)
        NSWorkspace.shared.open(url)
#else
        UIApplication.shared.open(url)
#endif
    }
}

// MARK: - 平台标识

enum AppUpdatePlatform {

    /// 与 `app_updates.platform` 的取值一一对应
    static var current: String {
#if os(macOS)
        "macos"
#else
        "ios"
#endif
    }
}

// MARK: - 版本比较

enum AppVersion {

    /// 按「数字段」逐段比较：`1.2.0` < `1.2.1` < `1.10.0`。
    /// 缺失的段按 0 处理（`1.2` == `1.2.0`）；
    /// 非数字部分只当作分隔符（`v1.2.0`、`1.2.0 (123)` 都能解析）。
    static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let l = segments(lhs)
        let r = segments(rhs)
        let count = max(l.count, r.count)

        for index in 0..<count {
            let a = index < l.count ? l[index] : 0
            let b = index < r.count ? r[index] : 0
            if a != b {
                return a < b ? .orderedAscending : .orderedDescending
            }
        }
        return .orderedSame
    }

    private static func segments(_ version: String) -> [Int] {
        var result: [Int] = []
        var digits = ""

        for character in version {
            if character.isNumber {
                digits.append(character)
            } else if !digits.isEmpty {
                result.append(Int(digits) ?? 0)
                digits = ""
            }
        }
        if !digits.isEmpty { result.append(Int(digits) ?? 0) }

        return result
    }
}

// MARK: - 更新信息

/// 一条可用的更新（已经从 `app_updates` 里挑出当前平台那一行）
struct AppUpdateInfo: Identifiable, Equatable {

    /// 线上版本号，如 `1.2.0`
    let version: String
    /// `force_update`：弹窗不可关闭、不出横幅，界面文案上不提示「强制」
    let forceUpdate: Bool
    /// 语言 → 更新条目。键用 lproj 名（zh-Hans / zh-HK / en），也接受 `*` 兜底
    let notes: [String: [String]]

    var id: String { version }

    /// 当前 App 语言对应的那组更新条目；找不到就逐级兜底
    var localizedNotes: [String] {
        let wanted = AppUpdateLanguage.current

        if let exact = notes[wanted], !exact.isEmpty { return exact }

        // 只差地区变体时（zh-Hant / zh-TW / zh 都算一类）退到同语种的第一组
        let prefix = wanted.hasPrefix("zh") ? "zh" : wanted
        if let fuzzy = notes.first(where: { $0.key.lowercased().hasPrefix(prefix.lowercased()) })?.value,
           !fuzzy.isEmpty {
            return fuzzy
        }

        if let fallback = notes["*"], !fallback.isEmpty { return fallback }
        return notes.values.first ?? []
    }
}

enum AppUpdateLanguage {

    /// 归一成 lproj 名，供 `AppUpdateInfo.localizedNotes` 匹配。
    /// 工程里只有 zh-Hans / zh-HK / en 三套，其余语言一律按英文展示。
    static var current: String {
        let code = (Bundle.main.preferredLocalizations.first ?? "en").lowercased()
        guard code.hasPrefix("zh") else { return "en" }
        let isTraditional = code.contains("hk") || code.contains("tw") || code.contains("hant")
        return isTraditional ? "zh-HK" : "zh-Hans"
    }
}

// MARK: - 检查结果

enum AppUpdateCheckResult: Equatable {

    /// 还没查过
    case idle
    /// 正在查
    case checking
    /// 和服务端一致
    case upToDate(current: String)
    /// 有新版本（弹窗已经弹出来了，这里只用于设置页提示）
    case updateAvailable(AppUpdateInfo)
    /// 本地版本**高于**线上（待发布 / 灰度包）。
    /// 界面上一律按「已是最新版本」呈现 —— 用户不需要知道「领先」这回事。
    case localAhead(local: String, remote: String)
    /// 拉取失败（离线、表还没建、RLS 没开……）
    case failed(reason: String)
}

// MARK: - 更新管理器

@MainActor
final class AppUpdateManager: ObservableObject {

    static let shared = AppUpdateManager()

    // MARK: 对外状态

    /// 启动静默检查发现的更新 → 顶部横幅
    @Published private(set) var availableUpdate: AppUpdateInfo?

    /// 需要弹窗的更新（手动检查命中 / 强制更新）→ 更新详情弹窗。
    /// 写成 `var` 是因为要绑 `.sheet(item:)`。
    @Published var presentedUpdate: AppUpdateInfo?

    /// 手动检查的状态 → 设置页那一行 + 脚注
    @Published private(set) var manualResult: AppUpdateCheckResult = .idle

    // MARK: 内部状态

    /// 用户主动关掉横幅（只对非强制更新生效；强制更新靠 `forceUpdate` 忽略这个标记）
    /// ⚠️ 必须 `@Published`：`showsBanner` 是读它算出来的，普通存储属性改了不会发
    ///    objectWillChange，横幅就会「点了 ✕ 完全没反应」。
    @Published private var bannerDismissed = false

    private init() {}

    // MARK: 派生状态

    /// 本地版本号（由 target 的 `CFBundleShortVersionString` 决定）
    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    var isChecking: Bool { manualResult == .checking }

    /// 横幅是否显示：有更新、没被关掉，且**不是**强制更新。
    /// ⚠️ `force_update` 时横幅一律不出现 —— 那种情况只需要那个关不掉的弹窗，
    ///    再叠一条横幅反而让用户以为「关掉横幅就没事了」。
    var showsBanner: Bool {
        guard let info = availableUpdate, !info.forceUpdate else { return false }
        return !bannerDismissed
    }

    // MARK: 启动检查（静默）

    /// 启动时调用：只更新横幅，不打扰用户；命中强制更新则直接弹窗。
    /// 失败静默忽略（离网、表未建都不该影响冷启动）。
    func checkForUpdateAtLaunch() async {
        do {
            guard let record = try await fetchRecord(), !record.version.isEmpty else { return }

            let local = currentVersion
            guard AppVersion.compare(record.version, local) == .orderedDescending else {
                Log(messageType: "AppUpdate", message: "启动检查：本地 \(local) 不落后于线上 \(record.version)")
                return
            }

            let info = AppUpdateInfo(version: record.version,
                                     forceUpdate: record.forceUpdate,
                                     notes: record.notes)

            if info.forceUpdate {
                // 强制更新：只弹窗，**不写横幅状态**（横幅在强制场景一律不出现）
                presentedUpdate = info
            } else {
                availableUpdate = info
                bannerDismissed = false
            }

            Log(messageType: "AppUpdate", message: "启动检查：发现新版本 \(info.version)（本地 \(local)，强制 \(info.forceUpdate)）")
        } catch {
            Log(messageType: "AppUpdate", message: "启动检查跳过：\(error.localizedDescription)")
        }
    }

    // MARK: 手动检查

    /// 设置页「检查更新」：结果写进 `manualResult`，有新版本时直接弹窗。
    /// ⚠️ **完全不碰 `availableUpdate`**：顶部横幅只属于启动静默检查。
    ///    之前这里也写了 `availableUpdate = info`，于是在设置页点一下「检查更新」，
    ///    弹窗关掉后首页就凭空冒出一条横幅 —— 用户没重启过，不该看到启动提示。
    func checkForUpdateManually() async {
        guard !isChecking else { return }
        manualResult = .checking

        do {
            guard let record = try await fetchRecord(), !record.version.isEmpty else {
                manualResult = .failed(reason: "empty")
                return
            }

            let local = currentVersion
            let info = AppUpdateInfo(version: record.version,
                                     forceUpdate: record.forceUpdate,
                                     notes: record.notes)

            switch AppVersion.compare(record.version, local) {
            case .orderedDescending:
                manualResult = .updateAvailable(info)
                presentedUpdate = info

            case .orderedSame:
                manualResult = .upToDate(current: local)

            case .orderedAscending:
                manualResult = .localAhead(local: local, remote: record.version)
            }

            Log(messageType: "AppUpdate", message: "手动检查：本地 \(local) / 线上 \(record.version)")
        } catch {
            manualResult = .failed(reason: error.localizedDescription)
            Log(messageType: "AppUpdate", message: "手动检查失败：\(error.localizedDescription)")
        }
    }

    // MARK: 用户动作

    /// 关掉顶部横幅（强制更新本来就不出横幅，这里再挡一道保险）
    func dismissBanner() {
        guard availableUpdate?.forceUpdate != true else { return }
        bannerDismissed = true
    }

    /// 关掉更新弹窗（强制更新时无效）
    func dismissPresentedUpdate() {
        guard presentedUpdate?.forceUpdate != true else { return }
        presentedUpdate = nil
    }

    /// 跳 App Store。非强制更新顺手收起弹窗；强制更新保持拦截，回来还在。
    func openAppStore() {
        AppStoreLink.open()
        if presentedUpdate?.forceUpdate != true {
            presentedUpdate = nil
        }
    }

    // MARK: 网络

    private func fetchRecord() async throws -> AppUpdateRecord? {
        // 真正的 PostgREST 查询放在 `SupabaseManager` 里：这里是纯状态机 + 版本比较，
        // 不直接依赖 supabase-swift，`tools/ios_typecheck` 才能完整检查本文件。
        let rows = try await SupabaseManager.shared.fetchAppUpdate(platform: AppUpdatePlatform.current)
        return rows.first
    }
}

// MARK: - 服务端行模型

/// `app_updates` 的一行（`SupabaseManager.fetchAppUpdate` 的返回元素）
struct AppUpdateRecord: Decodable {

    let platform: String
    let version: String
    let forceUpdate: Bool
    let notes: [String: [String]]

    enum CodingKeys: String, CodingKey {
        case platform
        case version
        case forceUpdate = "force_update"
        case notes = "release_notes"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        platform = (try? container.decode(String.self, forKey: .platform)) ?? ""
        version = try container.decode(String.self, forKey: .version)
        // 早期手填数据可能漏了这列，缺省按「不强制」处理
        forceUpdate = (try? container.decode(Bool.self, forKey: .forceUpdate)) ?? false
        notes = Self.decodeNotes(from: container)
    }

    /// `release_notes` 是 jsonb，Dashboard 里可能被写成三种样子，都要能读：
    /// ① `{"zh-Hans": ["…"], "en": ["…"]}`（推荐）
    /// ② `["…", "…"]`                        —— 单语言，当成 `*`
    /// ③ `{"zh-Hans": "…\n…"}`               —— 换行分段
    private static func decodeNotes(from container: KeyedDecodingContainer<CodingKeys>) -> [String: [String]] {
        if let keyed = try? container.decode([String: [String]].self, forKey: .notes) {
            return keyed
        }
        if let list = try? container.decode([String].self, forKey: .notes) {
            return ["*": list]
        }
        if let text = try? container.decode([String: String].self, forKey: .notes) {
            return text.mapValues { raw in
                raw.components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
            }
        }
        return [:]
    }
}

// MARK: - 每次打开 App 申请评分
//
// ⚠️ 两个平台**入口不同**，别互相抄：
//   - iOS：下面这个 `RequestReviewOnOpenModifier`，挂在根容器上；
//   - macOS：`LaunchReviewRequester`（文件末尾），由 `applicationDidFinishLaunching` 触发。
//     macOS 上没有挂修饰符 —— 那边必须等「窗口上屏 + App 前台」再申请，
//     否则请求会被 StoreKit 挂起并反复投递，表现成一次启动弹好几个评分弹窗。

/// 挂在根容器上：**每打开 `ReviewRequestGate.openInterval`（=3）次 App** 申请一次
/// App Store 评分（**仅 iOS 使用**）。
///
/// 产品口径：启动次数跨启动持久化在 `UserDefaults`（`review.launchCount`），
/// 只在第 3、6、9… 次打开时申请；退到后台但没退出 App，再回到前台
/// **不计数、也不再重复弹**。所以这里不跟着 `scenePhase` 反复申请，
/// 进程内也只判断一次（频率上限另有 StoreKit 自己的配额）。
///
/// ⚠️ `requestReview()` 只是向系统「申请」评分，弹不弹由 StoreKit 决定：
///   - 开发签名 / DEBUG：每次调用都会弹（方便调试）；
///   - TestFlight：不弹；
///   - App Store 正式版：每设备每 365 天最多 3 次，代码无法绕过这个上限。
///
/// ⚠️ 一次性标记必须放**进程级**（`ReviewRequestGate` 的静态量），不能放 `@State`：
///   - iOS 上系统浮层（评分面板自己、控制中心、来电、系统权限弹窗、App 切换器）
///     都会让 `scenePhase` 走 `active → inactive → active`。旧实现把「本次已申请」
///     存在 `@State` 里，且只要离开 active 就复位 —— 于是变成
///     「弹 → 面板让 App 失活 → 关面板回 active → 再弹」的连环弹窗，
///     这正是 iOS 上出现多个评分弹窗的根因；
///   - iPad 多窗口 / 场景重建会生成多份根视图，各自的 `@State` 互不可见，
///     同样会在同一次启动里各申请一遍。
private struct RequestReviewOnOpenModifier: ViewModifier {
    @Environment(\.requestReview) private var requestReview
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            // 冷启动：根视图一上屏就排一次（此刻场景往往还没 active，靠 1s 延迟等它就位）
            .task { scheduleReviewIfNeeded() }
            // 兜底：首次上屏时场景若还没 active、上面那次被 StoreKit 静默丢弃，
            // 就在第一次真正 active 时补排一次。闸门是进程级的，两个入口不会叠加；
            // 之后的后台↔前台再也不会触发第二次。
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                scheduleReviewIfNeeded()
            }
    }

    private func scheduleReviewIfNeeded() {
        guard ReviewRequestGate.claim() else {
            // 一次启动里 `.task` 与 scenePhase 可能各来一次，第二次在这里被挡住
            Log(message: "评分申请：本进程已申请过，忽略本次触发")
            return
        }
        // 冷启动瞬间场景还没 active，StoreKit 会静默丢弃这次申请
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1))
            Log(message: "评分申请：调用 requestReview()")
            requestReview()
        }
    }
}

/// 进程级闸门：整个 App 生命周期（= 一次启动）**只判断一次**，判断通过才放行评分申请。
///
/// 规则：每打开 App 都把 `UserDefaults` 里的 `review.launchCount` 加一，
/// 只有累加到 `openInterval`（=3）的整数倍时才返回 `true` —— 即「每打开 3 次弹一次」。
/// 计数在**首次被问到**时自增，一次启动只增一次，所以 `.task` 与 `scenePhase`
/// 两个入口不会把同一次启动记成两次。
///
/// `nonisolated(unsafe)`：只在主线程（SwiftUI 的 `.task` / `.onChange`、AppKit 的
/// `applicationDidFinishLaunching`）读写，一个 Bool 不存在撕裂风险；
/// 加它只是为了绕开默认 MainActor 隔离在闭包里的调用限制。
private enum ReviewRequestGate {
    /// 每打开这么多次 App 申请一次评分
    nonisolated static let openInterval = 3
    /// 启动次数键：跨启动持久化，卸载重装才会清零
    nonisolated static let launchCountKey = "review.launchCount"

    /// 本次进程是否已判断过（一次启动只判断一次，之后全部拒绝）
    nonisolated(unsafe) private static var decided = false

    /// 抢占一次申请名额：本次启动若正好是第 3/6/9… 次打开，首次调用返回 `true`；
    /// 同一次启动内再次调用永远 `false`。
    nonisolated static func claim() -> Bool {
        if decided { return false }
        decided = true

        let defaults = UserDefaults.standard
        let launchCount = defaults.integer(forKey: launchCountKey) + 1
        defaults.set(launchCount, forKey: launchCountKey)

        let shouldAsk = launchCount % openInterval == 0
        if !shouldAsk {
            Log(message: "评分申请：第 \(launchCount) 次打开，每 \(openInterval) 次才申请，本次跳过")
        }
        return shouldAsk
    }
}

#if os(macOS)
// MARK: - macOS：启动完成后申请一次评分

/// macOS 侧的评分申请入口（**全平台唯一调用点**，不再挂 SwiftUI 修饰符）。
///
/// 为什么不复用 `RequestReviewOnOpenModifier`：
/// - macOS 的评分必须由一个真实窗口的 `NSViewController` 发起
///   （`AppStore.requestReview(in:)`），SwiftUI 的环境动作在窗口还没成为 key 时
///   只是把请求挂起，等下一次激活才展示 —— 请求一旦挂起就会被反复投递，
///   用户看到的就是「一次启动弹好几次」；
/// - 修饰符挂在根视图上，`.task` / `scenePhase` 两个入口都会触发申请，
///   而「启动完成」这个时机在 AppKit 里有确定的信号（窗口上屏 + App 激活）。
///
/// 现在的口径：`applicationDidFinishLaunching` 排队 → 等「已有前台窗口」→ 只调一次。
/// 拿不到前台窗口就**不申请**（宁可这次不弹，也不把请求排进 StoreKit 的待展示队列）。
@MainActor
enum LaunchReviewRequester {

    /// 进程内只排队一次（`ReviewRequestGate` 再兜一层，防其它入口重复申请）
    private static var scheduled = false

    static func requestOnceAfterLaunch() {
        guard !scheduled else { return }
        scheduled = true
        guard ReviewRequestGate.claim() else { return }

        Task { @MainActor in
            // 最多等 20 秒：首帧 → 窗口上屏 → App 成为前台。
            // 三个条件必须**同时**成立才申请：StoreKit 在 App 非前台时只会把请求挂起，
            // 挂起的请求会在之后的每次激活时被重新投递 —— 这就是「一次启动弹好几次」。
            for _ in 0..<200 {
                if NSApp.isActive, let controller = presentingController() {
                    // 首屏还在铺（更新检查 / 骨架 / 窗口淡入）时先让一段，别和首帧抢绘制
                    try? await Task.sleep(for: .milliseconds(500))
                    guard NSApp.isActive else { continue }
                    Log(message: "评分申请：启动完成，requestReview(in:) 只调一次")
                    AppStore.requestReview(in: controller)
                    return
                }
                try? await Task.sleep(for: .milliseconds(100))
            }
            Log(message: "评分申请：20 秒内 App 未在前台就绪，放弃本次（不排进待展示队列）")
        }
    }

    /// 发起评分所需的宿主控制器：优先 key / main 窗口，其次任意可见窗口
    private static func presentingController() -> NSViewController? {
        var candidates: [NSWindow] = []
        if let key = NSApp.keyWindow { candidates.append(key) }
        if let main = NSApp.mainWindow, main !== NSApp.keyWindow { candidates.append(main) }
        candidates.append(contentsOf: NSApp.windows.filter { $0.isVisible })
        for window in candidates {
            if let controller = window.contentViewController { return controller }
        }
        return nil
    }
}
#endif

extension View {
    /// 每打开 3 次 App 向系统申请一次 App Store 评分（次数跨启动计数）。**仅 iOS 使用**：
    /// macOS 走 `LaunchReviewRequester`（`applicationDidFinishLaunching`）。
    /// 后台↔前台来回切既不计数也不会再申请，见 `RequestReviewOnOpenModifier`。
    func requestReviewOnEveryOpen() -> some View {
        modifier(RequestReviewOnOpenModifier())
    }
}
