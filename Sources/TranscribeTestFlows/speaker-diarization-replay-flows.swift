import Diarization
import MediaCore
import TestFlows

extension TranscribeFlowSuite {
    static var speakerDiarizationReplayFlow: TestFlow {
        TestFlow(
            "speaker-diarization-replay",
            tags: [
                "ablation",
                "clustering",
                "diarization",
                "replay",
                "speaker",
            ]
        ) {
            Step("retained speaker observations reproduce the same interpretation without acoustic analysis") {
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

                let configuration = DiarizationConfiguration(
                    expectedSpeakerCount: 2,
                    speakerObservation: .init(
                        minimumDurationSeconds: 0.25,
                        maximumDurationSeconds: 1,
                        maximumGapSeconds: 0.08
                    )
                )
                let diarizer = Diarizer()
                let source = try diarizer.diarize(
                    AudioTestFixture.buffer(
                        samples: samples
                    ),
                    configuration: configuration
                )
                let replayed = diarizer.replay(
                    source
                )

                try Expect.equal(
                    replayed.observations.map(\.id),
                    source.observations.map(\.id),
                    "speaker-replay.observation-identity"
                )
                try Expect.equal(
                    replayed.assignments.map(\.acousticSpeaker),
                    source.assignments.map(\.acousticSpeaker),
                    "speaker-replay.acoustic-assignments"
                )
                try Expect.equal(
                    replayed.assignments.map(\.resolvedSpeaker),
                    source.assignments.map(\.resolvedSpeaker),
                    "speaker-replay.resolved-assignments"
                )
                try Expect.equal(
                    replayed.segments,
                    source.segments,
                    "speaker-replay.segments"
                )
                try Expect.equal(
                    replayed.acoustic,
                    source.acoustic,
                    "speaker-replay.acoustic-evidence-preserved"
                )
                try Expect.equal(
                    replayed.method?.configuration,
                    source.method?.configuration,
                    "speaker-replay.configuration"
                )
            }

            Step("feature-family ablation reuses observations and records the effective feature space") {
                let samples = AudioTestFixture.sine(
                    frequency: 150,
                    duration: 0.8
                )
                    + AudioTestFixture.silence(
                        duration: 0.2
                    )
                    + AudioTestFixture.sine(
                        frequency: 290,
                        duration: 0.8
                    )
                    + AudioTestFixture.silence(
                        duration: 0.2
                    )
                    + AudioTestFixture.sine(
                        frequency: 150,
                        duration: 0.8
                    )
                    + AudioTestFixture.silence(
                        duration: 0.2
                    )
                    + AudioTestFixture.sine(
                        frequency: 290,
                        duration: 0.8
                    )

                let diarizer = Diarizer()
                let source = try diarizer.diarize(
                    AudioTestFixture.buffer(
                        samples: samples
                    ),
                    configuration: .init(
                        expectedSpeakerCount: 2,
                        speakerObservation: .init(
                            minimumDurationSeconds: 0.25,
                            maximumDurationSeconds: 1,
                            maximumGapSeconds: 0.08
                        )
                    )
                )
                let replayed = diarizer.replay(
                    source,
                    ablating: .pitch
                )

                try Expect.equal(
                    replayed.observations.map(\.acousticObservationIDs),
                    source.observations.map(\.acousticObservationIDs),
                    "speaker-replay.ablation-reuses-evidence"
                )
                try Expect.equal(
                    replayed.method?.configuration
                        .speakerObservation
                        .featureWeights
                        .pitch,
                    0,
                    "speaker-replay.pitch-ablation-configuration"
                )
                try Expect.equal(
                    replayed.method?.featureSpace.filter {
                        $0.family == .pitch
                    }.allSatisfy {
                        $0.weight == 0
                    },
                    true,
                    "speaker-replay.pitch-ablation-feature-space"
                )
            }

            Step("leave-one-out summaries compare every retained feature family cheaply") {
                let samples = AudioTestFixture.sine(
                    frequency: 170,
                    duration: 0.8
                )
                    + AudioTestFixture.silence(
                        duration: 0.2
                    )
                    + AudioTestFixture.sine(
                        frequency: 310,
                        duration: 0.8
                    )
                    + AudioTestFixture.silence(
                        duration: 0.2
                    )
                    + AudioTestFixture.sine(
                        frequency: 170,
                        duration: 0.8
                    )
                    + AudioTestFixture.silence(
                        duration: 0.2
                    )
                    + AudioTestFixture.sine(
                        frequency: 310,
                        duration: 0.8
                    )

                let diarizer = Diarizer()
                let source = try diarizer.diarize(
                    AudioTestFixture.buffer(
                        samples: samples
                    ),
                    configuration: .init(
                        expectedSpeakerCount: 2,
                        speakerObservation: .init(
                            minimumDurationSeconds: 0.25,
                            maximumDurationSeconds: 1,
                            maximumGapSeconds: 0.08
                        )
                    )
                )
                let summaries = diarizer.leaveOneOutSummaries(
                    source
                )

                try Expect.equal(
                    summaries.count,
                    SpeakerFeatureAblationTarget.allCases.count,
                    "speaker-replay.leave-one-out-count"
                )
                try Expect.equal(
                    Set(
                        summaries.map(\.ablation)
                    ),
                    Set(
                        SpeakerFeatureAblationTarget.allCases
                    ),
                    "speaker-replay.leave-one-out-targets"
                )
                try Expect.equal(
                    summaries.allSatisfy {
                        $0.changedAcousticAssignmentCount >= 0
                            && $0.changedResolvedAssignmentCount >= 0
                            && $0.speakerCount > 0
                    },
                    true,
                    "speaker-replay.leave-one-out-metrics"
                )
            }
        }
    }
}
