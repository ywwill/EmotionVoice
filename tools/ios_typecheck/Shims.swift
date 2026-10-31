//
//  Shims.swift
//  iOSEmora 类型检查辅助（**不进任何 Xcode target**）
//
//  本机 `xcodebuild` 被沙箱挡住 SPM 包解析（sandbox-exec: Operation not permitted），
//  拿不到 SQLite / Supabase / KeychainSwift 的 .swiftmodule，
//  于是 `swiftc -typecheck` 无法编译 iOS 端那些引用服务的视图。
//
//  这里给「依赖 SPM 的 6 个服务」写一份**同签名的最小替身**，
//  单独用来跑 `swiftc -typecheck`：只验证 iOS 端新代码的**类型正确性**，
//  不涉及任何运行行为（真机 / 模拟器编译仍走 Xcode + 真包）。
//
//  需要替身的 6 个文件（都 import 了 SPM 包）：
//  DatabaseManager.swift(SQLite) · VoiceService.swift(SQLite) ·
//  ProjectService.swift(SQLite) · CreditsService.swift(SQLite) ·
//  SupabaseManager.swift(Supabase) · DeviceIdentifier.swift(KeychainSwift)
//

import Foundation
import SwiftUI
import Combine

// MARK: - 通用分页结果（与 Services/CreditsService.swift 中定义一致）

struct PagedResult<T> {
    let items: [T]
    let totalCount: Int
    let currentPage: Int
    let pageSize: Int
    let totalPages: Int

    var hasNextPage: Bool { currentPage < totalPages }
    var hasPreviousPage: Bool { currentPage > 1 }
}

// MARK: - 积分记录（与 Services/CreditsService.swift 中定义一致）

enum CreditRecordType: String, CaseIterable, Identifiable {
    case consumption = "consumption"
    case purchase = "purchase"

    var id: String { rawValue }
    var displayName: String { rawValue }
    var icon: String { rawValue }
}

struct CreditRecord: Identifiable, Hashable {
    let id: String
    let type: CreditRecordType
    let title: String
    let subtitle: String
    let amount: Double
    let createdAt: Date

    var isPositive: Bool { type == .purchase }
    var formattedAmount: String {
        (type == .purchase ? "+" : "-") + String(format: "%.2f", amount)
    }
}

// MARK: - 替身：数据库

final class DatabaseManager {
    static let shared = DatabaseManager()
    private init() {}
}

// MARK: - 替身：音色服务

@MainActor
final class VoiceService {
    static let shared = VoiceService()
    private init() {}

    func displayName(forKey key: String) -> String? { nil }
    func voice(forKey key: String) -> Voice? { nil }
    func invalidateVoiceCache() {}
    func fetchAll() -> [Voice] { [] }
    func fetch(by category: VoiceCategory) -> [Voice] { [] }
    func count(category: VoiceCategory?, searchText: String) -> Int { 0 }
    func orderedVoices(showingFavorites: Bool,
                       category: VoiceCategory?,
                       searchText: String) -> [Voice] { [] }
    func fetchByKeys(_ keys: [String]) -> [Voice] { [] }
    func countFavorites() -> Int { 0 }
    func countFavorites(searchText: String) -> Int { 0 }
    @discardableResult
    func toggleFavorite(key: String) -> Bool { false }
}

// MARK: - 替身：项目服务

@MainActor
final class ProjectService {
    static let shared = ProjectService()
    nonisolated static let pageSize: Int = 50
    private init() {}

    func fetchAudios(page: Int, pageSize: Int = ProjectService.pageSize) -> (audios: [AudioItem], total: Int) {
        (audios: [], total: 0)
    }
    func fetchAllAudios() -> [AudioItem] { [] }

    func createAudio(fileName: String,
                     text: String,
                     voice: String,
                     format: String,
                     sampleRate: Int,
                     pointsCost: Double,
                     status: AudioStatus = .completed,
                     displayName: String? = nil,
                     duration: Double = 0.0) -> AudioItem? { nil }

    func updateAudioDuration(audioId: Int64, duration: Double) {}
    func renameAudio(id: Int64, displayName: String?) {}
    func duplicateAudio(_ source: AudioItem) -> AudioItem? { nil }
    // 真实实现是 `nonisolated static`（只依赖 FileManager，不碰 SQLite 连接），
    // 必须能脱离主线程调用 —— iOS 的左滑「复制」把它在 `Task.detached` 里跑。
    nonisolated static func stageDuplicatedFile(sourceURL: URL, fileExtension: String) -> String? { nil }
    nonisolated func finishDuplicate(source: AudioItem, newFileName: String) -> AudioItem? { nil }
    func deleteAudio(id: Int64) {}
    func estimatePoints(forText text: String) -> Int { 0 }
}

// MARK: - 替身：积分服务

final class CreditsService {
    static let shared = CreditsService()
    private init() {}

    @MainActor var balance: Double { 0 }
    @MainActor var monthlyUsed: Double { 0 }

    func fetchCreditRecords(page: Int) -> PagedResult<CreditRecord> {
        PagedResult(items: [], totalCount: 0, currentPage: page, pageSize: 10, totalPages: 1)
    }
    @discardableResult
    func addPurchaseRecord(quantity: Int) -> Bool { false }
    @discardableResult
    func addConsumptionRecord(voiceName: String,
                              voiceKey: String,
                              audioDuration: Double,
                              points: Double) -> Bool { false }
    @MainActor @discardableResult
    func consume(_ points: Double) -> Bool { false }
    @MainActor func canConsume(_ points: Double) -> Bool { false }
    @MainActor func purchase(_ points: Double) {}
    func fetchConsumptionRecords(page: Int) -> PagedResult<ConsumptionRecord> {
        PagedResult(items: [], totalCount: 0, currentPage: page, pageSize: 10, totalPages: 1)
    }
    func fetchPurchaseRecords(page: Int) -> PagedResult<PurchaseRecord> {
        PagedResult(items: [], totalCount: 0, currentPage: page, pageSize: 10, totalPages: 1)
    }
}

// MARK: - 替身：Supabase

final class SupabaseManager {
    static let shared = SupabaseManager()
    private init() {}

    func initializeUser() async throws -> (credits: Double, user: UserCreditsModel?) { (credits: 0, user: nil) }
    func updateCredits(_ credits: Double) async throws {}
}

// MARK: - 替身：设备标识

final class DeviceIdentifier {
    static let shared = DeviceIdentifier()
    private init() {}

    var deviceId: String { "" }
    func getUserUUID() -> String { "" }
}
