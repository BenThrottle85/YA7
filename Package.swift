// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "YA7",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "YA7", targets: ["YA7"])],
    targets: [
        .executableTarget(name: "YA7"),
        .testTarget(name: "YA7Tests", dependencies: ["YA7"], resources: [.copy("Fixtures")])
    ]
)
