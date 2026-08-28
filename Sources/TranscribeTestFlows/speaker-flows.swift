import Diarization
import TestFlows

extension TranscribeFlowSuite {
    static var speakerObservationFlow: TestFlow {
        TestFlow(
            "speaker-observations",
            tags: [
                "diarization",
                "speaker",
                "profile",
            ]
        ) {
            Step("contiguous voiced evidence aggregates into speaker observations") {
                let samples = AudioTestFixture.sine(
                    frequency: 160,
                    duration: 0.8
                )

                let analysis = try AcousticAnalyzer().analyze(
                    AudioTestFixture.buffer(
                        samples: samples
                    )
                )

                let observations = SpeakerObservationBuilder().build(
                    from: analysis
                )

                try Expect.equal(
                    observations.isEmpty,
                    false,
                    "speaker-observation.non-empty"
                )

                try Expect.equal(
                    observations.allSatisfy {
                        !$0.acousticObservationIDs.isEmpty
                            && !$0.features.values.isEmpty
                            && $0.range.duration > 0
                    },
                    true,
                    "speaker-observation.retained-evidence"
                )
            }
        }
    }

    static var sessionClusteringFlow: TestFlow {
        TestFlow(
            "session-speaker-clustering",
            tags: [
                "diarization",
                "clustering",
                "speaker",
            ]
        ) {
            Step("two distinct recurring synthetic voices produce two retained speaker profiles") {
                let samples = AudioTestFixture.sine(
                    frequency: 140,
                    duration: 0.8
                )
                    + AudioTestFixture.silence(
                        duration: 0.2
                    )
                    + AudioTestFixture.sine(
                        frequency: 270,
                        duration: 0.8
                    )
                    + AudioTestFixture.silence(
                        duration: 0.2
                    )
                    + AudioTestFixture.sine(
                        frequency: 140,
                        duration: 0.8
                    )
                    + AudioTestFixture.silence(
                        duration: 0.2
                    )
                    + AudioTestFixture.sine(
                        frequency: 270,
                        duration: 0.8
                    )

                let result = try Diarizer().diarize(
                    AudioTestFixture.buffer(
                        samples: samples
                    ),
                    configuration: .init(
                        expectedSpeakerCount: 2,
                        speakerObservation: .init(
                            minimumDurationSeconds: 0.25,
                            maximumDurationSeconds: 1.0,
                            maximumGapSeconds: 0.08
                        )
                    )
                )

                try Expect.equal(
                    result.speakers.count,
                    2,
                    "diarization.cluster.speaker-count"
                )

                try Expect.equal(
                    result.profiles.count,
                    2,
                    "diarization.cluster.profile-count"
                )

                try Expect.equal(
                    result.observations.isEmpty,
                    false,
                    "diarization.cluster.observations-retained"
                )

                try Expect.equal(
                    result.profiles.allSatisfy {
                        $0.acousticCentroid?.values.isEmpty == false
                            && $0.observationCount > 0
                    },
                    true,
                    "diarization.cluster.profiles-derived"
                )

                try Expect.equal(
                    result.segments.allSatisfy {
                        !$0.observationIDs.isEmpty
                    },
                    true,
                    "diarization.cluster.segment-provenance"
                )
            }
        }
    }
}
