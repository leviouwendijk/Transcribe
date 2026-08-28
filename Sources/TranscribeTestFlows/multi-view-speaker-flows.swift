import Diarization
import TestFlows

extension TranscribeFlowSuite {
    static var multiViewSpeakerFlow: TestFlow {
        TestFlow(
            "multi-view-speaker-profile",
            tags: [
                "diarization",
                "speaker",
                "profile",
                "multi-view",
            ]
        ) {
            Step("speaker observations carry weighted raw and enhanced feature evidence") {
                let samples = AudioTestFixture.sine(
                    frequency: 175,
                    duration: 0.9,
                    amplitude: 0.02
                )
                let accumulator = ParallelAcousticAnalysisAccumulator(
                    batchDurationSeconds: 1
                )

                try accumulator.consume(
                    .init(
                        trackID: 1,
                        buffer: AudioTestFixture.buffer(
                            samples: samples
                        ),
                        presentationTimeSeconds: 0,
                        durationSeconds: 0.9
                    )
                )

                let evidence = try accumulator.finish()
                let result = Diarizer().diarize(
                    evidence,
                    configuration: .init(
                        expectedSpeakerCount: 1,
                        speakerObservation: .init(
                            minimumDurationSeconds: 0.25,
                            maximumDurationSeconds: 1,
                            maximumGapSeconds: 0.08
                        )
                    )
                )
                let observation = try Expect.notNil(
                    result.observations.first,
                    "multi-view.observation"
                )

                try Expect.equal(
                    observation.features.values.count,
                    observation.features.weights.count,
                    "multi-view.weight-shape"
                )
                try Expect.equal(
                    observation.features.weights.contains {
                        $0 > 0 && $0 < 1
                    },
                    true,
                    "multi-view.non-uniform-weights"
                )
                try Expect.equal(
                    observation.viewAgreement != nil,
                    true,
                    "multi-view.agreement"
                )
            }

            Step("speaker profile retains distributions instead of only one centroid") {
                let samples = AudioTestFixture.sine(
                    frequency: 145,
                    duration: 0.8
                ) + AudioTestFixture.silence(
                    duration: 0.15
                ) + AudioTestFixture.sine(
                    frequency: 270,
                    duration: 0.8
                )
                let accumulator = ParallelAcousticAnalysisAccumulator(
                    batchDurationSeconds: 2
                )

                try accumulator.consume(
                    .init(
                        trackID: 1,
                        buffer: AudioTestFixture.buffer(
                            samples: samples
                        ),
                        presentationTimeSeconds: 0,
                        durationSeconds: 1.75
                    )
                )

                let evidence = try accumulator.finish()
                let result = Diarizer().diarize(
                    evidence,
                    configuration: .init(
                        expectedSpeakerCount: 2,
                        speakerObservation: .init(
                            minimumDurationSeconds: 0.25,
                            maximumDurationSeconds: 0.9,
                            maximumGapSeconds: 0.08
                        )
                    )
                )

                try Expect.equal(
                    result.profiles.count,
                    2,
                    "multi-view.profile-count"
                )
                try Expect.equal(
                    result.profiles.allSatisfy {
                        $0.acousticProfile?.quality.count ?? 0 > 0
                    },
                    true,
                    "multi-view.profile-distributions"
                )
                try Expect.equal(
                    result.profiles.allSatisfy {
                        $0.acousticProfile?.logMelMean.count == 24
                    },
                    true,
                    "multi-view.profile-log-mel"
                )
            }
        }
    }
}
