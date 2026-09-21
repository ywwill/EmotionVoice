//
//  UserCreditsModel.swift
//  CloneVoice
//
//  Created by young on 2026/7/23.
//

// MARK: - 用户数据模型

import Foundation

struct UserCreditsModel: Codable {
    var deviceId: String
    var credits: Int
    var region: String  // 用户区域：苹果地区代码，如 CN, US, JP 等
    var deviceInfo: String?  // 设备信息存储格式
    var createdAt: String?
    var updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case deviceId = "device_id"
        case credits
        case region
        case deviceInfo = "device_info"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    /// 本地时间格式化器（用于 createdAt 和 updatedAt）
    private static let localDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.locale = Locale.current
        formatter.timeZone = TimeZone.current
        return formatter
    }()

    /// 获取当前本地时间的 字符串
    static func currentLocalDateString() -> String {
        return localDateFormatter.string(from: Date())
    }

    init(deviceId: String, credits: Int = 0, region: String, deviceInfo: DeviceInfo? = nil) {
        self.deviceId = deviceId
        self.credits = credits
        self.region = region.uppercased()  // 确保保存为大写
        if let info = deviceInfo {
            self.deviceInfo = info.toStorageString()
        } else {
            self.deviceInfo = DeviceInfo.current().toStorageString()
        }
        // 使用本地时间
        let now = Self.currentLocalDateString()
        self.createdAt = now
        self.updatedAt = now
    }
}
