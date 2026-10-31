//
//  TabRouter.swift
//  iOSEmora
//
//  标签栏 + 每个标签各自的导航栈。
//
//  齿轮入口在三个标签的导航栏右上角，点击后 **push 进当前标签自己的导航栈**
//  （返回键回到该标签，而不是跳回别的标签）—— 所以路由状态要按标签分开保存。
//

import SwiftUI
import Combine   // @Published / ObservableObject 在 Combine，SwiftUI 不再隐式导出
import UIKit     // UIApplication（push 前收键盘）

/// 可 push 的二级页面
///
/// ⚠️「默认格式」「采样率」已改成**设置页就地弹 sheet**，不再占导航栈 ——
/// 能进栈的只剩「设置 / 积分记录 / 播放详情」三类真正的二级页。
enum Route: Hashable {
    case settings
    case creditRecords
    /// 播放详情（`AudioItem` 是 Hashable，可直接进导航栈；避免二级页再查一次库）
    case player(AudioItem)
}

@MainActor
final class TabRouter: ObservableObject {

    enum Tab: Int, CaseIterable, Identifiable {
        case studio
        case library
        case projects

        var id: Int { rawValue }

        var title: String {
            switch self {
            case .studio: return "创作".localized()
            case .library: return "音色库".localized()
            case .projects: return "项目".localized()
            }
        }

        var icon: String {
            switch self {
            case .studio: return "waveform"
            case .library: return "person.wave.2.fill"
            case .projects: return "folder.fill"
            }
        }
    }

    @Published var selection: Tab = .studio
    @Published var studioPath = NavigationPath()
    @Published var libraryPath = NavigationPath()
    @Published var projectsPath = NavigationPath()

    /// 当前标签的导航栈
    var activePath: NavigationPath {
        switch selection {
        case .studio: return studioPath
        case .library: return libraryPath
        case .projects: return projectsPath
        }
    }

    /// 二级界面隐藏底部标签栏
    ///
    /// ⚠️ 显隐必须由这个 **Bool** 驱动（而不是把 `.toolbar(.hidden, for: .tabBar)`
    /// 直接挂在 destination 上）：挂死植的 `.hidden` 是随视图出现 / 消失瞬切的，
    /// 没有过渡；交给 Bool 才能用 `.animation(_:value:)` 给它加动画。
    var isTabBarHidden: Bool { !activePath.isEmpty }

    /// 标签栏显隐动画（与导航 push / pop 的时长对齐）
    static let tabBarAnimation = Animation.easeOut(duration: 0.28)

    /// 从任一标签的齿轮 push 设置页
    func openSettings() {
        push(.settings)
    }

    func push(_ route: Route) {
        // ⚠️ 进栈前必须先把键盘收掉：**键盘还在屏上时直接 push**，返回后 SwiftUI 的键盘
        // 避让会失效 —— 内容区拿不到「键盘高度」这条安全区 inset，创作页底部那条
        // 「预计消耗 / 生成音频 / 完成」会被压到键盘底下（看着就是按钮全没了），
        // 而键盘本身又没有合适的退场时机。先 resign，回来时一切从干净状态重建。
        resignFirstResponder()
        // ⚠️ withAnimation 包住进栈：标签栏的隐藏要落在一个带动画的事务里
        withAnimation(Self.tabBarAnimation) {
            switch selection {
            case .studio: studioPath.append(route)
            case .library: libraryPath.append(route)
            case .projects: projectsPath.append(route)
            }
        }
    }

    /// 全局收键盘（等价于 StudioView 里「完成」按钮的做法）
    private func resignFirstResponder() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                        to: nil, from: nil, for: nil)
    }

    func binding(for tab: Tab) -> Binding<NavigationPath> {
        switch tab {
        case .studio: return Binding(get: { self.studioPath }, set: { self.studioPath = $0 })
        case .library: return Binding(get: { self.libraryPath }, set: { self.libraryPath = $0 })
        case .projects: return Binding(get: { self.projectsPath }, set: { self.projectsPath = $0 })
        }
    }
}
