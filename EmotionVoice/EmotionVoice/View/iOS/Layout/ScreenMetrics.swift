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
    var contentMaxWidth: CGFloat? {
        // 工作台走两栏时横向已经分过区了，再叠一层居中限宽只会在两侧各留一大条空白，
        // 而折叠屏展开态横屏（951pt）正是这种情况 —— 两栏布局不限宽。
        guard !usesTwoColumnStudio else { return nil }
        switch `class` {
        case .compact, .regular: return nil
        case .wide: return 720
        case .extraWide: return 820
        }
    }

    // MARK: - 列数

    /// 音色库卡片列数
    var voiceGridColumns: Int {
        switch `class` {
        case .compact: return 2
        case .regular: return 2
        case .wide: return 3
        case .extraWide: return 4
        }
    }

    /// 采样率选择网格列数
    var sampleRateColumns: Int {
        `class`.isWide ? 3 : 2
    }

    /// 播放详情 meta 卡片列数（macOS 四列在手机上折成 2×2）
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

    /// 设置页是否把「账户卡」与「其它分组」并排
    var usesTwoColumnSettings: Bool { `class` == .extraWide }

    /// 弹窗宽度：设计为 331pt（393 − 2×30 − 1），宽屏下放宽但有上限
    var dialogWidth: CGFloat {
        let w = min(width - 2 * 30 - 1, 420)
        return max(331, w)
    }

    /// 居中弹窗左右留白
    var dialogSideMargin: CGFloat { 30 }

    /// 编辑器最小高度
    ///
    /// ⚠️ 宽屏要把剩余纵向空间吃掉：折叠屏展开态横屏只有 669pt 高，
    /// 再按 260 给的话两栏下面会空出一大截。190 ≈ 导航栏 + 标签栏 + 生成条的固定开销。
    var editorMinHeight: CGFloat {
        guard `class`.isWide else { return 170 }
        return max(260, min(height - 190, 520))
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
