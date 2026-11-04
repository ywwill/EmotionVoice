//
//  VoiceCardAuxViews.swift
//  iOSEmora
//
//  音色卡片附属视图：试听呼吸条 / 骨架卡。
//  从 VoiceCardGrid.swift 拆出：代码逐字搬移，未改动任何逻辑（原 private 类型按需放开为 internal）。
//

import SwiftUI

/// 单根呼吸条：确定性延迟，不用 TimelineView（几百张卡同时跑会掉帧）
struct PreviewBar: View {
    let index: Int
    let color: Color
    @State private var animating = false

    private var heights: [CGFloat] { [8, 14, 6, 12] }

    var body: some View {
        RoundedRectangle(cornerRadius: 1, style: .continuous)
            .fill(color)
            .frame(width: 2, height: animating ? heights[index % 4] : 4)
            .animation(
                .easeInOut(duration: 0.6)
                    .repeatForever(autoreverses: true)
                    .delay(Double(index) * 0.1),
                value: animating
            )
            .onAppear { animating = true }
    }
}

// MARK: - 骨架卡

/// 首屏骨架（避免一次性同步查全表导致的白屏）
struct VoiceCardSkeleton: View {
    @Environment(\.aurora) private var c

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(c.surface3)
                    .frame(width: 38, height: 38)
                Spacer(minLength: 0)
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(c.surface3)
                    .frame(width: 44, height: 11)
            }
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(c.surface3)
                .frame(width: 72, height: 13)
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(c.surface3)
                .frame(height: 10)
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .fill(c.surface3)
                .frame(width: 96, height: 10)
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(c.surface3).frame(width: 28, height: 28)
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(c.surface3).frame(width: 28, height: 28)
                Spacer(minLength: 0)
                Circle().fill(c.surface3).frame(width: 26, height: 26)
            }
        }
        .padding(12)
        .frame(height: 168)
        .background(
            RoundedRectangle(cornerRadius: AuroraRadius.md, style: .continuous)
                .fill(c.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: AuroraRadius.md, style: .continuous)
                        .strokeBorder(c.line, lineWidth: 0.5)
                )
        )
        .redacted(reason: .placeholder)
    }
}
