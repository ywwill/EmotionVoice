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

    /// 左栏固定宽度
    private let panelWidth: CGFloat = 340
    /// 左右两栏头部统一高度
    private let panelHeaderHeight: CGFloat = 40
    /// 头部左右内边距
    private let headerPadding: CGFloat = 20
    /// 头部元素间距
    private let headerSpacing: CGFloat = 12
    /// waveform 图标预留槽位（SF Symbol 实际宽度通常略大于字号，留 24 防止与搜索框挤到一起）
    private let headerIconSlot: CGFloat = 24

    /// 搜索框展开后的宽度：撑满「waveform 图标 → 栏右边缘」的剩余空间。
    /// 展开是从右往左生长，所以左边缘最终会停在紧贴 waveform 图标的位置。
    private var searchExpandedWidth: CGFloat {
        panelWidth - headerPadding * 2 - headerIconSlot - headerSpacing
    }

    // MARK: - 日期分组（对齐 iOS 的「今天 / 昨天 / yyyy.MM.dd」）

    /// 组头完整日期固定 `yyyy.MM.dd`：POSIX locale + 公历，三语下都是同一串数字；
    /// 时区跟本地，与分桶用的 `Calendar.current` 午夜边界保持一致。
    private static let dayTitleFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = .current
        f.calendar = gregorian
        f.dateFormat = "yyyy.MM.dd"
        return f
    }()

    /// 按自然日分桶：今天 / 昨天各一组，其余一天一组，最新日期在最前。
    /// ⚠️ 桶 key 用 `startOfDay`，不能用「距今天数」；组 id 刻意不跟本地化标题走，
    /// 否则切换语言时 Section 身份变化会触发整组重建 / 滚动跳变。
    private var daySections: [HistoryDaySection] {
        let cal = Calendar.current
        let startToday = cal.startOfDay(for: Date())
        let startYesterday = cal.date(byAdding: .day, value: -1, to: startToday) ?? startToday

        var buckets: [Date: [AudioItem]] = [:]
        for item in viewModel.displayedAudios {
            buckets[cal.startOfDay(for: item.createdAt), default: []].append(item)
        }

        return buckets.keys.sorted(by: >).compactMap { day -> HistoryDaySection? in
            guard let list = buckets[day], !list.isEmpty else { return nil }
            let title: String
            let id: String
            if day == startToday {
                title = "今天".localized()
                id = "today"
            } else if day == startYesterday {
                title = "昨天".localized()
                id = "yesterday"
            } else {
                title = Self.dayTitleFormatter.string(from: day)
                id = "day-\(title)"
            }
            return HistoryDaySection(
                id: id,
                title: title,
                items: list.sorted { $0.createdAt > $1.createdAt }
            )
        }
    }

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
            TextField("", text: $renameText)
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
            Text("")
        }
    }

    // MARK: - 左侧音频列表面板

    private var audioListPanel: some View {
        VStack(spacing: 0) {
            // 列表头部 - 搜索框区域
            HStack(spacing: headerSpacing) {
                Image(systemName: "waveform.path")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(AppColor.accentPrimary)
                    .frame(width: headerIconSlot)

                ExpandableSearchField(
                    text: $viewModel.searchText,
                    placeholder: "搜索",
                    expandedWidth: searchExpandedWidth
                )
                .frame(width: searchExpandedWidth, alignment: .trailing)
            }
            // 头部宽度也钉死（= 栏宽 - 左右内边距），保证 overlay 的 Divider 宽度不随内容变
            .frame(width: panelWidth - headerPadding * 2, height: panelHeaderHeight)
            .padding(.horizontal, headerPadding)
            .overlay(alignment: .bottom) {
                Divider().background(AppColor.borderSubtle)
            }

            // 音频列表：按自然日分组（今天 / 昨天 / yyyy.MM.dd）
            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                    ForEach(daySections) { section in
                        Section {
                            LazyVStack(spacing: 4) {
                                ForEach(section.items) { audio in
                                    audioRow(audio)
                                }
                            }
                            .padding(.horizontal, 12)
                        } header: {
                            HistoryDaySectionHeader(section: section)
                        }
                    }

                    // 加载更多：只在所有分组之后放一处，避免每个 Section 各触发一次分页
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
                .padding(.bottom, 8)
            }

            // 批量操作菜单
            if isSelectionMode && !selectedAudioIds.isEmpty {
                batchOperationBar
            } else if isSelectionMode {
                batchOperationBar
            }
        }
        .frame(width: panelWidth)
        .background(AppColor.bgSecondary)
        .overlay(alignment: .trailing) {
            Divider().background(AppColor.borderSubtle)
        }
    }

    // MARK: - 列表行

    private func audioRow(_ audio: AudioItem) -> some View {
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

// MARK: - 历史记录日期分组（macOS 专属；iOS 用 HistorySection / HistorySectionHeader）

private struct HistoryDaySection: Identifiable {
    let id: String
    let title: String
    let items: [AudioItem]
}

/// 组头只显示日期 + 横线；按用户要求不显示「%d 条」计数。
/// ⚠️ 背景必须不透明，否则吸顶时下方滚动内容会透出来。
private struct HistoryDaySectionHeader: View {
    let section: HistoryDaySection

    var body: some View {
        HStack(spacing: 8) {
            Text(section.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppColor.textSecondary)
                .fixedSize(horizontal: true, vertical: false)
            Rectangle()
                .fill(AppColor.borderSubtle)
                .frame(height: 0.5)
        }
        .padding(.horizontal, 12)
        .padding(.top, 13)
        .padding(.bottom, 7)
        .background(AppColor.bgSecondary)
    }
}
