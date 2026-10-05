// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "VaultoNote",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0"),
    ],
    targets: [
        // Prebuilt whisper.cpp (Metal) — fetched by scripts/fetch-whisper.sh.
        .binaryTarget(name: "whisper", path: "Vendor/whisper.xcframework"),
        .executableTarget(
            name: "VaultoNote",
            dependencies: ["whisper", .product(name: "Sparkle", package: "Sparkle")],
            path: "Sources/VaultoNote",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
            ]
        ),
        .testTarget(
            name: "VaultoNoteTests",
            dependencies: ["VaultoNote"],
            path: "Tests/VaultoNoteTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
