public struct SpeakerClusteringNormalizedEvaluation:
    Sendable,
    Codable,
    Hashable
{
    public let clustering: SpeakerClusteringEvaluation
    public let effectiveFeatureWeight: Double
    public let totalReliabilityWeight: Double
    public let normalizedReliabilityWeightedSquaredError: Double

    public init?(
        method: DiarizationMethod
    ) {
        guard let clustering = method.clustering else {
            return nil
        }

        let count = min(
            method.featureSpace.count,
            method.standardization.deviations.count
        )

        var effectiveFeatureWeight = 0.0

        for index in 0..<count {
            guard method.standardization.deviations[index] > 1e-9 else {
                continue
            }

            effectiveFeatureWeight += method.featureSpace[index].weight
        }

        let totalReliabilityWeight = method.standardization
            .totalReliabilityWeight
        let scale = totalReliabilityWeight
            * effectiveFeatureWeight

        guard scale > 1e-12 else {
            return nil
        }

        self.clustering = clustering
        self.effectiveFeatureWeight = effectiveFeatureWeight
        self.totalReliabilityWeight = totalReliabilityWeight
        normalizedReliabilityWeightedSquaredError =
            clustering.reliabilityWeightedSquaredError
                / scale
    }
}

public extension DiarizationMethod {
    var normalizedClusteringEvaluation: SpeakerClusteringNormalizedEvaluation? {
        .init(
            method: self
        )
    }
}

public struct SpeakerDiarizationReplayCandidate:
    Sendable,
    Codable,
    Hashable
{
    public let name: String
    public let featureWeights: SpeakerFeatureWeights

    public init(
        name: String,
        featureWeights: SpeakerFeatureWeights
    ) {
        self.name = name
        self.featureWeights = featureWeights
    }
}

public struct SpeakerDiarizationReplayExperimentResult:
    Sendable,
    Codable,
    Hashable
{
    public let candidate: SpeakerDiarizationReplayCandidate
    public let result: DiarizationResult
    public let comparison: SpeakerDiarizationReplayComparison
    public let clustering: SpeakerClusteringNormalizedEvaluation?

    public init(
        candidate: SpeakerDiarizationReplayCandidate,
        result: DiarizationResult,
        comparison: SpeakerDiarizationReplayComparison,
        clustering: SpeakerClusteringNormalizedEvaluation?
    ) {
        self.candidate = candidate
        self.result = result
        self.comparison = comparison
        self.clustering = clustering
    }
}

public struct SpeakerDiarizationReplayExperiment:
    Sendable,
    Codable,
    Hashable
{
    public let baselineClustering: SpeakerClusteringNormalizedEvaluation?
    public let results: [SpeakerDiarizationReplayExperimentResult]

    public init(
        baselineClustering: SpeakerClusteringNormalizedEvaluation?,
        results: [SpeakerDiarizationReplayExperimentResult]
    ) {
        self.baselineClustering = baselineClustering
        self.results = results
    }
}

public extension SpeakerFeatureWeights {
    func replacing(
        mfcc: Double? = nil,
        logMel: Double? = nil,
        pitch: Double? = nil,
        spectral: Double? = nil,
        dynamics: Double? = nil,
        consistency: Double? = nil,
        quality: Double? = nil,
        enhancedView: Double? = nil
    ) -> Self {
        .init(
            mfcc: mfcc ?? self.mfcc,
            logMel: logMel ?? self.logMel,
            pitch: pitch ?? self.pitch,
            spectral: spectral ?? self.spectral,
            dynamics: dynamics ?? self.dynamics,
            consistency: consistency ?? self.consistency,
            quality: quality ?? self.quality,
            enhancedView: enhancedView ?? self.enhancedView
        )
    }
}

public extension SpeakerDiarizationReplayConfiguration {
    func replacingFeatureWeights(
        _ featureWeights: SpeakerFeatureWeights
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
            featureWeights: featureWeights
        )
    }
}

public extension Diarizer {
    func replayExperiment(
        _ source: DiarizationResult,
        candidates: [SpeakerDiarizationReplayCandidate]
    ) -> SpeakerDiarizationReplayExperiment {
        guard let method = source.method else {
            return .init(
                baselineClustering: nil,
                results: []
            )
        }

        let baselineConfiguration = SpeakerDiarizationReplayConfiguration(
            method.configuration
        )

        let results = candidates.map { candidate in
            let replayed = replay(
                source,
                configuration: baselineConfiguration.replacingFeatureWeights(
                    candidate.featureWeights
                )
            )

            return SpeakerDiarizationReplayExperimentResult(
                candidate: candidate,
                result: replayed,
                comparison: compare(
                    source,
                    to: replayed
                ),
                clustering: replayed.method?.normalizedClusteringEvaluation
            )
        }

        return .init(
            baselineClustering: method.normalizedClusteringEvaluation,
            results: results
        )
    }
}
