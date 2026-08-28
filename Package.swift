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
            name: "SpeechAnalysis",
            targets: [
                "SpeechAnalysis",
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
            url: "https://github.com/leviouwendijk/Media.git",
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
            name: "TranscribeApple",
            dependencies: [
                "Transcribe",
                .product(
                    name: "MediaCore",
                    package: "Media"
                ),
            ]
        ),
        .executableTarget(
            name: "TranscribeCLI",
            dependencies: [
                "TranscribeApple",
            ]
        ),
        .executableTarget(
            name: "TranscribeTestFlows",
            dependencies: [
                "Transcribe",
                "TranscribeApple",
                "Diarization",
                "SpeechAnalysis",
                .product(
                    name: "MediaCore",
                    package: "Media"
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
