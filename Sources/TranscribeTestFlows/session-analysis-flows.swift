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
