// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "TermDeck",
    platforms: [
        .macOS(.v15)
    ],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.20.0"),
        .package(url: "https://github.com/orlandos-nl/Citadel.git", from: "0.12.1"),
        .package(url: "https://github.com/Wellz26/swift-nio-ssh.git", "0.3.4"..<"0.4.0"),
    ],
    targets: [
        .executableTarget(
            name: "TermDeck",
            dependencies: [
                .product(name: "SwiftTerm", package: "SwiftTerm"),
                .product(name: "Citadel", package: "Citadel"),
                .product(name: "NIOSSH", package: "swift-nio-ssh"),
            ],
            path: "Sources/TermDeck"
        )
    ],
    swiftLanguageVersions: [.v5]
)
