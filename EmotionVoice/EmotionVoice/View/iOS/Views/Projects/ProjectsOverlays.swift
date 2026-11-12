//
//  ProjectsOverlays.swift
//  iOSEmora
//
//  项目页附属视图：重命名弹窗 / 播放呼吸条。
//  从 ProjectsView.swift 拆出：代码逐字搬移，未改动任何逻辑（原 private 类型按需放开为 internal）。
//

import SwiftUI

// MARK: - 重命名弹窗

/// ⚠️ 不用系统 `.alert` 的 TextField：它没有清空按钮，内容槽位也塞不进自定义视图。
struct RenameDialog: View {
    @Environment(\.aurora) private var c
    @Environment(\.screenMetrics) private var metrics

    @Binding var text: String
    var onCancel: () -> Void
    var onSave: () -> Void

    @FocusState private var focused: Bool
    @State private var appeared = false

    private var canSave: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ZStack {
            c.scrim
                .ignoresSafeArea()
                .background(.ultraThinMaterial)
                .onTapGesture(perform: onCancel)

            card
                .frame(width: metrics.dialogWidth)
                .scaleEffect(appeared ? 1 : 0.92)
                .opacity(appeared ? 1 : 0)
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: appeared)
        .onAppear {
            appeared = true
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 200_000_000)
                focused = true
            }
        }
    }

    private var card: some View {
        VStack(spacing: 0) {
            Text("重命名".localized())
                .font(.system(size: 16.5, weight: .semibold))
                .foregroundStyle(c.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 12)

            field
                .padding(.horizontal, 18)

            HStack(spacing: 10) {
                SecondaryButton(title: "取消".localized(), action: onCancel)
                PrimaryButton(title: "保存".localized(), isEnabled: canSave, action: onSave)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
        }
        .background(
            RoundedRectangle(cornerRadius: AuroraRadius.xxl, style: .continuous)
                .fill(c.surface)
                .shadow(color: c.shadow, radius: 30, x: 0, y: 14)
        )
    }

    private var field: some View {
        HStack(spacing: 8) {
            TextField("语音名称".localized(), text: $text)
                .font(.system(size: 15.5))
                .foregroundStyle(c.textPrimary)
                .focused($focused)
                .submitLabel(.done)
                .onSubmit { if canSave { onSave() } }

            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(c.textTertiary)
                }
                .buttonStyle(.plain)
                .transition(.opacity.combined(with: .scale(scale: 0.7)))
                .accessibilityLabel("清空".localized())
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 42)
        .background(
            RoundedRectangle(cornerRadius: AuroraRadius.md, style: .continuous)
                .fill(c.surface3)
                .overlay(
                    RoundedRectangle(cornerRadius: AuroraRadius.md, style: .continuous)
                        .strokeBorder(focused ? c.accent.opacity(0.55) : c.line2, lineWidth: 0.5)
                )
        )
        .animation(.easeOut(duration: 0.16), value: text.isEmpty)
    }
}

// MARK: - 播放中的呼吸条

struct PlayingBars: View {
    let color: Color
    var barCount: Int = 3

    var body: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<barCount, id: \.self) { i in
                PlayingBar(index: i, color: color)
            }
        }
    }
}

struct PlayingBar: View {
    let index: Int
    let color: Color
    @State private var animating = false

    private var base: CGFloat { [8, 13, 6, 11][index % 4] }

    var body: some View {
        RoundedRectangle(cornerRadius: 1, style: .continuous)
            .fill(color)
            .frame(width: 2, height: animating ? base : 3)
            .animation(
                .easeInOut(duration: 0.62)
                    .repeatForever(autoreverses: true)
                    .delay(Double(index) * 0.12),
                value: animating
            )
            .onAppear { animating = true }
    }
}
