import Diarization
import MediaCore
import TestFlows

extension TranscribeFlowSuite {
    static var speakerEmbeddingFlow: TestFlow {
        TestFlow(
            "speaker-embedding-semantics",
            tags: [
                "clustering",
                "diarization",
                "embedding",
                "speaker",
            ]
        ) {
            Step("speaker embeddings retain normalization provenance and cosine identity distance") {
                let provenance = SpeakerEmbeddingProvenance(
                    modelIdentifier: "fixture-speaker-model"
                )
                let source = SpeakerEmbedding(
                    [3, 4],
                    provenance: provenance
                )

                guard let normalized = source.l2Normalized else {
                    throw SpeakerEmbeddingFlowError.normalizationFailed
                }

                try Expect.equal(
                    abs(normalized.l2Norm - 1) < 1e-6,
                    true,
                    "speaker-embedding.unit-norm"
                )
                try Expect.equal(
                    normalized.provenance?.modelIdentifier,
                    "fixture-speaker-model",
                    "speaker-embedding.model-provenance"
                )
                try Expect.equal(
                    normalized.provenance?.normalization,
                    .l2,
                    "speaker-embedding.normalization-provenance"
                )

                guard let horizontal = SpeakerEmbedding([1, 0]).l2Normalized,
                      let vertical = SpeakerEmbedding([0, 1]).l2Normalized,
                      let identical = SpeakerEmbeddingDistance(
                          horizontal,
                          horizontal
                      ),
                      let orthogonal = SpeakerEmbeddingDistance(
                          horizontal,
                          vertical
                      ) else {
                    throw SpeakerEmbeddingFlowError.distanceFailed
                }

                try Expect.equal(
                    abs(identical.cosineDistance) < 1e-12,
                    true,
                    "speaker-embedding.identical-distance"
                )
                try Expect.equal(
                    abs(orthogonal.cosineDistance - 1) < 1e-12,
                    true,
                    "speaker-embedding.orthogonal-distance"
                )
            }

            Step("embedding profiles retain centroid dispersion and evidence count") {
                let provenance = SpeakerEmbeddingProvenance(
                    modelIdentifier: "fixture-speaker-model",
                    normalization: .l2
                )
                let embeddings = [
                    SpeakerEmbedding(
                        [1, 0],
                        provenance: provenance
                    ),
                    SpeakerEmbedding(
                        [1, 0],
                        provenance: provenance
                    ),
                ]

                guard let profile = SpeakerEmbeddingProfile(
                    embeddings: embeddings
                ) else {
                    throw SpeakerEmbeddingFlowError.profileFailed
                }

                try Expect.equal(
                    profile.evidenceCount,
                    2,
                    "speaker-embedding.profile-evidence-count"
                )
                try Expect.equal(
                    abs(profile.centroid.l2Norm - 1) < 1e-6,
                    true,
                    "speaker-embedding.profile-centroid-normalized"
                )
                try Expect.equal(
                    abs(profile.dispersion) < 1e-12,
                    true,
                    "speaker-embedding.profile-dispersion"
                )

                let speakerProfile = SpeakerProfile(
                    speaker: .init(
                        rawValue: "speaker_1"
                    ),
                    observationCount: 2,
                    observedDurationSeconds: 2,
                    embeddingProfile: profile
                )

                try Expect.equal(
                    speakerProfile.embeddingProfile,
                    profile,
                    "speaker-embedding.profile-retained"
                )
            }

            Step("speaker observations expose acoustic embedding and hybrid evidence while production remains acoustic") {
                guard let embedding = SpeakerEmbedding(
                    [1, 0],
                    provenance: .init(
                        modelIdentifier: "fixture-speaker-model"
                    )
                ).l2Normalized else {
                    throw SpeakerEmbeddingFlowError.normalizationFailed
                }

                let observation = SpeakerObservation(
                    id: .init(
                        rawValue: 0
                    ),
                    range: .init(
                        start: 0,
                        duration: 1
                    ),
                    acousticObservationIDs: [],
                    features: .init(
                        [1, 2]
                    ),
                    qualityScore: 1,
                    embedding: embedding
                )

                try Expect.equal(
                    observation.clusteringEvidence(
                        for: .acoustic
                    ) != nil,
                    true,
                    "speaker-embedding.acoustic-evidence"
                )
                try Expect.equal(
                    observation.clusteringEvidence(
                        for: .embedding
                    ) != nil,
                    true,
                    "speaker-embedding.embedding-evidence"
                )
                try Expect.equal(
                    observation.clusteringEvidence(
                        for: .hybrid
                    ) != nil,
                    true,
                    "speaker-embedding.hybrid-evidence"
                )

                let acousticOnly = SpeakerObservation(
                    id: .init(
                        rawValue: 1
                    ),
                    range: .init(
                        start: 1,
                        duration: 1
                    ),
                    acousticObservationIDs: [],
                    features: .init(
                        [1, 2]
                    ),
                    qualityScore: 1
                )

                try Expect.equal(
                    acousticOnly.clusteringEvidence(
                        for: .embedding
                    ) == nil,
                    true,
                    "speaker-embedding.missing-embedding-not-invented"
                )

                let result = try Diarizer().diarize(
                    AudioTestFixture.buffer(
                        samples: AudioTestFixture.sine(
                            frequency: 180,
                            duration: 0.8
                        )
                    ),
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
                    result.method?.clusteringRepresentation,
                    .acoustic,
                    "speaker-embedding.production-remains-acoustic"
                )
                try Expect.equal(
                    result.observations.allSatisfy {
                        $0.embedding == nil
                    },
                    true,
                    "speaker-embedding.production-does-not-invent-embeddings"
                )
            }
        }
    }
}

private enum SpeakerEmbeddingFlowError:
    Error,
    Sendable
{
    case normalizationFailed
    case distanceFailed
    case profileFailed
}
