import Diarization
import TestFlows

extension TranscribeFlowSuite {
    static var acousticTraceFlow: TestFlow {
        TestFlow(
            "acoustic-traces",
            tags: [
                "diarization",
                "acoustic",
                "trace",
                "consistency",
            ]
        ) {
            Step("spectral analysis retains log-mel evidence") {
                let analysis = try AcousticAnalyzer().analyze(
                    AudioTestFixture.buffer(
                        samples: AudioTestFixture.sine(
                            frequency: 180,
                            duration: 0.4
                        )
                    )
                )

                let observation = try Expect.notNil(
                    analysis.observations.first,
                    "acoustic.trace.first-observation"
                )

                try Expect.equal(
                    observation.spectral.logMelEnergies.count,
                    24,
                    "acoustic.trace.log-mel-count"
                )

                try Expect.equal(
                    observation.spectral.mfcc.count,
                    13,
                    "acoustic.trace.mfcc-count"
                )
            }

            Step("trace preserves the observation timeline and robust distributions") {
                let samples = AudioTestFixture.sine(
                    frequency: 165,
                    duration: 0.35,
                    amplitude: 0.10
                ) + AudioTestFixture.sine(
                    frequency: 165,
                    duration: 0.35,
                    amplitude: 0.40
                )

                let analysis = try AcousticAnalyzer().analyze(
                    AudioTestFixture.buffer(
                        samples: samples
                    )
                )
                let trace = analysis.trace

                try Expect.equal(
                    trace.samples.count,
                    analysis.observations.count,
                    "acoustic.trace.sample-count"
                )

                try Expect.equal(
                    trace.summary.rms.count,
                    trace.samples.count,
                    "acoustic.trace.rms-distribution-count"
                )

                try Expect.equal(
                    trace.summary.rms.q90 >= trace.summary.rms.q10,
                    true,
                    "acoustic.trace.rms-quantiles"
                )

                try Expect.equal(
                    trace.samples.dropFirst().contains {
                        $0.consistency.energyDeltaDB > 0
                    },
                    true,
                    "acoustic.trace.energy-change"
                )
            }

            Step("stable voiced audio is more consistent than an abrupt level transition") {
                let stable = try AcousticAnalyzer().analyze(
                    AudioTestFixture.buffer(
                        samples: AudioTestFixture.sine(
                            frequency: 190,
                            duration: 0.7,
                            amplitude: 0.2
                        )
                    )
                ).trace

                let changing = try AcousticAnalyzer().analyze(
                    AudioTestFixture.buffer(
                        samples: AudioTestFixture.sine(
                            frequency: 190,
                            duration: 0.35,
                            amplitude: 0.03
                        ) + AudioTestFixture.sine(
                            frequency: 190,
                            duration: 0.35,
                            amplitude: 0.7
                        )
                    )
                ).trace

                try Expect.equal(
                    stable.summary.consistency.median
                        >= changing.summary.consistency.q10,
                    true,
                    "acoustic.trace.consistency-separates-change"
                )
            }
        }
    }
}
