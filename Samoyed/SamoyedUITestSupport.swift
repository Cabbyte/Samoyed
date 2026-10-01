#if DEBUG
import Foundation
import SwiftUI

/// A bounded content preview, not an emulation of a different device or its sheets.
struct SamoyedQAViewport<Content: View>: View {
    @ViewBuilder let content: () -> Content
    @State private var measuredWidth: CGFloat = 0

    private var requestedWidth: CGFloat? {
        let environment = ProcessInfo.processInfo.environment
        guard environment["SAMOYED_UI_TEST_FIXTURE"] != nil,
              let value = environment["SAMOYED_QA_CONTENT_WIDTH"].flatMap(Double.init),
              (280 ... 500).contains(value) else { return nil }
        return CGFloat(value)
    }

    var body: some View {
        if let requestedWidth {
            content()
                .frame(width: requestedWidth)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { measuredWidth = $0 }
                .overlay(alignment: .bottomTrailing) {
                    Text("QA content \(Int(measuredWidth)) pt")
                        .font(.system(size: 10))
                        .padding(2)
                        .background(.regularMaterial)
                        .accessibilityIdentifier("qa-content-width")
                }
                .frame(maxWidth: .infinity)
        } else {
            content()
        }
    }
}

@MainActor
enum SamoyedUITestSupport {
    private static let fixtureKey = "SAMOYED_UI_TEST_FIXTURE"
    private static let resetKey = "SAMOYED_UI_TEST_RESET"
    private static let routeKey = "SAMOYED_UI_TEST_ROUTE"

    static func makeStoreIfRequested(
        processInfo: ProcessInfo = .processInfo,
        fileManager: FileManager = .default
    ) -> SamoyedStore? {
        guard let fixture = processInfo.environment[fixtureKey] else { return nil }

        // The app-group container survives process relaunches and test-runner reinstall cycles.
        // A dedicated subdirectory keeps fixtures isolated from the real shared document.
        let root = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: SamoyedSharedConfig.appGroupID
        ) ?? fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let fileURL = root
            .appending(path: "SamoyedUITests", directoryHint: .isDirectory)
            .appending(path: "document.json")
        let repository = SamoyedDocumentRepository(fileURL: fileURL)

        if processInfo.environment[resetKey] == "1" {
            try? fileManager.removeItem(at: fileURL)
            SamoyedTintPreference.save(.ocean)
            prepareFixture(
                fixture,
                repository: repository,
                fileURL: fileURL,
                fileManager: fileManager
            )
        }

        enqueueExternalRouteIfRequested(processInfo: processInfo)

        return SamoyedStore(
            documentRepository: repository,
            validationLogger: ValidationEventLogger(enabled: false)
        )
    }

    private static func prepareFixture(
        _ fixture: String,
        repository: SamoyedDocumentRepository,
        fileURL: URL,
        fileManager: FileManager
    ) {
        if fixture == "load-error" {
            do {
                try fileManager.createDirectory(
                    at: fileURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try Data("not-json".utf8).write(to: fileURL, options: .atomic)
            } catch {
                preconditionFailure("Unable to prepare load-error UI fixture: \(error)")
            }
            return
        }

        guard let document = SamoyedQAFixtureFactory.document(named: fixture) else {
            preconditionFailure("Unknown Samoyed UI test fixture: \(fixture)")
        }

        do {
            try repository.save(document)
        } catch {
            preconditionFailure("Unable to save Samoyed UI test fixture \(fixture): \(error)")
        }
    }

    private static func enqueueExternalRouteIfRequested(processInfo: ProcessInfo) {
        guard let routeValue = processInfo.environment[routeKey] else { return }
        guard
            let routeURL = URL(string: routeValue),
            SamoyedSystemRoute(url: routeURL) != nil
        else {
            preconditionFailure("Invalid Samoyed UI test route: \(routeValue)")
        }

        SamoyedExternalRouteCenter.shared.enqueue(routeURL)
    }
}
#endif
