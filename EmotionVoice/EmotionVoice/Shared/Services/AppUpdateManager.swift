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
