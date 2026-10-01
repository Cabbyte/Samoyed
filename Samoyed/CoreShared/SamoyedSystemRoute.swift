import Foundation

// 这一组常量是 app、widget、notification、shortcut 等系统表面共享的配置。
// 之所以放在一起，是因为它们大多都和“系统集成入口”有关。
enum SamoyedSharedConfig {
    private static let appGroupInfoKey = "SamoyedAppGroupIdentifier"

    static var appGroupID: String {
        guard
            let identifier = Bundle.main.object(forInfoDictionaryKey: appGroupInfoKey) as? String,
            !identifier.isEmpty,
            !identifier.contains("$(")
        else {
            preconditionFailure(
                "Missing or unresolved \(appGroupInfoKey) in the current bundle's Info.plist."
            )
        }
        return identifier
    }

    static let tintPresetDefaultsKey = "SAMOYED_TINT_PRESET"
    static let widgetKind = "Samoyed.NowWidget"
    static let currentBlockLiveActivityKind = "Samoyed.CurrentBlockLiveActivity"
    static let openNowControlKind = "Samoyed.OpenNowControl"
    static let completeCurrentTaskControlKind = "Samoyed.CompleteCurrentTaskControl"
    static let openCurrentBlockControlKind = "Samoyed.OpenCurrentBlockControl"
    static let startLiveActivityControlKind = "Samoyed.StartLiveActivityControl"
    static let deepLinkScheme = "samoyed"
    static let sharedDirectoryName = "Samoyed"
    static let documentFileName = "document.json"
    static let notificationCategoryIdentifier = "SAMOYED_REMINDER"
    static let notificationActionCompleteTopTask = "SAMOYED_COMPLETE_TOP_TASK"
    static let notificationActionSnooze = "SAMOYED_SNOOZE_10M"
    static let notificationUserInfoDateKey = "dateISO"
    static let notificationUserInfoBlockKey = "blockID"
    static let notificationUserInfoTaskKey = "taskID"
    static let quickActionNow = "tang.Samoyed.quickaction.now"
    static let quickActionToday = "tang.Samoyed.quickaction.today"
    static let quickActionLibrary = "tang.Samoyed.quickaction.library"
    static let quickActionCurrentBlock = "tang.Samoyed.quickaction.currentBlock"
}

// `SamoyedSystemSource` 用来标记“这次系统跳转/动作是从哪里来的”。
// 这既方便调试，也方便未来做埋点或差异化行为。
enum SamoyedSystemSource: String, Codable, Sendable {
    case app
    case widget
    case control
    case shortcut
    case notification
    case quickAction
    case liveActivity
}

// `SamoyedSystemRoute` 是项目内部统一的路由描述。
//
// 重点理解：
// - 外部世界看到的是 URL
// - app 内部真正流转的是这个 enum
//
// 这能把“字符串解析”限制在一个地方，避免整个项目到处手写 `if url.host == ...`。
enum SamoyedSystemRoute: Equatable, Sendable {
    case now(source: SamoyedSystemSource? = nil)
    case today(
        date: LocalDay? = nil,
        blockID: UUID? = nil,
        taskID: UUID? = nil,
        source: SamoyedSystemSource? = nil
    )
    case library(source: SamoyedSystemSource? = nil)
    case importRoutine(
        remoteURL: URL,
        title: String? = nil,
        source: SamoyedSystemSource? = nil
    )
    case importRoutinePayload(
        version: Int,
        payload: String,
        title: String? = nil,
        source: SamoyedSystemSource? = nil
    )
    case importSuggestion(
        version: Int,
        payload: String,
        source: SamoyedSystemSource? = nil
    )
    case startCurrentBlockLiveActivity(source: SamoyedSystemSource? = nil)
    case endCurrentBlockLiveActivity(source: SamoyedSystemSource? = nil)

    init?(url: URL) {
        // 先做最外层过滤：scheme 不对，说明根本不是本 app 的路由。
        guard
            url.scheme?.lowercased() == SamoyedSharedConfig.deepLinkScheme,
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else {
            return nil
        }

        guard let route = url.host?.lowercased(), !route.isEmpty else {
            return nil
        }

        let source = components.queryItems?.value(for: "source")
            .flatMap(SamoyedSystemSource.init(rawValue:))

        switch route {
        case "now":
            self = .now(source: source)

        case "today":
            self = .today(
                date: components.queryItems?.value(for: "date").flatMap(LocalDay.init(isoDateString:)),
                blockID: components.queryItems?.value(for: "block").flatMap(UUID.init(uuidString:)),
                taskID: components.queryItems?.value(for: "task").flatMap(UUID.init(uuidString:)),
                source: source
            )

        case "library":
            self = .library(source: source)

        case "import-routine":
            let queryItems = components.queryItems ?? []
            let hasRemoteURL = queryItems.contains(where: { $0.name == "url" })
            let hasPayload = queryItems.contains(where: { $0.name == "payload" })

            // A link must use exactly one transport. Rejecting ambiguous links keeps
            // future protocol additions from silently choosing the wrong source.
            guard hasRemoteURL != hasPayload else {
                return nil
            }

            if hasPayload {
                guard
                    let payload = queryItems.value(for: "payload"),
                    !payload.isEmpty,
                    let versionText = queryItems.value(for: "v"),
                    let version = Int(versionText),
                    version > 0
                else {
                    return nil
                }
                self = .importRoutinePayload(
                    version: version,
                    payload: payload,
                    title: queryItems.value(for: "title")?.samoyedNilIfBlank,
                    source: source
                )
            } else {
                guard
                    let remoteURLText = queryItems.value(for: "url"),
                    let remoteURL = URL(string: remoteURLText),
                    remoteURL.scheme != nil
                else {
                    return nil
                }
                self = .importRoutine(
                    remoteURL: remoteURL,
                    title: queryItems.value(for: "title")?.samoyedNilIfBlank,
                    source: source
                )
            }

        case "import-suggestion":
            guard
                let payload = components.queryItems?.value(for: "payload"),
                !payload.isEmpty,
                let versionText = components.queryItems?.value(for: "v"),
                let version = Int(versionText),
                version > 0
            else {
                return nil
            }
            self = .importSuggestion(version: version, payload: payload, source: source)

        case "start-live-activity":
            self = .startCurrentBlockLiveActivity(source: source)

        case "end-live-activity":
            self = .endCurrentBlockLiveActivity(source: source)

        default:
            // 无法识别的 host/path 直接返回 nil，让调用方决定是否忽略。
            return nil
        }
    }

    var url: URL? {
        // 与 `init?(url:)` 相反，这里负责把内部枚举重新序列化成 URL。
        var components = URLComponents()
        components.scheme = SamoyedSharedConfig.deepLinkScheme

        switch self {
        case let .now(source):
            components.host = "now"
            components.queryItems = queryItems(source: source)

        case let .today(date, blockID, taskID, source):
            components.host = "today"
            components.queryItems = queryItems(
                date: date,
                blockID: blockID,
                taskID: taskID,
                source: source
            )

        case let .library(source):
            components.host = "library"
            components.queryItems = queryItems(source: source)

        case let .importRoutine(remoteURL, title, source):
            components.host = "import-routine"
            components.queryItems = queryItems(
                remoteURL: remoteURL,
                routineTitle: title,
                source: source
            )

        case let .importRoutinePayload(version, payload, title, source):
            components.host = "import-routine"
            components.queryItems = queryItems(
                payloadVersion: version,
                payload: payload,
                routineTitle: title,
                source: source
            )

        case let .importSuggestion(version, payload, source):
            components.host = "import-suggestion"
            components.queryItems = queryItems(
                payloadVersion: version,
                payload: payload,
                source: source
            )

        case let .startCurrentBlockLiveActivity(source):
            components.host = "start-live-activity"
            components.queryItems = queryItems(source: source)

        case let .endCurrentBlockLiveActivity(source):
            components.host = "end-live-activity"
            components.queryItems = queryItems(source: source)
        }

        return components.url
    }

    private func queryItems(
        date: LocalDay? = nil,
        blockID: UUID? = nil,
        taskID: UUID? = nil,
        remoteURL: URL? = nil,
        payloadVersion: Int? = nil,
        payload: String? = nil,
        routineTitle: String? = nil,
        source: SamoyedSystemSource? = nil
    ) -> [URLQueryItem]? {
        // 只有非 nil 的参数才写进 URL，保持生成的 deep link 简洁。
        var items: [URLQueryItem] = []

        if let date {
            items.append(URLQueryItem(name: "date", value: date.description))
        }
        if let blockID {
            items.append(URLQueryItem(name: "block", value: blockID.uuidString))
        }
        if let taskID {
            items.append(URLQueryItem(name: "task", value: taskID.uuidString))
        }
        if let remoteURL {
            items.append(URLQueryItem(name: "url", value: remoteURL.absoluteString))
        }
        if let payloadVersion {
            items.append(URLQueryItem(name: "v", value: String(payloadVersion)))
        }
        if let payload {
            items.append(URLQueryItem(name: "payload", value: payload))
        }
        if let routineTitle = routineTitle?.samoyedNilIfBlank {
            items.append(URLQueryItem(name: "title", value: routineTitle))
        }
        if let source {
            items.append(URLQueryItem(name: "source", value: source.rawValue))
        }

        return items.isEmpty ? nil : items
    }
}

private extension String {
    var samoyedNilIfBlank: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

extension [URLQueryItem] {
    // 给 queryItems 数组补一个“按名称取值”的小 helper。
    func value(for name: String) -> String? {
        first(where: { $0.name == name })?.value
    }
}

extension LocalDay {
    // 从 ISO 日期字符串（例如 "2026-03-25"）构造 `LocalDay`。
    // 这个 helper 主要服务 deep link / notification / widget 参数解析。
    init?(isoDateString: String) {
        let parts = isoDateString.split(separator: "-", omittingEmptySubsequences: false)
        guard
            parts.count == 3,
            let year = Int(parts[0]),
            let month = Int(parts[1]),
            let day = Int(parts[2])
        else {
            return nil
        }

        self.init(year: year, month: month, day: day)
    }

    func date(
        minuteOfDay: Int = 0,
        calendar: Calendar = .current
    ) -> Date? {
        // 把“某天 + 某分钟”重新还原成系统 `Date`。
        // 这常用于通知触发时间、边界计算等需要真实时间点的地方。
        guard let startOfDay = calendar.date(
            from: DateComponents(year: year, month: month, day: day)
        ) else {
            return nil
        }

        return calendar.date(byAdding: .minute, value: minuteOfDay, to: startOfDay)
    }
}

extension Date {
    // 把系统 Date 投影为“当天第几分钟”，是本项目里最常用的时间表示之一。
    var minuteOfDay: Int {
        let components = Calendar.current.dateComponents([.hour, .minute], from: self)
        return (components.hour ?? 0) * 60 + (components.minute ?? 0)
    }
}
