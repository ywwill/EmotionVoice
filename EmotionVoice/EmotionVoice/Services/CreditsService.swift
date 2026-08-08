//
//  CreditsService.swift
//  EmotionVoice
//
//  Created by young on 2026/8/8.
//

import Foundation
import SQLite

/// 积分服务
/// 积分余额本地保存于 UserDefaults，统计与交易记录保存于 SQLite
final class CreditsService {

    static let shared = CreditsService()

    private let db = DatabaseManager.shared

    private let balanceKey = "ev.credits.balance"
    private let monthlyUsedKey = "ev.credits.monthly_used"

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
            print("CreditsService.fetchTransactions error: \(error)")
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
            print("CreditsService.addTransaction error: \(error)")
            return false
        }
    }
}