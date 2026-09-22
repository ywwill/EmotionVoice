//
//  CreditsService.swift
//  EmotionVoice
//
//  积分服务
/// 积分余额本地保存于 UserDefaults，统计与交易记录保存于 SQLite
/// 消耗记录和购买记录也保存于 SQLite
//

import Foundation
import SQLite

/// 积分记录类型
enum CreditRecordType: String, CaseIterable, Identifiable {
    case consumption = "consumption"
    case purchase = "purchase"
    
    var id: String { rawValue }
    
    var displayName: String {
        switch self {
        case .consumption: return "消耗".localized()
        case .purchase: return "购买".localized()
        }
    }
    
    var icon: String {
        switch self {
        case .consumption: return "-"
        case .purchase: return "+"
        }
    }
}

/// 积分记录（统一消耗和购买记录的展示）
struct CreditRecord: Identifiable, Hashable {
    let id: String
    let type: CreditRecordType
    let title: String
    let subtitle: String
    let amount: Int
    let createdAt: Date
    
    var isPositive: Bool {
        type == .purchase
    }
}

/// 分页结果
struct PagedResult<T> {
    let items: [T]
    let totalCount: Int
    let currentPage: Int
    let pageSize: Int
    let totalPages: Int
    
    var hasNextPage: Bool {
        currentPage < totalPages
    }
    
    var hasPreviousPage: Bool {
        currentPage > 1
    }
}

final class CreditsService {

    static let shared = CreditsService()

    private let db = DatabaseManager.shared

    private let balanceKey = "ev.credits.balance"
    private let monthlyUsedKey = "ev.credits.monthly_used"
    
    private let pageSize = 10

    /// 当前余额
    var balance: Int {
        get {
            let v = UserDefaults.standard.integer(forKey: balanceKey)
            return v == 0 ? Constants.defaultCreditsBalance : v
        }
        set {
            UserDefaults.standard.set(newValue, forKey: balanceKey)
        }
    }

    /// 本月已用积分
    var monthlyUsed: Int {
        get {
            let v = UserDefaults.standard.integer(forKey: monthlyUsedKey)
            return v == 0 ? Constants.defaultMonthlyUsed : v
        }
        set {
            UserDefaults.standard.set(newValue, forKey: monthlyUsedKey)
        }
    }

    /// 消耗积分（生成成功后调用）
    func consume(_ points: Int) {
        balance = max(0, balance - points)
        monthlyUsed += points
    }

    /// 检查是否可以消耗积分
    func canConsume(_ points: Int) -> Bool {
        return balance >= points
    }

    /// 充值
    func purchase(_ points: Int) {
        balance += points
    }

    // MARK: - 交易记录

    /// 获取所有交易记录
    func fetchTransactions() -> [TransactionRecord] {
        do {
            return try db.db.prepare(db.transactions.order(db.txCreatedAt.desc))
                .map { row in
                    TransactionRecord(
                        id: row[db.txId],
                        type: TransactionType(rawValue: row[db.txType]) ?? .consume,
                        title: row[db.txTitle],
                        amount: row[db.txAmount],
                        meta: row[db.txMeta],
                        createdAt: row[db.txCreatedAt]
                    )
                }
        } catch {
            Log(message: "CreditsService.fetchTransactions error: \(error)")
            return []
        }
    }

    /// 添加交易记录
    @discardableResult
    func addTransaction(_ record: TransactionRecord) -> Bool {
        do {
            try db.db.run(db.transactions.insert(
                db.txType <- record.type.rawValue,
                db.txTitle <- record.title,
                db.txAmount <- record.amount,
                db.txMeta <- record.meta,
                db.txCreatedAt <- record.createdAt
            ))
            return true
        } catch {
            Log(message: "CreditsService.addTransaction error: \(error)")
            return false
        }
    }
    
    // MARK: - 消耗记录
    
    /// 添加消耗记录
    @discardableResult
    func addConsumptionRecord(voiceName: String, voiceKey: String, audioDuration: Double, points: Int) -> Bool {
        do {
            try db.db.run(db.consumptionRecords.insert(
                db.consumeVoiceName <- voiceName,
                db.consumeVoiceKey <- voiceKey,
                db.consumeAudioDuration <- audioDuration,
                db.consumePoints <- points,
                db.consumeCreatedAt <- Date()
            ))
            return true
        } catch {
            Log(message: "CreditsService.addConsumptionRecord error: \(error)")
            return false
        }
    }
    
    /// 获取消耗记录（分页）
    func fetchConsumptionRecords(page: Int) -> PagedResult<ConsumptionRecord> {
        do {
            let offset = (page - 1) * pageSize
            
            // 获取总数量
            let totalCount = try db.db.scalar(db.consumptionRecords.count)
            let totalPages = max(1, Int(ceil(Double(totalCount) / Double(pageSize))))
            
            // 获取分页数据
            let query = db.consumptionRecords
                .order(db.consumeCreatedAt.desc)
                .limit(pageSize, offset: offset)
            
            let records = try db.db.prepare(query).map { row in
                ConsumptionRecord(
                    id: row[db.consumeId],
                    voiceName: row[db.consumeVoiceName],
                    voiceKey: row[db.consumeVoiceKey],
                    audioDuration: row[db.consumeAudioDuration],
                    points: row[db.consumePoints],
                    createdAt: row[db.consumeCreatedAt]
                )
            }
            
            return PagedResult(
                items: records,
                totalCount: totalCount,
                currentPage: page,
                pageSize: pageSize,
                totalPages: totalPages
            )
        } catch {
            Log(message: "CreditsService.fetchConsumptionRecords error: \(error)")
            return PagedResult(items: [], totalCount: 0, currentPage: page, pageSize: pageSize, totalPages: 1)
        }
    }
    
    // MARK: - 购买记录
    
    /// 添加购买记录
    @discardableResult
    func addPurchaseRecord(quantity: Int) -> Bool {
        do {
            try db.db.run(db.purchaseRecords.insert(
                db.purchaseQuantity <- quantity,
                db.purchaseCreatedAt <- Date()
            ))
            return true
        } catch {
            Log(message: "CreditsService.addPurchaseRecord error: \(error)")
            return false
        }
    }
    
    /// 获取购买记录（分页）
    func fetchPurchaseRecords(page: Int) -> PagedResult<PurchaseRecord> {
        do {
            let offset = (page - 1) * pageSize
            
            // 获取总数量
            let totalCount = try db.db.scalar(db.purchaseRecords.count)
            let totalPages = max(1, Int(ceil(Double(totalCount) / Double(pageSize))))
            
            // 获取分页数据
            let query = db.purchaseRecords
                .order(db.purchaseCreatedAt.desc)
                .limit(pageSize, offset: offset)
            
            let records = try db.db.prepare(query).map { row in
                PurchaseRecord(
                    id: row[db.purchaseId],
                    createdAt: row[db.purchaseCreatedAt],
                    quantity: row[db.purchaseQuantity]
                )
            }
            
            return PagedResult(
                items: records,
                totalCount: totalCount,
                currentPage: page,
                pageSize: pageSize,
                totalPages: totalPages
            )
        } catch {
            Log(message: "CreditsService.fetchPurchaseRecords error: \(error)")
            return PagedResult(items: [], totalCount: 0, currentPage: page, pageSize: pageSize, totalPages: 1)
        }
    }
    
    // MARK: - 统一积分记录（分页）
    
    /// 获取统一积分记录（消耗 + 购买，合并后按时间排序）
    func fetchCreditRecords(page: Int) -> PagedResult<CreditRecord> {
        // 获取消耗记录
        let consumptionResult = fetchConsumptionRecords(page: page)
        
        // 获取购买记录
        let purchaseResult = fetchPurchaseRecords(page: page)
        
        // 合并记录
        var combinedRecords: [CreditRecord] = []
        
        // 添加消耗记录
        for consume in consumptionResult.items {
            combinedRecords.append(CreditRecord(
                id: "c_\(consume.id)",
                type: .consumption,
                title: consume.voiceName,
                subtitle: "音频 \(consume.formattedDuration)",
                amount: consume.points,
                createdAt: consume.createdAt
            ))
        }
        
        // 添加购买记录
        for purchase in purchaseResult.items {
            combinedRecords.append(CreditRecord(
                id: "p_\(purchase.id)",
                type: .purchase,
                title: "购买积分",
                subtitle: "积分充值",
                amount: purchase.quantity,
                createdAt: purchase.createdAt
            ))
        }
        
        // 按时间排序（最新的在前）
        combinedRecords.sort { $0.createdAt > $1.createdAt }
        
        // 计算总记录数
        let totalCount = consumptionResult.totalCount + purchaseResult.totalCount
        let totalPages = max(1, Int(ceil(Double(totalCount) / Double(pageSize))))
        
        return PagedResult(
            items: combinedRecords,
            totalCount: totalCount,
            currentPage: page,
            pageSize: pageSize,
            totalPages: totalPages
        )
    }
}
