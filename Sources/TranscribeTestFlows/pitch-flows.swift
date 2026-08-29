import Diarization
import TestFlows

extension TranscribeFlowSuite {
    static var pitchInferenceFlow: TestFlow {
        TestFlow(
            "pitch-inference",
            tags: [
                "diarization",
                "pitch",
                "spectral",
            ]
        ) {
            Step("pitch estimation resolves between FFT bins") {
                let target = 181.0
                let analysis = try AcousticAnalyzer().analyze(
                    AudioTestFixture.buffer(
                        samples: AudioTestFixture.sine(
                            frequency: target,
                            duration: 0.6
                        )
                    )
                )

                let pitches = analysis.observations.compactMap {
                    $0.spectral.pitchHz
                }

                try Expect.equal(
                    pitches.isEmpty,
                    false,
                    "pitch.sub-bin.non-empty"
                )

                let sorted = pitches.sorted()
                let median = sorted[
                    sorted.count / 2
                ]

                try Expect.equal(
                    abs(median - target) < 3,
                    true,
                    "pitch.sub-bin.accuracy"
                )
            }

            Step("harmonic scoring prefers the fundamental") {
                let fundamental = AudioTestFixture.sine(
                    frequency: 220,
                    duration: 0.6,
                    amplitude: 0.12
                )
                let harmonic = AudioTestFixture.sine(
                    frequency: 440,
                    duration: 0.6,
                    amplitude: 0.24
                )

                let samples = zip(
                    fundamental,
                    harmonic
                ).map {
                    $0 + $1
                }

                let analysis = try AcousticAnalyzer().analyze(
                    AudioTestFixture.buffer(
                        samples: samples
                    )
                )

                let pitches = analysis.observations.compactMap {
                    $0.spectral.pitchHz
                }

                try Expect.equal(
                    pitches.isEmpty,
                    false,
                    "pitch.harmonic.non-empty"
                )

                let sorted = pitches.sorted()
                let median = sorted[
                    sorted.count / 2
                ]

                try Expect.equal(
                    abs(median - 220) < 5,
                    true,
                    "pitch.harmonic.fundamental"
                )
            }

            Step("harmonic-only evidence does not pin to the lower search boundary") {
                let second = AudioTestFixture.sine(
                    frequency: 156.25,
                    duration: 0.6,
                    amplitude: 0.18
                )
                let third = AudioTestFixture.sine(
                    frequency: 234.375,
                    duration: 0.6,
                    amplitude: 0.18
                )

                let samples = zip(
                    second,
                    third
                ).map {
                    $0 + $1
                }

                let analysis = try AcousticAnalyzer().analyze(
                    AudioTestFixture.buffer(
                        samples: samples
                    )
                )

                let pitches = analysis.observations.compactMap {
                    $0.spectral.pitchHz
                }

                try Expect.equal(
                    pitches.isEmpty,
                    false,
                    "pitch.lower-bound.non-empty"
                )

                let lowerBoundaryCount = pitches.filter {
                    abs($0 - 78.125) < 1
                }.count

                try Expect.equal(
                    Double(lowerBoundaryCount)
                        / Double(pitches.count)
                        < 0.10,
                    true,
                    "pitch.lower-bound.not-pinned"
                )

                let sorted = pitches.sorted()
                let median = sorted[
                    sorted.count / 2
                ]

                try Expect.equal(
                    median > 120,
                    true,
                    "pitch.lower-bound.prefers-present-fundamental"
                )
            }

            Step("pitch search retains fundamentals above the legacy ceiling") {
                let target = 420.0
                let analysis = try AcousticAnalyzer().analyze(
                    AudioTestFixture.buffer(
                        samples: AudioTestFixture.sine(
                            frequency: target,
                            duration: 0.6,
                            amplitude: 0.18
                        )
                    )
                )

                let pitches = analysis.observations.compactMap {
                    $0.spectral.pitchHz
                }

                try Expect.equal(
                    pitches.isEmpty,
                    false,
                    "pitch.upper-range.non-empty"
                )

                let sorted = pitches.sorted()
                let median = sorted[
                    sorted.count / 2
                ]

                try Expect.equal(
                    abs(median - target) < 6,
                    true,
                    "pitch.upper-range.accuracy"
                )

                try Expect.equal(
                    median > 350,
                    true,
                    "pitch.upper-range.above-legacy-ceiling"
                )
            }

            Step("silence does not invent confident pitch") {
                let analysis = try AcousticAnalyzer().analyze(
                    AudioTestFixture.buffer(
                        samples: AudioTestFixture.silence(
                            duration: 0.4
                        )
                    )
                )

                try Expect.equal(
                    analysis.observations.allSatisfy {
                        $0.spectral.pitchHz == nil
                            && $0.spectral.pitchConfidence < 0.25
                    },
                    true,
                    "pitch.silence.unpitched"
                )
            }
        }
    }
}
