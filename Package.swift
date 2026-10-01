// swift-tools-version: 6.2
import PackageDescription
let package = Package(
    name: "SamoyedCore",
    platforms: [.macOS(.v13)],
    products: [.library(name: "SamoyedCore", targets: ["SamoyedCore"])],
    dependencies: [.package(url: "https://github.com/groue/GRDB.swift.git", from: "7.9.0")],
    targets: [
        .target(name: "SamoyedCore", dependencies: [.product(name: "GRDB", package: "GRDB.swift")], path: "Samoyed/CoreShared"),
        .testTarget(name: "SamoyedCoreTests", dependencies: ["SamoyedCore"], path: "Tests/SamoyedCoreTests", resources: [.copy("Fixtures")])
    ]
)
