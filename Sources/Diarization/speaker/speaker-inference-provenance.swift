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
    public let distanceMetric: SpeakerClusteringDistanceMetric
    public let reliabilityWeightedCost: Double

    public init(
        observationCount: Int,
        selectedSpeakerCount: Int,
        reliabilityWeightedSquaredError: Double
    ) {
        self.init(
            observationCount: observationCount,
            selectedSpeakerCount: selectedSpeakerCount,
            distanceMetric: .standardizedWeightedSquaredEuclidean,
            reliabilityWeightedCost: reliabilityWeightedSquaredError
        )
    }

    public init(
        observationCount: Int,
        selectedSpeakerCount: Int,
        distanceMetric: SpeakerClusteringDistanceMetric,
        reliabilityWeightedCost: Double
    ) {
        self.observationCount = max(
            0,
            observationCount
        )
        self.selectedSpeakerCount = max(
            0,
            selectedSpeakerCount
        )
        self.distanceMetric = distanceMetric
        self.reliabilityWeightedCost = max(
            0,
            reliabilityWeightedCost
        )
    }

    /// Compatibility projection for the original acoustic clustering metric.
    /// Non-squared metrics intentionally do not masquerade as SSE.
    public var reliabilityWeightedSquaredError: Double {
        distanceMetric == .standardizedWeightedSquaredEuclidean
            ? reliabilityWeightedCost
            : 0
    }
}

public struct SpeakerHybridClusteringWeights:
    Sendable,
    Codable,
    Hashable
{
    public let acoustic: Double
    public let embedding: Double

    public init(
        acoustic: Double,
        embedding: Double
    ) {
        precondition(acoustic.isFinite)
        precondition(embedding.isFinite)
        precondition(acoustic >= 0)
        precondition(embedding >= 0)

        let total = acoustic
            + embedding

        precondition(total > 0)

        self.acoustic = acoustic
            / total
        self.embedding = embedding
            / total
    }
}

public enum SpeakerClusteringRepresentation:
    String,
    Sendable,
    Codable,
    Hashable
{
    case acoustic
    case embedding
    case hybrid
}

public struct DiarizationMethod:
    Sendable,
    Codable,
    Hashable
{
    /// Exact configuration consumed by the diarization run.
    public let configuration: DiarizationConfiguration

    /// Identity representation actually consumed by clustering.
    public let clusteringRepresentation: SpeakerClusteringRepresentation

    /// Relative authority of acoustic and embedding evidence when the
    /// clustering representation is hybrid.
    public let hybridWeights: SpeakerHybridClusteringWeights?

    /// Weighting semantics used to turn configured family weights into coordinate weights.
    public let featureWeighting: SpeakerFeatureWeighting

    /// Coordinate semantics and effective weights of the acoustic feature space actually clustered.
    public let featureSpace: [SpeakerFeatureCoordinate]

    /// Reliability-weighted session normalization actually applied before clustering.
    public let standardization: SpeakerFeatureStandardization

    /// Final clustering state selected by the configured clustering policy.
    public let clustering: SpeakerClusteringEvaluation?

    public init(
        configuration: DiarizationConfiguration,
        clusteringRepresentation: SpeakerClusteringRepresentation = .acoustic,
        hybridWeights: SpeakerHybridClusteringWeights? = nil,
        featureWeighting: SpeakerFeatureWeighting = .perCoordinate,
        featureSpace: [SpeakerFeatureCoordinate] = [],
        standardization: SpeakerFeatureStandardization = .empty,
        clustering: SpeakerClusteringEvaluation? = nil
    ) {
        self.configuration = configuration
        self.clusteringRepresentation = clusteringRepresentation
        self.hybridWeights = hybridWeights
        self.featureWeighting = featureWeighting
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
