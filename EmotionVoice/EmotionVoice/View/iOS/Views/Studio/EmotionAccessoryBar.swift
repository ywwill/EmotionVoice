//
//  EmotionAccessoryBar.swift
//  iOSEmora
//
//  键盘 accessory：23 个语气 + 7 个拟声 + 中断 + 清空。
//
//  ⚠️ 「完成」（收键盘）**不在这里** —— 它落在底部那条生成条上、与「生成音频」同一行。
//  accessory 那一排按钮太多，主操作（收键盘）混在 30 个胶囊里找不着；而生成条
//  永远露在最底下、也不会被键盘压住，手不用离开键盘区就能点到。
//
//  macOS 把标签铺成常驻网格，iPhone 上没有这个空间，改为「编辑聚焦时才出现的横向滚动条」。
//  23 个语气的 description 在 macOS 里是 tooltip，iOS 没有 hover，改为标签面板底部的副行。
//
//  ⚠️ 副行**必须常驻**（没选标签时显示当前分段的说明），不能「有才加一行」：
//  accessory 高度是写死的常量换来的，一会让副行把总高顶出容器之外被裁掉，
//  二会让键盘高度跟着点标签一跳一跳。
//

import SwiftUI
import Combine   // @Published / ObservableObject 在 Combine，SwiftUI 不再隐式导出

/// accessory 副行的内容（替代 iOS 上不存在的 tooltip）
struct AccessoryHint: Equatable {
    let emoji: String
    let label: String
    /// nil = 这条标签没有比名字更多的信息，只显示名字
    let detail: String?

    init(emoji: String, label: String, detail: String?) {
        self.emoji = emoji
        self.label = label
        self.detail = detail
    }

    init(item: EmotionItem) {
        let name = item.label.localized()
        let text = item.description.localized()
        self.init(emoji: item.emoji,
                  label: name,
                  // ⚠️ 描述跟名字一模一样时别再重复一遍（「大喊 · 大喊」看着像没显示描述）
                  detail: (text.isEmpty || text == name) ? nil : text)
    }
}

/// accessory 的高度构成。
///
/// ⚠️ `baseHeight` 只是「SwiftUI 还没量出来」时的占位值 —— 容器 frame 会跟着实测高度改
/// （见 `AccessoryContainerView`），所以偏几 pt 只闪一下、不会像以前那样留一条死空白。
/// 但改这里的行数 / 留白后要同步改，否则每次弹键盘都会先高后矮地跳一次。
enum AccessoryMetrics {
    /// 顶部留白
    static let topPadding: CGFloat = 5
    /// 控制行：分段控件 34（按钮 30 + 内边距 2×2）+ 与标签行的间距 6
    static let controlRowHeight: CGFloat = 40
    /// 标签行：胶囊 30 + 上下各 3
    static let tagRowHeight: CGFloat = 36
    /// 常驻总高（副行不在 body 里，别再把它算进来）
    static var baseHeight: CGFloat { topPadding + controlRowHeight + tagRowHeight }
}

/// accessory 的配置（由编辑器持有，SwiftUI 侧与 UIKit 侧共享）
@MainActor
final class EditorAccessoryConfig: ObservableObject {
    /// 0 = 语气，1 = 拟声
    @Published var segment: Int = 0
    /// 选中标签后的副行说明（替代 iOS 上不存在的 tooltip）；nil = 回落到分段说明
    @Published var hint: AccessoryHint? = nil
    /// SwiftUI 侧实测的内容高度。
    ///
    /// ⚠️ `inputAccessoryView` 的高度来自容器的 `intrinsicContentSize`，写死一个常量
    /// 就会把超出的那几 pt 裁掉（副行正好在最底下）—— 由 SwiftUI 报上来才保险。
    @Published var contentHeight: CGFloat = AccessoryMetrics.baseHeight

    /// 没有选中标签时副行显示的分段说明
    var segmentHint: AccessoryHint {
        segment == 0
        ? AccessoryHint(emoji: "🎭",
                        label: "语气".localized(),
                        detail: "从插入处一直生效，直到下一个语气标签或中断。".localized())
        : AccessoryHint(emoji: "🔊",
                        label: "拟声".localized(),
                        detail: "只在插入处播放一次，不改变周围的语气。".localized())
    }

    /// 副行那一块的固定高度（含上下留白）。⚠️ 副行当前不在 body 里，**不计入**总高
    static let hintHeight: CGFloat = 34

    var toneItems: [EmotionItem] { Constants.emotions }
    var soundItems: [EmotionItem] { Constants.richLanguageTags }

    var onPick: ((EmotionItem, EmotionCategory) -> Void)?
    var onInterrupt: (() -> Void)?
    /// 清空输入框（与 StudioView 文本卡标题行的「清空」同一个动作）
    var onClear: (() -> Void)?
}

/// 副行实测高度回传给 UIKit 容器（PreferenceKey 只能走 View 树）
private struct AccessoryHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct EmotionAccessoryBar: View {
    @Environment(\.aurora) private var c
    @ObservedObject var config: EditorAccessoryConfig

    var body: some View {
        VStack(spacing: 0) {
            controlRow
            tagScroll
        }
        .padding(.top, AccessoryMetrics.topPadding)
        .background(c.bar)
        .background(
            GeometryReader { geo in
                Color.clear.preference(key: AccessoryHeightKey.self, value: geo.size.height)
            }
        )
        .onPreferenceChange(AccessoryHeightKey.self) { height in
            guard height > 1, abs(config.contentHeight - height) > 0.5 else { return }
            config.contentHeight = height
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: 控制行

    private var controlRow: some View {
        HStack(spacing: 8) {
            AuroraSegmented(options: ["语气".localized(), "拟声".localized()],
                            selection: Binding(
                                get: { config.segment == 0 ? "语气".localized() : "拟声".localized() },
                                set: { picked in
                                    let next = (picked == "语气".localized()) ? 0 : 1
                                    guard next != config.segment else { return }
                                    config.segment = next
                                    // ⚠️ 换分段就把上一个分段的标签说明撤掉，否则副行说的是别的页的东西
                                    config.hint = nil
                                }
                            ))
            .frame(width: 126)

            // ⚠️ 「中断」紧跟在「语气 / 拟声」分段控件右边：它跟标签是同一类操作
            // （往文本里插标记），右边整条空白之后才轮到「清空」这类整篇动作 ——
            // 早年把两个不同类的动作挤在一起，视觉上像是同一组。
            Button {
                config.onInterrupt?()
                config.hint = AccessoryHint(item: Constants.interruptItem)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "speaker.slash.fill")
                        .font(.system(size: 11, weight: .semibold))
                    Text("中断".localized())
                        .font(.system(size: 12.5, weight: .medium))
                }
                .foregroundStyle(c.textSecondary)
                .padding(.horizontal, 11)
                .frame(height: 30)
                .background(
                    Capsule(style: .continuous)
                        .fill(c.surface3)
                        .overlay(Capsule(style: .continuous).strokeBorder(c.line, lineWidth: 0.5))
                )
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)

            Button {
                config.onClear?()
                config.hint = nil
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(c.textSecondary)
                    .frame(width: 30, height: 30)
                    .background(
                        Circle()
                            .fill(c.surface3)
                            .overlay(Circle().strokeBorder(c.line, lineWidth: 0.5))
                    )
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("清空".localized())
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    // MARK: 标签行

    private var tagScroll: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 7) {
                ForEach(items, id: \.tag) { item in
                    Button {
                        config.onPick?(item, category)
                        config.hint = AccessoryHint(item: item)
                    } label: {
                        HStack(spacing: 4) {
                            Text(item.emoji)
                                .font(.system(size: 13))
                            Text(item.label.localized())
                                .font(.system(size: 12.5, weight: .medium))
                        }
                        .foregroundStyle(c.textPrimary)
                        .padding(.horizontal, 11)
                        .frame(height: 32)
                        .background(
                            Capsule(style: .continuous)
                                .fill(c.surface3)
                                .overlay(
                                    Capsule(style: .continuous)
                                        .strokeBorder(tint(for: item).opacity(0.5), lineWidth: 1)
                                )
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 2)
        }
        .frame(height: AccessoryMetrics.tagRowHeight)
    }

    // MARK: 副行

    /// ⚠️ 常驻：没选标签时说当前分段，选了就说那个标签。**不参与高度变化** ——
    /// 一会让底部那几 pt 被容器裁掉，二会让键盘随点标签上下跳。
    private var hintRow: some View {
        let hint = config.hint ?? config.segmentHint
        return HStack(alignment: .firstTextBaseline, spacing: 5) {
            Text(hint.emoji)
                .font(.system(size: 11))
            Text(hint.label)
                .font(.system(size: 11.5, weight: .semibold))
                .foregroundStyle(c.textSecondary)
            if let detail = hint.detail {
                Text(detail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(c.textTertiary)
                    // ⚠️ fixedSize(vertical:)：不给它，两行的描述会被压成一行 + 省略号
                    .fixedSize(horizontal: false, vertical: true)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(minHeight: EditorAccessoryConfig.hintHeight - 3, alignment: .top)
        .padding(.horizontal, 16)
        .padding(.top, 3)
    }

    private var items: [EmotionItem] {
        config.segment == 0 ? config.toneItems : config.soundItems
    }

    private var category: EmotionCategory {
        config.segment == 0 ? .emotion : .richLanguage
    }

    private func tint(for item: EmotionItem) -> Color {
        EmotionPalette.color(forTag: item.tag, scheme: UIColor.isDarkMode ? .dark : .light)
    }
}

extension UIColor {
    /// 供 UIKit / 非 View 上下文判断当前深浅色
    static var isDarkMode: Bool {
        UITraitCollection.current.userInterfaceStyle == .dark
    }
}
