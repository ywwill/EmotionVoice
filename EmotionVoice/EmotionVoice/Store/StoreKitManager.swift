//
//  StoreKitManager.swift
//  EmotionVoice
//
//  StoreKit 2 内购管理模块
//

import Foundation
import StoreKit
import Combine

// MARK: - 商品配置
enum CreditProduct: String, CaseIterable, Sendable {
    case credits6 = "ai.emora.credit.60"      // $1.99 → 60 积分
    case credits30 = "ai.emora.credit.30"     // $9.99 → 400 积分（主推）
    case credits60 = "ai.emora.credit.900"     // $19.99 → 900 积分（主推）
    case credits98 = "ai.emora.credit.1500"   // $29.99 → 1500 积分
    
    nonisolated var creditsAmount: Int {
        switch self {
        case .credits6: return 60
        case .credits30: return 400
        case .credits60: return 900
        case .credits98: return 1500
        }
    }
    
    nonisolated var isRecommended: Bool {
        return self == .credits30
    }
    
    nonisolated static var allProductIds: [String] {
        return allCases.map { $0.rawValue }
    }
}

// MARK: - 购买状态

enum PurchaseState: Equatable, Sendable {
    case idle
    case loading
    case purchasing
    case success(credits: Int)
    case failed(message: String)
    
    static func == (lhs: PurchaseState, rhs: PurchaseState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle), (.loading, .loading), (.purchasing, .purchasing):
            return true
        case (.success(let a), .success(let b)):
            return a == b
        case (.failed(let a), .failed(let b)):
            return a == b
        default:
            return false
        }
    }
}

// MARK: - 内购错误

enum StoreError: LocalizedError {
    case productNotFound
    case purchaseFailed
    case verificationFailed
    case userCancelled
    case pending
    case unknown
    
    var errorDescription: String? {
        switch self {
        case .productNotFound: return "商品未找到"
        case .purchaseFailed: return "购买失败"
        case .verificationFailed: return "验证失败"
        case .userCancelled: return "用户取消"
        case .pending: return "等待确认"
        case .unknown: return "未知错误"
        }
    }
}

// MARK: - StoreKit 管理器

@MainActor
final class StoreKitManager: NSObject, ObservableObject {
    static let shared = StoreKitManager()
    
    // MARK: - 属性
    
    @Published private(set) var products: [Product] = []
    @Published private(set) var purchaseState: PurchaseState = .idle
    @Published private(set) var isLoading = false
    
    private var updateListenerTask: Task<Void, Error>?

    /// 已处理的交易 ID 集合（防止重复发放积分）
    private var processedTransactionIDs: Set<UInt64> = []
    private let processedTransactionLock = NSLock()

    /// 记录已发放本笔交易积分（线程安全）。返回 true 表示本次首次处理，可继续发放。
    private func markTransactionIfNeeded(_ id: UInt64) -> Bool {
        processedTransactionLock.lock()
        defer { processedTransactionLock.unlock() }
        if processedTransactionIDs.contains(id) {
            return false
        }
        processedTransactionIDs.insert(id)
        return true
    }


    // MARK: - 初始化
    
    private override init() {
        super.init()
        updateListenerTask = listenForTransactions()
        Task {
            await loadProducts()
        }
    }
    
    deinit {
        updateListenerTask?.cancel()
    }
    
    // MARK: - 加载商品
    
    func loadProducts() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            let storeProducts = try await Product.products(for: CreditProduct.allProductIds)
            // 按价格排序
            products = storeProducts.sorted { $0.price < $1.price }
            Log(messageType: "StoreKit", message: "✅ 加载了 \(products.count) 个商品")
            
            for product in products {
                Log(messageType: "StoreKit", message: "  - \(product.id): \(product.displayPrice)")
            }
        } catch {
            Log(messageType: "StoreKit", message: "❌ 加载商品失败: \(error.localizedDescription)")
        }
    }
    
    // MARK: - 购买商品
    
    func purchase(_ product: Product) async {
        purchaseState = .purchasing
        
        do {
            let result = try await product.purchase()
            
            switch result {
            case .success(let verification):
                let transaction = try checkVerified(verification)
                
                // 防止与 Transaction.updates 监听器重复发放积分
                guard markTransactionIfNeeded(transaction.id) else {
                    Log(messageType: "StoreKit", message: "⚠️ 交易 \(transaction.id) 已处理，跳过重复发放")
                    await transaction.finish()
                    purchaseState = .success(credits: 0)
                    return
                }
                
                // 获取积分数量
                if let creditProduct = CreditProduct(rawValue: product.id) {
                    let credits = creditProduct.creditsAmount
                    
                    // 添加积分
                    CreditManager.shared.addCredits(credits)
                    
                    // 保存购买记录
                    CreditsService.shared.addPurchaseRecord(quantity: credits)
                    
                    Log(messageType: "StoreKit", message: "✅ 购买成功，获得 \(credits) 积分")
                    purchaseState = .success(credits: credits)
                }
                
                // 完成交易
                await transaction.finish()
                
            case .userCancelled:
                Log(messageType: "StoreKit", message: "⚠️ 用户取消购买")
                purchaseState = .failed(message: StoreError.userCancelled.localizedDescription)
                
            case .pending:
                Log(messageType: "StoreKit", message: "⏳ 购买等待确认")
                purchaseState = .failed(message: StoreError.pending.localizedDescription)
                
            @unknown default:
                purchaseState = .failed(message: StoreError.unknown.localizedDescription)
            }
        } catch {
            Log(messageType: "StoreKit", message: "❌ 购买失败: \(error.localizedDescription)")
            purchaseState = .failed(message: error.localizedDescription)
        }
    }
    
    /// 便捷方法：通过商品类型购买
    func purchase(_ creditProduct: CreditProduct) async {
        guard let product = products.first(where: { $0.id == creditProduct.rawValue }) else {
            purchaseState = .failed(message: StoreError.productNotFound.localizedDescription)
            return
        }
        await purchase(product)
    }
    
    /// 重置购买状态
    func resetPurchaseState() {
        purchaseState = .idle
    }
    
    // MARK: - 私有方法
    
    private func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .unverified:
            throw StoreError.verificationFailed
        case .verified(let safe):
            return safe
        }
    }
    
    /// 监听交易更新（处理中断的购买、家庭共享等）
    private func listenForTransactions() -> Task<Void, Error> {
        return Task.detached { [weak self] in
            for await result in Transaction.updates {
                guard let self else { return }
                do {
                    let transaction = try await self.checkVerified(result)
                    
                    // 防止与 purchase() 重复发放积分
                    guard await self.markTransactionIfNeeded(transaction.id) else {
                        Log(messageType: "StoreKit", message: "⚠️ 交易 \(transaction.id) 已处理，跳过监听器重复发放")
                        await transaction.finish()
                        continue
                    }
                    
                    // 处理未完成的消耗型购买
                    if let creditProduct = CreditProduct(rawValue: transaction.productID) {
                        let credits = creditProduct.creditsAmount
                        await CreditManager.shared.addCredits(credits)
                        // 保存购买记录
                        CreditsService.shared.addPurchaseRecord(quantity: credits)
                        Log(messageType: "StoreKit", message: "✅ 恢复交易，获得 \(credits) 积分")
                    }
                    
                    await transaction.finish()
                } catch {
                    Log(messageType: "StoreKit", message: "❌ 交易验证失败: \(error.localizedDescription)")
                }
            }
        }
    }
}

// MARK: - 商品信息扩展

extension StoreKitManager {
    /// 获取指定商品
    func product(for creditProduct: CreditProduct) -> Product? {
        return products.first { $0.id == creditProduct.rawValue }
    }
    
    /// 获取商品显示价格
    func displayPrice(for creditProduct: CreditProduct) -> String {
        return product(for: creditProduct)?.displayPrice ?? "--"
    }
    
    /// 获取推荐商品
    var recommendedProduct: Product? {
        return product(for: .credits30)
    }
}
