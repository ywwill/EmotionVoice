//
//  View+Extension.swift
//  EmotionVoice
//
//  Created by young on 2026/8/8.
//

import SwiftUI

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
}