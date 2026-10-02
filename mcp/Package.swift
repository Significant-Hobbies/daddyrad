// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "DaddyRadMCP",
    platforms: [.macOS(.v15)],
    products: [.executable(name: "daddyrad-mcp", targets: ["DaddyRadMCP"])],
    dependencies: [
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", exact: "0.12.1"),
        .package(path: "../../performancedaddy"),
        .package(path: "../../contextdaddy"),
        .package(path: "../../storagedaddy"),
        .package(path: "../../browserdaddy"),
    ],
    targets: [
        .target(name: "DaddyDiagnostics", dependencies: [
            .product(name: "MCP", package: "swift-sdk"),
            .product(name: "PerformanceCore", package: "performancedaddy"),
            .product(name: "ContextCore", package: "contextdaddy"),
            .product(name: "DiskCore", package: "storagedaddy"),
            .product(name: "BrowserCore", package: "browserdaddy"),
        ]),
        .executableTarget(name: "DaddyRadMCP", dependencies: ["DaddyDiagnostics", .product(name: "MCP", package: "swift-sdk")]),
        .testTarget(name: "DaddyDiagnosticsTests", dependencies: ["DaddyDiagnostics"]),
    ]
)
