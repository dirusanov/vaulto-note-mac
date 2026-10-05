// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "VaultoNote",
    platforms: [.macOS(.v14)],
    targets: [
        // Prebuilt whisper.cpp (Metal) — fetched by scripts/fetch-whisper.sh.
        .binaryTarget(name: "whisper", path: "Vendor/whisper.xcframework"),
        .executableTarget(
            name: "VaultoNote",
            dependencies: ["whisper"],
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
