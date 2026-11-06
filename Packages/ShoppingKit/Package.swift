// swift-tools-version:5.9
import PackageDescription

// The app's logic, kept out of the Xcode project so it can be tested with `swift test`.
// - ShoppingCore: Foundation only (names, suggestions, list order, trip rules), so it stays free of storage and UI.
// - ShoppingStore: the Core Data + CloudKit layer. Every file is wrapped in `#if canImport(CoreData)`, so the package
//   still builds (empty) where Core Data doesn't exist.
let package = Package(
    name: "ShoppingKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "ShoppingCore", targets: ["ShoppingCore"]),
        .library(name: "ShoppingStore", targets: ["ShoppingStore"]),
    ],
    targets: [
        .target(name: "ShoppingCore", path: "Sources/ShoppingCore"),
        .target(name: "ShoppingStore", dependencies: ["ShoppingCore"], path: "Sources/ShoppingStore"),
        .testTarget(name: "ShoppingCoreTests", dependencies: ["ShoppingCore"], path: "Tests/ShoppingCoreTests"),
        .testTarget(name: "ShoppingStoreTests", dependencies: ["ShoppingStore"], path: "Tests/ShoppingStoreTests"),
    ]
)
