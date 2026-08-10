//
//  Func.swift
//  EmotionVoice
//
//  Created by young on 2026/8/9.
//

import Foundation

// MARK: 日志打印

nonisolated
func Log<T>(messageType: String? = nil, message: T, fileName: String = #file, methodName: String = #function, lineNumber: Int = #line) {
#if DEBUG
    //获取当前时间
    let now = Date()
    // 创建一个日期格式器
    let dformatter = DateFormatter()
    dformatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
    // 要把路径最后的字符串截取出来
    let lastName = ((fileName as NSString).pathComponents.last!)
    
    var msg = "\(message)"
    if let messageType = messageType {
        msg = "----\(messageType)--->\(msg)"
    }
    print("\(dformatter.string(from: now)) [\(lastName)][第\(lineNumber)行] \n\t\t \(msg)")
#endif
}
