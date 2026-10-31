//
//  iOSContentView.swift
//  iOSEmora
//
//  iOS 版入口容器。真正的实现全部在仓库根的 `iOS/` 目录：
//  `iOS/App/RootTabView.swift` —— 3 个标签 + 各自导航栈 + 全局浮层。
//

import SwiftUI

struct iOSContentView: View {
    var body: some View {
        RootTabView()
    }
}
