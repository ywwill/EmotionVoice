//
//  RecentlyDeletedView.swift
//  iOSEmora
//
//  最近删除页（从历史记录右上角 ⋯ 菜单 push 进来）。
//  按剩余天数分组，单行「恢复」，左滑「彻底删除」，底部「清空」需二次确认。
//  ⚠️ 到期前磁盘文件不删，只按 AudioFlagStore 的 deleted_at 过滤；到期清理在
//     `HistoryListViewModel.load()` / App 启动时执行一次。
//

import SwiftUI
import Combine

struct RecentlyDeletedView: View {
    @Environment(\.aurora) private var c
    @Environment(\.screenMetrics) private var metrics
    @EnvironmentObject private var uiState: IOSUIState

    @StateObject private var flags = AudioFlagStore.shared

    @State private var items: [AudioItem] = []
    @State private var sections: [HistorySection] = []
    @State private var confirmTarget: ConfirmTarget? = nil
    @State private var voiceNames: [String: String] = [:]

    private enum ConfirmTarget: Identifiable, Equatable {
        case clearAll
        case deleteOne(Int64)

        var id: String {
            switch self {
            case .clearAll: return "clearAll"
            case .deleteOne(let id): return "delete-\(id)"
            }
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                notice

                Text("最近删除".localized())
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(c.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, metrics.pageMargin)
                    .padding(.top, 6)

                Text("保留 30 天，到期自动清除".localized())
                    .font(.system(size: 12.5))
                    .foregroundStyle(c.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, metrics.pageMargin)
                    .padding(.top, 3)
                    .padding(.bottom, 12)

                if sections.isEmpty {
                    emptyHint
                } else {
                    ForEach(sections) { section in
                        Section {
                            ForEach(section.items) { audio in
                                row(audio)
                                    .padding(.horizontal, 12)
                                    .padding(.bottom, 7)
                                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                        Button(role: .destructive) {
                                            confirmTarget = .deleteOne(audio.id)
                                        } label: {
                                            Label("彻底删除".localized(), systemImage: "trash.fill")
                                        }
                                    }
                            }
                        } header: {
                            HistorySectionHeader(section: section)
                        }
                    }
                }
            }
            .padding(.bottom, 20)
        }
        .background(c.backgroundGrouped)
        .scrollContentBackground(.hidden)
        .navigationTitle("最近删除".localized())
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) {
            if !sections.isEmpty { clearAllBar }
        }
        .alert(item: $confirmTarget) { target in
            Alert(
                title: Text(target == .clearAll ? "清空最近删除？".localized() : "彻底删除？".localized()),
                message: Text("彻底删除不可撤销，音频文件也会被移除。".localized()),
                primaryButton: .destructive(
                    Text(target == .clearAll ? "清空".localized() : "彻底删除".localized()),
                    action: { performConfirm(target) }
                ),
                secondaryButton: .cancel(Text("取消".localized()))
            )
        }
        .onAppear { reload() }
    }

    // MARK: 区块

    private var notice: some View {
        HStack(spacing: 9) {
            Image(systemName: "clock")
                .font(.system(size: 16))
                .foregroundStyle(c.warning)
            Text("恢复后会回到原来的时间分组；彻底删除不可撤销。".localized())
                .font(.system(size: 11.5))
                .foregroundStyle(c.textSecondary)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(c.surface2)
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(c.line, lineWidth: 0.5)
                )
        )
        .padding(.horizontal, metrics.pageMargin)
        .padding(.bottom, 10)
    }

    private var emptyHint: some View {
        VStack(spacing: 10) {
            Image(systemName: "trash")
                .font(.system(size: 34))
                .foregroundStyle(c.textTertiary.opacity(0.6))
            Text("最近删除是空的".localized())
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(c.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 70)
    }

    private var clearAllBar: some View {
        Button {
            confirmTarget = .clearAll
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "trash.fill")
                    .font(.system(size: 15))
                Text("清空最近删除".localized())
                    .font(.system(size: 13.5, weight: .semibold))
            }
            .foregroundStyle(c.danger)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(c.bar)
        }
        .buttonStyle(.plain)
        .overlay(alignment: .top) { Hairline() }
    }

    // MARK: 行

    private func row(_ audio: AudioItem) -> some View {
        HStack(spacing: 11) {
            let name = voiceNames[audio.voice] ?? audio.voice
            VoiceAvatar(text: name.isEmpty ? "声" : String(name.suffix(1)),
                        seed: audio.voice, size: 44, corner: 12)

            VStack(alignment: .leading, spacing: 5) {
                Text(audio.shownName)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(c.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(deletedLabel(audio))
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(c.textTertiary)
                        .padding(.horizontal, 7)
                        .frame(height: 19)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(c.surface3)
                        )
                    Text(formatDuration(audio.duration))
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundStyle(c.textTertiary)
                }
            }

            Spacer(minLength: 0)

            Button {
                restore(audio)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: 11, weight: .semibold))
                    Text("恢复".localized())
                        .font(.system(size: 11.5, weight: .semibold))
                }
                .foregroundStyle(c.accent)
                .padding(.horizontal, 10)
                .frame(height: 26)
                .background(Capsule(style: .continuous).fill(c.accentSoft))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: AuroraRadius.md, style: .continuous)
                .fill(c.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: AuroraRadius.md, style: .continuous)
                        .strokeBorder(c.line, lineWidth: 0.5)
                )
        )
    }

    private func deletedLabel(_ audio: AudioItem) -> String {
        guard let date = flags.deletedDate(for: audio.id) else { return "" }
        return HistoryListViewModel.deletedTime(date)
    }

    // MARK: 行为

    private func reload() {
        var map: [String: String] = [:]
        for voice in VoiceService.shared.fetchAll() { map[voice.key] = voice.localizedName }
        voiceNames = map

        let deleted = flags.deletedIDs
        items = ProjectService.shared.fetchAllAudios()
            .filter { deleted.contains($0.id) }

        var buckets: [Int: [AudioItem]] = [:]
        for item in items {
            let days = flags.remainingDays(for: item.id)
            buckets[days, default: []].append(item)
        }
        sections = buckets.keys.sorted(by: >).map { days in
            let list = (buckets[days] ?? []).sorted { $0.createdAt > $1.createdAt }
            return HistorySection(id: "days-\(days)",
                                  title: "剩余 %d 天".localized(days),
                                  detail: nil,
                                  count: list.count,
                                  items: list)
        }
    }

    private func restore(_ audio: AudioItem) {
        flags.restore([audio.id])
        uiState.requestHistoryReload()
        reload()
        uiState.showToast(.success("已恢复音频".localized()))
    }

    private func performConfirm(_ target: ConfirmTarget) {
        let ids: [Int64]
        switch target {
        case .clearAll: ids = Array(flags.deletedIDs)
        case .deleteOne(let id): ids = [id]
        }
        guard !ids.isEmpty else { return }
        // ⚠️ 磁盘删除不夹在动画事务里
        for id in ids { ProjectService.shared.deleteAudio(id: id) }
        flags.clearFlags(ids)
        confirmTarget = nil
        reload()
        uiState.showToast(.success(ids.count == 1
                                   ? "已彻底删除".localized()
                                   : "已清空最近删除".localized()))
    }
}
