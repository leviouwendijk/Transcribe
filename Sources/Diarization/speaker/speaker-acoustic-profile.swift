import Foundation

public struct SpeakerAcousticProfile:
    Sendable,
    Codable,
    Hashable
{
    public let rms: AcousticDistribution
    public let pitchHz: AcousticDistribution
    public let pitchConfidence: AcousticDistribution
    public let centroidHz: AcousticDistribution
    public let flatness: AcousticDistribution
    public let consistency: AcousticDistribution

    public let rawQuality: AcousticDistribution
    public let enhancedQuality: AcousticDistribution
    public let recoveredObservationFraction: Double

    public let logMelMean: [Double]
    public let logMelDispersion: [Double]

    public let viewAgreement: AcousticDistribution
    public let mfccShapeAgreement: AcousticDistribution
    public let logMelShapeAgreement: AcousticDistribution

    public var quality: AcousticDistribution {
        rawQuality
    }

    public var enhancedAgreement: AcousticDistribution {
        viewAgreement
    }

    public init(
        rawObservations: [AcousticObservation],
        enhancedObservations: [AcousticObservation] = [],
        agreements: [AcousticViewAgreement] = []
    ) {
        rms = .init(
            values: rawObservations.map {
                $0.signal.rms
            }
        )
        pitchHz = .init(
            values: rawObservations.compactMap {
                $0.spectral.pitchHz
            }
        )
        pitchConfidence = .init(
            values: rawObservations.map {
                $0.spectral.pitchConfidence
            }
        )
        centroidHz = .init(
            values: rawObservations.map {
                $0.spectral.centroidHz
            }
        )
        flatness = .init(
            values: rawObservations.map {
                $0.spectral.flatness
            }
        )
        consistency = .init(
            values: rawObservations.map {
                $0.consistency.consistencyScore
            }
        )
        rawQuality = .init(
            values: rawObservations.map {
                $0.quality.score
            }
        )
        enhancedQuality = .init(
            values: enhancedObservations.map {
                $0.quality.score
            }
        )

        let enhancedByID = Dictionary(
            uniqueKeysWithValues: enhancedObservations.map {
                (
                    $0.id,
                    $0
                )
            }
        )

        let recovered = rawObservations.filter { observation in
            !observation.quality.isUsableForSpeakerProfile
                && enhancedByID[observation.id]?
                    .quality
                    .isUsableForSpeakerProfile == true
        }.count

        recoveredObservationFraction = rawObservations.isEmpty
            ? 0
            : Double(recovered)
                / Double(rawObservations.count)

        let mel = Self.logMelSummary(
            rawObservations
        )
        logMelMean = mel.mean
        logMelDispersion = mel.dispersion

        viewAgreement = .init(
            values: agreements.map(
                \.combined
            )
        )
        mfccShapeAgreement = .init(
            values: agreements.map(
                \.mfccShape
            )
        )
        logMelShapeAgreement = .init(
            values: agreements.map(
                \.logMelShape
            )
        )
    }
}

private extension SpeakerAcousticProfile {
    static func logMelSummary(
        _ observations: [AcousticObservation]
    ) -> (
        mean: [Double],
        dispersion: [Double]
    ) {
        let count = observations
            .map {
                $0.spectral.logMelEnergies.count
            }
            .min()
            ?? 0

        guard count > 0,
              !observations.isEmpty else {
            return (
                [],
                []
            )
        }

        var mean = Array(
            repeating: 0.0,
            count: count
        )

        for observation in observations {
            for index in 0..<count {
                mean[index] += observation
                    .spectral
                    .logMelEnergies[index]
            }
        }

        for index in mean.indices {
            mean[index] /= Double(
                observations.count
            )
        }

        var dispersion = Array(
            repeating: 0.0,
            count: count
        )

        for observation in observations {
            for index in 0..<count {
                let delta = observation
                    .spectral
                    .logMelEnergies[index]
                    - mean[index]

                dispersion[index] += delta
                    * delta
            }
        }

        for index in dispersion.indices {
            dispersion[index] = sqrt(
                dispersion[index]
                    / Double(observations.count)
            )
        }

        return (
            mean,
            dispersion
        )
    }
}
