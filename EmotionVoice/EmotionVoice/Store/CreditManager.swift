//
//  CreditManager.swift
//  EmotionVoice
//
//  积分管理模块 - 负责积分的存储、增减和校验
//  支持本地缓存 + Supabase 云端同步
//

import Foundation
import Combine

// MARK: - 积分消耗类型

enum CreditConsumptionType {
    case createVoice                    // 创建音色：10 积分/次
    case normalTTS(characterCount: Int) // 普通 TTS：2 积分/100字符
    case cloneTTS(characterCount: Int)  // 声音复刻 TTS：5 积分/100字符
}

// MARK: - 积分操作结果

enum CreditResult {
    case success
    case insufficientCredits(required: Int, available: Int)
}

// MARK: - 积分管理器

@MainActor
class CreditManager: ObservableObject {
    static let shared = CreditManager()
    
    // MARK: - 常量
    
    private enum Constants {
        static let creditsKey = "user_credits_balance"
        static let charactersPerUnit = 100          // 100 字符 = 1 积分单位
        static let createVoiceCost = 10             // 创建音色消耗
        static let normalTTSRate = 2                // 普通 TTS 每 100 字符消耗
        static let cloneTTSRate = 5                 // 复刻 TTS 每 100 字符消耗
    }
    
    // MARK: - 属性
    
    /// 当前积分余额
    @Published private(set) var balance: Int {
        didSet {
            saveBalanceLocally()
        }
    }
    
    /// 是否正在同步
    @Published private(set) var isSyncing = false
    
    private let userDefaults: UserDefaults
    
    // MARK: - 初始化
    
    private init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        self.balance = userDefaults.integer(forKey: Constants.creditsKey)
    }
    
    // MARK: - 云端同步
    
    /// 从云端同步积分（应用启动时调用）
    func syncFromCloud() {
        isSyncing = true
        
        Task {
            do {
                let (cloudCredits, _) = try await SupabaseManager.shared.initializeUser()
                await MainActor.run {
                    self.balance = cloudCredits
                    self.isSyncing = false
                    Log(messageType: "Credit", message: "☁️ 云端同步成功，积分: \(cloudCredits)")
                }
            } catch {
                await MainActor.run {
                    self.isSyncing = false
                    Log(messageType: "Credit", message: "⚠️ 云端同步失败: \(error.localizedDescription)，使用本地缓存")
                }
            }
        }
    }
    
    /// 同步积分到云端
    private func syncToCloud() {
        Task {
            do {
                try await SupabaseManager.shared.updateCredits(balance)
            } catch {
                Log(messageType: "Credit", message: "⚠️ 同步到云端失败: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - 公开方法
    
    /// 计算所需积分
    func calculateCredits(for type: CreditConsumptionType) -> Int {
        switch type {
        case .createVoice:
            return Constants.createVoiceCost
            
        case .normalTTS(let characterCount):
            return calculateTTSCredits(characterCount: characterCount, rate: Constants.normalTTSRate)
            
        case .cloneTTS(let characterCount):
            return calculateTTSCredits(characterCount: characterCount, rate: Constants.cloneTTSRate)
        }
    }
    
    /// 检查积分是否足够
    func hasEnoughCredits(for type: CreditConsumptionType) -> Bool {
        let required = calculateCredits(for: type)
        return balance >= required
    }
    
    /// 检查并返回详细结果
    func checkCredits(for type: CreditConsumptionType) -> CreditResult {
        let required = calculateCredits(for: type)
        if balance >= required {
            return .success
        } else {
            return .insufficientCredits(required: required, available: balance)
        }
    }
    
    /// 扣除积分（执行前请先调用 checkCredits 确认）
    @discardableResult
    func deduct(for type: CreditConsumptionType) -> CreditResult {
        let required = calculateCredits(for: type)
        
        guard balance >= required else {
            return .insufficientCredits(required: required, available: balance)
        }
        
        balance -= required
        Log(messageType: "Credit", message: "💰 扣除 \(required) 积分，剩余 \(balance)")
        
        // 同步到云端
        syncToCloud()
        
        return .success
    }
    
    /// 增加积分（内购成功后调用）
    func addCredits(_ amount: Int) {
        guard amount > 0 else { return }
        balance += amount
        Log(messageType: "Credit", message: "💰 增加 \(amount) 积分，当前积分 \(balance)")
        
        // 同步到云端
        syncToCloud()
    }
    
    // MARK: - 私有方法
    
    private func calculateTTSCredits(characterCount: Int, rate: Int) -> Int {
        guard characterCount > 0 else { return 0 }
        // 向上取整：(count + 99) / 100
        let units = (characterCount + Constants.charactersPerUnit - 1) / Constants.charactersPerUnit
        return units * rate
    }
    
    private func saveBalanceLocally() {
        userDefaults.set(balance, forKey: Constants.creditsKey)
    }
}

// MARK: - 便捷扩展

extension CreditManager {
    /// 普通 TTS 所需积分
    func creditsForNormalTTS(text: String) -> Int {
        let count = TextSplitter.calculateCharCount(text)
        return calculateCredits(for: .normalTTS(characterCount: count))
    }
    
    /// 声音复刻 TTS 所需积分
    func creditsForCloneTTS(text: String) -> Int {
        let count = TextSplitter.calculateCharCount(text)
        return calculateCredits(for: .cloneTTS(characterCount: count))
    }
    
    /// 创建音色所需积分
    var creditsForCreateVoice: Int {
        return calculateCredits(for: .createVoice)
    }
    
    /// 设备唯一标识
    var deviceId: String {
        return DeviceIdentifier.shared.deviceId
    }
}
