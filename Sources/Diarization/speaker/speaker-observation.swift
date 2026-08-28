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

public struct SpeakerFeatureWeights:
    Sendable,
    Codable,
    Hashable
{
    public let mfcc: Double
    public let logMel: Double
    public let pitch: Double
    public let spectral: Double
    public let dynamics: Double
    public let consistency: Double
    public let quality: Double
    public let enhancedView: Double

    public init(
        mfcc: Double = 1,
        logMel: Double = 0.75,
        pitch: Double = 0.65,
        spectral: Double = 0.45,
        dynamics: Double = 0.15,
        consistency: Double = 0.35,
        quality: Double = 0.25,
        enhancedView: Double = 0.45
    ) {
        self.mfcc = max(0, mfcc)
        self.logMel = max(0, logMel)
        self.pitch = max(0, pitch)
        self.spectral = max(0, spectral)
        self.dynamics = max(0, dynamics)
        self.consistency = max(0, consistency)
        self.quality = max(0, quality)
        self.enhancedView = max(0, enhancedView)
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
    public let viewAgreement: AcousticViewAgreement?

    public init(
        id: SpeakerObservationID,
        range: Audio.TimeRange,
        acousticObservationIDs: [AcousticObservationID],
        features: SpeakerFeatureVector,
        qualityScore: Double,
        viewAgreement: AcousticViewAgreement? = nil
    ) {
        self.id = id
        self.range = range
        self.acousticObservationIDs = acousticObservationIDs
        self.features = features
        self.qualityScore = qualityScore
        self.viewAgreement = viewAgreement
    }
}
