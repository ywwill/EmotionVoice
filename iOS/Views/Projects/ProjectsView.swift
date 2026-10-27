//
//  ProjectsView.swift
//  iOSEmora
//
//  我的项目列表
//
//  macOS 是「左 340pt 列表 + 右详细信息」两栏同屏，iOS 改为 push 导航栈：
//  - 点任意行「选中即播放」并 push 播放详情
//  - 右键 popover 菜单（编辑名称 / 复制 / 删除）→ **左滑 Swipe Actions**
//  - macOS 菜单里的「批量操作」→ 导航栏「选择」进入多选 + 底部工具条
//    （`safeAreaInset` 挂在标签栏之上）
//
//  搜索沿用 `HistoryViewModel`：只在**本地已加载数据**里过滤，与 macOS 一致。
//

import SwiftUI
import UniformTypeIdentifiers

struct ProjectsView: View {
    @Environment(\.aurora) private var c
    @Environment(\.screenMetrics) private var metrics

    @EnvironmentObject private var uiState: IOSUIState
    @EnvironmentObject private var router: TabRouter

    @StateObject private var vm = HistoryViewModel()
    @StateObject private var player = AudioPreviewPlayer.shared

    // MARK: 多选

    @State private var isSelecting = false
    @State private var selectedIDs: Set<Int64> = []

    // MARK: 重命名

    @State private var renameTarget: AudioItem? = nil
    @State private var renameText: String = ""

    // MARK: 删除确认

    @State private var deleteTarget: AudioItem? = nil
    @State private var deleteMany = false

    // MARK: 分享 / 导出

    @State private var shareURLs: [URL] = []
    @State private var isSharing = false
    @State private var isExporting = false
    @State private var exportItem: AudioItem? = nil

    /// key → 展示名（首屏拉一次，避免每行都查库）
    @State private var voiceNames: [String: String] = [:]

    var body: some View {
        List {
            Section {
                ForEach(vm.displayedAudios) { audio in
                    row(audio)
                        .listRowInsets(EdgeInsets(top: 5, leading: 12, bottom: 5, trailing: 12))
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) { deleteTarget = audio } label: {
                                Label("删除".localized(), systemImage: "trash.fill")
                            }
                            Button { duplicate(audio) } label: {
                                Label("复制".localized(), systemImage: "doc.on.doc.fill")
                            }
                            .tint(c.info)
                            Button { beginRename(audio) } label: {
                                Label("重命名".localized(), systemImage: "pencil")
                            }
                            .tint(c.success)
                        }
                        .onAppear { loadMoreIfNeeded(audio) }
                }
            } header: {
                if vm.displayedAudios.isEmpty && !vm.isLoading { emptyHint }
            } footer: {
                footerHint
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(c.backgroundGrouped)
        .searchable(text: $vm.searchText, prompt: "搜索音频名称".localized())
        .navigationTitle("项目".localized())
        .toolbar { toolbarContent }
        .safeAreaInset(edge: .bottom) {
            if isSelecting { selectionBar }
        }
        .sheet(isPresented: $isSharing) { ShareSheet(items: shareURLs) }
        .fileExporter(isPresented: $isExporting,
                      document: exportDocument,
                      contentType: exportContentType,
                      defaultFilename: exportFileName) { _ in }
        .alert("重命名".localized(), isPresented: renamePresented) {
            TextField("音频名称".localized(), text: $renameText)
            Button("取消".localized(), role: .cancel) { renameTarget = nil }
            Button("保存".localized()) { commitRename() }
        } message: {
            Text("给这条音频起一个更好记的名字".localized())
        }
        .alert("删除音频".localized(), isPresented: deletePresented) {
            Button("取消".localized(), role: .cancel) { deleteTarget = nil; deleteMany = false }
            Button("删除".localized(), role: .destructive) { commitDelete() }
        } message: {
            Text(deleteMessage)
        }
        .task {
            vm.loadInitialData()
            preloadVoiceNames()
        }
    }

    // MARK: - 行

    private func row(_ audio: AudioItem) -> some View {
        HStack(spacing: 11) {
            if isSelecting {
                selectionCircle(audio)
            }

            VoiceAvatar(text: avatarText(audio), seed: audio.voice, size: 44, corner: 12)

            VStack(alignment: .leading, spacing: 3) {
                Text(audio.shownName)
                    .font(.system(size: 15.5, weight: .medium))
                    .foregroundStyle(c.textPrimary)
                    .lineLimit(1)
                Text(metaLine(audio))
                    .font(.system(size: 11.5))
                    .foregroundStyle(c.textTertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if isPlaying(audio) {
                PlayingBars(color: c.accent)
                    .frame(width: 16, height: 14)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: AuroraRadius.sm, style: .continuous)
                .fill(isPlaying(audio) ? c.surface2 : c.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: AuroraRadius.sm, style: .continuous)
                        .strokeBorder(isPlaying(audio) ? c.accent.opacity(0.35) : c.line,
                                      lineWidth: 0.5)
                )
        )
        .contentShape(Rectangle())
        .onTapGesture { tap(audio) }
    }

    private func selectionCircle(_ audio: AudioItem) -> some View {
        let on = selectedIDs.contains(audio.id)
        return ZStack {
            Circle()
                .fill(on ? c.accent : Color.clear)
                .overlay(
                    Circle().strokeBorder(on ? Color.clear : c.line2, lineWidth: 1.5)
                )
            if on {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 23, height: 23)
    }

    // MARK: - 空态 / 底部

    private var emptyHint: some View {
        VStack(spacing: 8) {
            Image(systemName: "folder")
                .font(.system(size: 28))
                .foregroundStyle(c.textTertiary.opacity(0.6))
            Text(vm.searchText.isEmpty ? "还没有生成的音频".localized() : "没有匹配的音频".localized())
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(c.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
    }

    @ViewBuilder
    private var footerHint: some View {
        if vm.isLoading {
            HStack(spacing: 7) {
                ProgressView().controlSize(.small)
                Text("加载中…".localized())
                    .font(.system(size: 12))
                    .foregroundStyle(c.textTertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        } else if vm.hasMorePages && !vm.displayedAudios.isEmpty {
            Text("上拉加载更多".localized())
                .font(.system(size: 12))
                .foregroundStyle(c.textTertiary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .onAppear { vm.loadNextPage() }
        }
    }

    // MARK: - 导航栏

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            HStack(spacing: 14) {
                Button { router.openSettings() } label: {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(c.accent)
                        .frame(width: 30, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Button {
                    withAnimation(.easeOut(duration: 0.18)) {
                        isSelecting.toggle()
                        if !isSelecting { selectedIDs = [] }
                    }
                } label: {
                    Text(isSelecting ? "完成".localized() : "选择".localized())
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(c.accent)
                        .frame(height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - 多选工具条

    private var selectionBar: some View {
        HStack(spacing: 14) {
            Text("\(selectedIDs.count)")
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(Capsule(style: .continuous).fill(c.accent))

            Text("已选择".localized())
                .font(.system(size: 13))
                .foregroundStyle(c.textSecondary)

            Spacer(minLength: 0)

            Button {
                if selectedIDs.count == vm.displayedAudios.count {
                    selectedIDs = []
                } else {
                    selectedIDs = Set(vm.displayedAudios.map(\.id))
                }
            } label: {
                Text(selectedIDs.count == vm.displayedAudios.count ? "取消全选".localized() : "全选".localized())
                    .font(.system(size: 14.5, weight: .semibold))
                    .foregroundStyle(c.accent)
            }
            .buttonStyle(.plain)

            Rectangle()
                .fill(c.line2)
                .frame(width: 1, height: 22)

            Button { shareSelected() } label: {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(selectedIDs.isEmpty ? c.textTertiary : c.accent)
            }
            .buttonStyle(.plain)
            .disabled(selectedIDs.isEmpty)

            Button {
                deleteMany = true
            } label: {
                Image(systemName: "trash.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(selectedIDs.isEmpty ? c.textTertiary : c.danger)
            }
            .buttonStyle(.plain)
            .disabled(selectedIDs.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(c.bar)
        .overlay(alignment: .top) { Hairline() }
    }

    // MARK: - 行为

    private func tap(_ audio: AudioItem) {
        if isSelecting {
            if selectedIDs.contains(audio.id) {
                selectedIDs.remove(audio.id)
            } else {
                selectedIDs.insert(audio.id)
            }
            return
        }
        vm.selectAudio(audio)
        router.push(.player(audio))
    }

    private func loadMoreIfNeeded(_ audio: AudioItem) {
        guard audio.id == vm.displayedAudios.last?.id else { return }
        vm.loadNextPage()
    }

    private func isPlaying(_ audio: AudioItem) -> Bool {
        vm.isPlayingAudio(audio)
    }

    private func duplicate(_ audio: AudioItem) {
        vm.duplicateAudio(audio)
        uiState.showToast(.success("已复制音频".localized()))
    }

    private func beginRename(_ audio: AudioItem) {
        renameTarget = audio
        renameText = audio.shownName
    }

    private func commitRename() {
        guard let target = renameTarget else { return }
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty, trimmed != target.shownName {
            vm.renameAudio(target, newName: trimmed)
        }
        renameTarget = nil
    }

    private func commitDelete() {
        if deleteMany {
            let ids = selectedIDs
            for audio in vm.displayedAudios where ids.contains(audio.id) {
                vm.deleteAudio(audio)
            }
            selectedIDs = []
            deleteMany = false
        } else if let target = deleteTarget {
            vm.deleteAudio(target)
            deleteTarget = nil
        }
    }

    private func shareSelected() {
        let urls = vm.displayedAudios
            .filter { selectedIDs.contains($0.id) }
            .compactMap { audio -> URL? in
                guard audio.isOnDisk else { return nil }
                return audio.absoluteURL
            }
        guard !urls.isEmpty else {
            uiState.showToast(.failure("所选音频文件不存在".localized()))
            return
        }
        shareURLs = urls
        isSharing = true
    }

    // MARK: 导出（单个，fileExporter 替代 NSSavePanel）

    func beginExport(_ audio: AudioItem) {
        exportItem = audio
        isExporting = true
    }

    private var exportFileName: String {
        guard let item = exportItem else { return "audio" }
        return item.fileExtension.isEmpty ? item.shownName : "\(item.shownName).\(item.fileExtension)"
    }

    private var exportContentType: UTType {
        switch exportItem?.fileExtension.lowercased() ?? "" {
        case "mp3": return .mp3
        case "m4a": return .mpeg4Audio
        case "wav": return .wav
        default: return .audio
        }
    }

    private var exportDocument: AudioFileDocument? {
        guard let item = exportItem,
              let data = try? Data(contentsOf: item.absoluteURL) else { return nil }
        return AudioFileDocument(data: data)
    }

    // MARK: Alert 绑定

    private var renamePresented: Binding<Bool> {
        Binding(get: { renameTarget != nil }, set: { if !$0 { renameTarget = nil } })
    }

    private var deletePresented: Binding<Bool> {
        Binding(get: { deleteTarget != nil || deleteMany }, set: { if !$0 { deleteTarget = nil; deleteMany = false } })
    }

    private var deleteMessage: String {
        if deleteMany {
            return String(format: "确定删除选中的 %d 条音频？删除后无法恢复。".localized(), selectedIDs.count)
        }
        return "确定删除这条音频？删除后无法恢复。".localized()
    }

    // MARK: - 展示

    private func metaLine(_ audio: AudioItem) -> String {
        let voice = voiceNames[audio.voice] ?? audio.voice
        return "\(voice) · \(formatDuration(audio.duration)) · \(formatDataSize(audio.fileSize))"
    }

    private func avatarText(_ audio: AudioItem) -> String {
        let name = voiceNames[audio.voice] ?? audio.voice
        return name.isEmpty ? "声" : String(name.suffix(1))
    }

    private func preloadVoiceNames() {
        var map: [String: String] = [:]
        for v in VoiceService.shared.fetchAll() {
            map[v.key] = v.localizedName
        }
        voiceNames = map
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

private struct PlayingBar: View {
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
