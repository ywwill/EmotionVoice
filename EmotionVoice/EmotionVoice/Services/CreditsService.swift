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
    let amount: Double
    let createdAt: Date
    
    var isPositive: Bool {
        type == .purchase
    }
    
    /// 格式化积分显示
    var formattedAmount: String {
        let formatted = formatCredits(amount)
        if type == .purchase {
            return "+\(formatted)"
        } else {
            return "-\(formatted)"
        }
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
    private let creditManager = CreditManager.shared
    
    private let pageSize = 10

    /// 本月已用积分（本地存储，不需要云端同步）
    private let monthlyUsedKey = "ev.credits.monthly_used"
    var monthlyUsed: Int {
        get {
            let v = UserDefaults.standard.integer(forKey: monthlyUsedKey)
            return v == 0 ? Constants.defaultMonthlyUsed : v
        }
        set {
            UserDefaults.standard.set(newValue, forKey: monthlyUsedKey)
        }
    }

    /// 当前余额（使用 CreditManager 的云端同步数据）
    var balance: Int {
        creditManager.balance
    }

    /// 消耗积分（生成成功后调用）
    func consume(_ points: Int) {
        creditManager.deduct(for: .createVoice)
    }

    /// 检查是否可以消耗积分
    func canConsume(_ points: Int) -> Bool {
        return creditManager.balance >= points
    }

    /// 充值
    func purchase(_ points: Int) {
        creditManager.addCredits(points)
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
    func addConsumptionRecord(voiceName: String, voiceKey: String, audioDuration: Double, points: Double) -> Bool {
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
        // 获取所有消耗记录
        let allConsumption = fetchAllConsumptionRecords()
        
        // 获取所有购买记录
        let allPurchase = fetchAllPurchaseRecords()
        
        // 合并记录
        var combinedRecords: [CreditRecord] = []
        
        // 添加消耗记录
        for consume in allConsumption {
            combinedRecords.append(CreditRecord(
                id: "c_\(consume.id)",
                type: .consumption,
                title: consume.voiceName,
                subtitle: "\(consume.formattedDuration)",
                amount: consume.points,
                createdAt: consume.createdAt
            ))
        }
        
        // 添加购买记录
        for purchase in allPurchase {
            combinedRecords.append(CreditRecord(
                id: "p_\(purchase.id)",
                type: .purchase,
                title: "购买积分".localized(),
                subtitle: "/",
                amount: Double(purchase.quantity),
                createdAt: purchase.createdAt
            ))
        }
        
        // 按时间排序（最新的在前）
        combinedRecords.sort { $0.createdAt > $1.createdAt }
        
        // 计算总页数
        let totalCount = combinedRecords.count
        let totalPages = max(1, Int(ceil(Double(totalCount) / Double(pageSize))))
        
        // 计算分页偏移量
        let offset = (page - 1) * pageSize
        let endIndex = min(offset + pageSize, totalCount)
        
        // 提取当前页的数据
        let pageItems: [CreditRecord]
        if offset < totalCount {
            pageItems = Array(combinedRecords[offset..<endIndex])
        } else {
            pageItems = []
        }
        
        return PagedResult(
            items: pageItems,
            totalCount: totalCount,
            currentPage: page,
            pageSize: pageSize,
            totalPages: totalPages
        )
    }
    
    /// 获取所有消耗记录
    private func fetchAllConsumptionRecords() -> [ConsumptionRecord] {
        do {
            let query = db.consumptionRecords.order(db.consumeCreatedAt.desc)
            return try db.db.prepare(query).map { row in
                ConsumptionRecord(
                    id: row[db.consumeId],
                    voiceName: row[db.consumeVoiceName],
                    voiceKey: row[db.consumeVoiceKey],
                    audioDuration: row[db.consumeAudioDuration],
                    points: row[db.consumePoints],
                    createdAt: row[db.consumeCreatedAt]
                )
            }
        } catch {
            Log(message: "CreditsService.fetchAllConsumptionRecords error: \(error)")
            return []
        }
    }
    
    /// 获取所有购买记录
    private func fetchAllPurchaseRecords() -> [PurchaseRecord] {
        do {
            let query = db.purchaseRecords.order(db.purchaseCreatedAt.desc)
            return try db.db.prepare(query).map { row in
                PurchaseRecord(
                    id: row[db.purchaseId],
                    createdAt: row[db.purchaseCreatedAt],
                    quantity: row[db.purchaseQuantity]
                )
            }
        } catch {
            Log(message: "CreditsService.fetchAllPurchaseRecords error: \(error)")
            return []
        }
    }
}
