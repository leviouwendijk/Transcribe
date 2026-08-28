import Foundation

public struct AcousticTraceExportRow:
    Sendable,
    Codable,
    Hashable
{
    public let startSeconds: Double
    public let endSeconds: Double
    public let speaker: SpeakerID?

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

    public let rawQuality: Double
    public let enhancedQuality: Double?
    public let viewAgreement: Double?

    public init(
        startSeconds: Double,
        endSeconds: Double,
        speaker: SpeakerID?,
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
        rawQuality: Double,
        enhancedQuality: Double?,
        viewAgreement: Double?
    ) {
        self.startSeconds = startSeconds
        self.endSeconds = endSeconds
        self.speaker = speaker
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

        var speakerByAcousticID: [AcousticObservationID: SpeakerID] = [:]
        var agreementByAcousticID: [AcousticObservationID: Double] = [:]

        for observation in observations {
            if let agreement = observation.viewAgreement?.combined {
                for acousticID in observation.acousticObservationIDs {
                    agreementByAcousticID[acousticID] = agreement
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

            return .init(
                startSeconds: raw.range.start,
                endSeconds: raw.range.end,
                speaker: speakerByAcousticID[raw.id],
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
