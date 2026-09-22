//
//  HistoryView.swift
//  EmotionVoice
//
//  历史记录视图 - 两栏布局：左侧音频列表 | 右侧播放详情
//

import SwiftUI
import Combine
import AppKit

/// 历史记录视图 - 两栏布局
struct HistoryView: View {

    @StateObject private var viewModel = HistoryViewModel()
    @State private var isExporting: Bool = false
    @State private var showRenameAlert: Bool = false
    @State private var renameText: String = ""
    @State private var audioToRename: AudioItem?
    @State private var isSelectionMode: Bool = false
    @State private var selectedAudioIds: Set<Int64> = []

    var body: some View {
        HStack(spacing: 0) {
            // 左侧音频列表
            audioListPanel

            // 右侧播放详情
            playerDetailPanel
        }
        .background(AppColor.bgPrimary)
        .onAppear {
            viewModel.loadInitialData()
        }
        .alert("编辑名称", isPresented: $showRenameAlert) {
            TextField("音频名称", text: $renameText)
            Button("取消", role: .cancel) {
                audioToRename = nil
                renameText = ""
            }
            Button("保存") {
                if let audio = audioToRename {
                    viewModel.renameAudio(audio, newName: renameText)
                }
                audioToRename = nil
                renameText = ""
            }
        } message: {
            Text("请输入新的音频名称")
        }
    }

    // MARK: - 左侧音频列表面板

    private var audioListPanel: some View {
        VStack(spacing: 0) {
            // 列表头部 - 搜索框区域
            HStack(spacing: 12) {
                Image(systemName: "waveform")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppColor.accentPrimary)
                
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 11))
                        .foregroundStyle(AppColor.textTertiary)

                    TextField("搜索音频...", text: $viewModel.searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12))
                        .foregroundStyle(AppColor.textPrimary)
                        .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(AppColor.bgTertiary)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(AppColor.borderSubtle, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .frame(height: 40)
            .padding(.horizontal, 20)
            .overlay(alignment: .bottom) {
                Divider().background(AppColor.borderSubtle)
            }

            // 音频列表
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(viewModel.displayedAudios) { audio in
                        AudioRowItem(
                            audio: audio,
                            isSelected: viewModel.selectedAudio?.id == audio.id,
                            isPlaying: viewModel.isPlayingAudio(audio),
                            isSelectionMode: isSelectionMode,
                            isChecked: selectedAudioIds.contains(audio.id),
                            onSelect: {
                                viewModel.selectAudio(audio)
                            },
                            onToggleSelection: {
                                toggleSelection(audio)
                            },
                            onRename: {
                                audioToRename = audio
                                renameText = audio.shownName
                                showRenameAlert = true
                            },
                            onExport: {
                                viewModel.selectAudio(audio)
                                viewModel.exportAudio(audio)
                            },
                            onDelete: {
                                viewModel.deleteAudio(audio)
                            },
                            onBatchSelect: {
                                enterSelectionMode()
                            }
                        )
                    }

                    // 加载更多
                    if viewModel.hasMorePages {
                        HStack {
                            Spacer()
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: AppColor.textTertiary))
                                .scaleEffect(0.8)
                            Text("加载中...")
                                .font(.system(size: 12))
                                .foregroundStyle(AppColor.textTertiary)
                            Spacer()
                        }
                        .padding(.vertical, 16)
                        .onAppear {
                            viewModel.loadNextPage()
                        }
                    }

                    // 空状态
                    if viewModel.displayedAudios.isEmpty && !viewModel.isLoading {
                        VStack(spacing: 12) {
                            Text("🎧")
                                .font(.system(size: 36))
                            Text("暂无音频")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(AppColor.textSecondary)
                            Text("前往「语音合成」生成你的第一条音频")
                                .font(.system(size: 12))
                                .foregroundStyle(AppColor.textTertiary)
                        }
                        .padding(60)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }

            // 批量操作菜单
            if isSelectionMode && !selectedAudioIds.isEmpty {
                batchOperationBar
            } else if isSelectionMode {
                batchOperationBar
            }
        }
        .frame(width: 340)
        .background(AppColor.bgSecondary)
        .overlay(alignment: .trailing) {
            Divider().background(AppColor.borderSubtle)
        }
    }

    // MARK: - 批量操作栏

    private var batchOperationBar: some View {
        VStack(spacing: 0) {
            Divider().background(AppColor.borderSubtle)

            // 操作按钮组
            HStack(spacing: 12) {
                // 辅助操作区
                HStack(spacing: 8) {
                    Button {
                        selectAll()
                    } label: {
                        Text("全选")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(AppColor.textSecondary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(AppColor.bgTertiary)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)

                    Button {
                        exitSelectionMode()
                    } label: {
                        Text("取消")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(AppColor.textSecondary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(AppColor.bgTertiary)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                // 危险操作区
                HStack(spacing: 8) {
                    Button {
                        exportSelected()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 11))
                        }
                        .foregroundStyle(selectedAudioIds.isEmpty ? AppColor.textTertiary : AppColor.textPrimary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(AppColor.bgTertiary)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(selectedAudioIds.isEmpty ? Color.clear : AppColor.borderSubtle, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedAudioIds.isEmpty)
                    .help("导出音频")

                    Button {
                        deleteSelected()
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "trash")
                                .font(.system(size: 11))
                        }
                        .foregroundStyle(selectedAudioIds.isEmpty ? AppColor.textTertiary : AppColor.statusError)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(selectedAudioIds.isEmpty ? AppColor.bgTertiary : AppColor.statusError.opacity(0.12))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedAudioIds.isEmpty)
                    .help("删除")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(AppColor.bgTertiary)
        }
    }

    // MARK: - 右侧播放详情面板

    private var playerDetailPanel: some View {
        VStack(spacing: 0) {
            // 工具栏
            HStack {
                Text(viewModel.selectedAudio?.shownName ?? "选择音频播放")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppColor.textPrimary)
                    .lineLimit(1)

                Spacer()

                // 导出按钮
                if viewModel.selectedAudio != nil && !isSelectionMode {
                    Button {
                        viewModel.exportAudio(viewModel.selectedAudio!)
                    } label: {
                        if isExporting {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: AppColor.textTertiary))
                                .scaleEffect(0.7)
                        } else {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 14))
                                .foregroundStyle(AppColor.textTertiary)
                        }
                    }
                    .frame(width: 32, height: 32)
                    .disabled(isExporting)
                    .help("导出音频")
                }
            }
            .padding(.horizontal, 20)
            .frame(height: 40)
            .background(Color(hex: 0x15171B).opacity(0.5))
            .overlay(alignment: .bottom) {
                Divider().background(AppColor.borderSubtle)
            }

            if let audio = viewModel.selectedAudio {
                // 有选中音频 - 显示播放详情
                AudioPlayerDetailView(
                    audio: audio,
                    player: viewModel.player
                )
            } else {
                // 空状态
                VStack(spacing: 16) {
                    Spacer()

                    ZStack {
                        Circle()
                            .fill(AppColor.bgSecondary)
                            .frame(width: 64, height: 64)
                        Text("🎵")
                            .font(.system(size: 24))
                    }

                    Text("选择一个音频")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(AppColor.textSecondary)

                    Text("从左侧列表中选择要播放的音频")
                        .font(.system(size: 12))
                        .foregroundStyle(AppColor.textTertiary)

                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColor.bgPrimary)
    }

    // MARK: - 批量选择方法

    private func enterSelectionMode() {
        isSelectionMode = true
        selectedAudioIds.removeAll()
    }

    private func exitSelectionMode() {
        isSelectionMode = false
        selectedAudioIds.removeAll()
    }

    private func toggleSelection(_ audio: AudioItem) {
        if selectedAudioIds.contains(audio.id) {
            selectedAudioIds.remove(audio.id)
        } else {
            selectedAudioIds.insert(audio.id)
        }
    }

    private func selectAll() {
        selectedAudioIds = Set(viewModel.displayedAudios.map { $0.id })
    }

    private func exportSelected() {
        guard !selectedAudioIds.isEmpty else { return }

        // 获取选中的音频
        let selectedAudios = viewModel.displayedAudios.filter { selectedAudioIds.contains($0.id) }

        // 打开目录选择面板
        let openPanel = NSOpenPanel()
        openPanel.title = "选择导出目录".localized()
        openPanel.canChooseFiles = false
        openPanel.canChooseDirectories = true
        openPanel.canCreateDirectories = true
        openPanel.prompt = "导出到此处".localized()

        openPanel.begin { response in
            guard response == .OK, let targetDirectory = openPanel.url else { return }

            var exportedFiles: [URL] = []

            for audio in selectedAudios {
                guard let sourceURL = audio.absoluteURL as URL? else { continue }

                // 使用 shownName + 源文件扩展名，确保导出的文件有正确的后缀
                let fileName: String
                if !audio.fileExtension.isEmpty {
                    fileName = audio.shownName + "." + audio.fileExtension
                } else {
                    fileName = audio.shownName
                }
                let destinationURL = targetDirectory.appendingPathComponent(fileName)

                do {
                    if FileManager.default.fileExists(atPath: destinationURL.path) {
                        try FileManager.default.removeItem(at: destinationURL)
                    }
                    try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
                    exportedFiles.append(destinationURL)
                    Log(message: "HistoryView: 批量导出成功 - \(destinationURL.path)")
                } catch {
                    Log(message: "HistoryView: 批量导出失败 - \(error.localizedDescription)")
                }
            }

            // 打开导出目录
            if !exportedFiles.isEmpty {
                NSWorkspace.shared.activateFileViewerSelecting(exportedFiles)
            }
        }
    }

    private func deleteSelected() {
        guard !selectedAudioIds.isEmpty else { return }

        // 获取要删除的音频
        let audiosToDelete = viewModel.displayedAudios.filter { selectedAudioIds.contains($0.id) }

        // 检查是否有正在播放的音频被删除
        for audio in audiosToDelete {
            if viewModel.isPlayingAudio(audio) {
                viewModel.stopAudio()
                break
            }
        }

        // 删除所有选中的音频
        for audio in audiosToDelete {
            viewModel.deleteAudio(audio)
        }

        // 清空选择
        selectedAudioIds.removeAll()
    }
}

// MARK: - 历史记录视图模型

@MainActor
class HistoryViewModel: ObservableObject {

    // MARK: - 发布属性

    @Published var selectedAudio: AudioItem?
    @Published var searchText: String = "" {
        didSet {
            filterAndDisplay()
        }
    }
    @Published var displayedAudios: [AudioItem] = []
    @Published var totalCount: Int = 0
    @Published var isLoading: Bool = false
    @Published var hasMorePages: Bool = true

    let player = AudioPreviewPlayer.shared

    // MARK: - 私有属性

    private var currentPage: Int = 1
    private var allLoadedAudios: [AudioItem] = []

    // MARK: - 方法

    func loadInitialData() {
        currentPage = 1
        allLoadedAudios = []
        hasMorePages = true
        displayedAudios = []
        loadPage()
    }

    func loadNextPage() {
        guard !isLoading && hasMorePages else { return }
        currentPage += 1
        loadPage()
    }

    private func loadPage() {
        guard !isLoading else { return }
        isLoading = true

        let result = ProjectService.shared.fetchAudios(page: currentPage, pageSize: ProjectService.pageSize)
        let audios = result.audios
        totalCount = result.total

        if audios.isEmpty {
            hasMorePages = false
        } else {
            allLoadedAudios.append(contentsOf: audios)
            filterAndDisplay()
        }

        isLoading = false
    }

    func selectAudio(_ audio: AudioItem) {
        selectedAudio = audio
        playAudio(audio)
    }

    func playAudio(_ audio: AudioItem) {
        guard audio.isOnDisk else { return }
        if let url = audio.absoluteURL as URL? {
            player.play(url: url)
        }
    }

    func stopAudio() {
        player.stop()
    }

    func deleteAudio(_ audio: AudioItem) {
        // 如果删除的是正在播放或选中的音频，先停止
        if selectedAudio?.id == audio.id {
            player.stop()
            selectedAudio = nil
        }

        // 从列表中移除
        allLoadedAudios.removeAll { $0.id == audio.id }
        filterAndDisplay()
        totalCount = max(0, totalCount - 1)
    }

    func renameAudio(_ audio: AudioItem, newName: String) {
        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        ProjectService.shared.renameAudio(id: audio.id, displayName: trimmedName)

        // 更新本地数据 - 直接修改 displayName
        if let index = allLoadedAudios.firstIndex(where: { $0.id == audio.id }) {
            allLoadedAudios[index].displayName = trimmedName
        }
        filterAndDisplay()

        // 如果重命名的是当前选中的音频，也更新选中状态
        if selectedAudio?.id == audio.id {
            selectedAudio?.displayName = trimmedName
        }
    }

    func isPlayingAudio(_ audio: AudioItem) -> Bool {
        guard let url = audio.absoluteURL as URL? else { return false }
        return player.isPlaying(url: url)
    }

    func exportAudio(_ audio: AudioItem) {
        guard let sourceURL = audio.absoluteURL as URL? else { return }

        // 确保文件名带有正确的扩展名
        let fileName: String
        if !audio.fileExtension.isEmpty {
            fileName = audio.shownName + "." + audio.fileExtension
        } else {
            fileName = audio.shownName
        }

        let savePanel = NSSavePanel()
        savePanel.title = "导出音频".localized()
        savePanel.nameFieldStringValue = fileName
        savePanel.canCreateDirectories = true

        // 显示面板并处理结果
        savePanel.begin { response in
            if response == .OK, let destinationURL = savePanel.url {
                do {
                    if FileManager.default.fileExists(atPath: destinationURL.path) {
                        try FileManager.default.removeItem(at: destinationURL)
                    }
                    try FileManager.default.copyItem(at: sourceURL, to: destinationURL)

                    // 打开包含导出文件的文件夹
                    NSWorkspace.shared.activateFileViewerSelecting([destinationURL])
                    Log(message: "HistoryView: 导出成功 - \(destinationURL.path)")
                } catch {
                    Log(message: "HistoryView: 导出失败 - \(error.localizedDescription)")
                }
            }
        }
    }

    private func filterAndDisplay() {
        let filtered: [AudioItem]
        if searchText.isEmpty {
            filtered = allLoadedAudios
        } else {
            filtered = allLoadedAudios.filter {
                $0.shownName.localizedCaseInsensitiveContains(searchText)
            }
        }
        displayedAudios = filtered

        // 检查是否需要加载更多
        hasMorePages = displayedAudios.count < totalCount && searchText.isEmpty
    }
}
