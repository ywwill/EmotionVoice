//
//  HistoryViewModel.swift
//  EmotionVoice
//
//  Created by young on 2026/10/14.
//

import Foundation
import SwiftUI
import Combine
#if canImport(AppKit)
import AppKit
#endif

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

    /// 删除一条音频：磁盘文件 + 库内记录，并从列表里移除
    func deleteAudio(_ audio: AudioItem) {
        // ⚠️ 以前这里只改 UI 数组，`ProjectService.deleteAudio` 从来没被调用过 ——
        // 行看着消失了，文件和库记录都还在，重新进页面 / 重启后又整排冒出来。
        ProjectService.shared.deleteAudio(id: audio.id)
        removeAudioItem(audio)
    }

    /// 只做列表移除（ playback 状态清理 + 刷新）。
    ///
    /// ⚠️ 从 `deleteAudio` 里拆出来是为了给动画用：`withAnimation` 的事务里**不能夹磁盘 IO**，
    /// 否则主线程被卡住，列表渲出来的第一帧是一片空白（左滑「复制」踩过同一个坑）。
    /// 调用方：先在外面把磁盘 / 库删干净，再把这个纯内存操作包进动画。
    func removeAudioItem(_ audio: AudioItem) {
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

    /// 复制音频（磁盘文件 + 库内记录），新副本插入列表顶部并自动选中
    func duplicateAudio(_ audio: AudioItem) {
        guard let copy = ProjectService.shared.duplicateAudio(audio) else { return }
        appendAudioItem(copy)
    }

    /// 把一个**已经建好的**音频条目纯追加进列表顶部（不碰磁盘、不查库）。
    ///
    /// ⚠️ 之所以从 `duplicateAudio` 里拆出来：iOS 的左滑「复制」必须把
    /// 「复制文件 + 写库」这段**同步磁盘 IO** 放在动画事务之外（见 `ProjectsView.duplicate`）。
    /// 早年整块 `duplicateAudio` 被 `withAnimation` 包住，主线程在动画事务里被 IO 卡住，
    /// 列表渲出来的中间帧就是一片空白 —— 这就是「复制后该行先消失、过会儿才回来」。
    /// 拆开之后动画里只剩一次 `@Published` 写入，SwiftUI 看到的是纯插入。
    func appendAudioItem(_ item: AudioItem) {
        // 列表按创建时间倒序，新副本最新，置于顶部
        allLoadedAudios.insert(item, at: 0)
        totalCount += 1
        filterAndDisplay()

        // 选中新副本，方便用户立即查看
        selectedAudio = item
    }

    /// 把一个**已经建好的**音频条目插到 `afterID` 那一条的**下面**（找不到就回顶部）。
    ///
    /// ⚠️ iOS 的左滑「复制」用它而不是 `appendAudioItem`：列表默认按创建时间倒序，
    /// 新条目本来该去顶部，但那样整列表会被往下推一格，再配合一次滚到顶部，
    /// 用户看到的就是**「我刚操作的那一行不见了」**（其实是被顶出视野了）。
    /// 就地插入让被操作的行原地不动，副本在它下面长出来。
    func insertAudioItem(_ item: AudioItem, after afterID: Int64) {
        let at = allLoadedAudios.firstIndex(where: { $0.id == afterID })
            .map { min($0 + 1, allLoadedAudios.count) } ?? 0
        allLoadedAudios.insert(item, at: at)
        totalCount += 1
        filterAndDisplay()

        selectedAudio = item
    }

    func isPlayingAudio(_ audio: AudioItem) -> Bool {
        guard let url = audio.absoluteURL as URL? else { return false }
        return player.isPlaying(url: url)
    }

    /// 导出音频。
    ///
    /// ⚠️ macOS 走 `NSSavePanel`（有常驻导出目录）；iOS 没有常驻目录，
    /// 导出统一交给分享面板 / `fileExporter`，所以这里整段只在 macOS 编译。
    #if os(macOS)
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
    #endif

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
