//
//  AudioConcatenator.swift
//  EmotionVoice
//
//  把多次 TTS 合成返回的音频按文档顺序拼成一段。
//
//  为什么需要：中断标签（`[break]`）不是 API 支持的 tag，整段文本必须以它为界
//  切成多个**互相独立的合成请求**（见 `Array.toTTSSegments()`）。
//  合成完再按顺序拼回来，才是一次完整、语气互不污染的朗读。
//

import Foundation

enum AudioConcatenator {

    /// 按顺序拼接多个音频片段。
    ///
    /// - **全部是 16-bit PCM WAV**：解析各自 header，抽出 PCM 数据段拼在一起，
    ///   再重写一个总 header —— 无损，且播放器能正确读出完整时长。
    ///   直接字节拼接 WAV 是不行的：header 里的 `RIFF size` / `data size`
    ///   仍是第一段的，播放器会只认第一段或判为损坏。
    /// - **其余格式（mp3 / m4a …）**：直接字节拼接。MP3 帧自带同步头，
    ///   拼接后主流播放器能连续播放。
    ///
    /// - Parameter chunks: 按文档顺序排列的音频数据
    /// - Returns: 合并后的音频数据；入参为空时返回空 Data
    static func merge(_ chunks: [Data]) -> Data {
        let nonEmpty = chunks.filter { !$0.isEmpty }
        guard !nonEmpty.isEmpty else { return Data() }
        if nonEmpty.count == 1 { return nonEmpty[0] }

        guard let first = parseWAV(nonEmpty[0]) else {
            // 不是 WAV（mp3 等）→ 字节拼接即可
            return nonEmpty.reduce(into: Data()) { $0.append($1) }
        }

        var pcm = Data()
        for chunk in nonEmpty {
            guard let info = parseWAV(chunk), info.fmtChunk == first.fmtChunk else {
                // 参数不一致（不同采样率 / 通道）→ 不能无损合并，退回字节拼接
                return nonEmpty.reduce(into: Data()) { $0.append($1) }
            }
            pcm.append(chunk[info.dataOffset ..< (info.dataOffset + info.dataLength)])
        }
        return makeWAV(fmtChunk: first.fmtChunk, pcm: pcm)
    }

    // MARK: - WAV 解析 / 生成

    private struct WAVInfo {
        let fmtChunk: Data
        let dataOffset: Int
        let dataLength: Int
    }

    /// 解析一个 canonical WAV（"RIFF"...."WAVE"），返回 "fmt " 段与 "data" 段位置。
    /// 任何一点对不上就返回 nil —— 宁可让调用方回退字节拼接，也不能写坏 header。
    private static func parseWAV(_ d: Data) -> WAVInfo? {
        guard d.count >= 44,
              d[0..<4] == Data("RIFF".utf8),
              d[8..<12] == Data("WAVE".utf8) else { return nil }

        var fmt: Data?
        var dataOffset: Int?
        var dataLength: Int = 0
        var offset = 12

        while offset + 8 <= d.count {
            let id = d[offset ..< (offset + 4)]
            let size = Int(readLE32(d, offset + 4))
            let bodyStart = offset + 8
            guard bodyStart + size <= d.count else { break }

            if id == Data("fmt ".utf8) {
                if fmt == nil { fmt = d[bodyStart ..< (bodyStart + size)] }
            } else if id == Data("data".utf8) {
                if dataOffset == nil {
                    dataOffset = bodyStart
                    dataLength = size
                }
            }
            offset = bodyStart + size
            if size % 2 == 1 { offset += 1 }   // RIFF chunk 按偶数字节对齐
        }

        guard let f = fmt, let off = dataOffset, dataLength > 0 else { return nil }
        return WAVInfo(fmtChunk: f, dataOffset: off, dataLength: dataLength)
    }

    /// 生成 canonical 44 字节头的 WAV。
    private static func makeWAV(fmtChunk: Data, pcm: Data) -> Data {
        var out = Data()
        out.append(Data("RIFF".utf8))
        out.append(le(UInt32(36 + pcm.count)))
        out.append(Data("WAVE".utf8))
        out.append(Data("fmt ".utf8))
        out.append(le(UInt32(fmtChunk.count)))
        out.append(fmtChunk)
        out.append(Data("data".utf8))
        out.append(le(UInt32(pcm.count)))
        out.append(pcm)
        return out
    }

    private static func readLE32(_ d: Data, _ offset: Int) -> UInt32 {
        UInt32(d[offset]) | (UInt32(d[offset + 1]) << 8) |
        (UInt32(d[offset + 2]) << 16) | (UInt32(d[offset + 3]) << 24)
    }

    private static func le(_ v: UInt32) -> Data {
        var x = v.littleEndian
        return Data(bytes: &x, count: 4)
    }
}
