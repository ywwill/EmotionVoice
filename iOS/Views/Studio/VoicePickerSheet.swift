//
//  VoicePickerSheet.swift
//  iOSEmora
//
//  工作台里的「更换音色」。
//  macOS 是独立窗口级的音色库，iOS 收成一张 large detent 的 Sheet：搜索 + 列表 + 打勾。
//

import SwiftUI

struct VoicePickerSheet: View {
    @Environment(\.aurora) private var c
    @Environment(\.dismiss) private var dismiss

    @Binding var selectedKey: String

    @State private var searchText = ""
    @State private var all: [Voice] = []

    private let service = VoiceService.shared

    var body: some View {
        VStack(spacing: 0) {
            SheetNavBar(
                title: "选择音色".localized(),
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
                trailing: {
                    Button { dismiss() } label: {
                        Text("完成".localized())
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(c.accent)
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            )

            AuroraSearchField(text: $searchText, placeholder: "搜索音色名 / 特质 / 场景 / 语种".localized())
                .padding(.horizontal, 16)
                .padding(.bottom, 8)

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(filtered) { voice in
                        Button {
                            selectedKey = voice.key
                            dismiss()
                        } label: {
                            AuroraRow(
                                isSelected: voice.key == selectedKey,
                                leading: {
                                    HStack(spacing: 12) {
                                        VoiceAvatar(text: voice.localizedAvatar,
                                                    seed: voice.key,
                                                    size: 40)
                                        VStack(alignment: .leading, spacing: 3) {
                                            HStack(spacing: 6) {
                                                Text(voice.localizedName)
                                                    .font(.system(size: 15.5, weight: .semibold))
                                                    .foregroundStyle(c.textPrimary)
                                                    .lineLimit(1)
                                                if voice.isPremium {
                                                    Text("⭐ 旗舰".localized())
                                                        .font(.system(size: 10, weight: .semibold))
                                                        .foregroundStyle(Color(hex: 0xFFB457))
                                                }
                                            }
                                            Text(voice.localizedDesc)
                                                .font(.system(size: 12))
                                                .foregroundStyle(c.textSecondary)
                                                .lineLimit(1)
                                        }
                                    }
                                },
                                trailing: {
                                    if voice.key == selectedKey {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 15, weight: .semibold))
                                            .foregroundStyle(c.accent)
                                            .frame(width: 17)
                                    } else {
                                        Color.clear.frame(width: 17)
                                    }
                                }
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: AuroraRadius.md, style: .continuous)
                        .fill(c.surface)
                )
                .padding(.horizontal, 16)
                .padding(.bottom, 20)
            }
        }
        .background(c.backgroundGrouped)
        .onAppear {
            if all.isEmpty { all = service.fetchAll() }
        }
    }

    private var filtered: [Voice] {
        let needle = searchText.trimmingCharacters(in: .whitespaces)
        guard !needle.isEmpty else { return all }
        let lowered = needle.lowercased()
        return all.filter { v in
            v.localizedName.lowercased().contains(lowered)
            || v.name.lowercased().contains(lowered)
            || v.nameEn.lowercased().contains(lowered)
            || v.localizedDesc.lowercased().contains(lowered)
            || v.localizedScene.lowercased().contains(lowered)
            || v.key.lowercased().contains(lowered)
        }
    }
}
