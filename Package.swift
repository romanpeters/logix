// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LogixMouseMapper",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "LogixMouseMapper", targets: ["LogixMouseMapper"])
    ],
    targets: [
        .executableTarget(
            name: "LogixMouseMapper",
            path: "Sources/LogixMouseMapper"
        )
    ]
)
