import Foundation
import MediaCore

public struct SpeakerObservationID:
    RawRepresentable,
    Sendable,
    Codable,
    Hashable,
    Comparable
{
    public let rawValue: Int

    public init(
        rawValue: Int
    ) {
        self.rawValue = rawValue
    }

    public static func < (
        lhs: SpeakerObservationID,
        rhs: SpeakerObservationID
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public struct SpeakerObservation:
    Sendable,
    Codable,
    Hashable
{
    public let id: SpeakerObservationID
    public let range: Audio.TimeRange
    public let acousticObservationIDs: [AcousticObservationID]
    public let features: SpeakerFeatureVector
    public let qualityScore: Double

    public init(
        id: SpeakerObservationID,
        range: Audio.TimeRange,
        acousticObservationIDs: [AcousticObservationID],
        features: SpeakerFeatureVector,
        qualityScore: Double
    ) {
        self.id = id
        self.range = range
        self.acousticObservationIDs = acousticObservationIDs
        self.features = features
        self.qualityScore = qualityScore
    }
}
