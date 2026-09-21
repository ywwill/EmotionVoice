//
//  AudioDuration.swift
//  EmotionVoice
//
//  计算写入磁盘后的音频时长（秒）。
//  优先用 AVAudioFile 读取真实 PCM 帧数；失败时按 WAV header 精确计算。
//

import Foundation
import AVFoundation

enum AudioDuration {

    /// 读取音频时长。
    /// - Parameters:
    ///   - url: 写入磁盘的音频文件 URL
    ///   - sampleRate: 采样率（Hz），用于回退估算
    ///   - bytes: 音频原始字节数（用于粗估）
    ///   - format: 文件扩展名（wav/mp3/m4a …）
    /// - Returns: 时长（秒）；任何错误都返回 0
    static func read(url: URL, sampleRate: Int, bytes: Int, format: String) -> Double {
        // 1. 优先尝试 AVAudioFile（支持 WAV/AIFF/CAF/MP3/M4A）
        if let d = readViaAVAudioFile(url: url) {
            Log(message: "AudioDuration.AVAudioFile 读取成功: \(d)s (file: \(url.lastPathComponent))")
            return d
        }
        
        // 2. WAV 格式尝试直接解析 header 获取精确时长
        if format.lowercased() == "wav" {
            if let d = readWavHeader(url: url) {
                Log(message: "AudioDuration.WAV header 读取成功: \(d)s (file: \(url.lastPathComponent))")
                return d
            }
        }
        
        // 3. 尝试使用 AVAsset 读取时长（支持更多格式）
        if let d = readViaAVAsset(url: url) {
            Log(message: "AudioDuration.AVAsset 读取成功: \(d)s (file: \(url.lastPathComponent))")
            return d
        }
        
        // 4. 回退：按容器格式估算
        let estimated = estimate(bytes: bytes, sampleRate: sampleRate, format: format)
        Log(message: "AudioDuration.估算时长: \(estimated)s (bytes=\(bytes), sampleRate=\(sampleRate), format=\(format))")
        return estimated
    }

    /// AVAudioFile 读取
    private static func readViaAVAudioFile(url: URL) -> Double? {
        do {
            let file = try AVAudioFile(forReading: url)
            let sampleRate = file.processingFormat.sampleRate
            guard sampleRate > 0 else { return nil }
            let frames = Double(file.length)
            let duration = frames / sampleRate
            Log(message: "AudioDuration: AVAudioFile frames=\(file.length), sampleRate=\(sampleRate), duration=\(duration)s")
            return duration
        } catch {
            Log(message: "AudioDuration.AVAudioFile 读取失败 (\(url.lastPathComponent)): \(error.localizedDescription)")
            return nil
        }
    }
    
    /// AVAsset 读取（备用方案，支持更多格式）
    private static func readViaAVAsset(url: URL) -> Double? {
        let asset = AVURLAsset(url: url)
        let duration = asset.duration
        if duration.isValid && !duration.isIndefinite {
            let seconds = CMTimeGetSeconds(duration)
            Log(message: "AudioDuration.AVAsset duration=\(seconds)s")
            return seconds
        }
        Log(message: "AudioDuration.AVAsset 无法获取有效时长")
        return nil
    }
    
    /// 直接解析 WAV header 获取时长
    /// WAV 格式：
    /// - Bytes 0-3: "RIFF"
    /// - Bytes 4-7: 文件大小 - 8
    /// - Bytes 8-11: "WAVE"
    /// - Bytes 12-15: "fmt "
    /// - Bytes 16-19: fmt chunk 大小 (通常 16)
    /// - Bytes 20-21: 音频格式 (1 = PCM)
    /// - Bytes 22-23: 通道数
    /// - Bytes 24-27: 采样率
    /// - Bytes 28-31: 字节率 (sampleRate * numChannels * bitsPerSample / 8)
    /// - Bytes 32-33: 数据块对齐 (numChannels * bitsPerSample / 8)
    /// - Bytes 34-35: 位深度
    /// - Bytes 36-39: "data"
    /// - Bytes 40-43: 数据大小
    private static func readWavHeader(url: URL) -> Double? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else {
            Log(message: "AudioDuration: 无法读取文件数据")
            return nil
        }
        
        guard data.count >= 44 else {
            Log(message: "AudioDuration: WAV 文件太短 (小于 44 字节)")
            return nil
        }
        
        // 验证 RIFF header
        guard data[0...3] == Data("RIFF".utf8) else {
            Log(message: "AudioDuration: 不是有效的 RIFF 文件 (前4字节=\(data.prefix(4).map { String(format: "%02X", $0) }))")
            return nil
        }
        
        // 验证 WAVE format
        guard data[8...11] == Data("WAVE".utf8) else {
            Log(message: "AudioDuration: 不是有效的 WAVE 格式")
            return nil
        }
        
        // 查找 "data" chunk
        var dataOffset: Int?
        var dataSize: UInt32 = 0
        
        var offset = 12
        while offset + 8 <= data.count {
            let chunkId = data[offset..<(offset + 4)]
            let chunkSize = data.subdata(in: (offset + 4)..<(offset + 8)).withUnsafeBytes {
                $0.load(as: UInt32.self).littleEndian
            }
            
            if chunkId == Data("data".utf8) {
                dataOffset = offset + 8
                dataSize = chunkSize
                break
            }
            
            offset += Int(8 + chunkSize)
            // 奇数字节对齐
            if chunkSize % 2 == 1 {
                offset += 1
            }
        }
        
        guard var offset = dataOffset, dataSize > 0 else {
            Log(message: "AudioDuration: 找不到 data chunk")
            return nil
        }
        
        // 读取 fmt chunk 获取格式信息
        // 查找 fmt 位置（通常在 offset 12，但可能有其他 chunks）
        var numChannels: UInt16 = 1
        var bitsPerSample: UInt16 = 16
        var actualSampleRate: UInt32 = 0
        
        offset = 12
        while offset + 8 <= data.count {
            let chunkId = data[offset..<(offset + 4)]
            let chunkSize = data.subdata(in: (offset + 4)..<(offset + 8)).withUnsafeBytes {
                $0.load(as: UInt32.self).littleEndian
            }
            
            if chunkId == Data("fmt ".utf8) && chunkSize >= 16 {
                numChannels = data.subdata(in: (offset + 10)..<(offset + 12)).withUnsafeBytes {
                    $0.load(as: UInt16.self).littleEndian
                }
                actualSampleRate = data.subdata(in: (offset + 12)..<(offset + 16)).withUnsafeBytes {
                    $0.load(as: UInt32.self).littleEndian
                }
                bitsPerSample = data.subdata(in: (offset + 22)..<(offset + 24)).withUnsafeBytes {
                    $0.load(as: UInt16.self).littleEndian
                }
                Log(message: "AudioDuration.WAV: channels=\(numChannels), sampleRate=\(actualSampleRate), bitsPerSample=\(bitsPerSample)")
                break
            }
            
            offset += Int(8 + chunkSize)
            if chunkSize % 2 == 1 {
                offset += 1
            }
        }
        
        guard actualSampleRate > 0 else {
            Log(message: "AudioDuration: 无法解析采样率")
            return nil
        }
        
        // 计算时长：字节数 / (采样率 * 通道数 * 位深度 / 8)
        let bytesPerSample = Double(numChannels) * Double(bitsPerSample) / 8.0
        let bytesPerSecond = Double(actualSampleRate) * bytesPerSample
        let duration = Double(dataSize) / bytesPerSecond
        
        Log(message: "AudioDuration.WAV 计算: dataSize=\(dataSize), bytesPerSample=\(bytesPerSample), bytesPerSecond=\(bytesPerSecond), duration=\(duration)s")
        return duration
    }

    /// 粗略估算：仅用于回退
    private static func estimate(bytes: Int, sampleRate: Int, format: String) -> Double {
        guard bytes > 0 else { return 0 }
        let lower = format.lowercased()
        switch lower {
        case "wav", "aiff", "caf":
            guard sampleRate > 0 else { return 0 }
            // 保守估计：16-bit 单声道
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
