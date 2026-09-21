//
//  CreditService.swift
//  CloneVoice
//
//  积分服务 - 封装 TTS 和创建音色的积分校验流程
//

import Foundation

// MARK: - 积分服务错误

enum CreditServiceError: LocalizedError {
    case insufficientCredits(required: Int, available: Int)
    case operationFailed(Error)
    
    var errorDescription: String? {
        switch self {
        case .insufficientCredits(let required, let available):
            return "积分不足，需要 \(required) 积分，当前积分 \(available) 积分"
        case .operationFailed(let error):
            return error.localizedDescription
        }
    }
    
    var isInsufficientCredits: Bool {
        if case .insufficientCredits = self { return true }
        return false
    }
}

// MARK: - TTS 类型

enum TTSType {
    case normal     // 普通 TTS
    case clone      // 声音复刻 TTS
}

// MARK: - 积分服务

@MainActor
class CreditService {
    static let shared = CreditService()
    
    private let creditManager = CreditManager.shared
    
    private init() {}
    
    // MARK: - TTS 积分校验
    
    /// 校验 TTS 积分是否足够
    /// - Returns: nil 表示积分足够，否则返回错误
    func validateTTS(text: String, type: TTSType) -> CreditServiceError? {
        let characterCount = TextSplitter.calculateCharCount(text)
        let consumptionType: CreditConsumptionType = type == .normal
            ? .normalTTS(characterCount: characterCount)
            : .cloneTTS(characterCount: characterCount)
        
        let result = creditManager.checkCredits(for: consumptionType)
        
        switch result {
        case .success:
            return nil
        case .insufficientCredits(let required, let available):
            return .insufficientCredits(required: required, available: available)
        }
    }
    
    /// 执行 TTS 前扣除积分
    /// - Returns: 成功返回扣除的积分数，失败返回 nil
    func deductForTTS(text: String, type: TTSType) -> Int? {
        let characterCount = TextSplitter.calculateCharCount(text)
        let consumptionType: CreditConsumptionType = type == .normal
            ? .normalTTS(characterCount: characterCount)
            : .cloneTTS(characterCount: characterCount)
        
        let credits = creditManager.calculateCredits(for: consumptionType)
        let result = creditManager.deduct(for: consumptionType)
        
        switch result {
        case .success:
            return credits
        case .insufficientCredits:
            return nil
        }
    }
    
    /// TTS 合成失败时返还积分
    func refundTTS(credits: Int) {
        creditManager.addCredits(credits)
        Log(messageType: "Credit", message: "💰 TTS 合成失败，返还 \(credits) 积分")
    }
    
    // MARK: - 积分预估
    
    /// 获取 TTS 所需积分
    func estimateCredits(text: String, type: TTSType) -> Int {
        let characterCount = TextSplitter.calculateCharCount(text)
        return type == .normal
            ? creditManager.calculateCredits(for: .normalTTS(characterCount: characterCount))
            : creditManager.calculateCredits(for: .cloneTTS(characterCount: characterCount))
    }
    
    /// 当前积分余额
    var currentBalance: Int {
        return creditManager.balance
    }
}
