import Foundation
import MediaCore

public struct SpeakerEmbeddingWindow:
    Sendable,
    Codable,
    Hashable
{
    public let observationID: SpeakerObservationID
    public let range: Audio.TimeRange

    public init(
        observationID: SpeakerObservationID,
        range: Audio.TimeRange
    ) {
        self.observationID = observationID
        self.range = range
    }
}

public struct SpeakerEmbeddingRequest: Sendable {
    /// Source audio from which the requested speaker windows should be embedded.
    public let audio: MediaAudioBuffer

    /// Absolute timeline position corresponding to the first frame in `audio`.
    public let startingAt: TimeInterval

    /// Semantic speaker-observation windows requested from this source audio.
    public let windows: [SpeakerEmbeddingWindow]

    public init(
        audio: MediaAudioBuffer,
        startingAt: TimeInterval = 0,
        windows: [SpeakerEmbeddingWindow]
    ) {
        self.audio = audio
        self.startingAt = startingAt
        self.windows = windows
    }
}

public struct SpeakerEmbeddingBatch: Sendable {
    public let embeddings: [SpeakerObservationID: SpeakerEmbedding]

    public init(
        embeddings: [SpeakerObservationID: SpeakerEmbedding]
    ) {
        self.embeddings = embeddings
    }

    public var count: Int {
        embeddings.count
    }

    public subscript(
        observationID: SpeakerObservationID
    ) -> SpeakerEmbedding? {
        embeddings[observationID]
    }

    public static let empty = Self(
        embeddings: [:]
    )
}

public protocol SpeakerEmbeddingProvider: Sendable {
    /// Produces speaker-identity embeddings for any subset of the requested
    /// semantic observation windows. Absence from the returned batch means
    /// the provider produced no embedding for that observation.
    func embeddings(
        for request: SpeakerEmbeddingRequest
    ) async throws -> SpeakerEmbeddingBatch
}

public struct SpeakerEmbeddingEnricher: Sendable {
    public init() {}

    public func enrich(
        _ observations: [SpeakerObservation],
        audio: MediaAudioBuffer,
        startingAt: TimeInterval = 0,
        using provider: any SpeakerEmbeddingProvider
    ) async throws -> [SpeakerObservation] {
        guard !observations.isEmpty else {
            return observations
        }

        let request = SpeakerEmbeddingRequest(
            audio: audio,
            startingAt: startingAt,
            windows: observations.map {
                .init(
                    observationID: $0.id,
                    range: $0.range
                )
            }
        )

        let batch = try await provider.embeddings(
            for: request
        )

        return observations.map { observation in
            guard let embedding = batch[observation.id] else {
                return observation
            }

            return observation.replacingEmbedding(
                embedding
            )
        }
    }
}

public extension SpeakerObservation {
    func replacingEmbedding(
        _ embedding: SpeakerEmbedding?
    ) -> Self {
        .init(
            id: id,
            range: range,
            acousticObservationIDs: acousticObservationIDs,
            features: features,
            qualityScore: qualityScore,
            embedding: embedding,
            viewAgreement: viewAgreement
        )
    }
}
