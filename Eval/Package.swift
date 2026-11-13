// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "countlog-eval",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "countlog-eval",
            path: "Sources/countlog-eval"
        )
    ]
)
