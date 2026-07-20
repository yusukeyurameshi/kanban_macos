// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MeuKanban",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "MeuKanban", targets: ["MeuKanban"])],
    targets: [
        .executableTarget(
            name: "MeuKanban",
            resources: [.process("Resources")]
        )
    ]
)
