import Diarization
import TestFlows

extension TranscribeFlowSuite {
    static var acousticPerformanceFlow: TestFlow {
        TestFlow(
            "acoustic-performance-invariants",
            tags: [
                "diarization",
                "acoustic",
                "performance",
            ]
        ) {
            Step("optimized spectral plan retains 16 kHz feature semantics") {
                let analysis = try AcousticAnalyzer().analyze(
                    AudioTestFixture.buffer(
                        samples: AudioTestFixture.sine(
                            frequency: 180,
                            duration: 0.4
                        )
                    )
                )

                try Expect.equal(
                    analysis.sampleRate,
                    16_000,
                    "acoustic.performance.16k.sample-rate"
                )

                try Expect.equal(
                    analysis.observations.contains {
                        $0.spectral.mfcc.count == 13
                    },
                    true,
                    "acoustic.performance.16k.mfcc"
                )
            }

            Step("optimized spectral plan supports 48 kHz input") {
                let sampleRate = 48_000

                let analysis = try AcousticAnalyzer().analyze(
                    AudioTestFixture.buffer(
                        samples: AudioTestFixture.sine(
                            frequency: 180,
                            duration: 0.4,
                            sampleRate: sampleRate
                        ),
                        sampleRate: sampleRate
                    )
                )

                try Expect.equal(
                    analysis.sampleRate,
                    sampleRate,
                    "acoustic.performance.48k.sample-rate"
                )

                try Expect.equal(
                    analysis.observations.isEmpty,
                    false,
                    "acoustic.performance.48k.non-empty"
                )

                try Expect.equal(
                    analysis.observations.allSatisfy {
                        $0.spectral.mfcc.count == 13
                    },
                    true,
                    "acoustic.performance.48k.mfcc"
                )
            }
        }
    }
}
