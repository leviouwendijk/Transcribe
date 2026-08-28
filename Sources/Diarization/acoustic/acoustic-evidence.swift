import Foundation
import MediaCore

public struct AcousticNoiseProfile:
    Sendable,
    Codable,
    Hashable
{
    public let observationCount: Int
    public let rms: AcousticDistribution
    public let flatness: AcousticDistribution
    public let stationarity: AcousticDistribution
    public let logMelMean: [Double]
    public let logMelDispersion: [Double]

    public init(
        analysis: AcousticAnalysis
    ) {
        let candidates = analysis.observations.filter {
            $0.activity == .silence
                || $0.activity == .noise
        }

        observationCount = candidates.count
        rms = .init(
            values: candidates.map {
                $0.signal.rms
            }
        )
        flatness = .init(
            values: candidates.map {
                $0.spectral.flatness
            }
        )
        stationarity = .init(
            values: candidates.map {
                $0.consistency.consistencyScore
            }
        )

        let melCount = candidates
            .map {
                $0.spectral.logMelEnergies.count
            }
            .min()
            ?? 0

        var mean = Array(
            repeating: 0.0,
            count: melCount
        )

        for observation in candidates {
            for index in 0..<melCount {
                mean[index] += observation
                    .spectral
                    .logMelEnergies[index]
            }
        }

        if !candidates.isEmpty {
            for index in mean.indices {
                mean[index] /= Double(candidates.count)
            }
        }

        var dispersion = Array(
            repeating: 0.0,
            count: melCount
        )

        for observation in candidates {
            for index in 0..<melCount {
                let delta = observation
                    .spectral
                    .logMelEnergies[index]
                    - mean[index]
                dispersion[index] += delta * delta
            }
        }

        if !candidates.isEmpty {
            for index in dispersion.indices {
                dispersion[index] = sqrt(
                    dispersion[index]
                        / Double(candidates.count)
                )
            }
        }

        logMelMean = mean
        logMelDispersion = dispersion
    }
}

public struct AcousticEnhancementBlock:
    Sendable,
    Codable,
    Hashable
{
    public let range: Audio.TimeRange?
    public let inputRMSDB: Double
    public let outputRMSDB: Double
    public let appliedGainDB: Double

    public init(
        range: Audio.TimeRange?,
        inputRMSDB: Double,
        outputRMSDB: Double,
        appliedGainDB: Double
    ) {
        self.range = range
        self.inputRMSDB = inputRMSDB
        self.outputRMSDB = outputRMSDB
        self.appliedGainDB = appliedGainDB
    }
}

public struct AcousticEnhancementSummary:
    Sendable,
    Codable,
    Hashable
{
    public let blocks: [AcousticEnhancementBlock]
    public let blockCount: Int
    public let appliedGainDB: AcousticDistribution
    public let inputRMSDB: AcousticDistribution
    public let outputRMSDB: AcousticDistribution
    public let recoveredUsableObservationCount: Int

    public init(
        blocks: [AcousticEnhancementBlock],
        recoveredUsableObservationCount: Int
    ) {
        self.blocks = blocks
        blockCount = blocks.count
        appliedGainDB = .init(
            values: blocks.map(
                \.appliedGainDB
            )
        )
        inputRMSDB = .init(
            values: blocks.map(
                \.inputRMSDB
            )
        )
        outputRMSDB = .init(
            values: blocks.map(
                \.outputRMSDB
            )
        )
        self.recoveredUsableObservationCount = recoveredUsableObservationCount
    }
}

public struct ParallelAcousticEvidence:
    Sendable,
    Codable,
    Hashable
{
    public let raw: AcousticAnalysis
    public let enhanced: AcousticAnalysis
    public let noise: AcousticNoiseProfile
    public let enhancement: AcousticEnhancementSummary

    public init(
        raw: AcousticAnalysis,
        enhanced: AcousticAnalysis,
        noise: AcousticNoiseProfile,
        enhancement: AcousticEnhancementSummary
    ) {
        self.raw = raw
        self.enhanced = enhanced
        self.noise = noise
        self.enhancement = enhancement
    }
}
