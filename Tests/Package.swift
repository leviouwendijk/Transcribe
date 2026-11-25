// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "TranscribeTests",
    platforms: [
        .macOS(.v26),
    ],
    products: [

        // test binary
        .executable(
            name: "transtest",
            targets: [
                "TranscribeTestFlows",
            ]
        ),
    ],
    dependencies: [
        .package(
            url: "https://github.com/leviouwendijk/Media.git",
            branch: "master"
        ),
        .package(
            url: "https://github.com/leviouwendijk/Schema.git",
            branch: "master"
        ),
        .package(
            url: "https://github.com/swift-tooling/TestFlows.git",
            branch: "master"
        ),
        .package(path: ".."),
    ],
    targets: [
        .executableTarget(
            name: "TranscribeTestFlows",
            dependencies: [
                .product(name: "Transcribe", package: "Transcribe"),
                .product(name: "TranscribeApple", package: "Transcribe"),
                .product(name: "Diarization", package: "Transcribe"),
                .product(name: "DiarizationFluidAudio", package: "Transcribe"),
                .product(name: "EmbeddingProviderFluidAudio", package: "Transcribe"),
                .product(name: "SpeechAnalysis", package: "Transcribe"),
                .product(name: "SpeechAnalysisContext", package: "Transcribe"),
                .product(
                    name: "MediaCore",
                    package: "Media"
                ),
                .product(
                    name: "Schema",
                    package: "Schema"
                ),
                .product(
                    name: "TestFlows",
                    package: "TestFlows"
                ),
            ]
        ),
    ],
    swiftLanguageModes: [
        .v6,
    ]
)

for target in package.targets {
    switch target.type {
    case .regular, .executable, .test, .macro:
        var settings = target.swiftSettings ?? []

        settings.append(
            .treatAllWarnings(as: .error)
        )

        target.swiftSettings = settings

    case .plugin, .system, .binary:
        break

    @unknown default:
        break
    }
}
