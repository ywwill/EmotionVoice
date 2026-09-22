//
//  TextSplitter.swift
//  EmotionVoice
//
//  文本智能分割工具（按阿里云计费字符数）
//

import Foundation

class TextSplitter {
    
    /// 默认最大字符数，qwen-audio-3.0-tts-plus 没有限制
    static let defaultMaxCharCount = 10000
    
    /// 智能分割文本（按阿里云计费规则）
    /// 阿里云计费规则：汉字 = 2字符，其他 = 1字符
    /// - Parameters:
    ///   - text: 输入文本
    ///   - maxCharCount: 最大字符数，默认 550
    /// - Returns: 分割后的文本数组
    static func split(_ text: String, maxCharCount: Int = defaultMaxCharCount) -> [String] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        
        // 如果文本字符数不超过限制，直接返回
        if calculateCharCount(trimmed) <= maxCharCount {
            return [trimmed]
        }
        
        var chunks: [String] = []
        var remaining = trimmed
        
        while !remaining.isEmpty {
            if calculateCharCount(remaining) <= maxCharCount {
                chunks.append(remaining)
                break
            }
            
            // 找到不超过 maxCharCount 的最大子串
            let searchRange = findMaxSubstring(in: remaining, maxCharCount: maxCharCount)
            
            if let splitIndex = findBestSplitPoint(in: searchRange) {
                let chunk = String(remaining.prefix(splitIndex))
                chunks.append(chunk.trimmingCharacters(in: .whitespacesAndNewlines))
                remaining = String(remaining.dropFirst(splitIndex))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                // 兜底：强制分割
                let chunk = searchRange
                chunks.append(chunk)
                remaining = String(remaining.dropFirst(chunk.count))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        
        return chunks.filter { !$0.isEmpty }
    }
    
    /// 按阿里云规则计算字符数
    /// 汉字（中日韩）= 2字符，其他 = 1字符
    static func calculateCharCount(_ text: String) -> Int {
        var count = 0
        for char in text {
            if isCJKCharacter(char) {
                count += 2
            } else {
                count += 1
            }
        }
        return count
    }
    
    /// 判断是否为中日韩汉字
    private static func isCJKCharacter(_ char: Character) -> Bool {
        guard let scalar = char.unicodeScalars.first else { return false }
        let value = scalar.value
        
        // CJK 统一汉字范围
        // 基本区: U+4E00 - U+9FFF
        // 扩展A: U+3400 - U+4DBF
        // 扩展B-F: U+20000 - U+2CEAF
        // 兼容汉字: U+F900 - U+FAFF
        return (value >= 0x4E00 && value <= 0x9FFF) ||    // 基本区
               (value >= 0x3400 && value <= 0x4DBF) ||    // 扩展A
               (value >= 0x20000 && value <= 0x2CEAF) ||  // 扩展B-F
               (value >= 0xF900 && value <= 0xFAFF)       // 兼容汉字
    }
    
    /// 找到不超过指定字符数的最大子串
    private static func findMaxSubstring(in text: String, maxCharCount: Int) -> String {
        var currentCount = 0
        var endIndex = text.startIndex
        
        for index in text.indices {
            let char = text[index]
            let charCount = isCJKCharacter(char) ? 2 : 1
            
            if currentCount + charCount > maxCharCount {
                break
            }
            
            currentCount += charCount
            endIndex = text.index(after: index)
        }
        
        return String(text[text.startIndex..<endIndex])
    }
    
    /// 寻找最佳分割点（返回字符索引）
    private static func findBestSplitPoint(in text: String) -> Int? {
        // 优先级1：换行符
        if let index = text.lastIndex(of: "\n") {
            let pos = text.distance(from: text.startIndex, to: index) + 1
            if pos > 0 { return pos }
        }
        
        // 优先级2：段落结束标点（。！？）
        let paragraphPunctuation: [Character] = ["。", "！", "？", "!", "?", "."]
        for punct in paragraphPunctuation {
            if let index = text.lastIndex(of: punct) {
                let pos = text.distance(from: text.startIndex, to: index) + 1
                if pos > 0 { return pos }
            }
        }
        
        // 优先级3：句内标点（；，、）
        let sentencePunctuation: [Character] = ["；", "，", "、", ";", ","]
        for punct in sentencePunctuation {
            if let index = text.lastIndex(of: punct) {
                let pos = text.distance(from: text.startIndex, to: index) + 1
                if pos > 0 { return pos }
            }
        }
        
        // 优先级4：空格
        if let index = text.lastIndex(of: " ") {
            let pos = text.distance(from: text.startIndex, to: index) + 1
            if pos > 0 { return pos }
        }
        
        return nil
    }
}
