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

/// 可 push 的二级页面
enum Route: Hashable {
    case settings
    case creditRecords
    case defaultFormat
    case sampleRate
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

    /// 从任一标签的齿轮 push 设置页
    func openSettings() {
        push(.settings)
    }

    func push(_ route: Route) {
        switch selection {
        case .studio: studioPath.append(route)
        case .library: libraryPath.append(route)
        case .projects: projectsPath.append(route)
        }
    }

    func binding(for tab: Tab) -> Binding<NavigationPath> {
        switch tab {
        case .studio: return Binding(get: { self.studioPath }, set: { self.studioPath = $0 })
        case .library: return Binding(get: { self.libraryPath }, set: { self.libraryPath = $0 })
        case .projects: return Binding(get: { self.projectsPath }, set: { self.projectsPath = $0 })
        }
    }
}
