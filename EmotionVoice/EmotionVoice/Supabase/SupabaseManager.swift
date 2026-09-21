//
//  SupabaseManager.swift
//  EmotionVoice
//
//  Supabase 数据同步管理
//

import Foundation
import Supabase

// MARK: - Supabase 管理器

class SupabaseManager {
    static let shared = SupabaseManager()
    
    let client: SupabaseClient
    private let tableName = "user_credits"
    
    private var deviceId: String {
        DeviceIdentifier.shared.deviceId
    }
    
    // 缓存用户数据，避免重复请求
    private var cachedUserData: UserCreditsModel?
    private var isInitializing = false
    private var initializationTask: Task<(Int, UserCreditsModel?), Error>?
    
    /// 获取缓存的用户区域代码
    /// 如果缓存不存在，返回当前设备的区域代码
    func getCachedRegion() -> String {
        if let cached = cachedUserData {
            return cached.region.uppercased()  // 确保返回大写
        }
        // 缓存不存在时，返回当前设备区域（仅在初始化前使用）
        return RegionManager.getCurrentRegionCode()
    }
    
    private init() {
        client = SupabaseClient(
            supabaseURL: URL(string: "https://\(kSupabaseProjectRef).supabase.co")!,
            supabaseKey: kSupabasePublishableKey
        )
    }
}

// MARK: - 用户数据管理

extension SupabaseManager {
    
    /// 保存或更新用户数据
    func saveOrUpdateUser(_ userModel: UserCreditsModel) async throws {
        do {
            Log(messageType: "Supabase", message: "💾 开始保存用户数据: \(userModel.deviceId)")
            
            let _: [UserCreditsModel] = try await client
                .from(tableName)
                .upsert(userModel, onConflict: "device_id")
                .select()
                .execute()
                .value
            
            Log(messageType: "Supabase", message: "✅ 用户数据已保存/更新: \(userModel.deviceId), 积分: \(userModel.credits)")
        } catch let postgrestError as PostgrestError {
            Log(messageType: "Supabase", message: "❌ Supabase PostgreSQL 错误: \(postgrestError)")
            Log(messageType: "Supabase", message: "❌ 错误代码: \(postgrestError.code ?? "未知")")
            Log(messageType: "Supabase", message: "❌ 错误消息: \(postgrestError.message)")
            
            if postgrestError.code == "23505" {
                Log(messageType: "Supabase", message: "🔄 检测到唯一约束冲突，尝试直接更新")
                try await client
                    .from(tableName)
                    .update(["credits": AnyJSON(userModel.credits)])
                    .eq("device_id", value: userModel.deviceId)
                    .execute()
                Log(messageType: "Supabase", message: "✅ 用户数据已通过更新操作保存")
            } else {
                throw postgrestError
            }
        } catch {
            Log(messageType: "Supabase", message: "❌ 保存用户数据失败: \(error.localizedDescription)")
            throw error
        }
    }
    
    /// 获取用户数据（公开方法，供外部调用）
    func getUserData() async throws -> UserCreditsModel? {
        return try await getUser(deviceId: deviceId)
    }
    
    /// 获取用户数据
    private func getUser(deviceId: String) async throws -> UserCreditsModel? {
        do {
            Log(messageType: "Supabase", message: "🔍 开始获取用户数据: \(deviceId)")
            
            let response: [UserCreditsModel] = try await client
                .from(tableName)
                .select()
                .eq("device_id", value: deviceId)
                .limit(1)
                .execute()
                .value
            
            if let user = response.first {
                Log(messageType: "Supabase", message: "✅ 获取到用户数据: \(deviceId), 积分: \(user.credits)")
                return user
            } else {
                Log(messageType: "Supabase", message: "ℹ️ 用户不存在: \(deviceId)")
                return nil
            }
        } catch {
            Log(messageType: "Supabase", message: "❌ 获取用户数据失败: \(error.localizedDescription)")
            throw error
        }
    }
    
    /// 初始化用户（首次启动时调用）
    /// 返回：(积分, 用户数据)
    /// 使用缓存避免重复请求
    func initializeUser() async throws -> (credits: Int, user: UserCreditsModel?) {
        // 如果已经有缓存，直接返回
        if let cached = cachedUserData {
            Log(messageType: "Supabase", message: "📦 使用缓存的用户数据")
            return (cached.credits, cached)
        }
        
        // 如果正在初始化，等待现有任务完成
        if let existingTask = initializationTask {
            Log(messageType: "Supabase", message: "⏳ 等待现有初始化任务完成")
            return try await existingTask.value
        }
        
        // 创建新的初始化任务
        let task = Task<(Int, UserCreditsModel?), Error> {
            if let user = try await getUser(deviceId: deviceId) {
                // 用户已存在，缓存并返回
                self.cachedUserData = user
                // 检查是否需要更新 device_info
                if let info = DeviceInfo.fromStorageString(user.deviceInfo) {
                    if info.deviceModel == "Unknown" || info.deviceModel.isEmpty {
                        Log(messageType: "Supabase", message: "📱 用户缺少设备信息，正在更新...")
                        let newDeviceInfo = DeviceInfo.current()
                        var updatedUser = user
                        updatedUser.deviceInfo = newDeviceInfo.toStorageString()
                        // updatedAt 使用本地时间
                        updatedUser.updatedAt = UserCreditsModel.currentLocalDateString()
                        try await saveOrUpdateUser(updatedUser)
                        self.cachedUserData = updatedUser
                        Log(messageType: "Supabase", message: "✅ 设备信息已更新: \(newDeviceInfo.toStorageString())")
                    }
                } else {
                    Log(messageType: "Supabase", message: "📱 用户设备信息为空或格式无效，正在更新...")
                    let newDeviceInfo = DeviceInfo.current()
                    var updatedUser = user
                    updatedUser.deviceInfo = newDeviceInfo.toStorageString()
                    // updatedAt 使用本地时间
                    updatedUser.updatedAt = UserCreditsModel.currentLocalDateString()
                    try await saveOrUpdateUser(updatedUser)
                    self.cachedUserData = updatedUser
                    Log(messageType: "Supabase", message: "✅ 设备信息已更新: \(newDeviceInfo.toStorageString())")
                }
                return (user.credits, self.cachedUserData)
            } else {
                // 新用户，创建并赠送50积分作为试用
                let regionCode = RegionManager.getCurrentRegionCode()
                let newUser = UserCreditsModel(deviceId: deviceId, credits: 50, region: regionCode, deviceInfo: DeviceInfo.current())
                try await saveOrUpdateUser(newUser)
                Log(messageType: "Supabase", message: "✅ 新用户已创建，区域: \(regionCode)，设备: \(newUser.deviceInfo ?? "")，赠送50积分")
                self.cachedUserData = newUser
                return (50, newUser)
            }
        }
        
        initializationTask = task
        
        do {
            let result = try await task.value
            initializationTask = nil
            return result
        } catch {
            initializationTask = nil
            throw error
        }
    }
    
    /// 获取当前用户积分
    func fetchCredits() async throws -> Int {
        if let user = try await getUser(deviceId: deviceId) {
            return user.credits
        }
        return 0
    }
    
    /// 更新用户积分
    func updateCredits(_ credits: Int) async throws {
        // 优先使用缓存的 region，避免额外请求
        let region: String
        let deviceInfo: DeviceInfo
        let createdAt: String?
        if let cachedUser = cachedUserData {
            region = cachedUser.region
            if let info = DeviceInfo.fromStorageString(cachedUser.deviceInfo), info.deviceModel != "Unknown" && !info.deviceModel.isEmpty {
                deviceInfo = info
            } else {
                deviceInfo = DeviceInfo.current()
            }
            // 保留原有的 createdAt
            createdAt = cachedUser.createdAt
        } else {
            // 缓存不存在，从云端获取
            if let existingUser = try await getUser(deviceId: deviceId) {
                region = existingUser.region
                if let info = DeviceInfo.fromStorageString(existingUser.deviceInfo), info.deviceModel != "Unknown" && !info.deviceModel.isEmpty {
                    deviceInfo = info
                } else {
                    deviceInfo = DeviceInfo.current()
                }
                // 保留原有的 createdAt
                createdAt = existingUser.createdAt
            } else {
                // 用户不存在（理论上不应该发生），使用当前区域和设备信息
                region = RegionManager.getCurrentRegionCode()
                deviceInfo = DeviceInfo.current()
                createdAt = nil
            }
        }

        // 创建用户模型，使用本地时间更新 updatedAt
        var user = UserCreditsModel(deviceId: deviceId, credits: credits, region: region, deviceInfo: deviceInfo)
        // 保留原有的 createdAt
        user.createdAt = createdAt
        // updatedAt 在 init 中已经设置为当前本地时间

        try await saveOrUpdateUser(user)
        // 更新缓存
        cachedUserData = user
    }
    
    /// 增加积分（内购成功后调用）
    func addCredits(_ amount: Int) async throws -> Int {
        let currentCredits = try await fetchCredits()
        let newCredits = currentCredits + amount
        try await updateCredits(newCredits)
        return newCredits
    }
}
