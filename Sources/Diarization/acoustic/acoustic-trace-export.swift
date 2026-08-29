import Foundation

public struct AcousticTraceExportRow:
    Sendable,
    Codable,
    Hashable
{
    public let startSeconds: Double
    public let endSeconds: Double
    public let speaker: SpeakerID?
    public let acousticSpeaker: SpeakerID?
    public let temporalAdjusted: Bool
    public let speakerAcousticConfidence: Double?
    public let speakerReliability: Double?
    public let speakerEvidenceStrength: Double?
    public let speakerResolvedConfidence: Double?

    public let rawRMS: Double
    public let enhancedRMS: Double?
    public let enhancementGainDB: Double?

    public let pitchHz: Double?
    public let pitchConfidence: Double
    public let voicedProbability: Double

    public let centroidHz: Double
    public let flatness: Double
    public let consistency: Double
    public let transientLikelihood: Double

    public let noiseLikelihood: Double?
    public let noiseLowEnergy: Double?
    public let noiseFlatness: Double?
    public let noiseStationarity: Double?
    public let noisePitchUnreliability: Double?
    public let noiseTransient: Double?

    public let rawQuality: Double
    public let enhancedQuality: Double?
    public let viewAgreement: Double?

    public init(
        startSeconds: Double,
        endSeconds: Double,
        speaker: SpeakerID?,
        acousticSpeaker: SpeakerID?,
        temporalAdjusted: Bool,
        speakerAcousticConfidence: Double?,
        speakerReliability: Double?,
        speakerEvidenceStrength: Double?,
        speakerResolvedConfidence: Double?,
        rawRMS: Double,
        enhancedRMS: Double?,
        enhancementGainDB: Double?,
        pitchHz: Double?,
        pitchConfidence: Double,
        voicedProbability: Double,
        centroidHz: Double,
        flatness: Double,
        consistency: Double,
        transientLikelihood: Double,
        noiseLikelihood: Double?,
        noiseLowEnergy: Double?,
        noiseFlatness: Double?,
        noiseStationarity: Double?,
        noisePitchUnreliability: Double?,
        noiseTransient: Double?,
        rawQuality: Double,
        enhancedQuality: Double?,
        viewAgreement: Double?
    ) {
        self.startSeconds = startSeconds
        self.endSeconds = endSeconds
        self.speaker = speaker
        self.acousticSpeaker = acousticSpeaker
        self.temporalAdjusted = temporalAdjusted
        self.speakerAcousticConfidence = speakerAcousticConfidence
        self.speakerReliability = speakerReliability
        self.speakerEvidenceStrength = speakerEvidenceStrength
        self.speakerResolvedConfidence = speakerResolvedConfidence
        self.rawRMS = rawRMS
        self.enhancedRMS = enhancedRMS
        self.enhancementGainDB = enhancementGainDB
        self.pitchHz = pitchHz
        self.pitchConfidence = pitchConfidence
        self.voicedProbability = voicedProbability
        self.centroidHz = centroidHz
        self.flatness = flatness
        self.consistency = consistency
        self.transientLikelihood = transientLikelihood
        self.noiseLikelihood = noiseLikelihood
        self.noiseLowEnergy = noiseLowEnergy
        self.noiseFlatness = noiseFlatness
        self.noiseStationarity = noiseStationarity
        self.noisePitchUnreliability = noisePitchUnreliability
        self.noiseTransient = noiseTransient
        self.rawQuality = rawQuality
        self.enhancedQuality = enhancedQuality
        self.viewAgreement = viewAgreement
    }
}

public extension DiarizationResult {
    func acousticTraceRows() -> [AcousticTraceExportRow] {
        guard let acoustic else {
            return []
        }

        let enhancedByID = Dictionary(
            uniqueKeysWithValues: enhancedAcoustic?.observations.map {
                (
                    $0.id,
                    $0
                )
            } ?? []
        )

        let speakerObservationByID = Dictionary(
            uniqueKeysWithValues: observations.map {
                (
                    $0.id,
                    $0
                )
            }
        )

        let assignmentByObservationID = Dictionary(
            uniqueKeysWithValues: assignments.map {
                (
                    $0.observationID,
                    $0
                )
            }
        )

        var speakerByAcousticID: [AcousticObservationID: SpeakerID] = [:]
        var acousticSpeakerByAcousticID: [AcousticObservationID: SpeakerID] = [:]
        var temporalAdjustedByAcousticID: [AcousticObservationID: Bool] = [:]
        var acousticConfidenceByAcousticID: [AcousticObservationID: Double] = [:]
        var reliabilityByAcousticID: [AcousticObservationID: Double] = [:]
        var evidenceStrengthByAcousticID: [AcousticObservationID: Double] = [:]
        var resolvedConfidenceByAcousticID: [AcousticObservationID: Double] = [:]
        var agreementByAcousticID: [AcousticObservationID: Double] = [:]

        let noiseByAcousticID = Dictionary(
            uniqueKeysWithValues: noiseEvidence.map {
                (
                    $0.observationID,
                    $0
                )
            }
        )

        for observation in observations {
            if let agreement = observation.viewAgreement?.combined {
                for acousticID in observation.acousticObservationIDs {
                    agreementByAcousticID[acousticID] = agreement
                }
            }

            if let assignment = assignmentByObservationID[
                observation.id
            ] {
                for acousticID in observation.acousticObservationIDs {
                    acousticSpeakerByAcousticID[acousticID] = assignment.acousticSpeaker
                    temporalAdjustedByAcousticID[acousticID] = assignment.changedByContinuity
                    acousticConfidenceByAcousticID[acousticID] = assignment.acousticConfidence
                    reliabilityByAcousticID[acousticID] = assignment.reliability
                    evidenceStrengthByAcousticID[acousticID] = assignment.acousticEvidenceStrength

                    if let resolvedConfidence = assignment.resolvedConfidence {
                        resolvedConfidenceByAcousticID[acousticID] = resolvedConfidence
                    }
                }
            }
        }

        for segment in segments {
            for observationID in segment.observationIDs {
                guard let observation = speakerObservationByID[
                    observationID
                ] else {
                    continue
                }

                for acousticID in observation.acousticObservationIDs {
                    speakerByAcousticID[acousticID] = segment.speaker
                }
            }
        }

        let blocks = enhancement?.blocks.sorted {
            ($0.range?.start ?? 0)
                < ($1.range?.start ?? 0)
        } ?? []

        var blockIndex = 0

        return acoustic.observations.map { raw in
            while blockIndex + 1 < blocks.count,
                  let end = blocks[blockIndex].range?.end,
                  end <= raw.range.start {
                blockIndex += 1
            }

            let gain: Double?

            if blockIndex < blocks.count,
               let range = blocks[blockIndex].range,
               raw.range.start >= range.start,
               raw.range.start < range.end {
                gain = blocks[blockIndex].appliedGainDB
            } else {
                gain = nil
            }

            let enhanced = enhancedByID[
                raw.id
            ]

            let noise = noiseByAcousticID[
                raw.id
            ]

            return .init(
                startSeconds: raw.range.start,
                endSeconds: raw.range.end,
                speaker: speakerByAcousticID[raw.id],
                acousticSpeaker: acousticSpeakerByAcousticID[raw.id],
                temporalAdjusted: temporalAdjustedByAcousticID[raw.id] ?? false,
                speakerAcousticConfidence: acousticConfidenceByAcousticID[raw.id],
                speakerReliability: reliabilityByAcousticID[raw.id],
                speakerEvidenceStrength: evidenceStrengthByAcousticID[raw.id],
                speakerResolvedConfidence: resolvedConfidenceByAcousticID[raw.id],
                rawRMS: raw.signal.rms,
                enhancedRMS: enhanced?.signal.rms,
                enhancementGainDB: gain,
                pitchHz: raw.spectral.pitchHz,
                pitchConfidence: raw.spectral.pitchConfidence,
                voicedProbability: raw.spectral.voicedProbability,
                centroidHz: raw.spectral.centroidHz,
                flatness: raw.spectral.flatness,
                consistency: raw.consistency.consistencyScore,
                transientLikelihood: raw.consistency.transientLikelihood,
                noiseLikelihood: noise?.likelihood,
                noiseLowEnergy: noise?.lowEnergy,
                noiseFlatness: noise?.flatness,
                noiseStationarity: noise?.stationarity,
                noisePitchUnreliability: noise?.pitchUnreliability,
                noiseTransient: noise?.transient,
                rawQuality: raw.quality.score,
                enhancedQuality: enhanced?.quality.score,
                viewAgreement: agreementByAcousticID[raw.id]
            )
        }
    }

    func acousticTraceCSV() -> String {
        let header = [
            "start_seconds",
            "end_seconds",
            "speaker",
            "acoustic_speaker",
            "temporal_adjusted",
            "speaker_acoustic_confidence",
            "speaker_reliability",
            "speaker_evidence_strength",
            "speaker_resolved_confidence",
            "raw_rms",
            "enhanced_rms",
            "enhancement_gain_db",
            "pitch_hz",
            "pitch_confidence",
            "voiced_probability",
            "centroid_hz",
            "flatness",
            "consistency",
            "transient_likelihood",
            "noise_likelihood",
            "noise_low_energy",
            "noise_flatness",
            "noise_stationarity",
            "noise_pitch_unreliability",
            "noise_transient",
            "raw_quality",
            "enhanced_quality",
            "view_agreement",
        ].joined(
            separator: ","
        )

        let rows = acousticTraceRows().map { row in
            [
                traceDecimal(row.startSeconds),
                traceDecimal(row.endSeconds),
                traceCSVField(
                    row.speaker?.rawValue ?? ""
                ),
                traceCSVField(
                    row.acousticSpeaker?.rawValue ?? ""
                ),
                row.temporalAdjusted ? "1" : "0",
                traceOptionalDecimal(row.speakerAcousticConfidence),
                traceOptionalDecimal(row.speakerReliability),
                traceOptionalDecimal(row.speakerEvidenceStrength),
                traceOptionalDecimal(row.speakerResolvedConfidence),
                traceDecimal(row.rawRMS),
                traceOptionalDecimal(row.enhancedRMS),
                traceOptionalDecimal(row.enhancementGainDB),
                traceOptionalDecimal(row.pitchHz),
                traceDecimal(row.pitchConfidence),
                traceDecimal(row.voicedProbability),
                traceDecimal(row.centroidHz),
                traceDecimal(row.flatness),
                traceDecimal(row.consistency),
                traceDecimal(row.transientLikelihood),
                traceOptionalDecimal(row.noiseLikelihood),
                traceOptionalDecimal(row.noiseLowEnergy),
                traceOptionalDecimal(row.noiseFlatness),
                traceOptionalDecimal(row.noiseStationarity),
                traceOptionalDecimal(row.noisePitchUnreliability),
                traceOptionalDecimal(row.noiseTransient),
                traceDecimal(row.rawQuality),
                traceOptionalDecimal(row.enhancedQuality),
                traceOptionalDecimal(row.viewAgreement),
            ].joined(
                separator: ","
            )
        }

        return ([
            header,
        ] + rows).joined(
            separator: "\n"
        ) + "\n"
    }
}

private func traceDecimal(
    _ value: Double
) -> String {
    String(
        format: "%.8f",
        value
    )
}

private func traceOptionalDecimal(
    _ value: Double?
) -> String {
    value.map(
        traceDecimal
    ) ?? ""
}

private func traceCSVField(
    _ value: String
) -> String {
    guard value.contains(",")
        || value.contains("\"")
        || value.contains("\n") else {
        return value
    }

    return "\""
        + value.replacingOccurrences(
            of: "\"",
            with: "\"\""
        )
        + "\""
}
