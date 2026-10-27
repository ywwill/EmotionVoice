//
//  EmotionAccessoryBar.swift
//  iOSEmora
//
//  键盘 accessory：23 个语气 + 7 个拟声 + 中断 + 完成。
//
//  macOS 把标签铺成常驻网格，iPhone 上没有这个空间，改为「编辑聚焦时才出现的横向滚动条」。
//  23 个语气的 description 在 macOS 里是 tooltip，iOS 没有 hover，改为标签面板里的副行。
//

import SwiftUI
import Combine   // @Published / ObservableObject 在 Combine，SwiftUI 不再隐式导出

/// accessory 的配置（由编辑器持有，SwiftUI 侧与 UIKit 侧共享）
@MainActor
final class EditorAccessoryConfig: ObservableObject {
    /// 0 = 语气，1 = 拟声
    @Published var segment: Int = 0
    /// 选中标签后的副行说明（替代 iOS 上不存在的 tooltip）
    @Published var hint: String? = nil

    var toneItems: [EmotionItem] { Constants.emotions }
    var soundItems: [EmotionItem] { Constants.richLanguageTags }

    var onPick: ((EmotionItem, EmotionCategory) -> Void)?
    var onInterrupt: (() -> Void)?
    var onDone: (() -> Void)?
}

struct EmotionAccessoryBar: View {
    @Environment(\.aurora) private var c
    @ObservedObject var config: EditorAccessoryConfig

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                AuroraSegmented(options: ["语气".localized(), "拟声".localized()],
                                selection: Binding(
                                    get: { config.segment == 0 ? "语气".localized() : "拟声".localized() },
                                    set: { config.segment = ($0 == "语气".localized()) ? 0 : 1 }
                                ))
                .frame(width: 126)

                Spacer(minLength: 0)

                Button {
                    config.onInterrupt?()
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

                Button {
                    config.onDone?()
                } label: {
                    Text("完成".localized())
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(c.accent)
                        .frame(width: 44, height: 34)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 7) {
                    ForEach(items, id: \.tag) { item in
                        Button {
                            config.onPick?(item, category)
                            config.hint = item.description
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
            .frame(height: 38)

            if let hint = config.hint {
                Text(hint)
                    .font(.system(size: 11.5))
                    .foregroundStyle(c.textTertiary)
                    .lineLimit(2)
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.top, 6)
        .background(c.bar)
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
