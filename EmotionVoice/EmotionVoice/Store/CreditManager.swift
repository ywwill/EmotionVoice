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
    case normalTTS(characterCount: Int) // 普通 TTS：2 积分/100字符（按实际字符数计费）
    case cloneTTS(characterCount: Int)  // 声音复刻 TTS：5 积分/100字符（按实际字符数计费）
}

// MARK: - 积分操作结果

enum CreditResult {
    case success
    case insufficientCredits(required: Double, available: Double)
}

// MARK: - 积分精度

/// 积分统一按「最多 2 位小数」记账：余额、消耗、预估都走这个归一化，
/// 避免 Double 累加出现 0.30000000000000004 这类尾数。
enum CreditPrecision {
    /// 归一化到最多 2 位小数（四舍五入）
    static func normalize(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return (value * 100).rounded() / 100
    }
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
    
    /// 当前积分余额（支持最多 2 位小数）
    @Published private(set) var balance: Double {
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
        // 旧版本存的是整数，double(forKey:) 同样能读出来，无需迁移
        self.balance = CreditPrecision.normalize(userDefaults.double(forKey: Constants.creditsKey))
    }
    
    // MARK: - 云端同步
    
    /// 从云端同步积分（应用启动时调用）
    func syncFromCloud() {
        isSyncing = true
        
        Task {
            do {
                let (cloudCredits, _) = try await SupabaseManager.shared.initializeUser()
                await MainActor.run {
                    self.balance = CreditPrecision.normalize(cloudCredits)
                    // 同步到本地存储
                    self.saveBalanceLocally()
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
    
    /// 计算所需积分（按实际消耗，最多 2 位小数）
    func calculateCredits(for type: CreditConsumptionType) -> Double {
        switch type {
        case .createVoice:
            return Double(Constants.createVoiceCost)
            
        case .normalTTS(let characterCount):
            return calculateTTSCredits(characterCount: characterCount, rate: Constants.normalTTSRate)
            
        case .cloneTTS(let characterCount):
            return calculateTTSCredits(characterCount: characterCount, rate: Constants.cloneTTSRate)
        }
    }
    
    /// 计算所需积分（Double 类型，用于预估显示）
    /// 与 `calculateCredits(for:)` 等价，保留用于语义化调用
    func calculateCreditsDouble(for type: CreditConsumptionType) -> Double {
        return calculateCredits(for: type)
    }
    
    /// 检查积分是否足够
    func hasEnoughCredits(for type: CreditConsumptionType) -> Bool {
        let required = calculateCredits(for: type)
        return balance + 1e-9 >= required
    }
    
    /// 检查并返回详细结果
    func checkCredits(for type: CreditConsumptionType) -> CreditResult {
        let required = calculateCredits(for: type)
        if balance + 1e-9 >= required {
            return .success
        } else {
            return .insufficientCredits(required: required, available: balance)
        }
    }
    
    /// 扣除积分（执行前请先调用 checkCredits 确认）
    @discardableResult
    func deduct(for type: CreditConsumptionType) -> CreditResult {
        return deduct(points: calculateCredits(for: type))
    }
    
    /// 直接扣除指定积分（按实际消耗，最多 2 位小数）
    @discardableResult
    func deduct(points: Double) -> CreditResult {
        let required = CreditPrecision.normalize(points)
        guard required > 0 else { return .success }
        
        // 1e-9 容差：抵消浮点尾数，避免 0.30 余额扣 0.30 被判成不足
        guard balance + 1e-9 >= required else {
            return .insufficientCredits(required: required, available: balance)
        }
        
        balance = CreditPrecision.normalize(max(0, balance - required))
        Log(messageType: "Credit", message: "💰 扣除 \(formatCredits(required)) 积分，剩余 \(formatCredits(balance))")
        
        // 同步到云端
        syncToCloud()
        
        return .success
    }
    
    /// 增加积分（内购成功后调用）
    func addCredits(_ amount: Double) {
        guard amount > 0 else { return }
        balance = CreditPrecision.normalize(balance + amount)
        Log(messageType: "Credit", message: "💰 增加 \(formatCredits(amount)) 积分，当前积分 \(formatCredits(balance))")
        
        // 同步到云端
        syncToCloud()
    }
    
    // MARK: - 私有方法
    
    private func calculateTTSCredits(characterCount: Int, rate: Int) -> Double {
        guard characterCount > 0 else { return 0 }
        // 按实际字符数计费，无起扣门槛：10 字符 = 0.2 积分，5 字符 = 0.1 积分
        let credits = Double(characterCount) / Double(Constants.charactersPerUnit) * Double(rate)
        return CreditPrecision.normalize(credits)  // 最多保留 2 位小数
    }
    
    private func saveBalanceLocally() {
        userDefaults.set(balance, forKey: Constants.creditsKey)
    }
}

// MARK: - 便捷扩展

extension CreditManager {
    /// 普通 TTS 所需积分（Double，用于预估显示）
    func creditsForNormalTTS(text: String) -> Double {
        let count = TextSplitter.calculateCharCount(text)
        return calculateCreditsDouble(for: .normalTTS(characterCount: count))
    }
    
    /// 声音复刻 TTS 所需积分（Double，用于预估显示）
    func creditsForCloneTTS(text: String) -> Double {
        let count = TextSplitter.calculateCharCount(text)
        return calculateCreditsDouble(for: .cloneTTS(characterCount: count))
    }
    
    /// 创建音色所需积分
    var creditsForCreateVoice: Double {
        return calculateCredits(for: .createVoice)
    }
    
    /// 设备唯一标识
    var deviceId: String {
        return DeviceIdentifier.shared.deviceId
    }
}
