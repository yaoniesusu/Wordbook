// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Wordbook",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(name: "Wordbook", targets: ["Wordbook"]),
    ],
    targets: [
        .executableTarget(
            name: "Wordbook",
            path: "Sources/Wordbook"
        ),
        .testTarget(
            name: "WordbookTests",
            dependencies: ["Wordbook"],
            path: "Tests/WordbookTests"
        ),
    ]
)
