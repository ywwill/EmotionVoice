//
//  DeviceInfo.swift
//  EmotionVoice
//
//  Created by young on 2026/7/23.
//

// MARK: - 设备信息结构体

import Foundation
#if os(iOS)
import UIKit
#endif

struct DeviceInfo: Codable {
    var deviceType: String  // iPhone, iPad, MacBook
    var deviceModel: String  // 具体型号，如 "iPhone 15 Pro", "iPad Pro 12.9-inch"
    var systemVersion: String  // 系统版本，如 "iOS 17.5", "macOS 14.5"

    enum CodingKeys: String, CodingKey {
        case deviceType = "device_type"
        case deviceModel = "device_model"
        case systemVersion = "system_version"
    }

    static func current() -> DeviceInfo {
        #if os(iOS)
        let deviceModel = getDeviceModel()
        let systemVersion = "iOS \(UIDevice.current.systemVersion)"
        let deviceType: String
        switch UIDevice.current.userInterfaceIdiom {
        case .phone:
            deviceType = "iPhone"
        case .pad:
            deviceType = "iPad"
        case .mac:
            deviceType = "MacBook"
        default:
            deviceType = "Unknown"
        }
        return DeviceInfo(deviceType: deviceType, deviceModel: deviceModel, systemVersion: systemVersion)
        #elseif os(macOS)
        let model = getMacModel()
        let systemVersion = "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)"
        return DeviceInfo(deviceType: "MacBook", deviceModel: model, systemVersion: systemVersion)
        #else
        return DeviceInfo(deviceType: "Unknown", deviceModel: "Unknown", systemVersion: "Unknown")
        #endif
    }

    /// 获取 iOS 设备具体型号
    private static func getDeviceModel() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machineMirror = Mirror(reflecting: systemInfo.machine)
        let identifier = machineMirror.children.reduce("") { identifier, element in
            guard let value = element.value as? Int8, value != 0 else { return identifier }
            return identifier + String(UnicodeScalar(UInt8(value)))
        }
        return mapToDevice(identifier: identifier)
    }

    /// 获取 Mac 设备型号
    private static func getMacModel() -> String {
        #if os(macOS)
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &model, &size, nil, 0)
        return String(cString: model)
        #else
        return "Mac"
        #endif
    }

    /// 将设备标识符映射为可读型号
    private static func mapToDevice(identifier: String) -> String {
        switch identifier {
        // iPhone 16 series
        case "iPhone17,1": return "iPhone 16 Pro"
        case "iPhone17,2": return "iPhone 16 Pro Max"
        case "iPhone17,3": return "iPhone 16"
        case "iPhone17,4": return "iPhone 16 Plus"
        // iPhone 15 series
        case "iPhone15,4": return "iPhone 15"
        case "iPhone15,5": return "iPhone 15 Plus"
        case "iPhone16,1": return "iPhone 15 Pro"
        case "iPhone16,2": return "iPhone 15 Pro Max"
        // iPhone 14 series
        case "iPhone14,7": return "iPhone 14"
        case "iPhone14,8": return "iPhone 14 Plus"
        case "iPhone15,2": return "iPhone 14 Pro"
        case "iPhone15,3": return "iPhone 14 Pro Max"
        // iPhone 13 series
        case "iPhone14,5": return "iPhone 13"
        case "iPhone14,4": return "iPhone 13 mini"
        case "iPhone14,2": return "iPhone 13 Pro"
        case "iPhone14,3": return "iPhone 13 Pro Max"
        // iPhone 12 series
        case "iPhone13,2": return "iPhone 12"
        case "iPhone13,1": return "iPhone 12 mini"
        case "iPhone13,3": return "iPhone 12 Pro"
        case "iPhone13,4": return "iPhone 12 Pro Max"
        // iPhone 11 series
        case "iPhone12,1": return "iPhone 11"
        case "iPhone12,3": return "iPhone 11 Pro"
        case "iPhone12,5": return "iPhone 11 Pro Max"
        // iPhone SE
        case "iPhone14,6": return "iPhone SE (3rd generation)"
        case "iPhone12,8": return "iPhone SE (2nd generation)"
        // iPad Pro
        case "iPad13,4", "iPad13,5", "iPad13,6", "iPad13,7": return "iPad Pro 11-inch (3rd generation)"
        case "iPad13,8", "iPad13,9", "iPad13,10", "iPad13,11": return "iPad Pro 12.9-inch (5th generation)"
        case "iPad14,3", "iPad14,4": return "iPad Pro 11-inch (4th generation)"
        case "iPad14,5", "iPad14,6": return "iPad Pro 12.9-inch (6th generation)"
        // iPad Air
        case "iPad13,1", "iPad13,2": return "iPad Air (5th generation)"
        case "iPad13,16", "iPad13,17": return "iPad Air (6th generation)"
        // iPad mini
        case "iPad14,1", "iPad14,2": return "iPad mini (6th generation)"
        // iPad
        case "iPad13,18", "iPad13,19": return "iPad (10th generation)"
        case "iPad12,1", "iPad12,2": return "iPad (9th generation)"
        // Simulator
        case "i386", "x86_64", "arm64": return "Simulator"
        default: return identifier
        }
    }

    /// 简化为存储格式：iPhone15_iOS18
    func toStorageString() -> String {
        // 简化设备型号：移除空格和特殊字符
        let simplifiedModel = simplifyModel(deviceModel)
        // 简化系统版本：iOS 17.5 -> iOS18（只保留主版本）
        let simplifiedOS = simplifyOS(systemVersion)
        return "\(simplifiedModel)_\(simplifiedOS)"
    }

    private func simplifyModel(_ model: String) -> String {
        // 移除空格和特殊字符，只保留关键信息
        // iPhone 15 Pro -> iPhone15Pro
        // iPad Pro 11-inch -> iPadPro11
        var result = model
            .replacingOccurrences(of: "inch", with: "")
            .replacingOccurrences(of: "Inch", with: "")
            .replacingOccurrences(of: "-inch", with: "")
            .replacingOccurrences(of: "generation", with: "")
            .replacingOccurrences(of: "(", with: "")
            .replacingOccurrences(of: ")", with: "")

        // 合并空格
        result = result.components(separatedBy: .whitespaces).joined()
        return result
    }

    private func simplifyOS(_ os: String) -> String {
        // iOS 17.5.1 -> iOS18
        // macOS 14.5 -> macOS15
        let components = os.components(separatedBy: " ")
        if components.count >= 2 {
            let version = components[1]
            let parts = version.components(separatedBy: ".")
            if let major = parts.first {
                return "\(components[0])\(major)"
            }
        }
        return os
    }

    /// 从存储格式解析：iPhone15Pro_iOS18
    static func fromStorageString(_ storageString: String?) -> DeviceInfo? {
        guard let str = storageString, str.contains("_") else { return nil }

        let parts = str.components(separatedBy: "_")
        guard parts.count == 2 else { return nil }

        let modelPart = parts[0]
        let osPart = parts[1]

        // 尝试还原设备类型
        let deviceType: String
        if modelPart.hasPrefix("iPhone") {
            deviceType = "iPhone"
        } else if modelPart.hasPrefix("iPad") {
            deviceType = "iPad"
        } else if modelPart.hasPrefix("Mac") {
            deviceType = "MacBook"
        } else {
            deviceType = "Unknown"
        }

        // 尝试还原完整系统版本
        let systemVersion: String
        if osPart.hasPrefix("iOS") {
            let version = String(osPart.dropFirst(3))
            systemVersion = "iOS \(version)"
        } else if osPart.hasPrefix("macOS") {
            let version = String(osPart.dropFirst(5))
            systemVersion = "macOS \(version)"
        } else {
            systemVersion = osPart
        }

        return DeviceInfo(deviceType: deviceType, deviceModel: modelPart, systemVersion: systemVersion)
    }

    /// 转换为 JSON 字符串（保留以防需要）
    func toJSONString() -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        guard let data = try? encoder.encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// 从 JSON 字符串解析（保留以防需要）
    static func fromJSONString(_ jsonString: String?) -> DeviceInfo? {
        guard let jsonString = jsonString,
              let data = jsonString.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(DeviceInfo.self, from: data)
    }
}
