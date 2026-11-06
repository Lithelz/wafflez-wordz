// swift-tools-version:5.9
import PackageDescription

// Wafflez Wordz
// - WafflezCore: the writing engine (checks, tone, AI detector, humanizer, Claude client).
//   Foundation-only, so it also builds and tests on Linux.
// - WafflezWordz: the macOS app (menu bar assistant that works in other apps + the Studio window).
var targets: [Target] = [
    .target(
        name: "WafflezCore",
        path: "Sources/WafflezCore"
    ),
    .testTarget(
        name: "WafflezCoreTests",
        dependencies: ["WafflezCore"],
        path: "Tests/WafflezCoreTests"
    ),
]

var products: [Product] = [
    .library(name: "WafflezCore", targets: ["WafflezCore"]),
]

#if os(macOS)
targets.append(
    .executableTarget(
        name: "WafflezWordz",
        dependencies: ["WafflezCore"],
        path: "Sources/WafflezWordz",
        linkerSettings: [
            .linkedFramework("AppKit"),
            .linkedFramework("ApplicationServices"),
            .linkedFramework("Carbon"),
            .linkedFramework("CoreServices"),
            .linkedFramework("PDFKit"),
            .linkedFramework("ServiceManagement"),
        ]
    )
)
products.append(.executable(name: "WafflezWordz", targets: ["WafflezWordz"]))
#endif

let package = Package(
    name: "WafflezWordz",
    platforms: [.macOS(.v14)],
    products: products,
    targets: targets
)
