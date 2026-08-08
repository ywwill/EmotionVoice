//
//  String+Extension.swift
//  CloneVoice
//
//  Created by young on 2026/1/15.
//

import Foundation
import SwiftUI

extension String {
    
    /// 返回本地化字符串并替换占位符
    func localized(_ args: CVarArg...) -> String {
        let localizedString = NSLocalizedString(self, comment: "")
        return String(format: localizedString, arguments: args)
    }
}
