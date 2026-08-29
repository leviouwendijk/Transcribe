import Diarization
import MediaCore
import TestFlows

extension TranscribeFlowSuite {
    static var speakerTemporalCoherenceFlow: TestFlow {
        TestFlow(
            "speaker-temporal-coherence",
            tags: [
                "clustering",
                "diarization",
                "speaker",
                "temporal",
            ]
        ) {
            Step("isolated weak speaker flip is resolved by continuous surrounding evidence") {
                let speaker1 = SpeakerID(
                    rawValue: "speaker_1"
                )
                let speaker2 = SpeakerID(
                    rawValue: "speaker_2"
                )

                let observations = (0..<5).map {
                    temporalObservation(
                        id: $0,
                        start: Double($0) * 0.4
                    )
                }

                let assignments = [
                    temporalAssignment(
                        id: 0,
                        acousticSpeaker: speaker2,
                        speaker1: speaker1,
                        speaker2: speaker2,
                        speaker1Cost: 1,
                        speaker2Cost: 0.1,
                        confidence: 0.9
                    ),
                    temporalAssignment(
                        id: 1,
                        acousticSpeaker: speaker2,
                        speaker1: speaker1,
                        speaker2: speaker2,
                        speaker1Cost: 1,
                        speaker2Cost: 0.1,
                        confidence: 0.9
                    ),
                    temporalAssignment(
                        id: 2,
                        acousticSpeaker: speaker1,
                        speaker1: speaker1,
                        speaker2: speaker2,
                        speaker1Cost: 0.92,
                        speaker2Cost: 1,
                        confidence: 0.08
                    ),
                    temporalAssignment(
                        id: 3,
                        acousticSpeaker: speaker2,
                        speaker1: speaker1,
                        speaker2: speaker2,
                        speaker1Cost: 1,
                        speaker2Cost: 0.1,
                        confidence: 0.9
                    ),
                    temporalAssignment(
                        id: 4,
                        acousticSpeaker: speaker2,
                        speaker1: speaker1,
                        speaker2: speaker2,
                        speaker1Cost: 1,
                        speaker2Cost: 0.1,
                        confidence: 0.9
                    )
                ]

                let resolved = SpeakerTemporalCoherence().resolve(
                    observations: observations,
                    assignments: assignments
                )

                try Expect.equal(
                    resolved.map(
                        \.resolvedSpeaker
                    ),
                    Array(
                        repeating: speaker2,
                        count: 5
                    ),
                    "temporal-coherence.weak-flip-resolved"
                )

                try Expect.equal(
                    resolved[2].acousticSpeaker,
                    speaker1,
                    "temporal-coherence.raw-assignment-retained"
                )

                try Expect.equal(
                    resolved[2].changedByContinuity,
                    true,
                    "temporal-coherence.correction-provenance"
                )

                try Expect.equal(
                    resolved[2].resolvedConfidence == nil,
                    true,
                    "temporal-coherence.corrected-confidence-unclaimed"
                )

                try Expect.equal(
                    abs(
                        resolved[2].acousticEvidenceStrength
                            - 0.08
                    ) < 1e-12,
                    true,
                    "temporal-coherence.acoustic-evidence-strength-retained"
                )
            }

            Step("low-reliability acoustic flips yield more authority to continuity") {
                let speaker1 = SpeakerID(
                    rawValue: "speaker_1"
                )
                let speaker2 = SpeakerID(
                    rawValue: "speaker_2"
                )

                let observations = (0..<3).map {
                    temporalObservation(
                        id: $0,
                        start: Double($0) * 0.4
                    )
                }

                let reliable = [
                    temporalAssignment(
                        id: 0,
                        acousticSpeaker: speaker2,
                        speaker1: speaker1,
                        speaker2: speaker2,
                        speaker1Cost: 1,
                        speaker2Cost: 0.1,
                        confidence: 0.9
                    ),
                    temporalAssignment(
                        id: 1,
                        acousticSpeaker: speaker1,
                        speaker1: speaker1,
                        speaker2: speaker2,
                        speaker1Cost: 0.1,
                        speaker2Cost: 1,
                        confidence: 0.9
                    ),
                    temporalAssignment(
                        id: 2,
                        acousticSpeaker: speaker2,
                        speaker1: speaker1,
                        speaker2: speaker2,
                        speaker1Cost: 1,
                        speaker2Cost: 0.1,
                        confidence: 0.9
                    )
                ]

                let unreliable = reliable.enumerated().map {
                    index,
                    assignment in

                    SpeakerObservationAssignment(
                        observationID: assignment.observationID,
                        acousticSpeaker: assignment.acousticSpeaker,
                        acousticConfidence: assignment.acousticConfidence,
                        reliability: index == 1 ? 0.1 : 1,
                        candidates: assignment.candidates
                    )
                }

                let resolver = SpeakerTemporalCoherence()
                let reliableResolved = resolver.resolve(
                    observations: observations,
                    assignments: reliable
                )
                let unreliableResolved = resolver.resolve(
                    observations: observations,
                    assignments: unreliable
                )

                try Expect.equal(
                    reliableResolved[1].resolvedSpeaker,
                    speaker1,
                    "temporal-coherence.reliable-flip-survives"
                )

                try Expect.equal(
                    unreliableResolved[1].resolvedSpeaker,
                    speaker2,
                    "temporal-coherence.unreliable-flip-resolved"
                )
            }

            Step("clean short reply survives surrounding continuity") {
                let speaker1 = SpeakerID(
                    rawValue: "speaker_1"
                )
                let speaker2 = SpeakerID(
                    rawValue: "speaker_2"
                )

                let observations = (0..<3).map {
                    temporalObservation(
                        id: $0,
                        start: Double($0) * 0.4
                    )
                }

                let assignments = [
                    temporalAssignment(
                        id: 0,
                        acousticSpeaker: speaker2,
                        speaker1: speaker1,
                        speaker2: speaker2,
                        speaker1Cost: 1,
                        speaker2Cost: 0.1,
                        confidence: 0.9
                    ),
                    temporalAssignment(
                        id: 1,
                        acousticSpeaker: speaker1,
                        speaker1: speaker1,
                        speaker2: speaker2,
                        speaker1Cost: 0.45,
                        speaker2Cost: 1,
                        confidence: 0.55
                    ),
                    temporalAssignment(
                        id: 2,
                        acousticSpeaker: speaker2,
                        speaker1: speaker1,
                        speaker2: speaker2,
                        speaker1Cost: 1,
                        speaker2Cost: 0.1,
                        confidence: 0.9
                    ),
                ]

                let resolved = SpeakerTemporalCoherence().resolve(
                    observations: observations,
                    assignments: assignments
                )

                try Expect.equal(
                    resolved[1].resolvedSpeaker,
                    speaker1,
                    "temporal-coherence.clean-short-reply-survives"
                )

                try Expect.equal(
                    resolved[1].changedByContinuity,
                    false,
                    "temporal-coherence.clean-short-reply-unchanged"
                )

                try Expect.equal(
                    abs(
                        (
                            resolved[1].resolvedConfidence
                                ?? 0
                        ) - 0.55
                    ) < 1e-12,
                    true,
                    "temporal-coherence.clean-short-reply-confidence"
                )
            }

            Step("moderate onset of sustained turn keeps its acoustic boundary") {
                let speaker1 = SpeakerID(
                    rawValue: "speaker_1"
                )
                let speaker2 = SpeakerID(
                    rawValue: "speaker_2"
                )

                let observations = (0..<4).map {
                    temporalObservation(
                        id: $0,
                        start: Double($0) * 0.4
                    )
                }

                let assignments = [
                    temporalAssignment(
                        id: 0,
                        acousticSpeaker: speaker2,
                        speaker1: speaker1,
                        speaker2: speaker2,
                        speaker1Cost: 1,
                        speaker2Cost: 0.1,
                        confidence: 0.9
                    ),
                    temporalAssignment(
                        id: 1,
                        acousticSpeaker: speaker2,
                        speaker1: speaker1,
                        speaker2: speaker2,
                        speaker1Cost: 1,
                        speaker2Cost: 0.1,
                        confidence: 0.9
                    ),
                    temporalAssignment(
                        id: 2,
                        acousticSpeaker: speaker1,
                        speaker1: speaker1,
                        speaker2: speaker2,
                        speaker1Cost: 0.65,
                        speaker2Cost: 1,
                        confidence: 0.35
                    ),
                    temporalAssignment(
                        id: 3,
                        acousticSpeaker: speaker1,
                        speaker1: speaker1,
                        speaker2: speaker2,
                        speaker1Cost: 0.1,
                        speaker2Cost: 1,
                        confidence: 0.9
                    ),
                ]

                let resolved = SpeakerTemporalCoherence().resolve(
                    observations: observations,
                    assignments: assignments
                )

                try Expect.equal(
                    resolved.map(
                        \.resolvedSpeaker
                    ),
                    assignments.map(
                        \.acousticSpeaker
                    ),
                    "temporal-coherence.moderate-turn-boundary-retained"
                )
            }

            Step("strong sustained speaker transition survives continuity") {
                let speaker1 = SpeakerID(
                    rawValue: "speaker_1"
                )
                let speaker2 = SpeakerID(
                    rawValue: "speaker_2"
                )

                let observations = (0..<5).map {
                    temporalObservation(
                        id: $0,
                        start: Double($0) * 0.4
                    )
                }

                let acousticSpeakers = [
                    speaker2,
                    speaker2,
                    speaker1,
                    speaker1,
                    speaker1,
                ]

                let assignments = acousticSpeakers.enumerated().map {
                    index,
                    speaker in

                    temporalAssignment(
                        id: index,
                        acousticSpeaker: speaker,
                        speaker1: speaker1,
                        speaker2: speaker2,
                        speaker1Cost: speaker == speaker1 ? 0.1 : 1,
                        speaker2Cost: speaker == speaker2 ? 0.1 : 1,
                        confidence: 0.9
                    )
                }

                let resolved = SpeakerTemporalCoherence().resolve(
                    observations: observations,
                    assignments: assignments
                )

                try Expect.equal(
                    resolved.map(
                        \.resolvedSpeaker
                    ),
                    acousticSpeakers,
                    "temporal-coherence.strong-transition-retained"
                )

                try Expect.equal(
                    resolved.contains {
                        $0.changedByContinuity
                    },
                    false,
                    "temporal-coherence.strong-transition-unchanged"
                )
            }

            Step("large temporal gap removes continuity preference") {
                let speaker1 = SpeakerID(
                    rawValue: "speaker_1"
                )
                let speaker2 = SpeakerID(
                    rawValue: "speaker_2"
                )

                let observations = [
                    temporalObservation(
                        id: 0,
                        start: 0
                    ),
                    temporalObservation(
                        id: 1,
                        start: 1.5
                    )
                ]

                let assignments = [
                    temporalAssignment(
                        id: 0,
                        acousticSpeaker: speaker2,
                        speaker1: speaker1,
                        speaker2: speaker2,
                        speaker1Cost: 1,
                        speaker2Cost: 0.1,
                        confidence: 0.9
                    ),
                    temporalAssignment(
                        id: 1,
                        acousticSpeaker: speaker1,
                        speaker1: speaker1,
                        speaker2: speaker2,
                        speaker1Cost: 0.75,
                        speaker2Cost: 1,
                        confidence: 0.25
                    )
                ]

                let resolved = SpeakerTemporalCoherence().resolve(
                    observations: observations,
                    assignments: assignments
                )

                try Expect.equal(
                    resolved[1].resolvedSpeaker,
                    speaker1,
                    "temporal-coherence.gap-allows-switch"
                )
            }

            Step("several moderate observations can accumulate into a real turn") {
                let speaker1 = SpeakerID(
                    rawValue: "speaker_1"
                )
                let speaker2 = SpeakerID(
                    rawValue: "speaker_2"
                )

                let observations = (0..<5).map {
                    temporalObservation(
                        id: $0,
                        start: Double($0) * 0.4
                    )
                }

                let assignments = [
                    temporalAssignment(
                        id: 0,
                        acousticSpeaker: speaker2,
                        speaker1: speaker1,
                        speaker2: speaker2,
                        speaker1Cost: 1,
                        speaker2Cost: 0.1,
                        confidence: 0.9
                    ),
                    temporalAssignment(
                        id: 1,
                        acousticSpeaker: speaker2,
                        speaker1: speaker1,
                        speaker2: speaker2,
                        speaker1Cost: 1,
                        speaker2Cost: 0.1,
                        confidence: 0.9
                    ),
                    temporalAssignment(
                        id: 2,
                        acousticSpeaker: speaker1,
                        speaker1: speaker1,
                        speaker2: speaker2,
                        speaker1Cost: 0.75,
                        speaker2Cost: 1,
                        confidence: 0.25
                    ),
                    temporalAssignment(
                        id: 3,
                        acousticSpeaker: speaker1,
                        speaker1: speaker1,
                        speaker2: speaker2,
                        speaker1Cost: 0.75,
                        speaker2Cost: 1,
                        confidence: 0.25
                    ),
                    temporalAssignment(
                        id: 4,
                        acousticSpeaker: speaker1,
                        speaker1: speaker1,
                        speaker2: speaker2,
                        speaker1Cost: 0.75,
                        speaker2Cost: 1,
                        confidence: 0.25
                    )
                ]

                let resolved = SpeakerTemporalCoherence().resolve(
                    observations: observations,
                    assignments: assignments
                )

                try Expect.equal(
                    Array(
                        resolved.suffix(3).map(
                            \.resolvedSpeaker
                        )
                    ),
                    Array(
                        repeating: speaker1,
                        count: 3
                    ),
                    "temporal-coherence.moderate-run-establishes-turn"
                )
            }

            Step("diarization retains acoustic and resolved assignment evidence") {
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
                            maximumDurationSeconds: 1,
                            maximumGapSeconds: 0.08
                        )
                    )
                )

                try Expect.equal(
                    result.assignments.count,
                    result.observations.count,
                    "temporal-coherence.assignments-retained"
                )

                try Expect.equal(
                    zip(
                        result.observations,
                        result.assignments
                    ).allSatisfy {
                        $0.0.id == $0.1.observationID
                            && $0.1.candidates.count == 2
                    },
                    true,
                    "temporal-coherence.assignment-provenance"
                )

                try Expect.equal(
                    result.assignments.allSatisfy {
                        $0.acousticEvidenceStrength >= 0
                            && $0.acousticEvidenceStrength <= 1
                            && (
                                !$0.changedByContinuity
                                    || $0.resolvedConfidence == nil
                            )
                    },
                    true,
                    "temporal-coherence.confidence-provenance"
                )
            }
        }
    }
}

private func temporalObservation(
    id: Int,
    start: Double,
    duration: Double = 0.4
) -> SpeakerObservation {
    .init(
        id: .init(
            rawValue: id
        ),
        range: .init(
            start: start,
            duration: duration
        ),
        acousticObservationIDs: [],
        features: .init([
            Double(id),
        ]),
        qualityScore: 1
    )
}

private func temporalAssignment(
    id: Int,
    acousticSpeaker: SpeakerID,
    speaker1: SpeakerID,
    speaker2: SpeakerID,
    speaker1Cost: Double,
    speaker2Cost: Double,
    confidence: Double,
    reliability: Double = 1
) -> SpeakerObservationAssignment {
    .init(
        observationID: .init(
            rawValue: id
        ),
        acousticSpeaker: acousticSpeaker,
        acousticConfidence: confidence,
        reliability: reliability,
        candidates: [
            .init(
                speaker: speaker1,
                acousticCost: speaker1Cost
            ),
            .init(
                speaker: speaker2,
                acousticCost: speaker2Cost
            )
        ]
    )
}
