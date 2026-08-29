import Foundation

public enum SpeakerFeatureView:
    String,
    Sendable,
    Codable,
    Hashable
{
    case raw
    case enhanced
}

public enum SpeakerFeatureFamily:
    String,
    Sendable,
    Codable,
    Hashable
{
    case mfcc
    case logMel
    case pitch
    case spectral
    case dynamics
    case consistency
    case quality
}

public struct SpeakerFeatureCoordinate:
    Sendable,
    Codable,
    Hashable
{
    public let view: SpeakerFeatureView
    public let family: SpeakerFeatureFamily
    public let weight: Double

    public init(
        view: SpeakerFeatureView,
        family: SpeakerFeatureFamily,
        weight: Double
    ) {
        self.view = view
        self.family = family
        self.weight = max(
            0,
            weight
        )
    }
}

public struct SpeakerFeatureContribution:
    Sendable,
    Codable,
    Hashable
{
    public let view: SpeakerFeatureView
    public let family: SpeakerFeatureFamily
    public let weight: Double
    public let squaredDistance: Double
    public let fractionOfSquaredDistance: Double

    public init(
        view: SpeakerFeatureView,
        family: SpeakerFeatureFamily,
        weight: Double,
        squaredDistance: Double,
        fractionOfSquaredDistance: Double
    ) {
        self.view = view
        self.family = family
        self.weight = max(
            0,
            weight
        )
        self.squaredDistance = max(
            0,
            squaredDistance
        )
        self.fractionOfSquaredDistance = min(
            1,
            max(
                0,
                fractionOfSquaredDistance
            )
        )
    }
}

public struct SpeakerFeatureStandardization:
    Sendable,
    Codable,
    Hashable
{
    public let means: [Double]
    public let deviations: [Double]
    public let totalReliabilityWeight: Double

    public init(
        means: [Double] = [],
        deviations: [Double] = [],
        totalReliabilityWeight: Double = 0
    ) {
        self.means = means
        self.deviations = deviations
        self.totalReliabilityWeight = max(
            0,
            totalReliabilityWeight
        )
    }

    public static let empty = Self()
}

public struct SpeakerClusteringEvaluation:
    Sendable,
    Codable,
    Hashable
{
    public let observationCount: Int
    public let selectedSpeakerCount: Int
    public let reliabilityWeightedSquaredError: Double

    public init(
        observationCount: Int,
        selectedSpeakerCount: Int,
        reliabilityWeightedSquaredError: Double
    ) {
        self.observationCount = max(
            0,
            observationCount
        )
        self.selectedSpeakerCount = max(
            0,
            selectedSpeakerCount
        )
        self.reliabilityWeightedSquaredError = max(
            0,
            reliabilityWeightedSquaredError
        )
    }
}

public struct DiarizationMethod:
    Sendable,
    Codable,
    Hashable
{
    /// Exact configuration consumed by the diarization run.
    public let configuration: DiarizationConfiguration

    /// Coordinate semantics and effective weights of the feature space actually clustered.
    public let featureSpace: [SpeakerFeatureCoordinate]

    /// Reliability-weighted session normalization actually applied before clustering.
    public let standardization: SpeakerFeatureStandardization

    /// Final clustering state selected by the configured clustering policy.
    public let clustering: SpeakerClusteringEvaluation?

    public init(
        configuration: DiarizationConfiguration,
        featureSpace: [SpeakerFeatureCoordinate] = [],
        standardization: SpeakerFeatureStandardization = .empty,
        clustering: SpeakerClusteringEvaluation? = nil
    ) {
        self.configuration = configuration
        self.featureSpace = featureSpace
        self.standardization = standardization
        self.clustering = clustering
    }
}

public struct SpeakerTransitionEvaluation:
    Sendable,
    Codable,
    Hashable
{
    public let previousSpeaker: SpeakerID
    public let speaker: SpeakerID
    public let gapSeconds: Double
    public let gapScale: Double
    public let switchingEvidence: Double
    public let configuredSwitchPenalty: Double
    public let transitionCost: Double

    public init(
        previousSpeaker: SpeakerID,
        speaker: SpeakerID,
        gapSeconds: Double,
        gapScale: Double,
        switchingEvidence: Double,
        configuredSwitchPenalty: Double,
        transitionCost: Double
    ) {
        self.previousSpeaker = previousSpeaker
        self.speaker = speaker
        self.gapSeconds = max(
            0,
            gapSeconds
        )
        self.gapScale = min(
            1,
            max(
                0,
                gapScale
            )
        )
        self.switchingEvidence = min(
            1,
            max(
                0,
                switchingEvidence
            )
        )
        self.configuredSwitchPenalty = max(
            0,
            configuredSwitchPenalty
        )
        self.transitionCost = max(
            0,
            transitionCost
        )
    }

    public var changedSpeaker: Bool {
        previousSpeaker != speaker
    }
}
