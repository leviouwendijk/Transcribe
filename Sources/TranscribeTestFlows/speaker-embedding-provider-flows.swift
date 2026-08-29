import Diarization
import MediaCore
import TestFlows

extension TranscribeFlowSuite {
    static var speakerEmbeddingProviderFlow: TestFlow {
        TestFlow(
            "speaker-embedding-provider",
            tags: [
                "diarization",
                "embedding",
                "provider",
                "speaker",
            ]
        ) {
            Step("provider receives source audio and semantic observation windows") {
                let observations = fixtureSpeakerObservations()
                let audio = AudioTestFixture.buffer(
                    samples: AudioTestFixture.sine(
                        frequency: 180,
                        duration: 1
                    )
                )

                let enriched = try await SpeakerEmbeddingEnricher().enrich(
                    observations,
                    audio: audio,
                    startingAt: 12,
                    using: FixtureSpeakerEmbeddingProvider()
                )

                try Expect.equal(
                    enriched.map(\.id),
                    observations.map(\.id),
                    "speaker-embedding-provider.identity-preserved"
                )
                try Expect.equal(
                    enriched.map(\.range),
                    observations.map(\.range),
                    "speaker-embedding-provider.ranges-preserved"
                )
                try Expect.equal(
                    enriched.compactMap(\.embedding).count,
                    2,
                    "speaker-embedding-provider.embeddings-attached"
                )
                try Expect.equal(
                    enriched.first?.embedding?.provenance?.providerIdentifier,
                    "fixture",
                    "speaker-embedding-provider.provider-provenance"
                )
                try Expect.equal(
                    enriched.first?.embedding?.provenance?.modelIdentifier,
                    "fixture-speaker-model",
                    "speaker-embedding-provider.model-provenance"
                )
            }

            Step("partial provider output remains partial evidence") {
                let observations = fixtureSpeakerObservations()
                let audio = AudioTestFixture.buffer(
                    samples: AudioTestFixture.sine(
                        frequency: 180,
                        duration: 1
                    )
                )

                let enriched = try await SpeakerEmbeddingEnricher().enrich(
                    observations,
                    audio: audio,
                    startingAt: 12,
                    using: PartialFixtureSpeakerEmbeddingProvider()
                )

                try Expect.equal(
                    enriched[0].embedding != nil,
                    true,
                    "speaker-embedding-provider.partial-present"
                )
                try Expect.equal(
                    enriched[1].embedding == nil,
                    true,
                    "speaker-embedding-provider.partial-absence-retained"
                )
            }

            Step("enrichment preserves previously retained embedding when provider has no replacement") {
                let existing = SpeakerEmbedding(
                    [1, 0],
                    provenance: .init(
                        providerIdentifier: "existing",
                        modelIdentifier: "existing-model"
                    )
                )

                let observations = fixtureSpeakerObservations().enumerated().map {
                    index,
                    observation in

                    index == 1
                        ? observation.replacingEmbedding(existing)
                        : observation
                }

                let audio = AudioTestFixture.buffer(
                    samples: AudioTestFixture.sine(
                        frequency: 180,
                        duration: 1
                    )
                )

                let enriched = try await SpeakerEmbeddingEnricher().enrich(
                    observations,
                    audio: audio,
                    startingAt: 12,
                    using: PartialFixtureSpeakerEmbeddingProvider()
                )

                try Expect.equal(
                    enriched[1].embedding,
                    existing,
                    "speaker-embedding-provider.existing-evidence-preserved"
                )
            }
        }
    }
}

private struct FixtureSpeakerEmbeddingProvider:
    SpeakerEmbeddingProvider
{
    func embeddings(
        for request: SpeakerEmbeddingRequest
    ) async throws -> SpeakerEmbeddingBatch {
        guard request.startingAt == 12,
              request.windows.count == 2,
              request.windows[0].range.start == 12,
              request.windows[1].range.start == 12.5 else {
            throw SpeakerEmbeddingProviderFlowError.unexpectedRequest
        }

        return .init(
            embeddings: Dictionary(
                uniqueKeysWithValues: request.windows.map { window in
                    (
                        window.observationID,
                        SpeakerEmbedding(
                            [
                                Float(window.observationID.rawValue + 1),
                                1,
                            ],
                            provenance: .init(
                                providerIdentifier: "fixture",
                                modelIdentifier: "fixture-speaker-model"
                            )
                        )
                    )
                }
            )
        )
    }
}

private struct PartialFixtureSpeakerEmbeddingProvider:
    SpeakerEmbeddingProvider
{
    func embeddings(
        for request: SpeakerEmbeddingRequest
    ) async throws -> SpeakerEmbeddingBatch {
        guard let first = request.windows.first else {
            return .empty
        }

        return .init(
            embeddings: [
                first.observationID: .init(
                    [1, 0],
                    provenance: .init(
                        providerIdentifier: "partial-fixture",
                        modelIdentifier: "fixture-speaker-model"
                    )
                ),
            ]
        )
    }
}

private func fixtureSpeakerObservations() -> [SpeakerObservation] {
    [
        .init(
            id: .init(
                rawValue: 0
            ),
            range: .init(
                start: 12,
                duration: 0.4
            ),
            acousticObservationIDs: [],
            features: .init(
                [1, 2]
            ),
            qualityScore: 1
        ),
        .init(
            id: .init(
                rawValue: 1
            ),
            range: .init(
                start: 12.5,
                duration: 0.4
            ),
            acousticObservationIDs: [],
            features: .init(
                [3, 4]
            ),
            qualityScore: 1
        ),
    ]
}

private enum SpeakerEmbeddingProviderFlowError:
    Error,
    Sendable
{
    case unexpectedRequest
}
