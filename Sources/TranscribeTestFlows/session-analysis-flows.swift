import Diarization
import MediaCore
import TestFlows

extension TranscribeFlowSuite {
    static var sessionAcousticFlow: TestFlow {
        TestFlow(
            "session-acoustic-analysis",
            tags: [
                "diarization",
                "session",
                "media",
                "provenance",
            ]
        ) {
            Step("multiple timed chunks accumulate into one ordered acoustic analysis") {
                let firstSamples = AudioTestFixture.sine(
                    frequency: 150,
                    duration: 0.5
                )

                let secondSamples = AudioTestFixture.sine(
                    frequency: 150,
                    duration: 0.5
                )

                let accumulator = AcousticAnalysisAccumulator(
                    batchDurationSeconds: 1
                )

                try accumulator.consume(
                    MediaAudioChunk(
                        trackID: 1,
                        buffer: AudioTestFixture.buffer(
                            samples: firstSamples
                        ),
                        presentationTimeSeconds: 0,
                        durationSeconds: 0.5
                    )
                )

                try accumulator.consume(
                    MediaAudioChunk(
                        trackID: 1,
                        buffer: AudioTestFixture.buffer(
                            samples: secondSamples
                        ),
                        presentationTimeSeconds: 0.5,
                        durationSeconds: 0.5
                    )
                )

                let analysis = try accumulator.finish()

                try Expect.equal(
                    analysis.observations.isEmpty,
                    false,
                    "session-acoustic.non-empty"
                )

                try Expect.equal(
                    analysis.observations.map {
                        $0.id.rawValue
                    },
                    Array(
                        0..<analysis.observations.count
                    ),
                    "session-acoustic.rebased-ids"
                )

                try Expect.equal(
                    analysis.observations.allSatisfy {
                        $0.range.start >= 0
                            && $0.range.end <= 1.01
                    },
                    true,
                    "session-acoustic.timeline"
                )
            }

            Step("batch boundaries preserve continuous complete acoustic frames") {
                let sampleRate = 16_000
                let base = AudioTestFixture.sine(
                    frequency: 181,
                    duration: 0.65,
                    amplitude: 0.2,
                    sampleRate: sampleRate
                )

                let samples = base.enumerated().map {
                    index,
                    sample in

                    let progress = Double(index)
                        / Double(
                            max(
                                1,
                                base.count - 1
                            )
                        )

                    return sample
                        * Float(
                            0.5 + 0.5 * progress
                        )
                }

                let buffer = AudioTestFixture.buffer(
                    samples: samples,
                    sampleRate: sampleRate
                )

                let direct = try AcousticAnalyzer().analyze(
                    buffer
                )

                let accumulator = AcousticAnalysisAccumulator(
                    batchDurationSeconds: 0.1
                )

                try accumulator.consume(
                    .init(
                        trackID: 1,
                        buffer: buffer,
                        presentationTimeSeconds: 0,
                        durationSeconds: Double(samples.count)
                            / Double(sampleRate)
                    )
                )

                let accumulated = try accumulator.finish()

                try Expect.equal(
                    accumulated.observations.count,
                    direct.observations.count,
                    "session-acoustic.batch-independent-count"
                )

                try Expect.equal(
                    zip(
                        accumulated.observations,
                        direct.observations
                    ).allSatisfy {
                        accumulated,
                        direct in

                        abs(
                            accumulated.range.start
                                - direct.range.start
                        ) < 1e-9
                            && abs(
                                accumulated.range.duration
                                    - 0.032
                            ) < 1e-9
                    },
                    true,
                    "session-acoustic.batch-independent-timeline"
                )

                try Expect.equal(
                    zip(
                        accumulated.observations,
                        accumulated.observations.dropFirst()
                    ).allSatisfy {
                        previous,
                        current in

                        abs(
                            current.range.start
                                - previous.range.start
                                - 0.016
                        ) < 1e-9
                    },
                    true,
                    "session-acoustic.continuous-hop-grid"
                )

                try Expect.equal(
                    accumulated.observations
                        .dropFirst()
                        .contains {
                            abs(
                                $0.consistency.consistencyScore
                                    - 1
                            ) < 1e-12
                                && abs(
                                    $0.consistency.transientLikelihood
                                ) < 1e-12
                        },
                    false,
                    "session-acoustic.no-batch-consistency-reset"
                )
            }

            Step("diarization retains its low-level acoustic evidence") {
                let samples = AudioTestFixture.sine(
                    frequency: 165,
                    duration: 0.8
                )

                let acoustic = try AcousticAnalyzer().analyze(
                    AudioTestFixture.buffer(
                        samples: samples
                    )
                )

                let diarization = Diarizer().diarize(
                    acoustic,
                    configuration: .init(
                        expectedSpeakerCount: 1,
                        speakerObservation: .init(
                            minimumDurationSeconds: 0.25,
                            maximumDurationSeconds: 1,
                            maximumGapSeconds: 0.08
                        )
                    )
                )

                try Expect.equal(
                    diarization.acoustic?.observations.count,
                    acoustic.observations.count,
                    "session-acoustic.retained-through-diarization"
                )

                try Expect.equal(
                    diarization.acoustic?.sampleRate,
                    acoustic.sampleRate,
                    "session-acoustic.sample-rate-retained"
                )
            }
        }
    }
}
