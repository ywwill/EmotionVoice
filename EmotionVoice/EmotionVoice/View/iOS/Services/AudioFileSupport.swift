//
//  AudioFileSupport.swift
//  iOSEmora
//
//  音频波形提取、导出文档与系统分享面板（生成弹窗 / 历史记录 / 播放详情共用）。
//  从 GenerationDialog.swift 拆出：代码逐字搬移，未改动任何逻辑（原 private 类型按需放开为 internal）。
//

import SwiftUI
import Foundation
import UniformTypeIdentifiers
import AVFoundation
import UIKit

/// 从音频文件抽取真实振幅包络（峰值 × RMS 混合），结果按「路径 + 大小 + 条数」缓存
enum AudioWaveformExtractor {
    private static let cache = NSCache<NSString, NSArray>()

    static func envelope(url: URL, barCount: Int) -> [CGFloat] {
        let key = cacheKey(url, barCount: barCount)
        if let hit = cache.object(forKey: key as NSString) as? [NSNumber] {
            return hit.map { CGFloat($0.doubleValue) }
        }
        let values = extract(url: url, barCount: barCount)
        if !values.isEmpty {
            cache.setObject(values.map { NSNumber(value: Double($0)) } as NSArray,
                            forKey: key as NSString)
        }
        return values
    }

    private static func cacheKey(_ url: URL, barCount: Int) -> String {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attrs?[.size] as? NSNumber)?.intValue ?? 0
        return "\(url.path)#\(size)#\(barCount)"
    }

    private static func extract(url: URL, barCount: Int) -> [CGFloat] {
        guard barCount > 0,
              let file = try? AVAudioFile(forReading: url) else { return [] }
        let totalFrames = Int(file.length)
        guard totalFrames > 0 else { return [] }

        let per = max(1, totalFrames / barCount)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat,
                                            frameCapacity: AVAudioFrameCount(per)) else { return [] }

        var raw: [CGFloat] = []
        raw.reserveCapacity(barCount)

        for _ in 0..<barCount {
            do { try file.read(into: buffer, frameCount: AVAudioFrameCount(per)) } catch { break }
            let n = Int(buffer.frameLength)
            guard n > 0 else { break }

            let step = max(1, n / 256)
            var peak: Float = 0
            var sumSq: Float = 0
            var count = 0
            if let f = buffer.floatChannelData {
                let ch = f[0]
                for i in stride(from: 0, to: n, by: step) {
                    let v = ch[i]
                    let a = abs(v)
                    if a > peak { peak = a }
                    sumSq += v * v
                    count += 1
                }
            } else if let s = buffer.int16ChannelData {
                let ch = s[0]
                for i in stride(from: 0, to: n, by: step) {
                    let v = Float(ch[i]) / 32768
                    let a = abs(v)
                    if a > peak { peak = a }
                    sumSq += v * v
                    count += 1
                }
            } else { break }

            guard count > 0 else { break }
            let rms = sqrt(sumSq / Float(count))
            // 峰值偏尖、RMS 偏平，混合后视觉更接近听感
            raw.append(CGFloat(min(max(peak * 0.55 + rms * 1.9, 0.015), 1)))
        }

        guard let maxV = raw.max(), maxV > 0.001 else { return [] }
        // 整体归一：真实录音常常整体偏小，抬到 0.9 峰值但保留相对形状
        return maxV < 0.9 ? raw.map { min($0 * (0.9 / maxV), 1) } : raw
    }
}

// MARK: - 导出 / 分享

struct AudioFileDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.audio] }

    var data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

/// `UIActivityViewController` 包装（替代 macOS 的分享面板）
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
