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

public struct AcousticNoiseEvidence:
    Sendable,
    Codable,
    Hashable
{
    public let observationID: AcousticObservationID
    public let likelihood: Double
    public let lowEnergy: Double
    public let flatness: Double
    public let stationarity: Double
    public let pitchUnreliability: Double
    public let transient: Double

    public init(
        observationID: AcousticObservationID,
        likelihood: Double,
        lowEnergy: Double,
        flatness: Double,
        stationarity: Double,
        pitchUnreliability: Double,
        transient: Double
    ) {
        self.observationID = observationID
        self.likelihood = Self.clamp(likelihood)
        self.lowEnergy = Self.clamp(lowEnergy)
        self.flatness = Self.clamp(flatness)
        self.stationarity = Self.clamp(stationarity)
        self.pitchUnreliability = Self.clamp(pitchUnreliability)
        self.transient = Self.clamp(transient)
    }
}

public extension AcousticNoiseProfile {
    func evidence(
        for analysis: AcousticAnalysis
    ) -> [AcousticNoiseEvidence] {
        analysis.observations.map {
            evidence(
                for: $0
            )
        }
    }

    func evidence(
        for observation: AcousticObservation
    ) -> AcousticNoiseEvidence {
        guard observationCount > 0 else {
            return .init(
                observationID: observation.id,
                likelihood: 0,
                lowEnergy: 0,
                flatness: 0,
                stationarity: 0,
                pitchUnreliability: 0,
                transient: 0
            )
        }

        let noiseRMS = max(
            rms.q90,
            1e-9
        )

        let rmsRatio = observation.signal.rms
            / noiseRMS

        let lowEnergy = 1
            / (1 + rmsRatio * rmsRatio)

        let flatnessReference = max(
            flatness.median,
            0.05
        )

        let flatnessEvidence = AcousticNoiseEvidence.clamp(
            observation.spectral.flatness
                / flatnessReference
        )

        let stationarityReference = max(
            stationarity.median,
            0.10
        )

        let stationarityEvidence = AcousticNoiseEvidence.clamp(
            observation.consistency.consistencyScore
                / stationarityReference
        )

        let pitchUnreliability = observation.spectral.pitchHz == nil
            ? 1
            : 1 - observation.spectral.pitchConfidence

        let transient = observation
            .consistency
            .transientLikelihood

        let likelihood = 0.40 * flatnessEvidence
            + 0.15 * lowEnergy
            + 0.15 * stationarityEvidence
            + 0.25 * pitchUnreliability
            + 0.05 * transient

        return .init(
            observationID: observation.id,
            likelihood: likelihood,
            lowEnergy: lowEnergy,
            flatness: flatnessEvidence,
            stationarity: stationarityEvidence,
            pitchUnreliability: pitchUnreliability,
            transient: transient
        )
    }
}

private extension AcousticNoiseEvidence {
    static func clamp(
        _ value: Double
    ) -> Double {
        min(
            1,
            max(
                0,
                value
            )
        )
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
    public let noiseEvidence: [AcousticNoiseEvidence]
    public let enhancement: AcousticEnhancementSummary

    public init(
        raw: AcousticAnalysis,
        enhanced: AcousticAnalysis,
        noise: AcousticNoiseProfile,
        noiseEvidence: [AcousticNoiseEvidence] = [],
        enhancement: AcousticEnhancementSummary
    ) {
        self.raw = raw
        self.enhanced = enhanced
        self.noise = noise
        self.noiseEvidence = noiseEvidence
        self.enhancement = enhancement
    }
}
