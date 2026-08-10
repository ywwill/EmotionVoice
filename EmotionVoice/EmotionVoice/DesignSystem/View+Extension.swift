//
//  View+Extension.swift
//  EmotionVoice
//
//  Created by young on 2026/8/8.
//

import SwiftUI
import AppKit

extension View {

    /// 应用卡片样式
    func cardStyle(
        background: Color = AppColor.bgSecondary,
        cornerRadius: CGFloat = AppRadius.medium,
        borderColor: Color = AppColor.borderSubtle,
        borderWidth: CGFloat = 1
    ) -> some View {
        self
            .background(background)
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: borderWidth)
            )
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }

    /// 玻璃质感背景（标题栏/工具栏）
    func glassBackground(opacity: Double = 0.75) -> some View {
        self.background(
            Color(hex: 0x15171B).opacity(opacity)
                .background(.ultraThinMaterial)
        )
    }

    /// 鼠标悬浮时切换为手型（进入 push pointingHand，离开 pop）
    /// 仅作用于手型覆盖：会和箭头栈交互，多次 push 会被 pop 抵消
    func pointingHandCursor() -> some View {
        self.onHover { hovering in
            if hovering {
                NSCursor.pointingHand.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}
