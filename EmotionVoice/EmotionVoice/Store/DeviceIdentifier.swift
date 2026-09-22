//
//  DeviceIdentifier.swift
//  EmotionVoice
//

import Foundation
import KeychainSwift

class DeviceIdentifier {
    static let shared = DeviceIdentifier()
    
    private let keychain: KeychainSwift
    
    private init() {
        keychain = KeychainSwift()
        keychain.synchronizable = false
    }
    
    /// 获取设备唯一标识
    var deviceId: String {
        getUserUUID()
    }

    func getUserUUID() -> String {
        if let existingUUID = keychain.get(kUserUUID) {
            return existingUUID
        } else {
            let newUUID = UUID().uuidString
            keychain.set(newUUID, forKey: kUserUUID)
            return newUUID
        }
    }
}
