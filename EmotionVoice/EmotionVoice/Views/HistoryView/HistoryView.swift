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

    /// 左右两栏头部统一高度
    private let panelHeaderHeight: CGFloat = 40

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
            .frame(height: panelHeaderHeight)
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
                            onCopy: {
                                viewModel.duplicateAudio(audio)
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
                            Image(systemName: "music.note.list")
                                .font(.system(size: 22))
                            Text("暂无音频")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(AppColor.textSecondary)
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

    private var isAllSelected: Bool {
        !viewModel.displayedAudios.isEmpty && selectedAudioIds.count == viewModel.displayedAudios.count
    }

    private var batchOperationBar: some View {
        VStack(spacing: 0) {
            Divider()
                .background(AppColor.borderSubtle)

            HStack(spacing: 12) {
                // 左侧：已选数量
                HStack(spacing: 8) {
                    Text("\(selectedAudioIds.count)")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppColor.bgPrimary)
                        .frame(minWidth: 22, minHeight: 22)
                        .padding(.horizontal, 6)
                        .background(AppColor.accentPrimary)
                        .clipShape(Capsule())

                    Text("已选择")
                        .font(.system(size: 13))
                        .foregroundStyle(AppColor.textSecondary)
                }

                Spacer()

                // 右侧：操作按钮组
                HStack(spacing: 6) {
                    // 全选 / 取消全选
                    Button {
                        if isAllSelected {
                            selectedAudioIds.removeAll()
                        } else {
                            selectAll()
                        }
                    } label: {
                        Text(isAllSelected ? "取消全选" : "全选")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppColor.accentPrimary)

                    Divider()
                        .frame(height: 16)
                        .padding(.horizontal, 2)

                    // 取消
                    Button("取消") {
                        exitSelectionMode()
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppColor.textSecondary)

                    // 删除
                    Button {
                        deleteSelected()
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 13))
                            .frame(width: 28, height: 22)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(selectedAudioIds.isEmpty ? AppColor.textTertiary : AppColor.statusError)
                    .disabled(selectedAudioIds.isEmpty)

                    // 导出
                    Button {
                        exportSelected()
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 13))
                            .frame(width: 28, height: 22)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(selectedAudioIds.isEmpty ? AppColor.textTertiary : AppColor.textPrimary)
                    .disabled(selectedAudioIds.isEmpty)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(AppColor.bgElevated)
    }

    // MARK: - 右侧播放详情面板

    private var playerDetailPanel: some View {
        VStack(spacing: 0) {
            // 工具栏
            HStack(spacing: 12) {
                Spacer()

                // 导出按钮
                if let selected = viewModel.selectedAudio, !isSelectionMode {
                    Button {
                        viewModel.exportAudio(selected)
                    } label: {
                        HStack(spacing: 6) {
                            if isExporting {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: AppColor.textTertiary))
                                    .scaleEffect(0.6)
                                    .frame(width: 14, height: 14)
                            } else {
                                Image(systemName: "square.and.arrow.up")
                                    .font(.system(size: 13))
                                Text("导出")
                                    .font(.system(size: 12))
                            }
                        }
                        .foregroundStyle(AppColor.textSecondary)
                        .padding(.horizontal, 12)
                        .frame(height: 30)
                        .background(AppColor.bgTertiary)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(AppColor.borderSubtle, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(isExporting)
                    .pointingHandCursor()
                    .help("导出音频")
                }
            }
            .padding(.horizontal, 22)
            .frame(height: panelHeaderHeight)
            .background(Color(hex: 0x15171B).opacity(0.5))
            .overlay(alignment: .bottom) {
                Divider().background(AppColor.borderSubtle)
            }

            if let audio = viewModel.selectedAudio {
                // 有选中音频 - 显示播放详情 + 底部状态栏
                AudioPlayerDetailView(
                    audio: audio,
                    player: viewModel.player
                )
                // 面板可见期间接管播放快捷键（空格 / ←→ / ⇧←→ / Home / End）
                .playbackKeyboardShortcuts(player: viewModel.player, audio: audio)

                PlaybackStatusBar(player: viewModel.player)
            } else {
                // 空状态
                VStack(spacing: 16) {
                    Spacer()

                    ZStack {
                        Circle()
                            .fill(AppColor.bgSecondary)
                            .frame(width: 64, height: 64)
                        Image(systemName: "music.quarternote.3")
                            .font(.system(size: 26))
                            .symbolEffect(.pulse)
                    }

                    Text("从列表中选择要播放的音频")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(AppColor.textSecondary)

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
        // 删除所有选中的音频
        for audio in audiosToDelete {
            viewModel.deleteAudio(audio)
        }

        // 清空选择
        selectedAudioIds.removeAll()
    }
}
