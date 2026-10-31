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

    /// 列表滚动代理：复制后要滚回顶部，让用户看见新行
    @State private var scrollProxy: ScrollViewProxy? = nil

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
        ScrollViewReader { proxy in
        List {
            Section {
                ForEach(vm.displayedAudios) { audio in
                    row(audio)
                        .id(audio.id)
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
        // ⚠️ 列表的统一转场：行内容的增删（复制插入 / 删除 / 重命名）默认是一帧硬切，
        // 这里统一给一条 spring，避免「点一下 → 整列表闪一下」。
        .animation(.spring(response: 0.34, dampingFraction: 0.9),
                   value: vm.displayedAudios.count)
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
        // ⚠️ 重命名**不用系统 `.alert`**：它的 `TextField` 没有清空按钮，而 Alert 的
        // 内容槽位里也塞不进自定义视图（塞进去会被排版成一整行按钮）。
        // 重命名恰恰是最需要「先清一遍再重输」的入口 —— 名字通常是随手起的代号。
        .overlay {
            if renameTarget != nil {
                RenameDialog(text: $renameText,
                             onCancel: { renameTarget = nil },
                             onSave: { commitRename() })
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: renameTarget?.id)
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
        .onAppear { scrollProxy = proxy }
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
        // ⚠️ 这里**不放设置入口**：设置已经能从另外两个标签页进（创作 / 音色库），
        // 项目页右上角要留给「进入多选」这一个动作，两个按钮挤在一起时用户
        // 分不清哪个是选择、哪个是设置。
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                withAnimation(.easeOut(duration: 0.18)) {
                    isSelecting.toggle()
                    if !isSelecting { selectedIDs = [] }
                }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: isSelecting ? "checkmark.circle.fill" : "checklist")
                        .font(.system(size: 17, weight: .semibold))
                    Text(isSelecting ? "完成".localized() : "选择".localized())
                        .font(.system(size: 15.5, weight: .semibold))
                }
                .foregroundStyle(c.accent)
                .padding(.horizontal, isSelecting ? 11 : 8)
                .frame(height: 32)
                .background(
                    Capsule(style: .continuous)
                        .fill(c.accentSoft)
                        .overlay(
                            Capsule(style: .continuous)
                                .strokeBorder(c.accent.opacity(0.28), lineWidth: 0.5)
                        )
                )
                .contentShape(Capsule(style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isSelecting ? "结束多选".localized() : "进入多选".localized())
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

    /// 左滑「复制」。
    ///
    /// ⚠️ 三件事各对应一种「该行先消失、留一段空白、过会儿才回来」，缺一件都会复现：
    ///  ⓿ **等左滑菜单的回弹动画走完再动列表**：SwiftUI 在菜单未被判为「已收起」时改数据，
    ///     那一行会被重挂载一次 —— 期间它的内容还停在滑开的位置上，视觉上就是整行凭空没了；
    ///  ① **「复制文件」必须脱离主线程**：这是同步磁盘 IO（音频文件几 MB 起），
    ///     卡在主线程会把上面的回弹动画冻在半路 ——
    ///     **「当前行先消失、隔一下才回来」** 就是这么来的（`ProjectService.stageDuplicatedFile`）；
    ///  ② **列表只能纯插入**：`insertAudioItem` 一次写完 `displayedAudios`，不出现
    ///     「先删后插」的中间态 —— SwiftUI 一旦在差分里看到 remove + insert，
    ///     就会把那一行 unmount 再 mount（视觉上闪一下 + 空一帧）。
    ///
    /// ⚠️ 副本插在被操作那一行的**下面**（而不是列表顶部）：列表按创建时间倒序，
    /// 理论上新条目该去顶部，但那会把整列表往下推一格 —— 配合一次滚到顶部，
    /// 用户看到的就是「刚操作的那行被顶出视野」。就地插入 + 最小滚动（不带 anchor）
    /// 让原来的行一动不动，只在副本落在屏幕边缘时补一点位移把它露出来。
    ///
    /// ⚠️ 用 `Task { @MainActor }` 而不是 `DispatchQueue.main.asyncAfter`：
    /// `AudioItem` 不是 `Sendable`，扔进 GCD 的逃逸闭包在 Swift 6 下过不了并发检查。
    private func duplicate(_ audio: AudioItem) {
        // 先把要用的值类型抠出来：逃逸闭包里不碰 `AudioItem` 本体
        let sourceURL = audio.absoluteURL
        let sourceExtension = audio.fileExtension
        let sourceID = audio.id

        Task { @MainActor in
            // ⓿ 等左滑菜单基本收完，别让菜单回弹动画和插入动画抢同一帧
            try? await Task.sleep(nanoseconds: 260_000_000)

            // ① 重活（磁盘复制）在**后台线程**完成，写库仍然留在主线程
            let stagedName = await Task.detached(priority: .userInitiated) { () -> String? in
                ProjectService.stageDuplicatedFile(sourceURL: sourceURL,
                                                   fileExtension: sourceExtension)
            }.value
            guard let newFileName = stagedName,
                  let copy = ProjectService.shared.finishDuplicate(source: audio,
                                                                   newFileName: newFileName) else {
                uiState.showToast(.failure("复制失败".localized()))
                return
            }

            // ② 纯插入：一次写入，只有 insert 没有 remove
            withAnimation(.spring(response: 0.36, dampingFraction: 0.86)) {
                vm.insertAudioItem(copy, after: sourceID)
            }
            uiState.showToast(.success("已复制音频".localized()))

            // ③ 让插入这一帧先提交。不带 anchor 的 `scrollTo` 只会做最小位移，
            //    副本已经在视野里时就一步都不会走 —— 列表不会跳。
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard vm.displayedAudios.contains(where: { $0.id == copy.id }) else { return }
            withAnimation(.spring(response: 0.34, dampingFraction: 0.9)) {
                scrollProxy?.scrollTo(copy.id)
            }
        }
    }

    private func beginRename(_ audio: AudioItem) {
        renameTarget = audio
        renameText = audio.shownName
    }

    private func commitRename() {
        guard let target = renameTarget else { return }
        let trimmed = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        renameTarget = nil
        if !trimmed.isEmpty, trimmed != target.shownName {
            // 行里的名字是行内容的一部分，给它一条动画，别一帧硬切
            withAnimation(.spring(response: 0.34, dampingFraction: 0.9)) {
                vm.renameAudio(target, newName: trimmed)
            }
        }
    }

    /// 删除（单条 / 多选）。
    ///
    /// ⚠️ 与「复制」同一个道理：**磁盘删除 + 数据库操作不能夹在动画事务里**，
    /// 只有「把这一行从数组里拿掉」这一步才包 `withAnimation` —— 早年直接把
    /// `vm.deleteAudio` 扔进动画，左滑删除会先卡一帧再把行推走。
    private func commitDelete() {
        if deleteMany {
            let ids = selectedIDs
            let targets = vm.displayedAudios.filter { ids.contains($0.id) }
            deleteMany = false
            selectedIDs = []

            Task { @MainActor in
                for audio in targets { ProjectService.shared.deleteAudio(id: audio.id) }
                guard !targets.isEmpty else { return }
                withAnimation(.spring(response: 0.34, dampingFraction: 0.9)) {
                    for audio in targets { vm.removeAudioItem(audio) }
                }
            }
        } else if let target = deleteTarget {
            deleteTarget = nil
            Task { @MainActor in
                ProjectService.shared.deleteAudio(id: target.id)
                withAnimation(.spring(response: 0.34, dampingFraction: 0.9)) {
                    vm.removeAudioItem(target)
                }
            }
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

    private var deletePresented: Binding<Bool> {
        Binding(get: { deleteTarget != nil || deleteMany }, set: { if !$0 { deleteTarget = nil; deleteMany = false } })
    }

    private var deleteMessage: String {
        if deleteMany {
            return "确定删除选中的 %d 条音频？删除后无法恢复。".localized(selectedIDs.count)
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

// MARK: - 重命名弹窗

/// 重命名弹窗。
///
/// ⚠️ 不用系统 `.alert`：它的 `TextField` 没有清空按钮，而 Alert 的内容槽位也塞不进
/// 自定义视图（塞进去会被排版成一整行按钮）。重命名偏偏是最需要「先清一遍再重输」的入口 ——
/// 名字通常是随手起的代号，改的时候往往是整串重敲，而不是在一串字符里挪光标。
/// 这里自己画一张和生成弹窗同款的小卡片，输入框右侧挂一个随输入出现的清空按钮。
struct RenameDialog: View {
    @Environment(\.aurora) private var c
    @Environment(\.screenMetrics) private var metrics

    /// 待编辑的名字（外面持有，配合「取消即丢弃」）
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
                // ⚠️ 键盘要等卡片转场落定再弹：抢在 scale 动画中间 focus，
                // 输入框会被往上顶的过程中带着整张卡片一起位移，看着像抖了一下。
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

    /// 输入框 + 清空按钮。
    ///
    /// ⚠️ 清空按钮只在有字时出现：空输入框顶着一个灰 ×，既没用又把占位文案挤短一截。
    private var field: some View {
        HStack(spacing: 8) {
            TextField("音频名称".localized(), text: $text)
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
