import Diarization
import MediaCore
import TestFlows

extension TranscribeFlowSuite {
    static var speakerHybridClusteringFlow: TestFlow {
        TestFlow(
            "speaker-hybrid-clustering",
            tags: [
                "acoustic",
                "clustering",
                "embedding",
                "hybrid",
                "replay",
                "speaker",
            ]
        ) {
            Step("hybrid endpoints reproduce established acoustic and embedding interpretations") {
                let diarizer = Diarizer()
                let acoustic = diarizer.replay(
                    embeddingReplayFixture()
                )

                guard let embedding = diarizer.replay(
                    acoustic,
                    clusteringRepresentation: .embedding
                ),
                      let acousticEndpoint = diarizer.replay(
                        acoustic,
                        clusteringRepresentation: .hybrid,
                        hybridWeights: .init(
                            acoustic: 1,
                            embedding: 0
                        )
                      ),
                      let embeddingEndpoint = diarizer.replay(
                        acoustic,
                        clusteringRepresentation: .hybrid,
                        hybridWeights: .init(
                            acoustic: 0,
                            embedding: 1
                        )
                      ) else {
                    throw SpeakerHybridClusteringFlowError.replayMissing
                }

                try Expect.equal(
                    acousticEndpoint.assignments.map(\.clusteringSpeaker),
                    acoustic.assignments.map(\.clusteringSpeaker),
                    "speaker-hybrid-clustering.acoustic-endpoint-clustering"
                )
                try Expect.equal(
                    acousticEndpoint.assignments.map(\.resolvedSpeaker),
                    acoustic.assignments.map(\.resolvedSpeaker),
                    "speaker-hybrid-clustering.acoustic-endpoint-resolved"
                )
                try Expect.equal(
                    embeddingEndpoint.assignments.map(\.clusteringSpeaker),
                    embedding.assignments.map(\.clusteringSpeaker),
                    "speaker-hybrid-clustering.embedding-endpoint-clustering"
                )
                try Expect.equal(
                    embeddingEndpoint.assignments.map(\.resolvedSpeaker),
                    embedding.assignments.map(\.resolvedSpeaker),
                    "speaker-hybrid-clustering.embedding-endpoint-resolved"
                )
            }

            Step("hybrid replay retains normalized authority and fused candidate provenance") {
                let diarizer = Diarizer()
                let acoustic = diarizer.replay(
                    embeddingReplayFixture()
                )

                guard let hybrid = diarizer.replay(
                    acoustic,
                    clusteringRepresentation: .hybrid,
                    hybridWeights: .init(
                        acoustic: 35,
                        embedding: 65
                    )
                ) else {
                    throw SpeakerHybridClusteringFlowError.replayMissing
                }

                try Expect.equal(
                    hybrid.method?.clusteringRepresentation,
                    .hybrid,
                    "speaker-hybrid-clustering.representation"
                )
                try Expect.equal(
                    hybrid.method?.hybridWeights,
                    .init(
                        acoustic: 0.35,
                        embedding: 0.65
                    ),
                    "speaker-hybrid-clustering.normalized-weights"
                )
                try Expect.equal(
                    hybrid.method?.clustering?.distanceMetric,
                    .fusedNormalizedCandidateCost,
                    "speaker-hybrid-clustering.cost-metric"
                )
                try Expect.equal(
                    hybrid.assignments.allSatisfy {
                        $0.clusteringRepresentation == .hybrid
                    },
                    true,
                    "speaker-hybrid-clustering.assignment-representation"
                )
                try Expect.equal(
                    hybrid.assignments.flatMap(\.candidates).allSatisfy {
                        $0.clusteringRepresentation == .hybrid
                            && $0.featureContributions.isEmpty
                    },
                    true,
                    "speaker-hybrid-clustering.candidate-provenance"
                )
            }

            Step("hybrid replay experiment evaluates the requested authority axis from retained evidence") {
                let diarizer = Diarizer()
                let acoustic = diarizer.replay(
                    embeddingReplayFixture()
                )
                let results = diarizer.replayHybridExperiment(
                    acoustic,
                    candidates: [
                        .init(
                            name: "100-0",
                            weights: .init(
                                acoustic: 1,
                                embedding: 0
                            )
                        ),
                        .init(
                            name: "50-50",
                            weights: .init(
                                acoustic: 0.5,
                                embedding: 0.5
                            )
                        ),
                        .init(
                            name: "0-100",
                            weights: .init(
                                acoustic: 0,
                                embedding: 1
                            )
                        ),
                    ]
                )

                try Expect.equal(
                    results.map(\.candidate.name),
                    [
                        "100-0",
                        "50-50",
                        "0-100",
                    ],
                    "speaker-hybrid-clustering.experiment-candidates"
                )
            }

            Step("comparison compaction merges nearby changes only when direction agrees") {
                let changes = [
                    speakerHybridChange(
                        id: 0,
                        start: 1.00,
                        duration: 0.40,
                        baseline: "speaker_1",
                        replay: "speaker_2"
                    ),
                    speakerHybridChange(
                        id: 1,
                        start: 1.45,
                        duration: 0.40,
                        baseline: "speaker_1",
                        replay: "speaker_2"
                    ),
                    speakerHybridChange(
                        id: 2,
                        start: 2.00,
                        duration: 0.40,
                        baseline: "speaker_2",
                        replay: "speaker_1"
                    ),
                ]
                let comparison = SpeakerDiarizationReplayComparison(
                    clusteringChanges: changes,
                    resolvedChanges: changes,
                    speakerCount: 2,
                    segmentCount: 2,
                    distanceMetric: nil,
                    reliabilityWeightedCost: nil
                )
                let spans = comparison.compactedResolvedChanges(
                    maximumGapSeconds: 0.10
                )

                try Expect.equal(
                    spans.count,
                    2,
                    "speaker-hybrid-clustering.compacted-span-count"
                )
                try Expect.equal(
                    spans[0].observationCount,
                    2,
                    "speaker-hybrid-clustering.compacted-observation-count"
                )
                try Expect.equal(
                    spans[0].baselineSpeaker.rawValue,
                    "speaker_1",
                    "speaker-hybrid-clustering.compacted-baseline-speaker"
                )
                try Expect.equal(
                    spans[0].replaySpeaker.rawValue,
                    "speaker_2",
                    "speaker-hybrid-clustering.compacted-replay-speaker"
                )
            }
        }
    }
}

private func speakerHybridChange(
    id: Int,
    start: Double,
    duration: Double,
    baseline: String,
    replay: String
) -> SpeakerDiarizationAssignmentChange {
    let observationID = SpeakerObservationID(
        rawValue: id
    )
    let baselineSpeaker = SpeakerID(
        rawValue: baseline
    )
    let replaySpeaker = SpeakerID(
        rawValue: replay
    )

    return .init(
        observationID: observationID,
        range: .init(
            start: start,
            duration: duration
        ),
        baseline: .init(
            observationID: observationID,
            acousticSpeaker: baselineSpeaker,
            resolvedSpeaker: baselineSpeaker,
            acousticConfidence: 1,
            reliability: 1,
            candidates: []
        ),
        replay: .init(
            observationID: observationID,
            acousticSpeaker: replaySpeaker,
            resolvedSpeaker: replaySpeaker,
            acousticConfidence: 1,
            reliability: 1,
            candidates: []
        )
    )
}

private enum SpeakerHybridClusteringFlowError:
    Error,
    Sendable
{
    case replayMissing
}
