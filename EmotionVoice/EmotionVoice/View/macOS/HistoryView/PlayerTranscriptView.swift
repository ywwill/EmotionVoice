//
//  PlayerTranscriptView.swift
//  EmotionVoice
//
//  音频文本卡片：标题行（字数 / 句数 / 复制）+ 可滚动正文
//

import SwiftUI
import AppKit

struct PlayerTranscriptView: View {

    let audio: AudioItem

    @State private var didCopy: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            ScrollView {
                Text(audio.text.isEmpty ? "暂无原文内容" : audio.text)
                    .font(.system(size: 14.5))
                    .foregroundStyle(audio.text.isEmpty ? AppColor.textTertiary : AppColor.textSecondary)
                    .lineSpacing(6)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 268)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .background(AppColor.bgSecondary)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(AppColor.borderSubtle, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - 标题行

    private var header: some View {
        HStack(spacing: 10) {
            Text("%d 字 · %d 句".localized(charCount, sentenceCount))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(AppColor.textTertiary)

            Spacer()

            copyButton
        }
    }

    private var copyButton: some View {
        Button {
            copyText()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: didCopy ? "checkmark" : "square.on.square")
                    .font(.system(size: 11))
                Text(didCopy ? "已复制" : "复制")
                    .font(.system(size: 11))
            }
            .foregroundStyle(didCopy ? AppColor.statusSuccess : AppColor.textSecondary)
            .padding(.horizontal, 9)
            .frame(height: 26)
            .background(AppColor.bgTertiary)
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(AppColor.borderSubtle, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
    }

    // MARK: - 行为

    private var charCount: Int {
        PlayerTextMetrics.charCount(of: audio.text)
    }

    private var sentenceCount: Int {
        PlayerTextMetrics.sentenceCount(of: audio.text)
    }

    private func copyText() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(audio.text, forType: .string)
        didCopy = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) {
            didCopy = false
        }
    }
}
