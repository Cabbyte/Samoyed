import AppIntents
import SwiftUI

// `@main` 是 SwiftUI App 的程序入口，作用接近 C++ 里的 `int main()`。
// 不同点在于：事件循环、窗口生命周期、应用启动时机都由 iOS 系统掌管，
// 我们只需要提供一个 `App` 值，告诉系统“根场景(scene)长什么样”。
@main
struct SamoyedApp: App {
    var body: some Scene {
        // `WindowGroup` 代表应用的主窗口集合。
        // 在 iPhone 上通常可以粗略理解为“主界面容器”。
        WindowGroup {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--nest-connection-probe") {
                NestConnectionProbeView()
            } else if ProcessInfo.processInfo.arguments.contains(where: { $0.hasPrefix("--nest-acceptance-") }) {
                NestDeviceAcceptanceView()
            } else {
                SamoyedQAViewport { ContentView() }
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
// 2. 监听系统入口（deep link、场景激活）
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
                SamoyedLegacySurfaceMigration.apply()
                store.loadIfNeeded()
                await store.nest.restore(store: store)
                consumePendingExternalRoute()
            }
            .task(id: remoteRoutineImportRequest?.id) {
                await loadRemoteRoutineImportIfNeeded()
            }
            // 当系统用 URL 打开 app 时，这里会收到回调。
            // iOS 的 deep link、widget 点击、shortcut 跳转，很多最终都会落到这里。
            .onOpenURL(perform: applyExternalURL)
            // UI fixtures can enqueue a route before the root view appears.
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
                store.nest.scheduleSync()
                consumePendingExternalRoute()
            }
            .onChange(of: store.selectedDate) { _, _ in store.nest.scheduleSync() }
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
        // Consume routes queued by the UI fixture before the root view appeared.
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
