public enum SpeakerFeatureAblationTarget:
    String,
    Sendable,
    Codable,
    Hashable,
    CaseIterable
{
    case mfcc
    case logMel
    case pitch
    case spectral
    case dynamics
    case consistency
    case quality
    case enhancedView
}

public struct SpeakerDiarizationReplayConfiguration:
    Sendable,
    Codable,
    Hashable
{
    public let expectedSpeakerCount: Int?
    public let maximumSpeakerCount: Int
    public let minimumSpeakerObservationsPerCluster: Int
    public let minimumSplitImprovement: Double
    public let maximumIterations: Int
    public let segmentMergeGapSeconds: Double
    public let temporalCoherence: SpeakerTemporalCoherenceConfiguration
    public let speakerReliability: SpeakerEvidenceReliabilityConfiguration
    public let featureWeights: SpeakerFeatureWeights
    public let featureWeighting: SpeakerFeatureWeighting

    public init(
        _ configuration: DiarizationConfiguration
    ) {
        expectedSpeakerCount = configuration.expectedSpeakerCount
        maximumSpeakerCount = configuration.maximumSpeakerCount
        minimumSpeakerObservationsPerCluster = configuration.minimumSpeakerObservationsPerCluster
        minimumSplitImprovement = configuration.minimumSplitImprovement
        maximumIterations = configuration.maximumIterations
        segmentMergeGapSeconds = configuration.segmentMergeGapSeconds
        temporalCoherence = configuration.temporalCoherence
        speakerReliability = configuration.speakerReliability
        featureWeights = configuration.speakerObservation.featureWeights
        featureWeighting = .perCoordinate
    }

    public init(
        _ method: DiarizationMethod
    ) {
        self.init(
            method.configuration,
            featureWeighting: method.featureWeighting
        )
    }

    public init(
        _ configuration: DiarizationConfiguration,
        featureWeighting: SpeakerFeatureWeighting
    ) {
        expectedSpeakerCount = configuration.expectedSpeakerCount
        maximumSpeakerCount = configuration.maximumSpeakerCount
        minimumSpeakerObservationsPerCluster = configuration.minimumSpeakerObservationsPerCluster
        minimumSplitImprovement = configuration.minimumSplitImprovement
        maximumIterations = configuration.maximumIterations
        segmentMergeGapSeconds = configuration.segmentMergeGapSeconds
        temporalCoherence = configuration.temporalCoherence
        speakerReliability = configuration.speakerReliability
        featureWeights = configuration.speakerObservation.featureWeights
        self.featureWeighting = featureWeighting
    }

    public init(
        expectedSpeakerCount: Int?,
        maximumSpeakerCount: Int,
        minimumSpeakerObservationsPerCluster: Int,
        minimumSplitImprovement: Double,
        maximumIterations: Int,
        segmentMergeGapSeconds: Double,
        temporalCoherence: SpeakerTemporalCoherenceConfiguration,
        speakerReliability: SpeakerEvidenceReliabilityConfiguration,
        featureWeights: SpeakerFeatureWeights,
        featureWeighting: SpeakerFeatureWeighting = .perCoordinate
    ) {
        self.expectedSpeakerCount = expectedSpeakerCount
        self.maximumSpeakerCount = maximumSpeakerCount
        self.minimumSpeakerObservationsPerCluster = minimumSpeakerObservationsPerCluster
        self.minimumSplitImprovement = minimumSplitImprovement
        self.maximumIterations = maximumIterations
        self.segmentMergeGapSeconds = segmentMergeGapSeconds
        self.temporalCoherence = temporalCoherence
        self.speakerReliability = speakerReliability
        self.featureWeights = featureWeights
        self.featureWeighting = featureWeighting
    }

    public func ablating(
        _ target: SpeakerFeatureAblationTarget
    ) -> Self {
        .init(
            expectedSpeakerCount: expectedSpeakerCount,
            maximumSpeakerCount: maximumSpeakerCount,
            minimumSpeakerObservationsPerCluster: minimumSpeakerObservationsPerCluster,
            minimumSplitImprovement: minimumSplitImprovement,
            maximumIterations: maximumIterations,
            segmentMergeGapSeconds: segmentMergeGapSeconds,
            temporalCoherence: temporalCoherence,
            speakerReliability: speakerReliability,
            featureWeights: featureWeights.ablating(target),
            featureWeighting: featureWeighting
        )
    }
}

public struct SpeakerDiarizationReplaySummary:
    Sendable,
    Codable,
    Hashable
{
    public let ablation: SpeakerFeatureAblationTarget
    public let speakerCount: Int
    public let segmentCount: Int
    public let changedAcousticAssignmentCount: Int
    public let changedResolvedAssignmentCount: Int
    public let reliabilityWeightedSquaredError: Double?
    public let normalizedReliabilityWeightedSquaredError: Double?

    public init(
        ablation: SpeakerFeatureAblationTarget,
        speakerCount: Int,
        segmentCount: Int,
        changedAcousticAssignmentCount: Int,
        changedResolvedAssignmentCount: Int,
        reliabilityWeightedSquaredError: Double?,
        normalizedReliabilityWeightedSquaredError: Double? = nil
    ) {
        self.ablation = ablation
        self.speakerCount = speakerCount
        self.segmentCount = segmentCount
        self.changedAcousticAssignmentCount = changedAcousticAssignmentCount
        self.changedResolvedAssignmentCount = changedResolvedAssignmentCount
        self.reliabilityWeightedSquaredError = reliabilityWeightedSquaredError
        self.normalizedReliabilityWeightedSquaredError =
            normalizedReliabilityWeightedSquaredError
    }
}

private extension SpeakerFeatureWeights {
    func ablating(
        _ target: SpeakerFeatureAblationTarget
    ) -> Self {
        .init(
            mfcc: target == .mfcc ? 0 : mfcc,
            logMel: target == .logMel ? 0 : logMel,
            pitch: target == .pitch ? 0 : pitch,
            spectral: target == .spectral ? 0 : spectral,
            dynamics: target == .dynamics ? 0 : dynamics,
            consistency: target == .consistency ? 0 : consistency,
            quality: target == .quality ? 0 : quality,
            enhancedView: target == .enhancedView ? 0 : enhancedView
        )
    }
}

extension SpeakerDiarizationReplayConfiguration {
    func resolved(
        preservingNonReplayableFrom source: DiarizationConfiguration
    ) -> DiarizationConfiguration {
        .init(
            expectedSpeakerCount: expectedSpeakerCount,
            maximumSpeakerCount: maximumSpeakerCount,
            minimumSpeakerObservationsPerCluster: minimumSpeakerObservationsPerCluster,
            minimumSplitImprovement: minimumSplitImprovement,
            maximumIterations: maximumIterations,
            segmentMergeGapSeconds: segmentMergeGapSeconds,
            temporalCoherence: temporalCoherence,
            speakerReliability: speakerReliability,
            acoustic: source.acoustic,
            speakerObservation: .init(
                minimumDurationSeconds: source.speakerObservation.minimumDurationSeconds,
                maximumDurationSeconds: source.speakerObservation.maximumDurationSeconds,
                maximumGapSeconds: source.speakerObservation.maximumGapSeconds,
                featureWeights: featureWeights
            )
        )
    }
}
