// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "Transcribe",
    platforms: [
        .macOS(.v26),
    ],
    products: [
        .library(
            name: "Transcribe",
            targets: [
                "Transcribe",
            ]
        ),
        .library(
            name: "TranscribeApple",
            targets: [
                "TranscribeApple",
            ]
        ),
        .library(
            name: "Diarization",
            targets: [
                "Diarization",
            ]
        ),
        .library(
            name: "EmbeddingProviderFluidAudio",
            targets: [
                "EmbeddingProviderFluidAudio",
            ]
        ),
        .library(
            name: "SpeechAnalysis",
            targets: [
                "SpeechAnalysis",
            ]
        ),
        .library(
            name: "SpeechAnalysisContext",
            targets: [
                "SpeechAnalysisContext",
            ]
        ),
        .executable(
            name: "transcribe",
            targets: [
                "TranscribeCLI",
            ]
        ),
        .executable(
            name: "transtest",
            targets: [
                "TranscribeTestFlows",
            ]
        ),
    ],
    dependencies: [
        .package(
            url: "https://github.com/leviouwendijk/Arguments.git",
            branch: "master"
        ),
        .package(
            url: "https://github.com/FluidInference/FluidAudio.git",
            exact: "0.15.5"
        ),
        .package(
            url: "https://github.com/leviouwendijk/Media.git",
            branch: "master"
        ),
        .package(
            url: "https://github.com/leviouwendijk/Schema.git",
            branch: "master"
        ),
        .package(
            url: "https://github.com/leviouwendijk/SchemaMacros.git",
            branch: "master"
        ),
        .package(
            url: "https://github.com/leviouwendijk/Terminal.git",
            branch: "master"
        ),
        .package(
            url: "https://github.com/leviouwendijk/TestFlows.git",
            branch: "master"
        ),
    ],
    targets: [
        .target(
            name: "Transcribe",
            dependencies: [
                .product(
                    name: "MediaCore",
                    package: "Media"
                ),
            ]
        ),
        .target(
            name: "Diarization",
            dependencies: [
                .product(
                    name: "MediaCore",
                    package: "Media"
                ),
                .product(
                    name: "MediaAudio",
                    package: "Media"
                ),
            ]
        ),
        .target(
            name: "EmbeddingProviderFluidAudio",
            dependencies: [
                "Diarization",
                .product(
                    name: "FluidAudio",
                    package: "FluidAudio"
                ),
                .product(
                    name: "MediaAudio",
                    package: "Media"
                ),
                .product(
                    name: "MediaCore",
                    package: "Media"
                ),
            ]
        ),
        .target(
            name: "SpeechAnalysis",
            dependencies: [
                "Transcribe",
                "Diarization",
                .product(
                    name: "MediaCore",
                    package: "Media"
                ),
            ]
        ),
        .target(
            name: "SpeechAnalysisContext",
            dependencies: [
                "Transcribe",
                "Diarization",
                "SpeechAnalysis",
                .product(
                    name: "MediaCore",
                    package: "Media"
                ),
                .product(
                    name: "Schema",
                    package: "Schema"
                ),
                .product(
                    name: "SchemaMacros",
                    package: "SchemaMacros"
                ),
            ]
        ),
        .target(
            name: "TranscribeApple",
            dependencies: [
                "Transcribe",
                "Diarization",
                "SpeechAnalysis",
                .product(
                    name: "MediaCore",
                    package: "Media"
                ),
                .product(
                    name: "MediaAudio",
                    package: "Media"
                ),
                .product(
                    name: "MediaAV",
                    package: "Media"
                ),
            ]
        ),
        .executableTarget(
            name: "TranscribeCLI",
            dependencies: [
                "TranscribeApple",
                "Diarization",
                "EmbeddingProviderFluidAudio",
                "SpeechAnalysis",
                "SpeechAnalysisContext",
                .product(
                    name: "Arguments",
                    package: "Arguments"
                ),
                .product(
                    name: "Terminal",
                    package: "Terminal"
                ),
            ]
        ),
        .executableTarget(
            name: "TranscribeTestFlows",
            dependencies: [
                "Transcribe",
                "TranscribeApple",
                "Diarization",
                "EmbeddingProviderFluidAudio",
                "SpeechAnalysis",
                "SpeechAnalysisContext",
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
