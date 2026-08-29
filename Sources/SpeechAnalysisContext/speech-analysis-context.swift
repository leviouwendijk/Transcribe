import Diarization
import MediaCore
import Schema
import SchemaMacros
import SpeechAnalysis
import Transcribe

@JSONSchema
public enum SpeechAnalysisContextDetail:
    String,
    Sendable,
    Codable,
    Hashable
{
    case conversation
    case diagnostic
    case complete
}

@JSONSchema
public struct SpeechAnalysisTimeRangeContext:
    Sendable,
    Codable,
    Hashable
{
    public let startSeconds: Double
    public let endSeconds: Double
    public let durationSeconds: Double
}

@JSONSchema
public struct SpeechAnalysisTranscriptSegmentContext:
    Sendable,
    Codable,
    Hashable
{
    /// Index of the authoritative transcription segment.
    public let segmentIndex: Int
    public let text: String
    public let range: SpeechAnalysisTimeRangeContext?
    public let transcriptionConfidence: Double?
    public let alternatives: [String]
    public let isFinal: Bool
    public let speaker: String?
    public let speakerConfidence: Double?
    public let assignmentMethod: String?
    public let speakerSegmentIndices: [Int]
}

@JSONSchema
public struct SpeechAnalysisTranscriptContext:
    Sendable,
    Codable,
    Hashable
{
    public let localeIdentifier: String?
    public let text: String
    public let segments: [SpeechAnalysisTranscriptSegmentContext]
    public let assignedSegmentCount: Int
    public let unassignedSegmentCount: Int
}

@JSONSchema
public struct SpeechAnalysisDistributionContext:
    Sendable,
    Codable,
    Hashable
{
    public let count: Int
    public let minimum: Double
    public let maximum: Double
    public let mean: Double
    public let median: Double
    public let standardDeviation: Double
    public let q10: Double
    public let q25: Double
    public let q75: Double
    public let q90: Double
}

@JSONSchema
public struct SpeechAnalysisSpeakerProfileContext:
    Sendable,
    Codable,
    Hashable
{
    public let speaker: String
    public let observationCount: Int
    public let observedDurationSeconds: Double
    public let acousticCentroid: [Double]
    public let acousticDispersion: [Double]
    public let rms: SpeechAnalysisDistributionContext?
    public let pitchHz: SpeechAnalysisDistributionContext?
    public let pitchConfidence: SpeechAnalysisDistributionContext?
    public let centroidHz: SpeechAnalysisDistributionContext?
    public let flatness: SpeechAnalysisDistributionContext?
    public let consistency: SpeechAnalysisDistributionContext?
    public let rawQuality: SpeechAnalysisDistributionContext?
    public let enhancedQuality: SpeechAnalysisDistributionContext?
    public let recoveredObservationFraction: Double?
    public let viewAgreement: SpeechAnalysisDistributionContext?
}

@JSONSchema
public struct SpeechAnalysisFeatureWeightsContext:
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
}

@JSONSchema
public struct SpeechAnalysisFeatureCoordinateContext:
    Sendable,
    Codable,
    Hashable
{
    public let view: String
    public let family: String
    public let effectiveWeight: Double
}

@JSONSchema
public struct SpeechAnalysisStandardizationContext:
    Sendable,
    Codable,
    Hashable
{
    public let means: [Double]
    public let deviations: [Double]
    public let totalReliabilityWeight: Double
}

@JSONSchema
public struct SpeechAnalysisClusteringContext:
    Sendable,
    Codable,
    Hashable
{
    public let observationCount: Int
    public let selectedSpeakerCount: Int
    public let reliabilityWeightedSquaredError: Double
}

@JSONSchema
public struct SpeechAnalysisAcousticConfigurationContext:
    Sendable,
    Codable,
    Hashable
{
    public let frameDurationSeconds: Double
    public let hopDurationSeconds: Double
    public let minimumFFTSize: Int
    public let rolloffFraction: Double
    public let minimumPitchHz: Double
    public let maximumPitchHz: Double
    public let minimumPitchEvidence: Double
    public let minimumPitchConfidence: Double
    public let silenceRMS: Double
    public let adaptiveNoiseMultiplier: Double
    public let clippingThreshold: Double
    public let maximumClippingFraction: Double
    public let maximumSpeechFlatness: Double
    public let maximumSpeechZeroCrossingRate: Double
    public let minimumProfileQuality: Double
    public let melFilterCount: Int
    public let mfccCount: Int
}

@JSONSchema
public struct SpeechAnalysisSpeakerObservationConfigurationContext:
    Sendable,
    Codable,
    Hashable
{
    public let minimumDurationSeconds: Double
    public let maximumDurationSeconds: Double
    public let maximumGapSeconds: Double
    public let featureWeights: SpeechAnalysisFeatureWeightsContext
}

@JSONSchema
public struct SpeechAnalysisReliabilityConfigurationContext:
    Sendable,
    Codable,
    Hashable
{
    public let fullAuthorityMaximumNoiseLikelihood: Double
    public let minimumAuthorityNoiseLikelihood: Double
    public let minimumReliability: Double
}

@JSONSchema
public struct SpeechAnalysisTemporalConfigurationContext:
    Sendable,
    Codable,
    Hashable
{
    public let switchPenalty: Double
    public let maximumContinuityGapSeconds: Double
}

@JSONSchema
public struct SpeechAnalysisDiarizationConfigurationContext:
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
    public let temporalCoherence: SpeechAnalysisTemporalConfigurationContext
    public let speakerReliability: SpeechAnalysisReliabilityConfigurationContext
    public let acoustic: SpeechAnalysisAcousticConfigurationContext
    public let speakerObservation: SpeechAnalysisSpeakerObservationConfigurationContext
}

@JSONSchema
public struct SpeechAnalysisDiarizationMethodContext:
    Sendable,
    Codable,
    Hashable
{
    /// Exact configuration consumed by the diarization run.
    public let configuration: SpeechAnalysisDiarizationConfigurationContext
    /// Weighting semantics used to derive effective coordinate weights.
    public let featureWeighting: String
    /// Exact semantic coordinate layout and effective weights clustered in this run.
    public let featureSpace: [SpeechAnalysisFeatureCoordinateContext]
    public let standardization: SpeechAnalysisStandardizationContext
    public let clustering: SpeechAnalysisClusteringContext?
}

@JSONSchema
public struct SpeechAnalysisAlignmentConfigurationContext:
    Sendable,
    Codable,
    Hashable
{
    public let maximumBridgeGapSeconds: Double
    public let maximumNearestEvidenceDistanceSeconds: Double
    public let minimumBridgedConfidence: Double
    public let minimumNearestConfidence: Double
}

@JSONSchema
public struct SpeechAnalysisInferenceContext:
    Sendable,
    Codable,
    Hashable
{
    public let diarization: SpeechAnalysisDiarizationMethodContext?
    public let alignment: SpeechAnalysisAlignmentConfigurationContext?
}

@JSONSchema
public struct SpeechAnalysisFeatureContributionContext:
    Sendable,
    Codable,
    Hashable
{
    public let view: String
    public let family: String
    public let effectiveWeight: Double
    public let squaredDistance: Double
    public let fractionOfSquaredDistance: Double
}

@JSONSchema
public struct SpeechAnalysisSpeakerCandidateContext:
    Sendable,
    Codable,
    Hashable
{
    public let speaker: String
    public let acousticCost: Double
    public let squaredDistance: Double
    public let featureContributions: [SpeechAnalysisFeatureContributionContext]
}

@JSONSchema
public struct SpeechAnalysisReliabilityEvaluationContext:
    Sendable,
    Codable,
    Hashable
{
    public let noiseLikelihood: Double?
    public let sourceObservationCount: Int
    public let taper: Double
    public let reliability: Double
}

@JSONSchema
public struct SpeechAnalysisTransitionEvaluationContext:
    Sendable,
    Codable,
    Hashable
{
    public let previousSpeaker: String
    public let speaker: String
    public let gapSeconds: Double
    public let gapScale: Double
    public let switchingEvidence: Double
    public let configuredSwitchPenalty: Double
    public let transitionCost: Double
    public let changedSpeaker: Bool
}

@JSONSchema
public struct SpeechAnalysisSpeakerDecisionContext:
    Sendable,
    Codable,
    Hashable
{
    public let observationID: Int
    public let acousticSpeaker: String
    public let resolvedSpeaker: String
    public let acousticConfidence: Double
    public let acousticEvidenceStrength: Double
    public let changedByContinuity: Bool
    public let resolvedConfidence: Double?
    public let reliability: SpeechAnalysisReliabilityEvaluationContext
    public let candidates: [SpeechAnalysisSpeakerCandidateContext]
    public let temporalTransition: SpeechAnalysisTransitionEvaluationContext?
}

@JSONSchema
public struct SpeechAnalysisSpeakerObservationContext:
    Sendable,
    Codable,
    Hashable
{
    public let id: Int
    public let range: SpeechAnalysisTimeRangeContext
    public let acousticObservationIDs: [Int]
    public let featureValues: [Double]
    public let featureCoordinates: [SpeechAnalysisFeatureCoordinateContext]
    public let qualityScore: Double
    public let viewAgreement: Double?
}

@JSONSchema
public struct SpeechAnalysisSignalFeaturesContext:
    Sendable,
    Codable,
    Hashable
{
    public let rms: Double
    public let peak: Double
    public let zeroCrossingRate: Double
    public let clippingFraction: Double
}

@JSONSchema
public struct SpeechAnalysisSpectralFeaturesContext:
    Sendable,
    Codable,
    Hashable
{
    public let centroidHz: Double
    public let spreadHz: Double
    public let rolloffHz: Double
    public let flatness: Double
    public let pitchHz: Double?
    public let pitchConfidence: Double
    public let voicedProbability: Double
    public let logMelEnergies: [Double]
    public let mfcc: [Double]
}

@JSONSchema
public struct SpeechAnalysisConsistencyFeaturesContext:
    Sendable,
    Codable,
    Hashable
{
    public let energyDeltaDB: Double
    public let spectralDelta: Double
    public let mfccDelta: Double
    public let pitchDeltaSemitones: Double?
    public let consistencyScore: Double
    public let transientLikelihood: Double
}

@JSONSchema
public struct SpeechAnalysisQualityContext:
    Sendable,
    Codable,
    Hashable
{
    public let score: Double
    public let isUsableForSpeakerProfile: Bool
    public let issues: [String]
}

@JSONSchema
public struct SpeechAnalysisAcousticObservationContext:
    Sendable,
    Codable,
    Hashable
{
    public let id: Int
    public let range: SpeechAnalysisTimeRangeContext
    public let signal: SpeechAnalysisSignalFeaturesContext
    public let spectral: SpeechAnalysisSpectralFeaturesContext
    public let consistency: SpeechAnalysisConsistencyFeaturesContext
    public let activity: String
    public let quality: SpeechAnalysisQualityContext
}

@JSONSchema
public struct SpeechAnalysisAcousticAnalysisContext:
    Sendable,
    Codable,
    Hashable
{
    public let sampleRate: Int
    public let noiseFloorRMS: Double
    public let observations: [SpeechAnalysisAcousticObservationContext]
}

@JSONSchema
public struct SpeechAnalysisNoiseProfileContext:
    Sendable,
    Codable,
    Hashable
{
    public let observationCount: Int
    public let rms: SpeechAnalysisDistributionContext
    public let flatness: SpeechAnalysisDistributionContext
    public let stationarity: SpeechAnalysisDistributionContext
    public let logMelMean: [Double]
    public let logMelDispersion: [Double]
}

@JSONSchema
public struct SpeechAnalysisNoiseEvidenceContext:
    Sendable,
    Codable,
    Hashable
{
    public let observationID: Int
    public let likelihood: Double
    public let lowEnergy: Double
    public let flatness: Double
    public let stationarity: Double
    public let pitchUnreliability: Double
    public let transient: Double
}

@JSONSchema
public struct SpeechAnalysisEnhancementBlockContext:
    Sendable,
    Codable,
    Hashable
{
    public let range: SpeechAnalysisTimeRangeContext?
    public let inputRMSDB: Double
    public let outputRMSDB: Double
    public let appliedGainDB: Double
}

@JSONSchema
public struct SpeechAnalysisEnhancementContext:
    Sendable,
    Codable,
    Hashable
{
    public let blocks: [SpeechAnalysisEnhancementBlockContext]
    public let blockCount: Int
    public let appliedGainDB: SpeechAnalysisDistributionContext
    public let inputRMSDB: SpeechAnalysisDistributionContext
    public let outputRMSDB: SpeechAnalysisDistributionContext
    public let recoveredUsableObservationCount: Int
}

@JSONSchema
public struct SpeechAnalysisAcousticEvidenceContext:
    Sendable,
    Codable,
    Hashable
{
    /// Complete retained raw acoustic analysis.
    public let raw: SpeechAnalysisAcousticAnalysisContext?
    /// Complete retained enhanced acoustic analysis.
    public let enhanced: SpeechAnalysisAcousticAnalysisContext?
    public let noiseProfile: SpeechAnalysisNoiseProfileContext?
    public let noiseEvidence: [SpeechAnalysisNoiseEvidenceContext]
    public let enhancement: SpeechAnalysisEnhancementContext?
}

@JSONSchema
public struct SpeechAnalysisContext:
    Sendable,
    Codable,
    Hashable
{
    /// Controls projection breadth; it never changes the authoritative SpeechAnalysisResult.
    public let detail: SpeechAnalysisContextDetail
    public let transcript: SpeechAnalysisTranscriptContext?
    public let speakers: [SpeechAnalysisSpeakerProfileContext]
    /// Present for diagnostic and complete projections.
    public let inference: SpeechAnalysisInferenceContext?
    /// Present for diagnostic and complete projections.
    public let speakerObservations: [SpeechAnalysisSpeakerObservationContext]
    /// Present for diagnostic and complete projections.
    public let speakerDecisions: [SpeechAnalysisSpeakerDecisionContext]
    /// Present only for complete projection and may be very large.
    public let acousticEvidence: SpeechAnalysisAcousticEvidenceContext?
}

public struct SpeechAnalysisContextProjector: Sendable {
    public init() {}

    public func project(
        _ result: SpeechAnalysisResult,
        detail: SpeechAnalysisContextDetail = .conversation
    ) -> SpeechAnalysisContext {
        let diarization = result.diarization
        let includesDiagnostics = detail != .conversation
        let includesAcoustics = detail == .complete

        return .init(
            detail: detail,
            transcript: transcript(
                result.attributedTranscription
            ),
            speakers: diarization?.profiles.map(
                speakerProfile
            ) ?? [],
            inference: includesDiagnostics
                ? inference(result)
                : nil,
            speakerObservations: includesDiagnostics
                ? diarization?.observations.map(speakerObservation) ?? []
                : [],
            speakerDecisions: includesDiagnostics
                ? diarization?.assignments.map(speakerDecision) ?? []
                : [],
            acousticEvidence: includesAcoustics
                ? acousticEvidence(diarization)
                : nil
        )
    }
}

private extension SpeechAnalysisContextProjector {
    func range(
        _ value: Audio.TimeRange
    ) -> SpeechAnalysisTimeRangeContext {
        .init(
            startSeconds: value.start,
            endSeconds: value.end,
            durationSeconds: value.duration
        )
    }

    func transcript(
        _ value: AttributedTranscription?
    ) -> SpeechAnalysisTranscriptContext? {
        guard let value else {
            return nil
        }

        let segments = value.segments.map { attributed in
            SpeechAnalysisTranscriptSegmentContext(
                segmentIndex: attributed.segmentIndex,
                text: attributed.segment.text,
                range: attributed.segment.range.map(range),
                transcriptionConfidence: attributed.segment.confidence,
                alternatives: attributed.segment.alternatives,
                isFinal: attributed.segment.isFinal,
                speaker: attributed.speaker?.rawValue,
                speakerConfidence: attributed.speakerConfidence,
                assignmentMethod: attributed.assignmentMethod?.rawValue,
                speakerSegmentIndices: attributed.speakerSegmentIndices
            )
        }

        let assigned = segments.filter {
            $0.speaker != nil
        }.count

        return .init(
            localeIdentifier: value.localeIdentifier,
            text: value.text,
            segments: segments,
            assignedSegmentCount: assigned,
            unassignedSegmentCount: segments.count - assigned
        )
    }

    func distribution(
        _ value: AcousticDistribution
    ) -> SpeechAnalysisDistributionContext {
        .init(
            count: value.count,
            minimum: value.minimum,
            maximum: value.maximum,
            mean: value.mean,
            median: value.median,
            standardDeviation: value.standardDeviation,
            q10: value.q10,
            q25: value.q25,
            q75: value.q75,
            q90: value.q90
        )
    }

    func speakerProfile(
        _ value: SpeakerProfile
    ) -> SpeechAnalysisSpeakerProfileContext {
        let acoustic = value.acousticProfile

        return .init(
            speaker: value.speaker.rawValue,
            observationCount: value.observationCount,
            observedDurationSeconds: value.observedDurationSeconds,
            acousticCentroid: value.acousticCentroid?.values ?? [],
            acousticDispersion: value.acousticDispersion?.values ?? [],
            rms: acoustic.map { distribution($0.rms) },
            pitchHz: acoustic.map { distribution($0.pitchHz) },
            pitchConfidence: acoustic.map { distribution($0.pitchConfidence) },
            centroidHz: acoustic.map { distribution($0.centroidHz) },
            flatness: acoustic.map { distribution($0.flatness) },
            consistency: acoustic.map { distribution($0.consistency) },
            rawQuality: acoustic.map { distribution($0.rawQuality) },
            enhancedQuality: acoustic.map { distribution($0.enhancedQuality) },
            recoveredObservationFraction: acoustic?.recoveredObservationFraction,
            viewAgreement: acoustic.map { distribution($0.viewAgreement) }
        )
    }

    func featureWeights(
        _ value: SpeakerFeatureWeights
    ) -> SpeechAnalysisFeatureWeightsContext {
        .init(
            mfcc: value.mfcc,
            logMel: value.logMel,
            pitch: value.pitch,
            spectral: value.spectral,
            dynamics: value.dynamics,
            consistency: value.consistency,
            quality: value.quality,
            enhancedView: value.enhancedView
        )
    }

    func featureCoordinate(
        _ value: SpeakerFeatureCoordinate
    ) -> SpeechAnalysisFeatureCoordinateContext {
        .init(
            view: value.view.rawValue,
            family: value.family.rawValue,
            effectiveWeight: value.weight
        )
    }

    func acousticConfiguration(
        _ value: AcousticAnalyzerConfiguration
    ) -> SpeechAnalysisAcousticConfigurationContext {
        .init(
            frameDurationSeconds: value.frameDurationSeconds,
            hopDurationSeconds: value.hopDurationSeconds,
            minimumFFTSize: value.minimumFFTSize,
            rolloffFraction: value.rolloffFraction,
            minimumPitchHz: value.minimumPitchHz,
            maximumPitchHz: value.maximumPitchHz,
            minimumPitchEvidence: value.minimumPitchEvidence,
            minimumPitchConfidence: value.minimumPitchConfidence,
            silenceRMS: value.silenceRMS,
            adaptiveNoiseMultiplier: value.adaptiveNoiseMultiplier,
            clippingThreshold: value.clippingThreshold,
            maximumClippingFraction: value.maximumClippingFraction,
            maximumSpeechFlatness: value.maximumSpeechFlatness,
            maximumSpeechZeroCrossingRate: value.maximumSpeechZeroCrossingRate,
            minimumProfileQuality: value.minimumProfileQuality,
            melFilterCount: value.melFilterCount,
            mfccCount: value.mfccCount
        )
    }

    func diarizationConfiguration(
        _ value: DiarizationConfiguration
    ) -> SpeechAnalysisDiarizationConfigurationContext {
        let observation = value.speakerObservation
        let reliability = value.speakerReliability
        let temporal = value.temporalCoherence

        return .init(
            expectedSpeakerCount: value.expectedSpeakerCount,
            maximumSpeakerCount: value.maximumSpeakerCount,
            minimumSpeakerObservationsPerCluster: value.minimumSpeakerObservationsPerCluster,
            minimumSplitImprovement: value.minimumSplitImprovement,
            maximumIterations: value.maximumIterations,
            segmentMergeGapSeconds: value.segmentMergeGapSeconds,
            temporalCoherence: .init(
                switchPenalty: temporal.switchPenalty,
                maximumContinuityGapSeconds: temporal.maximumContinuityGapSeconds
            ),
            speakerReliability: .init(
                fullAuthorityMaximumNoiseLikelihood: reliability.fullAuthorityMaximumNoiseLikelihood,
                minimumAuthorityNoiseLikelihood: reliability.minimumAuthorityNoiseLikelihood,
                minimumReliability: reliability.minimumReliability
            ),
            acoustic: acousticConfiguration(value.acoustic),
            speakerObservation: .init(
                minimumDurationSeconds: observation.minimumDurationSeconds,
                maximumDurationSeconds: observation.maximumDurationSeconds,
                maximumGapSeconds: observation.maximumGapSeconds,
                featureWeights: featureWeights(observation.featureWeights)
            )
        )
    }

    func diarizationMethod(
        _ value: DiarizationMethod
    ) -> SpeechAnalysisDiarizationMethodContext {
        .init(
            configuration: diarizationConfiguration(value.configuration),
            featureWeighting: value.featureWeighting.rawValue,
            featureSpace: value.featureSpace.map(featureCoordinate),
            standardization: .init(
                means: value.standardization.means,
                deviations: value.standardization.deviations,
                totalReliabilityWeight: value.standardization.totalReliabilityWeight
            ),
            clustering: value.clustering.map {
                .init(
                    observationCount: $0.observationCount,
                    selectedSpeakerCount: $0.selectedSpeakerCount,
                    reliabilityWeightedSquaredError: $0.reliabilityWeightedSquaredError
                )
            }
        )
    }

    func alignmentConfiguration(
        _ value: SpeakerTranscriptAligner.Configuration
    ) -> SpeechAnalysisAlignmentConfigurationContext {
        .init(
            maximumBridgeGapSeconds: value.maximumBridgeGapSeconds,
            maximumNearestEvidenceDistanceSeconds: value.maximumNearestEvidenceDistanceSeconds,
            minimumBridgedConfidence: value.minimumBridgedConfidence,
            minimumNearestConfidence: value.minimumNearestConfidence
        )
    }

    func inference(
        _ value: SpeechAnalysisResult
    ) -> SpeechAnalysisInferenceContext {
        .init(
            diarization: value.diarization?.method.map(diarizationMethod),
            alignment: value.alignment?.configuration.map(alignmentConfiguration)
        )
    }

    func speakerObservation(
        _ value: SpeakerObservation
    ) -> SpeechAnalysisSpeakerObservationContext {
        .init(
            id: value.id.rawValue,
            range: range(value.range),
            acousticObservationIDs: value.acousticObservationIDs.map(\.rawValue),
            featureValues: value.features.values,
            featureCoordinates: value.features.coordinates.map(featureCoordinate),
            qualityScore: value.qualityScore,
            viewAgreement: value.viewAgreement?.combined
        )
    }

    func reliability(
        _ value: SpeakerEvidenceReliabilityEvaluation
    ) -> SpeechAnalysisReliabilityEvaluationContext {
        .init(
            noiseLikelihood: value.noiseLikelihood,
            sourceObservationCount: value.sourceObservationCount,
            taper: value.taper,
            reliability: value.reliability
        )
    }

    func contribution(
        _ value: SpeakerFeatureContribution
    ) -> SpeechAnalysisFeatureContributionContext {
        .init(
            view: value.view.rawValue,
            family: value.family.rawValue,
            effectiveWeight: value.weight,
            squaredDistance: value.squaredDistance,
            fractionOfSquaredDistance: value.fractionOfSquaredDistance
        )
    }

    func candidate(
        _ value: SpeakerAssignmentCandidate
    ) -> SpeechAnalysisSpeakerCandidateContext {
        .init(
            speaker: value.speaker.rawValue,
            acousticCost: value.acousticCost,
            squaredDistance: value.squaredDistance,
            featureContributions: value.featureContributions.map(contribution)
        )
    }

    func transition(
        _ value: SpeakerTransitionEvaluation
    ) -> SpeechAnalysisTransitionEvaluationContext {
        .init(
            previousSpeaker: value.previousSpeaker.rawValue,
            speaker: value.speaker.rawValue,
            gapSeconds: value.gapSeconds,
            gapScale: value.gapScale,
            switchingEvidence: value.switchingEvidence,
            configuredSwitchPenalty: value.configuredSwitchPenalty,
            transitionCost: value.transitionCost,
            changedSpeaker: value.changedSpeaker
        )
    }

    func speakerDecision(
        _ value: SpeakerObservationAssignment
    ) -> SpeechAnalysisSpeakerDecisionContext {
        .init(
            observationID: value.observationID.rawValue,
            acousticSpeaker: value.acousticSpeaker.rawValue,
            resolvedSpeaker: value.resolvedSpeaker.rawValue,
            acousticConfidence: value.acousticConfidence,
            acousticEvidenceStrength: value.acousticEvidenceStrength,
            changedByContinuity: value.changedByContinuity,
            resolvedConfidence: value.resolvedConfidence,
            reliability: reliability(value.reliabilityEvaluation),
            candidates: value.candidates.map(candidate),
            temporalTransition: value.temporalTransition.map(transition)
        )
    }

    func acousticObservation(
        _ value: AcousticObservation
    ) -> SpeechAnalysisAcousticObservationContext {
        .init(
            id: value.id.rawValue,
            range: range(value.range),
            signal: .init(
                rms: value.signal.rms,
                peak: value.signal.peak,
                zeroCrossingRate: value.signal.zeroCrossingRate,
                clippingFraction: value.signal.clippingFraction
            ),
            spectral: .init(
                centroidHz: value.spectral.centroidHz,
                spreadHz: value.spectral.spreadHz,
                rolloffHz: value.spectral.rolloffHz,
                flatness: value.spectral.flatness,
                pitchHz: value.spectral.pitchHz,
                pitchConfidence: value.spectral.pitchConfidence,
                voicedProbability: value.spectral.voicedProbability,
                logMelEnergies: value.spectral.logMelEnergies,
                mfcc: value.spectral.mfcc
            ),
            consistency: .init(
                energyDeltaDB: value.consistency.energyDeltaDB,
                spectralDelta: value.consistency.spectralDelta,
                mfccDelta: value.consistency.mfccDelta,
                pitchDeltaSemitones: value.consistency.pitchDeltaSemitones,
                consistencyScore: value.consistency.consistencyScore,
                transientLikelihood: value.consistency.transientLikelihood
            ),
            activity: value.activity.rawValue,
            quality: .init(
                score: value.quality.score,
                isUsableForSpeakerProfile: value.quality.isUsableForSpeakerProfile,
                issues: value.quality.issues.map(\.rawValue)
            )
        )
    }

    func acousticAnalysis(
        _ value: AcousticAnalysis
    ) -> SpeechAnalysisAcousticAnalysisContext {
        .init(
            sampleRate: value.sampleRate,
            noiseFloorRMS: value.noiseFloorRMS,
            observations: value.observations.map(acousticObservation)
        )
    }

    func noiseProfile(
        _ value: AcousticNoiseProfile
    ) -> SpeechAnalysisNoiseProfileContext {
        .init(
            observationCount: value.observationCount,
            rms: distribution(value.rms),
            flatness: distribution(value.flatness),
            stationarity: distribution(value.stationarity),
            logMelMean: value.logMelMean,
            logMelDispersion: value.logMelDispersion
        )
    }

    func noiseEvidence(
        _ value: AcousticNoiseEvidence
    ) -> SpeechAnalysisNoiseEvidenceContext {
        .init(
            observationID: value.observationID.rawValue,
            likelihood: value.likelihood,
            lowEnergy: value.lowEnergy,
            flatness: value.flatness,
            stationarity: value.stationarity,
            pitchUnreliability: value.pitchUnreliability,
            transient: value.transient
        )
    }

    func enhancement(
        _ value: AcousticEnhancementSummary
    ) -> SpeechAnalysisEnhancementContext {
        .init(
            blocks: value.blocks.map {
                .init(
                    range: $0.range.map(range),
                    inputRMSDB: $0.inputRMSDB,
                    outputRMSDB: $0.outputRMSDB,
                    appliedGainDB: $0.appliedGainDB
                )
            },
            blockCount: value.blockCount,
            appliedGainDB: distribution(value.appliedGainDB),
            inputRMSDB: distribution(value.inputRMSDB),
            outputRMSDB: distribution(value.outputRMSDB),
            recoveredUsableObservationCount: value.recoveredUsableObservationCount
        )
    }

    func acousticEvidence(
        _ value: DiarizationResult?
    ) -> SpeechAnalysisAcousticEvidenceContext? {
        guard let value else {
            return nil
        }

        return .init(
            raw: value.acoustic.map(acousticAnalysis),
            enhanced: value.enhancedAcoustic.map(acousticAnalysis),
            noiseProfile: value.noiseProfile.map(noiseProfile),
            noiseEvidence: value.noiseEvidence.map(noiseEvidence),
            enhancement: value.enhancement.map(enhancement)
        )
    }
}
