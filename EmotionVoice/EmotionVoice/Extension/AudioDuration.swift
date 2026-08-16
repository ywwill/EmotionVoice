//
//  AudioDuration.swift
//  EmotionVoice
//
//  计算写入磁盘后的音频时长（秒）。
//  优先用 AVAudioFile 读取真实 PCM 帧数；失败时按容器粗略估算。
//

import Foundation
import AVFoundation

enum AudioDuration {

    /// 读取音频时长。
    /// - Parameters:
    ///   - url: 写入磁盘的音频文件 URL
    ///   - sampleRate: 采样率（Hz），用于回退估算
    ///   - bytes: 音频原始字节数（用于 WAV 估算）
    ///   - format: 文件扩展名（wav/mp3/m4a …）
    /// - Returns: 时长（秒）；任何错误都返回 0
    static func read(url: URL, sampleRate: Int, bytes: Int, format: String) -> Double {
        if let d = readViaAVAudioFile(url: url) {
            return d
        }
        return estimate(bytes: bytes, sampleRate: sampleRate, format: format)
    }

    /// 真实读取（推荐）：AVAudioFile 在 WAV/AIFF/CAF/MP3/M4A 等容器上均能工作
    private static func readViaAVAudioFile(url: URL) -> Double? {
        do {
            let file = try AVAudioFile(forReading: url)
            let sampleRate = file.processingFormat.sampleRate
            guard sampleRate > 0 else { return nil }
            return Double(file.length) / sampleRate
        } catch {
            Log(message: "AudioDuration.AVAudioFile 读取失败 (\(url.lastPathComponent)): \(error.localizedDescription)")
            return nil
        }
    }

    /// 粗略估算：仅用于回退，精度有限
    /// - WAV(16-bit PCM 单声道)：bytes / (sampleRate * 2)
    /// - MP3 128 kbps：bytes / 16000
    /// - M4A/AAC 128 kbps：bytes / 16000
    private static func estimate(bytes: Int, sampleRate: Int, format: String) -> Double {
        guard bytes > 0 else { return 0 }
        let lower = format.lowercased()
        switch lower {
        case "wav", "aiff", "caf":
            guard sampleRate > 0 else { return 0 }
            // 假设 16-bit 单声道（保守估计）
            return Double(bytes) / Double(sampleRate * 2)
        case "mp3":
            // ~128 kbps
            return Double(bytes) / 16_000.0
        case "m4a", "aac", "mp4":
            // ~128 kbps
            return Double(bytes) / 16_000.0
        default:
            guard sampleRate > 0 else { return 0 }
            return Double(bytes) / Double(sampleRate * 2)
        }
    }
}
