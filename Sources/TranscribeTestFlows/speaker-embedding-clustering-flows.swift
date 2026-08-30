import Diarization
import MediaCore
import TestFlows

extension TranscribeFlowSuite {
    static var speakerEmbeddingClusteringFlow: TestFlow {
        TestFlow(
            "speaker-embedding-clustering",
            tags: [
                "clustering",
                "diarization",
                "embedding",
                "replay",
                "speaker",
            ]
        ) {
            Step("embedding replay clusters retained identity vectors with cosine geometry") {
                let source = embeddingReplayFixture()

                guard let replay = Diarizer().replay(
                    source,
                    clusteringRepresentation: .embedding
                ) else {
                    throw SpeakerEmbeddingClusteringFlowError.replayMissing
                }

                try Expect.equal(
                    replay.method?.clusteringRepresentation,
                    .embedding,
                    "speaker-embedding-clustering.representation"
                )
                try Expect.equal(
                    replay.method?.clustering?.distanceMetric,
                    .cosine,
                    "speaker-embedding-clustering.metric"
                )
                try Expect.equal(
                    replay.method?.featureSpace,
                    [],
                    "speaker-embedding-clustering.no-acoustic-feature-space"
                )
                try Expect.equal(
                    replay.method?.standardization,
                    .empty,
                    "speaker-embedding-clustering.no-acoustic-standardization"
                )
                try Expect.equal(
                    replay.assignments.allSatisfy {
                        $0.clusteringRepresentation == .embedding
                    },
                    true,
                    "speaker-embedding-clustering.assignment-representation"
                )
                try Expect.equal(
                    replay.assignments[0].clusteringSpeaker,
                    replay.assignments[1].clusteringSpeaker,
                    "speaker-embedding-clustering.first-identity-cluster"
                )
                try Expect.equal(
                    replay.assignments[2].clusteringSpeaker,
                    replay.assignments[3].clusteringSpeaker,
                    "speaker-embedding-clustering.second-identity-cluster"
                )
                try Expect.equal(
                    replay.assignments[0].clusteringSpeaker
                        != replay.assignments[2].clusteringSpeaker,
                    true,
                    "speaker-embedding-clustering.identities-separated"
                )
                try Expect.equal(
                    replay.assignments.flatMap(\.candidates).allSatisfy {
                        $0.clusteringRepresentation == .embedding
                            && $0.featureContributions.isEmpty
                    },
                    true,
                    "speaker-embedding-clustering.embedding-candidate-provenance"
                )
                try Expect.equal(
                    replay.profiles.allSatisfy {
                        $0.embeddingProfile != nil
                    },
                    true,
                    "speaker-embedding-clustering.embedding-profiles"
                )

                let acousticReplay = Diarizer().replay(
                    source
                )

                try Expect.equal(
                    acousticReplay.method?.clusteringRepresentation,
                    .acoustic,
                    "speaker-embedding-clustering.default-replay-remains-acoustic"
                )
            }

            Step("embedding replay requires complete compatible embedding evidence") {
                let source = embeddingReplayFixture(
                    omittingLastEmbedding: true
                )

                try Expect.equal(
                    Diarizer().replay(
                        source,
                        clusteringRepresentation: .embedding
                    ),
                    nil,
                    "speaker-embedding-clustering.incomplete-evidence-rejected"
                )
            }
        }
    }
}

private func embeddingReplayFixture(
    omittingLastEmbedding: Bool = false
) -> DiarizationResult {
    let embeddings: [[Float]] = [
        [1, 0],
        [0.99, 0.01],
        [0, 1],
        [0.01, 0.99],
    ]

    let observations = embeddings.enumerated().map {
        index,
        values in

        SpeakerObservation(
            id: .init(
                rawValue: index
            ),
            range: .init(
                start: Double(index) * 0.5,
                duration: 0.4
            ),
            acousticObservationIDs: [],
            features: .init(
                [
                    Double(index),
                    Double(index % 2),
                ]
            ),
            qualityScore: 1,
            embedding: omittingLastEmbedding
                && index == embeddings.count - 1
                ? nil
                : SpeakerEmbedding(
                    values,
                    provenance: .init(
                        providerIdentifier: "fixture",
                        modelIdentifier: "fixture-speaker-model",
                        normalization: .l2
                    )
                ).l2Normalized
        )
    }

    let configuration = DiarizationConfiguration(
        expectedSpeakerCount: 2,
        temporalCoherence: .init(
            switchPenalty: 0,
            maximumContinuityGapSeconds: 0.45
        )
    )

    return .init(
        segments: [],
        observations: observations,
        assignments: [],
        method: .init(
            configuration: configuration
        ),
        acoustic: .init(
            sampleRate: 16_000,
            noiseFloorRMS: 0,
            observations: []
        )
    )
}

private enum SpeakerEmbeddingClusteringFlowError:
    Error,
    Sendable
{
    case replayMissing
}
