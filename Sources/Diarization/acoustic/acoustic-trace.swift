import Foundation
import MediaCore

public struct AcousticDistribution:
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

    public init(
        values: [Double]
    ) {
        let sorted = values.sorted()
        count = sorted.count

        guard !sorted.isEmpty else {
            minimum = 0
            maximum = 0
            mean = 0
            median = 0
            standardDeviation = 0
            q10 = 0
            q25 = 0
            q75 = 0
            q90 = 0
            return
        }

        minimum = sorted[0]
        maximum = sorted[sorted.count - 1]
        let average = sorted.reduce(0, +)
            / Double(sorted.count)

        mean = average
        median = Self.quantile(
            0.5,
            sorted: sorted
        )
        q10 = Self.quantile(
            0.10,
            sorted: sorted
        )
        q25 = Self.quantile(
            0.25,
            sorted: sorted
        )
        q75 = Self.quantile(
            0.75,
            sorted: sorted
        )
        q90 = Self.quantile(
            0.90,
            sorted: sorted
        )

        let variance = sorted.reduce(0) {
            partial,
            value in

            let delta = value - average
            return partial + delta * delta
        } / Double(sorted.count)

        standardDeviation = sqrt(variance)
    }
}

private extension AcousticDistribution {
    static func quantile(
        _ fraction: Double,
        sorted: [Double]
    ) -> Double {
        guard !sorted.isEmpty else {
            return 0
        }

        let position = min(
            1,
            max(
                0,
                fraction
            )
        ) * Double(sorted.count - 1)

        let lower = Int(
            floor(position)
        )
        let upper = Int(
            ceil(position)
        )

        guard lower != upper else {
            return sorted[lower]
        }

        let amount = position
            - Double(lower)

        return sorted[lower]
            + (sorted[upper] - sorted[lower])
                * amount
    }
}

public struct AcousticTraceSample:
    Sendable,
    Codable,
    Hashable
{
    public let observationID: AcousticObservationID
    public let range: Audio.TimeRange
    public let rms: Double
    public let peak: Double
    public let crestFactor: Double
    public let pitchHz: Double?
    public let pitchConfidence: Double
    public let voicedProbability: Double
    public let centroidHz: Double
    public let spreadHz: Double
    public let rolloffHz: Double
    public let flatness: Double
    public let qualityScore: Double
    public let consistency: AcousticConsistencyFeatures
    public let activity: AcousticActivity
}

public struct AcousticTraceSummary:
    Sendable,
    Codable,
    Hashable
{
    public let rms: AcousticDistribution
    public let crestFactor: AcousticDistribution
    public let pitchHz: AcousticDistribution
    public let pitchConfidence: AcousticDistribution
    public let centroidHz: AcousticDistribution
    public let flatness: AcousticDistribution
    public let quality: AcousticDistribution
    public let consistency: AcousticDistribution
    public let transientLikelihood: AcousticDistribution
    public let voicedFraction: Double

    public init(
        samples: [AcousticTraceSample]
    ) {
        rms = .init(
            values: samples.map(\.rms)
        )
        crestFactor = .init(
            values: samples.map(\.crestFactor)
        )
        pitchHz = .init(
            values: samples.compactMap(\.pitchHz)
        )
        pitchConfidence = .init(
            values: samples.map(\.pitchConfidence)
        )
        centroidHz = .init(
            values: samples.map(\.centroidHz)
        )
        flatness = .init(
            values: samples.map(\.flatness)
        )
        quality = .init(
            values: samples.map(\.qualityScore)
        )
        consistency = .init(
            values: samples.map {
                $0.consistency.consistencyScore
            }
        )
        transientLikelihood = .init(
            values: samples.map {
                $0.consistency.transientLikelihood
            }
        )

        voicedFraction = samples.isEmpty
            ? 0
            : Double(
                samples.filter {
                    $0.activity == .voicedSpeech
                }.count
            ) / Double(samples.count)
    }
}

public struct AcousticTrace:
    Sendable,
    Codable,
    Hashable
{
    public let samples: [AcousticTraceSample]
    public let summary: AcousticTraceSummary

    public init(
        samples: [AcousticTraceSample]
    ) {
        self.samples = samples
        summary = .init(
            samples: samples
        )
    }
}

public extension AcousticAnalysis {
    var trace: AcousticTrace {
        let observations = observationsWithConsistency()

        return .init(
            samples: observations.map { observation in
                .init(
                    observationID: observation.id,
                    range: observation.range,
                    rms: observation.signal.rms,
                    peak: observation.signal.peak,
                    crestFactor: observation.signal.rms > 1e-12
                        ? observation.signal.peak
                            / observation.signal.rms
                        : 0,
                    pitchHz: observation.spectral.pitchHz,
                    pitchConfidence: observation.spectral.pitchConfidence,
                    voicedProbability: observation.spectral.voicedProbability,
                    centroidHz: observation.spectral.centroidHz,
                    spreadHz: observation.spectral.spreadHz,
                    rolloffHz: observation.spectral.rolloffHz,
                    flatness: observation.spectral.flatness,
                    qualityScore: observation.quality.score,
                    consistency: observation.consistency,
                    activity: observation.activity
                )
            }
        )
    }

    func observationsWithConsistency() -> [AcousticObservation] {
        var previous: AcousticObservation?

        return observations.map { observation in
            let consistency = Self.consistency(
                previous: previous,
                current: observation,
                sampleRate: sampleRate
            )

            previous = observation

            return .init(
                id: observation.id,
                range: observation.range,
                signal: observation.signal,
                spectral: observation.spectral,
                consistency: consistency,
                activity: observation.activity,
                quality: observation.quality
            )
        }
    }
}

private extension AcousticAnalysis {
    static func consistency(
        previous: AcousticObservation?,
        current: AcousticObservation,
        sampleRate: Int
    ) -> AcousticConsistencyFeatures {
        guard let previous else {
            return .neutral
        }

        let sampleTolerance = 1
            / Double(
                max(
                    1,
                    sampleRate
                )
            )

        guard current.range.start
            <= previous.range.end + sampleTolerance else {
            return .neutral
        }

        let energyDeltaDB = abs(
            db(current.signal.rms)
                - db(previous.signal.rms)
        )

        let nyquist = max(
            1,
            Double(sampleRate) / 2
        )

        let centroidDelta = abs(
            current.spectral.centroidHz
                - previous.spectral.centroidHz
        ) / nyquist

        let spreadDelta = abs(
            current.spectral.spreadHz
                - previous.spectral.spreadHz
        ) / nyquist

        let flatnessDelta = abs(
            current.spectral.flatness
                - previous.spectral.flatness
        )

        let spectralDelta = min(
            1,
            centroidDelta
                + spreadDelta
                + flatnessDelta
        )

        let mfccDelta = normalizedDistance(
            current.spectral.mfcc,
            previous.spectral.mfcc
        )

        let pitchDelta = pitchDeltaSemitones(
            current.spectral.pitchHz,
            previous.spectral.pitchHz
        )

        let pitchPenalty = min(
            1,
            (pitchDelta ?? 0) / 12
        )

        let energyPenalty = min(
            1,
            energyDeltaDB / 18
        )

        let change = min(
            1,
            0.30 * energyPenalty
                + 0.35 * spectralDelta
                + 0.25 * min(1, mfccDelta / 8)
                + 0.10 * pitchPenalty
        )

        let transient = min(
            1,
            max(
                change,
                energyPenalty * spectralDelta
            )
        )

        return .init(
            energyDeltaDB: energyDeltaDB,
            spectralDelta: spectralDelta,
            mfccDelta: mfccDelta,
            pitchDeltaSemitones: pitchDelta,
            consistencyScore: 1 - change,
            transientLikelihood: transient
        )
    }

    static func normalizedDistance(
        _ lhs: [Double],
        _ rhs: [Double]
    ) -> Double {
        let count = min(
            lhs.count,
            rhs.count
        )

        guard count > 0 else {
            return 0
        }

        var squared = 0.0

        for index in 0..<count {
            let delta = lhs[index]
                - rhs[index]
            squared += delta * delta
        }

        return sqrt(
            squared / Double(count)
        )
    }

    static func pitchDeltaSemitones(
        _ lhs: Double?,
        _ rhs: Double?
    ) -> Double? {
        guard let lhs,
              let rhs,
              lhs > 0,
              rhs > 0 else {
            return nil
        }

        return abs(
            12 * log2(lhs / rhs)
        )
    }

    static func db(
        _ value: Double
    ) -> Double {
        20 * log10(
            max(
                value,
                1e-12
            )
        )
    }
}
