import Foundation
import MediaCore

public struct AcousticObservationID:
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
        lhs: AcousticObservationID,
        rhs: AcousticObservationID
    ) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

public enum AcousticActivity:
    String,
    Sendable,
    Codable,
    Hashable
{
    case silence
    case uncertain
    case noise
    case voicedSpeech
}

public enum AcousticQualityIssue:
    String,
    Sendable,
    Codable,
    Hashable
{
    case lowEnergy
    case clipping
    case unvoiced
    case noiseLike
}

public struct AcousticSignalFeatures:
    Sendable,
    Codable,
    Hashable
{
    public let rms: Double
    public let peak: Double
    public let zeroCrossingRate: Double
    public let clippingFraction: Double

    public init(
        rms: Double,
        peak: Double,
        zeroCrossingRate: Double,
        clippingFraction: Double
    ) {
        self.rms = rms
        self.peak = peak
        self.zeroCrossingRate = zeroCrossingRate
        self.clippingFraction = clippingFraction
    }
}

public struct AcousticSpectralFeatures:
    Sendable,
    Codable,
    Hashable
{
    public let centroidHz: Double
    public let spreadHz: Double
    public let rolloffHz: Double
    public let flatness: Double
    public let pitchHz: Double?
    public let voicedProbability: Double
    public let mfcc: [Double]

    public init(
        centroidHz: Double,
        spreadHz: Double,
        rolloffHz: Double,
        flatness: Double,
        pitchHz: Double?,
        voicedProbability: Double,
        mfcc: [Double]
    ) {
        self.centroidHz = centroidHz
        self.spreadHz = spreadHz
        self.rolloffHz = rolloffHz
        self.flatness = flatness
        self.pitchHz = pitchHz
        self.voicedProbability = voicedProbability
        self.mfcc = mfcc
    }
}

public struct AcousticQuality:
    Sendable,
    Codable,
    Hashable
{
    public let score: Double
    public let isUsableForSpeakerProfile: Bool
    public let issues: [AcousticQualityIssue]

    public init(
        score: Double,
        isUsableForSpeakerProfile: Bool,
        issues: [AcousticQualityIssue]
    ) {
        self.score = score
        self.isUsableForSpeakerProfile = isUsableForSpeakerProfile
        self.issues = issues
    }
}

public struct AcousticObservation:
    Sendable,
    Codable,
    Hashable
{
    public let id: AcousticObservationID
    public let range: Audio.TimeRange
    public let signal: AcousticSignalFeatures
    public let spectral: AcousticSpectralFeatures
    public let activity: AcousticActivity
    public let quality: AcousticQuality

    public init(
        id: AcousticObservationID,
        range: Audio.TimeRange,
        signal: AcousticSignalFeatures,
        spectral: AcousticSpectralFeatures,
        activity: AcousticActivity,
        quality: AcousticQuality
    ) {
        self.id = id
        self.range = range
        self.signal = signal
        self.spectral = spectral
        self.activity = activity
        self.quality = quality
    }
}

public struct AcousticAnalysis:
    Sendable,
    Codable,
    Hashable
{
    public let sampleRate: Int
    public let noiseFloorRMS: Double
    public let observations: [AcousticObservation]

    public init(
        sampleRate: Int,
        noiseFloorRMS: Double,
        observations: [AcousticObservation]
    ) {
        self.sampleRate = sampleRate
        self.noiseFloorRMS = noiseFloorRMS
        self.observations = observations
    }

    public var usableObservations: [AcousticObservation] {
        observations.filter {
            $0.quality.isUsableForSpeakerProfile
        }
    }
}
