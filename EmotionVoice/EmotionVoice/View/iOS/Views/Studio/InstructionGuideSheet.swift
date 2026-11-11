//
//  InstructionGuideSheet.swift
//  iOSEmora
//
//  语音指令编写指南 Sheet。
//

import SwiftUI

// MARK: - 指令指南

struct InstructionGuideSheet: View {
    @Environment(\.aurora) private var c
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            SheetNavBar(
                title: "如何编写高质量的声音描述".localized(),
                leading: {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 19, weight: .medium))
                            .foregroundStyle(c.textTertiary)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                },
                trailing: { EmptyView() }
            )
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    guideItem("1. 先说语种与方言".localized(), "中文，粤语，四川话……".localized())
                    guideItem("2. 再说性别与年龄".localized(), "年轻男性，中年女性，童声……".localized())
                    guideItem("3. 然后描述音色与节奏".localized(), "温柔柔和，语速偏快，语调积极……".localized())
                    guideItem("4. 最后补充场景".localized(), "适合新闻播报 / 有声书 / 广告配音……".localized())
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
            }
        }
        .background(c.backgroundGrouped)
    }

    private func guideItem(_ title: String, _ detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 14.5, weight: .semibold))
                .foregroundStyle(c.textPrimary)
            Text(detail)
                .font(.system(size: 13))
                .foregroundStyle(c.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: AuroraRadius.md, style: .continuous)
                .fill(c.surface)
        )
    }
}
