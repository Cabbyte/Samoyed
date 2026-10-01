import AppIntents
import SwiftUI
import UIKit
import UserNotifications

// `@main` 是 SwiftUI App 的程序入口，作用接近 C++ 里的 `int main()`。
// 不同点在于：事件循环、窗口生命周期、应用启动时机都由 iOS 系统掌管，
// 我们只需要提供一个 `App` 值，告诉系统“根场景(scene)长什么样”。
@main
struct SamoyedApp: App {
    // `UIApplicationDelegateAdaptor` 是 SwiftUI 和传统 UIKit 生命周期的桥梁。
    // 可以把它理解成：
    // - SwiftUI 负责声明式 UI
    // - AppDelegate 负责接系统级回调
    // 两边都能存在，但各自负责不同层面的事情。
    @UIApplicationDelegateAdaptor(SamoyedAppDelegate.self) private var appDelegate

    var body: some Scene {
        // `WindowGroup` 代表应用的主窗口集合。
        // 在 iPhone 上通常可以粗略理解为“主界面容器”。
        WindowGroup {
            #if DEBUG
            SamoyedQAViewport {
                ContentView()
            }
            #else
            ContentView()
            #endif
        }
    }
}

// MARK: - Root Views

// `ContentView` 是整个 SwiftUI 树的“组合根(composition root)”。
// 这里做的事情主要有三类：
// 1. 创建并长期持有 `SamoyedStore`
// 2. 监听系统入口（deep link、场景激活、快捷操作）
// 3. 把这些系统事件翻译成对 store 的显式调用
struct ContentView: View {
    // `scenePhase` 反映当前场景状态：前台 active、非活跃 inactive、后台 background。
    // 这和桌面/游戏开发里常见的应用激活/挂起概念相似。
    @Environment(\.scenePhase) private var scenePhase
    // `@State` 不是“普通成员变量”，而是 SwiftUI 托管的持久状态槽位。
    // 对 C++ 开发者最重要的一点：
    // SwiftUI 的 `View` 是值类型，会频繁被重建；如果这里不用 `@State`，
    // `store` 会在每次重绘时重新创建，整个应用状态就丢了。
    @State private var store: SamoyedStore
    @State private var remoteRoutineImportRequest: RemoteRoutineImportRequest?
    @State private var pendingRoutineImport: PendingRoutineImport?
    @State private var isLoadingRemoteRoutineImport = false

    private let remoteRoutineConfigLoader: SamoyedRemoteRoutineConfigLoader

    @MainActor
    init(
        store: SamoyedStore? = nil,
        remoteRoutineConfigLoader: SamoyedRemoteRoutineConfigLoader = .init()
    ) {
        // `@MainActor` 表示这个初始化过程要求在主线程/主 actor 上运行。
        // UI 相关对象通常都应该这么做，避免线程竞争和 UI 读写越界。
        #if DEBUG
        let resolvedStore = store ?? SamoyedUITestSupport.makeStoreIfRequested() ?? SamoyedStore()
        #else
        let resolvedStore = store ?? SamoyedStore()
        #endif
        _store = State(initialValue: resolvedStore)
        _remoteRoutineImportRequest = State(initialValue: nil)
        _pendingRoutineImport = State(initialValue: nil)
        self.remoteRoutineConfigLoader = remoteRoutineConfigLoader
    }

    var body: some View {
        Group {
            switch store.bootstrapState {
            case .loading:
                ScreenLoadingView(
                    title: "Loading Samoyed",
                    systemImage: "clock",
                    description: "Opening your local day structure."
                )

            case .needsActivation:
                ActivationRootView()

            case .ready:
                AppShellView()

            case let .loadError(message):
                RecoverableErrorView(
                    title: "Unable to Open Your Data",
                    message: message,
                    retry: store.retryBootstrap
                )
            }
        }
            // `.environment(store)` 会把 store 注入到整棵子视图树。
            // 后代视图可以用 `@Environment(SamoyedStore.self)` 直接取到它，
            // 不需要像传统 MVC/MVVM 那样层层手传。
            .environment(store)
            .task {
                // `.task` 会在视图出现后执行一次异步/副作用逻辑。
                // 可以把它看成“和这个 View 生命周期绑定的启动钩子”。
                store.loadIfNeeded()
                consumePendingExternalRoute()
                SamoyedSystemSurfaceDormancy.apply()
            }
            .task(id: remoteRoutineImportRequest?.id) {
                await loadRemoteRoutineImportIfNeeded()
            }
            // 当系统用 URL 打开 app 时，这里会收到回调。
            // iOS 的 deep link、widget 点击、shortcut 跳转，很多最终都会落到这里。
            .onOpenURL(perform: applyExternalURL)
            // 这里监听的是“应用内部”转发出来的外部路由事件。
            // 为什么还需要一层 NotificationCenter？
            // 因为有些系统入口（比如快捷操作）发生在 SwiftUI 视图树建立前后，
            // 先缓存 URL，再由 ContentView 消费，会更稳定。
            .onReceive(NotificationCenter.default.publisher(for: .samoyedExternalRouteDidChange)) { notification in
                guard let url = notification.object as? URL else { return }
                applyExternalURL(url)
            }
            .onChange(of: scenePhase) { _, newPhase in
                // Reload shared data on foreground without reactivating frozen surfaces.
                // 这是移动端常见的做法：因为应用可能在后台被系统暂停很久，
                // 重新激活时需要一次“轻量复位”。
                guard newPhase == .active, store.isLoaded else { return }
                store.reload()
                consumePendingExternalRoute()
            }
            .sheet(item: $pendingRoutineImport) { pendingImport in
                RoutineImportPreviewSheet(pendingImport: pendingImport)
                    .environment(store)
            }
            .overlay {
                if isLoadingRemoteRoutineImport {
                    RemoteRoutineImportLoadingOverlay()
                }
            }
    }

    private func consumePendingExternalRoute() {
        // 如果系统事件比 UI 先到达（例如 AppDelegate / SceneDelegate 先收到），
        // URL 会暂存在 `SamoyedExternalRouteCenter` 里。
        // 这里就是把缓存取出来并真正应用到当前 UI 状态。
        guard let pendingURL = SamoyedExternalRouteCenter.shared.consumePendingURL() else {
            return
        }

        applyExternalURL(pendingURL)
    }

    private func applyExternalURL(_ url: URL) {
        // 先把原始 URL 解析成项目内部统一的 `SamoyedSystemRoute`。
        // 这是一个很重要的“解耦点”：
        // UI / Widget / Notification 不直接解析字符串，而是都依赖同一个路由枚举。
        guard let route = SamoyedSystemRoute(url: url) else {
            return
        }

        switch route {
        case .now:
            store.showNow()

        case let .today(date, blockID, _, _):
            store.showToday(date: date, blockID: blockID)

        case .library:
            store.showLibrary()

        case let .importRoutine(remoteURL, title, _):
            pendingRoutineImport = nil
            remoteRoutineImportRequest = RemoteRoutineImportRequest(
                remoteURL: remoteURL,
                suggestedTitle: title
            )

        case let .importRoutinePayload(version, payload, title, _):
            remoteRoutineImportRequest = nil
            isLoadingRemoteRoutineImport = false
            pendingRoutineImport = nil
            prepareInlineRoutineImport(
                version: version,
                payload: payload,
                suggestedTitle: title
            )

        case let .importSuggestion(version, payload, _):
            do {
                try store.importSuggestion(version: version, payload: payload)
            } catch {
                store.presentError(error)
            }

        case .startCurrentBlockLiveActivity:
            store.startCurrentBlockLiveActivity(
                referenceDate: SamoyedSimulationClock.adjusted(.now)
            )

        case .endCurrentBlockLiveActivity:
            store.endCurrentBlockLiveActivity()
        }
    }

    private func prepareInlineRoutineImport(
        version: Int,
        payload: String,
        suggestedTitle: String?
    ) {
        do {
            let yaml = try SamoyedInlineRoutineConfigDecoder().decode(
                version: version,
                payload: payload
            )
            let summary = try store.previewRoutineConfigImport(yaml)
            let normalizedTitle = suggestedTitle?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedTitle: String
            if let normalizedTitle, !normalizedTitle.isEmpty {
                resolvedTitle = normalizedTitle
            } else {
                resolvedTitle = "Imported Routine"
            }
            pendingRoutineImport = PendingRoutineImport(
                origin: .inlineLink,
                yaml: yaml,
                summary: summary,
                suggestedTitle: resolvedTitle
            )
        } catch {
            store.presentError(error)
        }
    }

    private func loadRemoteRoutineImportIfNeeded() async {
        guard let request = remoteRoutineImportRequest else { return }

        isLoadingRemoteRoutineImport = true
        defer {
            if remoteRoutineImportRequest?.id == request.id {
                isLoadingRemoteRoutineImport = false
            }
        }

        do {
            let loadedConfig = try await remoteRoutineConfigLoader.load(from: request.remoteURL)
            try Task.checkCancellation()
            let summary = try store.previewRoutineConfigImport(loadedConfig.yaml)
            try Task.checkCancellation()
            guard remoteRoutineImportRequest?.id == request.id else { return }

            pendingRoutineImport = PendingRoutineImport(
                origin: .remote(loadedConfig.sourceURL),
                yaml: loadedConfig.yaml,
                summary: summary,
                suggestedTitle: request.resolvedTitle
            )
        } catch is CancellationError {
            return
        } catch {
            guard remoteRoutineImportRequest?.id == request.id else { return }
            store.presentError(error)
        }
    }
}

// `AppShellView` 是顶层 UI 外壳，负责三个主标签页和全局错误弹窗。
// 你可以把它看成桌面应用里的“主框架窗口”。
struct AppShellView: View {
    // `@Environment(Type.self)` 是 SwiftUI 中按类型读取依赖的方式。
    // 它和依赖注入容器有一点像，但更加轻量，且由视图树自动传播。
    @Environment(SamoyedStore.self) private var store

    var body: some View {
        // `@Bindable` 会把 `@Observable` 对象暴露成可双向绑定的视图数据源。
        // 这样 `$store.selectedTab` 这种绑定才成立。
        @Bindable var store = store

        TabView(selection: $store.selectedTab) {
            NowRootView()
                .tabItem {
                    Label("Now", systemImage: "bolt.circle")
                }
                .tag(RootTab.now)

            TodayRootView()
                .tabItem {
                    Label("Today", systemImage: "calendar")
                }
                .tag(RootTab.today)

            LibraryRootView()
                .tabItem {
                    Label("Library", systemImage: "square.stack.3d.up")
                }
                .tag(RootTab.library)
        }
        // `.tint` 是 SwiftUI 中对强调色/选中态颜色的统一设置。
        .tint(store.tintPreset.tintColor)
        .environment(\.samoyedTintPreset, store.tintPreset)
        // 全局错误弹窗统一放在壳层，而不是每个页面自己维护一套 alert 状态。
        .alert(
            "Unable to Complete Action",
            isPresented: Binding(
                get: { store.lastErrorMessage != nil },
                set: { if !$0 { store.dismissError() } }
            )
        ) {
            Button("OK") {
                store.dismissError()
            }
        } message: {
            Text(store.lastErrorMessage ?? "")
        }
    }
}

// MARK: - App Lifecycle

// `AppDelegate` 仍然是接收“应用级”UIKit 回调的标准入口。
// SwiftUI 并没有让它消失，只是把 UI 声明从这里挪走了。
final class SamoyedAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        // 一个 iOS 应用可以有多个 scene（多窗口/多实例概念）。
        // 这里告诉系统：新场景要使用哪个 scene delegate。
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = SamoyedSceneDelegate.self

        // 如果用户是通过主屏快捷操作启动 app，系统会把 shortcutItem 放在这里。
        if let shortcutItem = options.shortcutItem {
            _ = SamoyedQuickActionManager.handle(shortcutItem)
        }

        return configuration
    }

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        Task { @MainActor in
            SamoyedSystemSurfaceDormancy.apply()
        }
        return true
    }
}

// `SceneDelegate` 负责场景级(system scene level)事件。
// 在这里我们只关心快捷操作的二次分发。
final class SamoyedSceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(
        _ windowScene: UIWindowScene,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void
    ) {
        completionHandler(SamoyedQuickActionManager.handle(shortcutItem))
    }
}

// MARK: - External Routing

// `Notification.Name` 的扩展只是给字符串事件名一个强类型包装，
// 比起到处散落原始字符串更安全。
extension Notification.Name {
    static let samoyedExternalRouteDidChange = Notification.Name("SamoyedExternalRouteDidChange")
}

@MainActor
final class SamoyedExternalRouteCenter {
    // 这是一个很小的“事件缓冲站”：
    // - 系统入口先把 URL 放进来
    // - SwiftUI 根视图稍后把它取出来
    // 之所以不用更复杂的事件总线，是因为这里只有一个很简单的需求。
    static let shared = SamoyedExternalRouteCenter()

    private(set) var pendingURL: URL?

    func enqueue(_ url: URL) {
        // 先缓存，后广播。
        pendingURL = url
        NotificationCenter.default.post(name: .samoyedExternalRouteDidChange, object: url)
    }

    func consumePendingURL() -> URL? {
        let url = pendingURL
        pendingURL = nil
        return url
    }
}

private enum SamoyedQuickActionRouteKey {
    // 主屏快捷操作的 `userInfo` 是字典，key 仍然用字符串；
    // 用一个小 enum 集中管理，避免硬编码散落。
    static let routeURL = "routeURL"
}

@MainActor
enum SamoyedQuickActionManager {
    // `refresh` 会动态生成主屏快捷操作列表。
    // iOS 允许我们在运行时更新这些入口，而不是只能写死在 Info.plist。
    static func refresh(referenceDate: Date = .now) {
        var items: [UIApplicationShortcutItem] = [
            shortcutItem(
                type: SamoyedSharedConfig.quickActionNow,
                title: "Now",
                subtitle: "Open the current focus",
                systemImageName: "bolt.circle",
                route: .now(source: .quickAction)
            ),
            shortcutItem(
                type: SamoyedSharedConfig.quickActionToday,
                title: "Today",
                subtitle: "Open today's timeline",
                systemImageName: "calendar",
                route: .today(date: .today(), blockID: nil, taskID: nil, source: .quickAction)
            ),
            shortcutItem(
                type: SamoyedSharedConfig.quickActionLibrary,
                title: "Library",
                subtitle: "Choose today’s routine",
                systemImageName: "square.stack.3d.up",
                route: .library(source: .quickAction)
            )
        ]

        let executor = SamoyedSystemActionExecutor()
        if
            let snapshot = try? executor.currentSnapshot(at: referenceDate),
            let currentBlock = snapshot.currentBlock,
            let routeURL = SamoyedSystemRoute.today(
                date: currentBlock.date,
                blockID: currentBlock.blockID,
                taskID: snapshot.topTask?.taskID,
                source: .quickAction
            ).url
        {
            items.insert(
                UIApplicationShortcutItem(
                    type: SamoyedSharedConfig.quickActionCurrentBlock,
                    localizedTitle: currentBlock.title,
                    localizedSubtitle: currentBlock.timeRangeText,
                    icon: UIApplicationShortcutIcon(systemImageName: "scope"),
                    userInfo: [
                        SamoyedQuickActionRouteKey.routeURL: routeURL.absoluteString as NSString
                    ]
                ),
                at: 1
            )
        }

        UIApplication.shared.shortcutItems = items
    }

    @discardableResult
    static func handle(_ shortcutItem: UIApplicationShortcutItem) -> Bool {
        // 系统给的是 `UIApplicationShortcutItem`，而 app 内部只想处理 URL 路由。
        // 这里负责把前者翻译成后者。
        guard let routeURL = routeURL(for: shortcutItem) else {
            return false
        }

        SamoyedExternalRouteCenter.shared.enqueue(routeURL)
        return true
    }

    private static func shortcutItem(
        type: String,
        title: String,
        subtitle: String,
        systemImageName: String,
        route: SamoyedSystemRoute
    ) -> UIApplicationShortcutItem {
        // `UIApplicationShortcutItem` 就是 iOS 主屏长按图标弹出的快捷入口定义。
        UIApplicationShortcutItem(
            type: type,
            localizedTitle: title,
            localizedSubtitle: subtitle,
            icon: UIApplicationShortcutIcon(systemImageName: systemImageName),
            userInfo: [
                SamoyedQuickActionRouteKey.routeURL: (route.url?.absoluteString ?? "") as NSString
            ]
        )
    }

    private static func routeURL(for shortcutItem: UIApplicationShortcutItem) -> URL? {
        // 优先读取我们自己存进去的 routeURL；如果没有，再根据 type 回退。
        if
            let routeString = shortcutItem.userInfo?[SamoyedQuickActionRouteKey.routeURL] as? String,
            let url = URL(string: routeString)
        {
            return url
        }

        switch shortcutItem.type {
        case SamoyedSharedConfig.quickActionNow:
            return SamoyedSystemRoute.now(source: .quickAction).url
        case SamoyedSharedConfig.quickActionToday:
            return SamoyedSystemRoute.today(
                date: .today(),
                blockID: nil,
                taskID: nil,
                source: .quickAction
            ).url
        case SamoyedSharedConfig.quickActionLibrary:
            return SamoyedSystemRoute.library(source: .quickAction).url
        default:
            return nil
        }
    }
}

// MARK: - Previews

#Preview("Content - Now") {
    ContentView(store: PreviewSupport.store(tab: .now))
}

#Preview("Content - Today") {
    ContentView(store: PreviewSupport.store(tab: .today))
}

#Preview("Content - Library Tab") {
    ContentView(store: PreviewSupport.store(tab: .library))
}

#Preview("Content - Routines in Library") {
    ContentView(
        store: PreviewSupport.store(
            tab: .library,
            libraryNavigationPath: [.routines]
        )
    )
}

#Preview("App Shell - Now") {
    AppShellView()
        .environment(PreviewSupport.store(tab: .now))
}

#Preview("App Shell - Today") {
    AppShellView()
        .environment(PreviewSupport.store(tab: .today))
}

#Preview("App Shell - Library") {
    AppShellView()
        .environment(PreviewSupport.store(tab: .library))
}

#Preview("App Shell - Routines in Library") {
    AppShellView()
        .environment(
            PreviewSupport.store(
                tab: .library,
                libraryNavigationPath: [.routines]
            )
        )
}

#Preview("App Shell - Error Alert") {
    AppShellView()
        .environment(
            PreviewSupport.store(
                tab: .now,
                lastErrorMessage: "This is a preview alert message."
            )
        )
}
