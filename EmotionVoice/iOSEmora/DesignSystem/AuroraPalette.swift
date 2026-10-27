//
//  AuroraPalette.swift
//  iOSEmora
//
//  Aurora Pop 设计语言（iOS 版）
//  雾紫中性底 + 紫 / 玫瑰 / 薄荷 / 暖橙 四色强调，渐变优先。
//  令牌与 UI/iOS/emotionvoice-ios-design.html「设计系统」章节 1:1 对应。
//

import SwiftUI

// MARK: - 装饰四色（跨主题共用）

/// 只用于渐变 / 发光 / 网格点亮 / 装饰，不承载正文
enum AuroraDecor {
    /// 紫 #8A5BFF — 主色：CTA 起点、选中态、强调图标
    static let violet = Color(hex: 0x8A5BFF)
    /// 玫瑰 #FF5FA2 — CTA 终点、进行中点、播放头、网格高亮
    static let rose = Color(hex: 0xFF5FA2)
    /// 薄荷 #2ED9BF — 成功 / 完成态顶部条、速率 ↑、已播波形
    static let mint = Color(hex: 0x2ED9BF)
    /// 暖橙 #FFB457 — 积分 / 计费
    static let amber = Color(hex: 0xFFB457)

    /// 积分渐变两端
    static let creditA = Color(hex: 0xFF9838)
    static let creditB = Color(hex: 0xFF5FA2)

    /// 品牌主渐变 115° 紫 → 玫瑰 → 橙（品牌标 / 接收网格点亮 / 弹窗顶部条）
    static let popGradient = LinearGradient(
        colors: [violet, rose, amber],
        startPoint: UnitPoint(x: 0, y: 0),
        endPoint: UnitPoint(x: 0.86, y: 1)
    )

    /// 紫 → 薄荷（完成态顶部条）
    static let popAltGradient = LinearGradient(
        colors: [violet, mint],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// 积分渐变 135°
    static let creditGradient = LinearGradient(
        colors: [creditA, creditB],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

// MARK: - 语义色板

/// 按 `ColorScheme` 解析出的一套完整语义色
///
/// 中性面走 iOS 语义色的明度结构（背景 / 分组背景 / 卡片三级），底色统一偏紫。
/// 承载文字的强调色与承载面积的渐变色拆成两套：
///  - `accent`：文字 / 图标强调（浅色 #6D3BF5 白底 5.9:1，深色 #B79AFF 底 8.2:1）
///  - `ctaGradient`：可点按钮底色（深一档的紫 → 玫瑰，白字 4.5–7:1）
struct AuroraPalette {

    // MARK: 背景层

    /// 主背景（浅 #FFFFFF / 深 #12101F）
    let background: Color
    /// 分组背景（浅 #F5F1FE / 深 #0B0916）
    let backgroundGrouped: Color
    /// 卡片 Surface（浅 #FFFFFF / 深 #1B1731）
    let surface: Color
    /// 次级块底（浅 #F7F4FE / 深 #221D3D）
    let surface2: Color
    /// 输入框 / 浮起块（浅 #EDE8FB / 深 #2B2549）
    let surface3: Color
    /// 导航栏 / 工具条底色（毛玻璃）
    let bar: Color

    // MARK: 文字

    let textPrimary: Color
    let textSecondary: Color
    let textTertiary: Color

    // MARK: 描边 / 填充

    let line: Color
    let line2: Color
    let fill: Color
    let fill2: Color

    // MARK: 强调

    /// 文字 / 图标强调色
    let accent: Color
    /// 装饰用亮强调（发光、描边）
    let accentGlow: Color
    /// 强调底（选中态胶囊、徽章底）
    let accentSoft: Color
    /// 按钮渐变（135° 紫 → 玫瑰）
    let ctaGradient: LinearGradient
    let ctaStart: Color
    let ctaEnd: Color
    let ctaForeground: Color

    // MARK: 状态

    let success: Color
    let warning: Color
    let danger: Color
    let info: Color

    // MARK: 其它

    /// 接收网格空槽底
    let slot: Color
    /// 卡片投影色
    let shadow: Color
    /// 弹窗遮罩
    let scrim: Color

    init(scheme: ColorScheme) {
        let dark = scheme == .dark
        if dark {
            background = Color(hex: 0x12101F)
            backgroundGrouped = Color(hex: 0x0B0916)
            surface = Color(hex: 0x1B1731)
            surface2 = Color(hex: 0x221D3D)
            surface3 = Color(hex: 0x2B2549)
            bar = Color(hex: 0x171328, opacity: 0.78)

            textPrimary = Color(hex: 0xF5F2FF)
            textSecondary = Color(hex: 0xADA5CC)
            textTertiary = Color(hex: 0x8E86B0)

            line = Color.white.opacity(0.09)
            line2 = Color.white.opacity(0.17)
            fill = Color.white.opacity(0.06)
            fill2 = Color.white.opacity(0.11)

            accent = Color(hex: 0xB79AFF)
            accentGlow = Color(hex: 0xD3C2FF)
            accentSoft = Color(hex: 0x8B5CFF, opacity: 0.24)
            ctaStart = Color(hex: 0x7C4DFF)
            ctaEnd = Color(hex: 0xE23C86)
            ctaForeground = .white

            success = Color(hex: 0x3ED99A)
            warning = Color(hex: 0xFFC24B)
            danger = Color(hex: 0xFF6B7E)
            info = Color(hex: 0x5BA8FF)

            slot = Color.white.opacity(0.06)
            shadow = Color.black.opacity(0.55)
            scrim = Color(hex: 0x221248, opacity: 0.52)
        } else {
            background = .white
            backgroundGrouped = Color(hex: 0xF5F1FE)
            surface = .white
            surface2 = Color(hex: 0xF7F4FE)
            surface3 = Color(hex: 0xEDE8FB)
            bar = Color.white.opacity(0.84)

            textPrimary = Color(hex: 0x1B1533)
            textSecondary = Color(hex: 0x5C5780)
            textTertiary = Color(hex: 0x736D8F)

            line = Color(hex: 0x583FB2, opacity: 0.11)
            line2 = Color(hex: 0x583FB2, opacity: 0.20)
            fill = Color(hex: 0x6D3BF5, opacity: 0.055)
            fill2 = Color(hex: 0x6D3BF5, opacity: 0.10)

            accent = Color(hex: 0x6D3BF5)
            accentGlow = Color(hex: 0xA78BFF)
            accentSoft = Color(hex: 0x6D3BF5, opacity: 0.12)
            ctaStart = Color(hex: 0x5B2EDB)
            ctaEnd = Color(hex: 0xCE2B72)
            ctaForeground = .white

            success = Color(hex: 0x0FA36B)
            warning = Color(hex: 0xB87200)
            danger = Color(hex: 0xE0344B)
            info = Color(hex: 0x2E7BE0)

            slot = Color(hex: 0x6D3BF5, opacity: 0.10)
            shadow = Color(hex: 0x4E2CA0, opacity: 0.16)
            scrim = Color(hex: 0x221248, opacity: 0.44)
        }
        ctaGradient = LinearGradient(colors: [ctaStart, ctaEnd],
                                     startPoint: .topLeading,
                                     endPoint: .bottomTrailing)
    }
}

// MARK: - 环境注入

private struct PaletteKey: EnvironmentKey {
    static let defaultValue = AuroraPalette(scheme: .light)
}

extension EnvironmentValues {
    /// 当前主题下的 Aurora 色板。由根视图按 `colorScheme` 注入一次。
    var aurora: AuroraPalette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}

// MARK: - 圆角与间距

enum AuroraRadius {
    static let xs: CGFloat = 6
    static let sm: CGFloat = 8
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 20
    static let xxl: CGFloat = 26
    static let full: CGFloat = 999
}

enum AuroraSpace {
    /// 基准 4pt
    static let unit: CGFloat = 4
    /// 页面左右边距
    static let page: CGFloat = 16
    static let s1: CGFloat = 4
    static let s2: CGFloat = 8
    static let s3: CGFloat = 12
    static let s4: CGFloat = 16
    static let s5: CGFloat = 20
    static let s6: CGFloat = 24
    static let s8: CGFloat = 32
}

// MARK: - 字体

enum AuroraFont {
    /// 大标题 34 / Bold
    static let largeTitle = Font.system(size: 34, weight: .bold)
    /// 导航栏标题 17 / Semibold
    static let navTitle = Font.system(size: 17, weight: .semibold)
    /// 区块标题 15.5 / Semibold
    static let sectionTitle = Font.system(size: 15.5, weight: .semibold)
    /// 列表主标题 16
    static let body = Font.system(size: 16, weight: .regular)
    /// 卡片标题 15.5 / Semibold
    static let cardTitle = Font.system(size: 15.5, weight: .semibold)
    /// 副标题 13
    static let subhead = Font.system(size: 13, weight: .regular)
    /// 脚注 12
    static let footnote = Font.system(size: 12, weight: .regular)
    /// 标注 11 / Mono
    static let captionMono = Font.system(size: 11, weight: .regular, design: .monospaced)
    /// 数值 13 / Mono
    static let mono13 = Font.system(size: 13, weight: .regular, design: .monospaced)
    /// 数值 15 / Mono
    static let mono15 = Font.system(size: 15, weight: .regular, design: .monospaced)
    /// 数值 17 / Mono Semibold
    static let mono17 = Font.system(size: 17, weight: .semibold, design: .monospaced)
    /// 余额大数字 46 / Mono Bold
    static let balance = Font.system(size: 46, weight: .bold, design: .monospaced)
}

// MARK: - 十六进制取色

extension Color {
    // ⚠️ `init(hex:opacity:)` 复用 macOS 的 `DesignSystem/AppColor.swift`
    // （它已经进了 iOSEmora target，因为 `DataReceiveGridView` 依赖 AppColor/AppFont/AppRadius）。
    // 同模块里两份同签名扩展会变成 ambiguous，这里不再重复定义。

    /// 把颜色向指定基色压暗（浅色模式下保证白底可读）
    func darkened(toward base: Color = Color(hex: 0x1B1533), fraction: CGFloat) -> Color {
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        ui.getRed(&r, green: &g, blue: &b, alpha: &a)
        let baseUI = UIColor(base)
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        baseUI.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        let f = min(max(fraction, 0), 1)
        return Color(.sRGB,
                     red: r + (br - r) * f,
                     green: g + (bg - g) * f,
                     blue: b + (bb - b) * f,
                     opacity: a)
    }
}
