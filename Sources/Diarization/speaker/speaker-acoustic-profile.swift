import Foundation

public struct SpeakerAcousticProfile:
    Sendable,
    Codable,
    Hashable
{
    public let rms: AcousticDistribution
    public let pitchHz: AcousticDistribution
    public let centroidHz: AcousticDistribution
    public let flatness: AcousticDistribution
    public let consistency: AcousticDistribution
    public let quality: AcousticDistribution
    public let logMelMean: [Double]
    public let logMelDispersion: [Double]
    public let enhancedAgreement: AcousticDistribution

    public init(
        observations: [AcousticObservation],
        enhancedAgreements: [Double] = []
    ) {
        rms = .init(
            values: observations.map {
                $0.signal.rms
            }
        )
        pitchHz = .init(
            values: observations.compactMap {
                $0.spectral.pitchHz
            }
        )
        centroidHz = .init(
            values: observations.map {
                $0.spectral.centroidHz
            }
        )
        flatness = .init(
            values: observations.map {
                $0.spectral.flatness
            }
        )
        consistency = .init(
            values: observations.map {
                $0.consistency.consistencyScore
            }
        )
        quality = .init(
            values: observations.map {
                $0.quality.score
            }
        )
        enhancedAgreement = .init(
            values: enhancedAgreements
        )

        let melCount = observations
            .map {
                $0.spectral.logMelEnergies.count
            }
            .min()
            ?? 0

        var mean = Array(
            repeating: 0.0,
            count: melCount
        )

        for observation in observations {
            for index in 0..<melCount {
                mean[index] += observation
                    .spectral
                    .logMelEnergies[index]
            }
        }

        if !observations.isEmpty {
            for index in mean.indices {
                mean[index] /= Double(observations.count)
            }
        }

        var dispersion = Array(
            repeating: 0.0,
            count: melCount
        )

        for observation in observations {
            for index in 0..<melCount {
                let delta = observation
                    .spectral
                    .logMelEnergies[index]
                    - mean[index]
                dispersion[index] += delta * delta
            }
        }

        if !observations.isEmpty {
            for index in dispersion.indices {
                dispersion[index] = sqrt(
                    dispersion[index]
                        / Double(observations.count)
                )
            }
        }

        logMelMean = mean
        logMelDispersion = dispersion
    }
}
