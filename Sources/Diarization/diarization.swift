import Foundation
import MediaCore

public struct SpeakerID:
    RawRepresentable,
    Sendable,
    Codable,
    Hashable
{
    public let rawValue: String

    public init(
        rawValue: String
    ) {
        self.rawValue = rawValue
    }
}

public struct SpeakerEmbedding:
    Sendable,
    Codable,
    Hashable
{
    public let values: [Float]

    public init(
        _ values: [Float]
    ) {
        self.values = values
    }
}

public struct SpeakerFeatureVector:
    Sendable,
    Codable,
    Hashable
{
    public let values: [Double]

    public init(
        _ values: [Double]
    ) {
        self.values = values
    }
}

public struct SpeakerProfile:
    Sendable,
    Codable,
    Hashable
{
    public let speaker: SpeakerID
    public let observationCount: Int
    public let observedDurationSeconds: TimeInterval
    public let acousticCentroid: SpeakerFeatureVector?
    public let acousticDispersion: SpeakerFeatureVector?
    public let embeddingCentroid: SpeakerEmbedding?
    public let embeddingDispersion: SpeakerEmbedding?

    public init(
        speaker: SpeakerID,
        observationCount: Int,
        observedDurationSeconds: TimeInterval,
        acousticCentroid: SpeakerFeatureVector? = nil,
        acousticDispersion: SpeakerFeatureVector? = nil,
        embeddingCentroid: SpeakerEmbedding? = nil,
        embeddingDispersion: SpeakerEmbedding? = nil
    ) {
        self.speaker = speaker
        self.observationCount = observationCount
        self.observedDurationSeconds = observedDurationSeconds
        self.acousticCentroid = acousticCentroid
        self.acousticDispersion = acousticDispersion
        self.embeddingCentroid = embeddingCentroid
        self.embeddingDispersion = embeddingDispersion
    }
}

public struct SpeakerSegment:
    Sendable,
    Codable,
    Hashable
{
    public let range: Audio.TimeRange
    public let speaker: SpeakerID
    public let confidence: Double?
    public let observationIDs: [SpeakerObservationID]

    public init(
        range: Audio.TimeRange,
        speaker: SpeakerID,
        confidence: Double? = nil,
        observationIDs: [SpeakerObservationID] = []
    ) {
        self.range = range
        self.speaker = speaker
        self.confidence = confidence
        self.observationIDs = observationIDs
    }
}

public struct DiarizationResult:
    Sendable,
    Codable,
    Hashable
{
    public let segments: [SpeakerSegment]
    public let profiles: [SpeakerProfile]
    public let observations: [SpeakerObservation]

    public init(
        segments: [SpeakerSegment],
        profiles: [SpeakerProfile] = [],
        observations: [SpeakerObservation] = []
    ) {
        self.segments = segments
        self.profiles = profiles
        self.observations = observations
    }

    public var speakers: [SpeakerID] {
        var speakers = Set(
            segments.map(
                \.speaker
            )
        )

        speakers.formUnion(
            profiles.map(
                \.speaker
            )
        )

        return speakers.sorted {
            $0.rawValue < $1.rawValue
        }
    }
}
