//
//  ScreenMetrics.swift
//  iOSEmora
//
//  尺寸自适应：折叠态（393pt）单列 → 展开态 / iPad 宽屏多列。
//  「iPhone Duo」展开后宽度接近小平板，这里统一按可视宽度分档，
//  不依赖具体机型，避免机型判断失效。
//

import SwiftUI

/// 屏幕档位
enum ScreenClass {
    /// 窄屏（iPhone SE / mini，< 375pt）
    case compact
    /// 标准手机竖屏（375 ~ 659pt）—— 单列布局，基准 393pt
    case regular
    /// iPhone Duo 展开态 / iPad 竖屏（660 ~ 1023pt）—— 多列、内容居中限宽
    ///
    /// ⚠️ 上界从 700 下移到 660：**iPhone Duo 展开态是 669pt**，按老阈值会掉进 `regular`
    /// 单列档，展开后只是把手机布局拉宽。660 这一刀正好卡在「手机横屏最大值」与
    /// 「Duo 展开宽度」之间。
    case wide
    /// 大屏（iPad 全尺寸 / 横屏满宽，>= 1024pt）
    case extraWide

    var isWide: Bool {
        switch self {
        case .wide, .extraWide: return true
        case .compact, .regular: return false
        }
    }
}

/// 由可视宽度派生的布局度量
struct ScreenMetrics: Equatable {
    /// 可视宽度（pt）
    let width: CGFloat
    /// 可视高度（pt）—— 宽屏判断只看宽度，但「编辑区该多高」要看高度
    let height: CGFloat
    let `class`: ScreenClass

    init(width: CGFloat, height: CGFloat, sizeClass: UserInterfaceSizeClass?) {
        self.width = width
        self.height = height
        // 横屏 / 展开态也可能被系统标成 regular，这里一律以实际宽度为准
        switch width {
        case ..<375: self.`class` = .compact
        case 375..<660: self.`class` = .regular
        case 660..<1024: self.`class` = .wide
        default: self.`class` = .extraWide
        }
    }

    static let fallback = ScreenMetrics(width: 393, height: 852, sizeClass: .compact)

    // MARK: - 边距

    /// 页面左右边距（窄屏收紧到 12）
    var pageMargin: CGFloat {
        switch `class` {
        case .compact: return 12
        case .regular: return 16
        case .wide: return 24
        case .extraWide: return 32
        }
    }

    /// 内容最大宽度（宽屏下居中，避免行太长）
    ///
    /// 宽屏档的下限现在是 660（Duo 展开态），比这个值还小的 `contentMaxWidth`
    /// 会让整个档位一进来就被夹住 —— 所以 cap 必须大于 660。
    /// ⚠️ 折叠屏展开态横屏（951×669）走两栏时横向已经分过区，再叠一层居中限宽
    ///    只会在两侧各留一大条空白，所以「两栏 + 非 iPad 大屏」彻底取消 cap。
    /// ⚠️ 音色卡片网格**不走这里**：它改用 `voiceGridPadding()` / `voiceGridMaxWidth`，
    ///    iPad 大屏要额外放开限宽才能一行排更多音色；这里只管正文类页面。
    var contentMaxWidth: CGFloat? {
        guard !(usesTwoColumnStudio && !isPadClass) else { return nil }
        switch `class` {
        case .compact, .regular: return nil
        case .wide: return 720
        case .extraWide: return 820
        }
    }

    // MARK: - 列数

    /// 音色卡片网格的最大宽度。
    ///
    /// ⚠️ iPad 类大屏**不限宽**：`contentMaxWidth`（wide 720 / extraWide 820）会把音色库
    ///    夹在屏幕中间 —— 820pt 的 iPad 竖屏网格仅 672pt 宽、只能排 3 列，两侧还各空 50pt。
    ///    放开后网格吃到整屏宽度，配合 `voiceGridColumns` 排 4~5 列。
    ///    非 iPad 设备沿用原 cap，避免 Duo 展开态横屏把卡片拉成宽条。
    var voiceGridMaxWidth: CGFloat? { isPadClass ? nil : contentMaxWidth }

    /// 音色卡片网格的目标列数。
    ///
    /// ⚠️ 只有 iPad 大屏提列，其余档位保持原值（2 / 2 / 3 / 4）不变：
    ///    * iPad 竖屏 820pt → 4 列（单卡 ≈185pt）
    ///    * iPad 横屏 1180pt / mini 横屏 1133pt → 5 列（单卡 ≈215pt）
    ///    * 分屏 410×1180 不满足 `isPadClass`，仍按档位走单列密度
    var voiceGridColumns: Int {
        if isPadClass { return width >= 1000 ? 5 : 4 }
        switch `class` {
        case .compact, .regular: return 2
        case .wide: return 3
        case .extraWide: return 4
        }
    }

    /// 按**实测网格内容宽度**再给列数封顶。
    /// - Parameter contentWidth: 已扣掉左右 `pageMargin` 的网格可用宽度
    ///
    /// ⚠️ Sheet 的环境值继承的是全屏 `ScreenMetrics`，但 iPad 上的 sheet 本身可能比屏幕窄，
    ///    直接套 `voiceGridColumns` 会把 4~5 列硬塞进窄卡片。这里按单卡 180pt + 间距 10pt
    ///    反推「这个宽度最多放几列」，取较小值；下限 2 保住 SE 等小屏的两列。
    ///    全屏的音色库标签页宽度与 `ScreenMetrics.width` 一致，算出来就是目标列数本身。
    func voiceGridColumns(forContentWidth contentWidth: CGFloat) -> Int {
        let spacing: CGFloat = 10
        let targetCardWidth: CGFloat = 180
        let fits = Int(floor((contentWidth + spacing) / (targetCardWidth + spacing)))
        return min(voiceGridColumns, max(2, fits))
    }

    /// 历史记录卡片网格的目标列数（**仅 iPad 大屏启用**；iPhone / 分屏固定 1 = 单列 List）。
    ///
    /// 历史卡是横向布局（44pt 头像 + 文案 + 32pt 播放键），比音色卡宽得多，
    /// 目标单卡宽取 340pt：
    ///  * iPad 竖屏 820pt → 2 列（单卡 ≈381pt）
    ///  * iPad 横屏 1180pt / mini 横屏 1133pt → 3 列（单卡 ≈365pt）
    var historyGridColumns: Int {
        guard isPadClass else { return 1 }
        return width >= 1000 ? 3 : 2
    }

    /// 按实测网格内容宽度给历史网格列数封顶（防止过窄容器把卡片挤成细条）。
    func historyGridColumns(forContentWidth contentWidth: CGFloat) -> Int {
        let spacing: CGFloat = 10
        let targetCardWidth: CGFloat = 340
        let fits = Int(floor((contentWidth + spacing) / (targetCardWidth + spacing)))
        return min(historyGridColumns, max(1, fits))
    }

    /// 采样率选择网格列数
    var sampleRateColumns: Int {
        `class`.isWide ? 3 : 2
    }
    var metaColumns: Int {
        `class`.isWide ? 4 : 2
    }

    // MARK: - 结构性开关

    /// 工作台是否走「左编辑 + 右参数」两栏（宽屏复用 macOS 的两栏思路）
    ///
    /// ⚠️ 比 wide 档门槛再高一档：侧栏固定 300pt，加上两倍的 `pageMargin` 与 16pt 间距，
    /// 视口 669pt（iPhone Duo 展开态）留给编辑区的只剩 ~305pt —— 比手机竖屏的 361pt 还窄，
    /// 展开反而更难写字。所以 Duo 展开态走 **单列 + wide 档的其它红利**（3 列网格 / 24pt 边距）。
    var usesTwoColumnStudio: Bool { width >= 740 && `class`.isWide }

    /// 「iPad 类大屏」：宽 ≥ 740 且高 ≥ 700。
    ///
    /// 同样是 `wide` 档，纵向空间可能差一倍：
    ///  * iPad 竖屏 820×1180 / 横屏 1180×820 / iPad mini 横屏 1133×744 —— 高度充裕，内容要吃掉整屏；
    ///  * 折叠屏展开态横屏 951×669 / iPhone 横屏 ≤430 —— 高度紧张，只能按紧凑布局。
    /// 700 这一刀正好卡在 Duo 展开态的 669pt 与 iPad mini 横屏的 744pt 之间。
    /// ⚠️ 不能用 `horizontalSizeClass == .regular` 判 iPad：分屏（410×1180）也是 regular，
    ///    而那个宽度必须走单列。同理 740 的下限与 `usesTwoColumnStudio` 对齐。
    var isPadClass: Bool { width >= 740 && height >= 700 }

    /// 工作台两栏右侧参数栏宽度：iPad 侧栏铺开完整参数面板（滑块 / 采样率网格 / 语音指令），
    /// 需要 360pt 才不挤；折叠屏横屏仍只放两张摘要卡，保持 300 给编辑区让位。
    var studioSidebarWidth: CGFloat { isPadClass ? 360 : 300 }

    /// 底部浮层（mini player / 后台浮条 / Toast）要给标签栏让出的高度。
    ///
    /// iPadOS 18 起 `TabView` 在 iPad 上把标签栏放到**顶部**（与工具栏同一行，见真机截图：
    /// Create / Voice Library / Project 胶囊居中、积分与设置分列两侧），底部没有标签栏 ——
    /// 仍按 iPhone 的 58pt 抬升会让浮层悬在半空。二级页标签栏本来隐藏，统一贴底 18pt。
    var tabBarClearance: CGFloat { isPadClass ? 18 : 58 }

    /// 设置页是否把「账户卡」与「其它分组」并排
    var usesTwoColumnSettings: Bool { `class` == .extraWide }

    /// 弹窗宽度：设计为 331pt（393 − 2×30 − 1），宽屏下放宽但有上限
    var dialogWidth: CGFloat {
        let w = min(width - 2 * 30 - 1, 420)
        return max(331, w)
    }

    /// 居中弹窗左右留白
    var dialogSideMargin: CGFloat { 30 }

    /// 编辑器高度下限（两栏分支的兜底，主值由 `StudioView` 实测 ScrollView 高度给出）
    ///
    /// ⚠️ 宽屏要把剩余纵向空间吃掉：折叠屏展开态横屏只有 669pt 高，
    /// 再按 260 给的话两栏下面会空出一大截。190 ≈ 导航栏 + 标签栏 + 生成条的固定开销。
    /// ⚠️ 这里**不能再夹 520 上限**：iPad 竖屏 1180pt 高时，520 会让编辑卡停在半屏、
    /// 下方空出四百多 pt（用户实测 820×1180 的 iPad Air 即此问题）。
    var editorMinHeight: CGFloat {
        guard `class`.isWide else { return 170 }
        return max(260, height - 190)
    }
}

// MARK: - 环境注入

private struct ScreenMetricsKey: EnvironmentKey {
    static let defaultValue = ScreenMetrics.fallback
}

extension EnvironmentValues {
    var screenMetrics: ScreenMetrics {
        get { self[ScreenMetricsKey.self] }
        set { self[ScreenMetricsKey.self] = newValue }
    }
}

/// 读取可视宽度并向下注入 `ScreenMetrics`。
///
/// 只在这里用一次 `GeometryReader`：它能拿到最外层安全区之后的真实宽度，
/// 比 `UIScreen.main.bounds` 在多窗口 / 分屏下更可靠。
struct ScreenMetricsReader<Content: View>: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    let content: (ScreenMetrics) -> Content

    var body: some View {
        GeometryReader { geo in
            let metrics = ScreenMetrics(width: geo.size.width,
                                        height: geo.size.height,
                                        sizeClass: sizeClass)
            content(metrics)
                .frame(width: geo.size.width, height: geo.size.height)
                .environment(\.screenMetrics, metrics)
        }
    }
}

/// 按档位给内容加页面边距 + 居中限宽
struct PagePadding: ViewModifier {
    @Environment(\.screenMetrics) private var metrics

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, metrics.pageMargin)
            .frame(maxWidth: metrics.contentMaxWidth ?? .infinity, alignment: .leading)
            .frame(maxWidth: .infinity)
    }
}

extension View {
    func pagePadding() -> some View { modifier(PagePadding()) }
}

/// 音色卡片网格专用边距：与 `PagePadding` 同构，但限宽走 `voiceGridMaxWidth`
/// —— iPad 大屏铺满整屏以便一行排更多音色。
///
/// ⚠️ 只给「音色库标签页」与「选择音色 Sheet」这两个 LazyVGrid 用；
///    正文类页面继续用 `pagePadding()`，别把 820pt 的正文行拉成宽条。
struct VoiceGridPadding: ViewModifier {
    @Environment(\.screenMetrics) private var metrics

    func body(content: Content) -> some View {
        content
            .padding(.horizontal, metrics.pageMargin)
            .frame(maxWidth: metrics.voiceGridMaxWidth ?? .infinity, alignment: .leading)
            .frame(maxWidth: .infinity)
    }
}

extension View {
    func voiceGridPadding() -> some View { modifier(VoiceGridPadding()) }
}
