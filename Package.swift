// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "EDFBrowserMac",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "EDFBrowserMac", targets: ["EDFBrowserMac"]), .executable(name: "EDFCoreCheck", targets: ["EDFCoreCheck"]), .library(name: "EDFCore", targets: ["EDFCore"])],
    targets: [
        .target(name: "CDSP", publicHeadersPath: "include", cSettings: [.headerSearchPath("upstream"), .define("_LARGEFILE64_SOURCE"), .define("_LARGEFILE_SOURCE")]),
        .target(name: "EDFCore", dependencies: ["CDSP"]),
        .executableTarget(name: "EDFBrowserMac", dependencies: ["EDFCore"], resources: [.copy("Resources")]),
        .executableTarget(name: "EDFCoreCheck", dependencies: ["EDFCore", "CDSP"]),
        .testTarget(name: "EDFCoreTests", dependencies: ["EDFCore", "CDSP"])
    ]
)
