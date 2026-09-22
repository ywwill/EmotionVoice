//
//  AudioGenerationModal.swift
//  EmotionVoice
//
//  Created by young on 2026/9/20.
//

import SwiftUI
import UniformTypeIdentifiers

// MARK: - 无限循环进度条

struct InfiniteProgressBar: View {
    @State private var offset: CGFloat = -0.6
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                // 进度条背景
                RoundedRectangle(cornerRadius: 3)
                    .fill(AppColor.bgElevated)
                
                // 无限循环的填充动画（使用 clipped 确保不超出）
                RoundedRectangle(cornerRadius: 3)
                    .fill(
                        LinearGradient(
                            colors: [AppColor.accentPrimary, AppColor.accentGlow, AppColor.accentPrimary],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                    .frame(width: geometry.size.width * 0.5)
                    .offset(x: offset * geometry.size.width)
            }
            .clipShape(RoundedRectangle(cornerRadius: 3))
        }
        .frame(height: 6)
        .onAppear {
            withAnimation(
                .linear(duration: 1.5)
                .repeatForever(autoreverses: false)
            ) {
                offset = 1.6
            }
        }
    }
}

// MARK: - 旋转外圈

struct RotatingRing: View {
    @State private var rotation: Double = 0
    
    var body: some View {
        Circle()
            .trim(from: 0, to: 0.7)
            .stroke(
                AppColor.accentPrimary,
                style: StrokeStyle(lineWidth: 2, lineCap: .round)
            )
            .frame(width: 80, height: 80)
            .rotationEffect(.degrees(rotation))
            .onAppear {
                withAnimation(
                    .linear(duration: 1.2)
                    .repeatForever(autoreverses: false)
                ) {
                    rotation = 360
                }
            }
    }
}

// MARK: - 通用图标按钮

/// 通用的图标按钮组件，可复用
/// - Parameters:
///   - icon: SF Symbol 图标名
///   - title: 按钮文字
///   - isLoading: 是否显示加载状态
///   - action: 点击回调
struct ActionIconButton: View {
    let icon: String
    let title: String
    var isLoading: Bool = false
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            ZStack {
                VStack(spacing: 4) {
                    Image(systemName: icon)
                        .font(.system(size: 14))
                    Text(title)
                        .font(.system(size: 10))
                }
                .foregroundStyle(AppColor.textSecondary)
                .opacity(isLoading ? 0 : 1)
                
                if isLoading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(0.6)
                }
            }
        }
        .buttonStyle(.plain)
        .pointingHandCursor()
        .disabled(isLoading)
    }
}

// MARK: - 音频生成弹窗

struct AudioGenerationModal: View {
    @ObservedObject var vm: VoiceStudioViewModel
    @Binding var isPresented: Bool
    @State private var isCompleted: Bool = false
    @State private var audioName: String = ""
    @State private var isEditingName: Bool = false
    @State private var isPlaying: Bool = false
    @State private var playbackProgress: Double = 0.0
    @State private var playbackTimer: Timer? = nil
    @State private var showDownloadOverlay: Bool = false
    @State private var isExporting: Bool = false
    @State private var exportSuccess: Bool = false
    @State private var isSeeking: Bool = false  // 是否正在拖动滑块
    @State private var playerIsPlaying: Bool = false  // 播放器实际播放状态
    
    // 使用真实的音频时长（生成完成后从 ViewModel 获取）
    @State private var audioDuration: TimeInterval = 0
    // 记录播放开始时的系统时间，用于精确计算进度
    @State private var playbackStartTime: Date?
    
    var body: some View {
        ZStack {
            // 遮罩
            Color.black.opacity(0.75)
                .ignoresSafeArea()
                .onTapGesture {
                    if !isGenerating { isPresented = false }
                }
            
            // 弹窗主体
            VStack(spacing: 0) {
                // 头部
                header
                
                // 内容
                if isGenerating {
                    generatingContent
                } else {
                    completedContent
                }
                
                // 底部
                footer
            }
            .frame(width: 520)
            .background(AppColor.bgSecondary)
            .clipShape(RoundedRectangle(cornerRadius: AppRadius.large))
            .shadow(color: .black.opacity(0.6), radius: 40, x: 0, y: 12)
            .overlay(
                RoundedRectangle(cornerRadius: AppRadius.large)
                    .stroke(AppColor.borderSubtle, lineWidth: 1)
            )
        }
        .animation(.easeInOut(duration: 0.35), value: isGenerating)
        .animation(.easeInOut(duration: 0.35), value: isCompleted)
        .onChange(of: vm.generationProgress) { _, newProgress in
            if newProgress >= 1.0 {
                withAnimation {
                    isCompleted = true
                }
            }
        }
        .onChange(of: vm.generatedAudioDuration) { _, newDuration in
            // 文件保存成功后立即更新时长
            if newDuration > 0 {
                audioDuration = newDuration
            }
        }
        .onAppear {
            audioName = generateDefaultAudioName()

            // 观察播放器实际播放状态
            observePlayerState()
        }
        .onDisappear {
            playbackTimer?.invalidate()
            AudioPreviewPlayer.shared.stop()
        }
        .onChange(of: AudioPreviewPlayer.shared.isPlaying) { _, newValue in
            playerIsPlaying = newValue
            // 外部停止（如系统控制中心）时同步状态
            if !newValue && isPlaying {
                isPlaying = false
                playbackTimer?.invalidate()
            }
        }
    }
    
    /// 观察播放器状态
    private func observePlayerState() {
        Task { @MainActor in
            playerIsPlaying = AudioPreviewPlayer.shared.isPlaying
        }
    }
    
    // MARK: - 计算属性
    
    private var isGenerating: Bool {
        vm.isGenerating && !isCompleted
    }
    
    private var currentVoice: Voice? {
        vm.voice
    }
    
    private var estimatedRemainingTime: Int {
        let remaining = 1.0 - vm.generationProgress
        return max(1, Int(remaining * 10))
    }
    
    /// 格式化已接收字节数
    private var formattedReceivedBytes: String {
        let bytes = vm.receivedBytes
        if bytes < 1000 {
            return "\(bytes) B"
        } else if bytes < 1000 * 1000{
            return String(format: "%.1f KB", Double(bytes) / 1000.0)
        } else {
            return String(format: "%.2f MB", Double(bytes) / (1000.0 * 1000.0))
        }
    }
    
    /// 格式化文件大小
    private var formattedFileSize: String {
        let bytes = vm.receivedBytes
        if bytes < 1000 {
            return "\(bytes) B"
        } else if bytes < 1000 * 1000 {
            return String(format: "%.1f KB", Double(bytes) / 1000.0)
        } else {
            return String(format: "%.2f MB", Double(bytes) / (1000.0 * 1000.0))
        }
    }
    
    private var formattedDuration: String {
        let duration = audioDuration > 0 ? audioDuration : 0
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    private var formattedCurrentTime: String {
        let duration = audioDuration > 0 ? audioDuration : 1
        let current = duration * playbackProgress
        let minutes = Int(current) / 60
        let seconds = Int(current) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
    
    // MARK: - 头部
    
    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        LinearGradient(
                            colors: [AppColor.accentPrimary, AppColor.accentSecondary],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 28, height: 28)
                Text("🎵")
                    .font(.system(size: 14))
            }
            
            Text(isCompleted ? "生成完成" : "音频生成")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(AppColor.textPrimary)
            
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(Color.clear)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(AppColor.borderSubtle)
                .frame(height: 0.5)
        }
    }
    
    // MARK: - 生成中内容
    
    private var generatingContent: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 20) {
                    // 旋转图标
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        AppColor.accentPrimary.opacity(0.15),
                                        AppColor.accentPrimary.opacity(0.05)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 72, height: 72)
                            .overlay(
                                Circle()
                                    .stroke(AppColor.accentPrimary.opacity(0.25), lineWidth: 1)
                            )
                        
                        // 旋转外圈
                        RotatingRing()
                        
                        Text("⚡")
                            .font(.system(size: 28))
                    }
                    .frame(width: 80, height: 80)
                    
                    // 标题
                    Text("正在合成音频")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(AppColor.textPrimary)
                    
                    // 副标题
                    Text(voiceInfoSubtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(AppColor.textTertiary)
                    
                    // 进度条
                    VStack(spacing: 30) {
                        // 无限循环进度条
                        InfiniteProgressBar()
                        
                        // 已接收数据大小
                        HStack(spacing: 6) {
                            Spacer()
                            Image(systemName: "arrow.down.circle.fill")
                                .font(.system(size: 14))
                            Text("已接收: %@".localized(formattedReceivedBytes))
                                .font(.system(size: 15, weight: .medium))
                            Spacer()
                        }
                        .frame(maxWidth: .infinity)
                        .foregroundStyle(AppColor.textSecondary)
                    }
                    .padding(.horizontal, 0)
                }
                .padding(20)
            }
        }
    }
    
    // MARK: - 完成内容
    
    private var completedContent: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 16) {
                    // 音频信息
                    audioInfoCard
                    
                    // 音频播放器
                    audioPlayerCard
                    
                    // 音色信息
                    voiceInfoRow
                    
                    // 标签
                    tagsSection
                    
                    // 消耗积分
                    costInfo
                }
                .padding(20)
            }
        }
    }
    
    // MARK: - 音频信息卡片
    
    private var audioInfoCard: some View {
        HStack(spacing: 16) {
            // 头像
            ZStack(alignment: .topTrailing) {
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [AppColor.accentPrimary, AppColor.accentSecondary],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 52, height: 52)
                    
                    Text("🎵")
                        .font(.system(size: 18, weight: .bold))
                }
                
                // 成功徽章
                if isCompleted {
                    ZStack {
                        Circle()
                            .fill(AppColor.statusSuccess)
                            .frame(width: 20, height: 20)
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                    }
                    .shadow(color: AppColor.statusSuccess.opacity(0.4), radius: 4)
                    .offset(x: 4, y: -4)
                }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    if isEditingName {
                        TextField("音频名称", text: $audioName)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(AppColor.textPrimary)
                            .textFieldStyle(.plain)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(AppColor.bgElevated)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(AppColor.borderMedium, lineWidth: 1)
                            )
                            .onSubmit {
                                isEditingName = false
                            }
                    } else {
                        Text(audioName)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(AppColor.textPrimary)
                    }
                    
                    Button {
                        isEditingName.toggle()
                        if !isEditingName && audioName.isEmpty {
                            audioName = generateDefaultAudioName()
                        }
                    } label: {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 14))
                            .foregroundStyle(AppColor.textTertiary)
                            .frame(width: 22, height: 22)
                            .background(Color.clear)
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                    }
                    .buttonStyle(.plain)
                    .pointingHandCursor()
                }
                
                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Image(systemName: "doc")
                            .font(.system(size: 10))
                        Text(formattedFileSize)
                    }
                    
                    Text("·")
                    
                    Text("48 kHz")
                    
                    Text("·")
                    
                    Text(vm.selectedFormat.uppercased())
                }
                .font(.system(size: 12))
                .foregroundStyle(AppColor.textTertiary)
            }
            
            Spacer()
        }
        .padding(16)
        .background(AppColor.bgTertiary)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium))
    }
    
    // MARK: - 音频播放器
    
    private var audioPlayerCard: some View {
        VStack(spacing: 12) {
            HStack(spacing: 16) {
                // 播放按钮
                Button {
                    togglePlayback()
                } label: {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [AppColor.accentPrimary, AppColor.accentSecondary],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 48, height: 48)
                            .shadow(color: AppColor.accentPrimary.opacity(0.3), radius: 8, y: 4)
                        
                        if isPlaying {
                            // 暂停图标
                            HStack(spacing: 3) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(AppColor.bgPrimary)
                                    .frame(width: 4, height: 16)
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(AppColor.bgPrimary)
                                    .frame(width: 4, height: 16)
                            }
                        } else {
                            // 播放图标
                            Image(systemName: "play.fill")
                                .font(.system(size: 16))
                                .foregroundStyle(AppColor.bgPrimary)
                                .offset(x: 2)
                        }
                    }
                }
                .buttonStyle(.plain)
                .pointingHandCursor()
                
                // 波形条
                HStack(spacing: 2) {
                    ForEach(0..<60, id: \.self) { i in
                        RoundedRectangle(cornerRadius: 1.5)
                            .fill(i < Int(60 * playbackProgress) ? AppColor.accentPrimary : AppColor.bgElevated)
                            .frame(width: 3, height: CGFloat.random(in: 8...40))
                    }
                }
                .frame(height: 50)
                
                // 时间显示
                Text("\(formattedCurrentTime) / \(formattedDuration)")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(AppColor.textTertiary)
                    .frame(minWidth: 85, alignment: .trailing)
            }
            
            // 进度条
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(AppColor.bgElevated)
                        .frame(height: 4)
                    
                    RoundedRectangle(cornerRadius: 2)
                        .fill(
                            LinearGradient(
                                colors: [AppColor.accentPrimary, AppColor.accentGlow],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geometry.size.width * playbackProgress, height: 4)
                }
                .frame(height: 4)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            isSeeking = true
                            let progress = max(0, min(1, value.location.x / geometry.size.width))
                            playbackProgress = progress
                        }
                        .onEnded { value in
                            isSeeking = false
                            let progress = max(0, min(1, value.location.x / geometry.size.width))
                            playbackProgress = progress
                            // 同步到播放器实际时间
                            let seekTime = audioDuration * progress
                            AudioPreviewPlayer.shared.seek(to: seekTime)
                        }
                )
            }
            .frame(height: 4)
            .pointingHandCursor()
        }
        .padding(20)
        .background(AppColor.bgTertiary)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium))
    }
    
    // MARK: - 音色信息
    
    private var voiceInfoRow: some View {
        HStack(spacing: 12) {
            if let voice = currentVoice {
                AvatarView(text: String(voice.name.prefix(1)), size: 32)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(voice.isPremium ? "\(voice.name) · 旗舰音色" : voice.name)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(AppColor.textPrimary)
                    
                    HStack(spacing: 4) {
                        if !voice.gender.isEmpty {
                            Text(voice.gender)
                        }
                        if let age = voice.age {
                            Text("\(age)岁")
                        }
                        if !voice.lang.isEmpty {
                            Text("· \(voice.lang)")
                        }
                    }
                    .font(.system(size: 11))
                    .foregroundStyle(AppColor.textTertiary)
                }
                
                Spacer()
            }
        }
        .padding(12)
        .background(AppColor.bgTertiary)
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium))
    }
    
    // MARK: - 标签
    
    private var tagsSection: some View {
        HStack(spacing: 6) {
            if let voice = currentVoice {
                if !voice.scene.isEmpty {
                    tagView(voice.scene, isAccent: true)
                }
                if !voice.desc.isEmpty {
                    tagView(voice.desc, isAccent: false)
                }
            }
        }
    }
    
    private func tagView(_ text: String, isAccent: Bool) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(isAccent ? AppColor.accentGlow : AppColor.textSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(isAccent ? AppColor.accentPrimary.opacity(0.12) : AppColor.bgTertiary)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(
                        isAccent ? AppColor.accentPrimary.opacity(0.25) : AppColor.borderSubtle,
                        lineWidth: 1
                    )
            )
    }
    
    // MARK: - 消耗积分
    
    private var costInfo: some View {
        HStack {
            HStack(spacing: 6) {
                Text("💎")
                    .font(.system(size: 14))
                Text("消耗积分")
                    .font(.system(size: 12))
                    .foregroundStyle(AppColor.textTertiary)
            }
            
            Spacer()
            
            Text("\(vm.estimatedPoints)")
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundStyle(AppColor.accentPrimary)
        }
        .padding(12)
        .background(
            LinearGradient(
                colors: [
                    AppColor.accentPrimary.opacity(0.08),
                    AppColor.accentPrimary.opacity(0.02)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: AppRadius.medium))
        .overlay(
            RoundedRectangle(cornerRadius: AppRadius.medium)
                .stroke(AppColor.accentPrimary.opacity(0.15), lineWidth: 1)
        )
    }
    
    // MARK: - 底部
    
    private var footer: some View {
        HStack(spacing: 12) {
            if isCompleted {
                // 小尺寸的操作按钮 - 统一样式
                HStack(spacing: 16) {
                    // 导出按钮
                    exportButton
                }
            }
            
            Spacer()
            
            Button {
                if isCompleted {
                    saveAudioNameIfNeeded()
                    isPresented = false
                }
            } label: {
                HStack(spacing: 6) {
                    Text("完成")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(AppColor.bgPrimary)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(
                    LinearGradient(
                        colors: [AppColor.accentPrimary, AppColor.accentSecondary],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: AppRadius.small))
                .shadow(color: AppColor.accentPrimary.opacity(0.25), radius: 8, y: 4)
            }
            .buttonStyle(.plain)
            .pointingHandCursor()
            .opacity(isCompleted ? 1 : 0)
            .disabled(!isCompleted)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(
            Color.clear
                .background(AppColor.bgSecondary.opacity(0.4))
        )
        .overlay(alignment: .top) {
            Rectangle()
                .fill(AppColor.borderSubtle)
                .frame(height: 0.5)
        }
        .opacity(isCompleted ? 1 : 0)
        .disabled(!isCompleted)
    }
    
    private var downloadOverlaySmall: some View {
        Text("导出中...")
            .font(.system(size: 10))
            .foregroundStyle(AppColor.textPrimary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(AppColor.bgPrimary)
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
    
    // MARK: - 导出和分享按钮
    
    /// 导出按钮
    private var exportButton: some View {
        ActionIconButton(icon: "arrow.down.doc", title: "导出", isLoading: isExporting) {
            exportAudio()
        }
    }
    
    // MARK: - 导出功能
    
    /// 导出音频到用户选择的位置
    private func exportAudio() {
        guard let sourceURL = vm.generatedAudioURL else {
            Log(message: "AudioGenerationModal: 无音频文件可导出")
            return
        }
        
        isExporting = true
        
        // 确定默认文件名
        let defaultFileName = "\(audioName).\(sourceURL.pathExtension)"
        
        // 创建保存面板
        let savePanel = NSSavePanel()
        savePanel.title = "导出音频".localized()
        savePanel.message = "选择保存位置".localized()
        savePanel.nameFieldStringValue = defaultFileName
        savePanel.canCreateDirectories = true
        savePanel.allowedContentTypes = [.audio]
        
        // 显示面板
        savePanel.begin { [self] response in
            if response == .OK, let destinationURL = savePanel.url {
                // 复制文件到目标位置
                do {
                    // 如果目标文件已存在，先删除
                    if FileManager.default.fileExists(atPath: destinationURL.path) {
                        try FileManager.default.removeItem(at: destinationURL)
                    }
                    try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
                    
                    Log(message: "AudioGenerationModal: 导出成功 - \(destinationURL.path)")
                    
                    // 打开包含导出文件的文件夹
                    NSWorkspace.shared.selectFile(destinationURL.path, inFileViewerRootedAtPath: destinationURL.deletingLastPathComponent().path)
                    
                    // 显示成功提示
                    DispatchQueue.main.async {
                        isExporting = false
                        exportSuccess = true
                        // 2秒后自动隐藏成功提示
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            exportSuccess = false
                        }
                    }
                } catch {
                    Log(message: "AudioGenerationModal: 导出失败 - \(error.localizedDescription)")
                    isExporting = false
                }
            } else {
                isExporting = false
            }
        }
    }
    
    // MARK: - 辅助方法
    
    private var voiceInfoSubtitle: String {
        guard let voice = currentVoice else { return "" }
        return "\(voice.name) · \(voice.desc) · 情感标签"
    }
    
    private func generateDefaultAudioName() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd HH:mm"
        return "音频_\(formatter.string(from: Date()))"
    }
    
    /// 保存编辑后的音频名称
    private func saveAudioNameIfNeeded() {
        guard let audioId = vm.generatedAudioId else { return }
        
        let nameToSave = audioName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !nameToSave.isEmpty && nameToSave != generateDefaultAudioName() {
            ProjectService.shared.renameAudio(id: audioId, displayName: nameToSave)
        }
    }
    
    private func togglePlayback() {
        // 确保有生成的音频 URL
        guard let audioURL = vm.generatedAudioURL else {
            Log(message: "AudioGenerationModal: 无音频文件可播放")
            return
        }
        
        Task { @MainActor in
            let player = AudioPreviewPlayer.shared
            
            if player.isPlaying(url: audioURL) {
                // 正在播放同一文件 → 暂停
                player.stop()
                isPlaying = false
                playbackTimer?.invalidate()
            } else {
                // 停止之前的播放
                player.stop()
                playbackProgress = 0
                
                // 播放前验证文件有效性
                guard FileManager.default.fileExists(atPath: audioURL.path) else {
                    Log(message: "AudioGenerationModal: 音频文件不存在")
                    isPlaying = false
                    return
                }
                
                // 检查文件大小（过小的文件可能不完整）
                do {
                    let attributes = try FileManager.default.attributesOfItem(atPath: audioURL.path)
                    if let fileSize = attributes[.size] as? Int64, fileSize < 1000 {
                        Log(message: "AudioGenerationModal: 音频文件过小，可能不完整")
                        isPlaying = false
                        return
                    }
                } catch {
                    Log(message: "AudioGenerationModal: 无法读取文件属性: \(error)")
                }
                
                // 开始播放
                if player.play(url: audioURL, identifier: audioURL.path) {
                    isPlaying = true
                    // 从 ViewModel 获取真实时长
                    audioDuration = vm.generatedAudioDuration
                    startPlaybackTimer()
                } else {
                    Log(message: "AudioGenerationModal: 播放失败")
                    isPlaying = false
                }
            }
        }
    }
    
    private func startPlaybackTimer() {
        playbackTimer?.invalidate()
        let duration = audioDuration > 0 ? audioDuration : 1.0
        
        // 记录播放开始时间，用于精确计算进度
        playbackStartTime = Date()
        
        // 延迟启动定时器，等待播放器状态稳定
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.playbackTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
                Task { @MainActor in
                    let player = AudioPreviewPlayer.shared
                    guard let url = self.vm.generatedAudioURL else { return }
                    
                    // 如果正在拖动滑块，跳过进度更新
                    if self.isSeeking {
                        return
                    }
                    
                    if player.isPlaying(url: url) {
                        // 使用播放器实际时间计算进度
                        let currentTime = player.currentTime
                        if duration > 0 {
                            self.playbackProgress = min(1.0, currentTime / duration)
                        }
                    } else {
                        // 播放结束或停止
                        if self.isPlaying {
                            self.isPlaying = false
                            self.playbackProgress = 0
                        }
                        self.playbackTimer?.invalidate()
                    }
                }
            }
        }
    }
}
