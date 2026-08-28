import Foundation
import MediaCore

public struct SpeakerObservationBuilder: Sendable {
    public struct Configuration:
        Sendable,
        Codable,
        Hashable
    {
        public let minimumDurationSeconds: Double
        public let maximumDurationSeconds: Double
        public let maximumGapSeconds: Double
        public let featureWeights: SpeakerFeatureWeights

        public init(
            minimumDurationSeconds: Double = 0.35,
            maximumDurationSeconds: Double = 1.5,
            maximumGapSeconds: Double = 0.12,
            featureWeights: SpeakerFeatureWeights = .init()
        ) {
            precondition(minimumDurationSeconds > 0)
            precondition(maximumDurationSeconds >= minimumDurationSeconds)
            precondition(maximumGapSeconds >= 0)

            self.minimumDurationSeconds = minimumDurationSeconds
            self.maximumDurationSeconds = maximumDurationSeconds
            self.maximumGapSeconds = maximumGapSeconds
            self.featureWeights = featureWeights
        }
    }

    public let configuration: Configuration

    public init(
        configuration: Configuration = .init()
    ) {
        self.configuration = configuration
    }

    public func build(
        from analysis: AcousticAnalysis,
        enhanced: AcousticAnalysis? = nil
    ) -> [SpeakerObservation] {
        let enhancedByID = Dictionary(
            uniqueKeysWithValues: enhanced?.observations.map {
                (
                    $0.id,
                    $0
                )
            } ?? []
        )

        let usable = analysis.observations.filter { observation in
            observation.quality.isUsableForSpeakerProfile
                || enhancedByID[observation.id]?
                    .quality
                    .isUsableForSpeakerProfile == true
        }

        guard !usable.isEmpty else {
            return []
        }

        var groups: [[AcousticObservation]] = []
        var current: [AcousticObservation] = []

        func appendCurrent() {
            guard !current.isEmpty else {
                return
            }

            let duration = current.last!.range.end
                - current.first!.range.start

            if duration >= configuration.minimumDurationSeconds {
                groups.append(
                    current
                )
            }
        }

        for observation in usable {
            guard let previous = current.last else {
                current = [
                    observation,
                ]
                continue
            }

            let gap = observation.range.start
                - previous.range.end

            let prospectiveDuration = observation.range.end
                - current[0].range.start

            if gap <= configuration.maximumGapSeconds,
               prospectiveDuration <= configuration.maximumDurationSeconds {
                current.append(
                    observation
                )
            } else {
                appendCurrent()
                current = [
                    observation,
                ]
            }
        }

        appendCurrent()

        return groups.enumerated().map {
            index,
            group in

            observation(
                id: index,
                group: group,
                enhancedByID: enhancedByID,
                sampleRate: analysis.sampleRate
            )
        }
    }
}

private extension SpeakerObservationBuilder {
    func observation(
        id: Int,
        group: [AcousticObservation],
        enhancedByID: [AcousticObservationID: AcousticObservation],
        sampleRate: Int
    ) -> SpeakerObservation {
        let start = group[0].range.start
        let end = group.last!.range.end
        let raw = featureVector(
            group,
            sampleRate: sampleRate,
            viewWeight: 1
        )
        let enhancedGroup = group.compactMap {
            enhancedByID[$0.id]
        }
        let enhanced = enhancedGroup.isEmpty
            ? nil
            : featureVector(
                enhancedGroup,
                sampleRate: sampleRate,
                viewWeight: configuration.featureWeights.enhancedView
            )

        var values = raw.values
        var weights = raw.weights

        if let enhanced {
            values.append(
                contentsOf: enhanced.values
            )
            weights.append(
                contentsOf: enhanced.weights
            )
        }

        let agreement = enhancedGroup.isEmpty
            ? nil
            : viewAgreement(
                raw: group,
                enhanced: enhancedGroup
            )

        return .init(
            id: .init(
                rawValue: id
            ),
            range: .init(
                start: start,
                duration: end - start
            ),
            acousticObservationIDs: group.map(
                \.id
            ),
            features: .init(
                values,
                weights: weights
            ),
            qualityScore: mean(
                group.map { rawObservation in
                    max(
                        rawObservation.quality.score,
                        enhancedByID[rawObservation.id]?
                            .quality
                            .score
                            ?? 0
                    )
                }
            ),
            viewAgreement: agreement
        )
    }

    func featureVector(
        _ group: [AcousticObservation],
        sampleRate: Int,
        viewWeight: Double
    ) -> SpeakerFeatureVector {
        var values: [Double] = []
        var weights: [Double] = []

        let mfccCount = group
            .map {
                $0.spectral.mfcc.count
            }
            .min()
            ?? 0

        for coefficient in 0..<mfccCount {
            values.append(
                mean(
                    group.map {
                        $0.spectral.mfcc[coefficient]
                    }
                )
            )
            weights.append(
                configuration.featureWeights.mfcc
                    * viewWeight
            )
        }

        for coefficient in 0..<mfccCount {
            values.append(
                standardDeviation(
                    group.map {
                        $0.spectral.mfcc[coefficient]
                    }
                )
            )
            weights.append(
                configuration.featureWeights.mfcc
                    * viewWeight
            )
        }

        let melCount = group
            .map {
                $0.spectral.logMelEnergies.count
            }
            .min()
            ?? 0

        for band in 0..<melCount {
            values.append(
                mean(
                    group.map {
                        $0.spectral.logMelEnergies[band]
                    }
                )
            )
            weights.append(
                configuration.featureWeights.logMel
                    * viewWeight
            )
        }

        let pitches = group.compactMap {
            $0.spectral.pitchHz
        }
        let medianPitch = median(
            pitches
        )

        values.append(
            medianPitch > 0
                ? log2(
                    medianPitch / 100
                )
                : 0
        )
        weights.append(
            configuration.featureWeights.pitch
                * viewWeight
        )

        values.append(
            standardDeviation(
                pitches
            ) / 200
        )
        weights.append(
            configuration.featureWeights.pitch
                * viewWeight
        )

        let sampleRate = max(
            1,
            sampleRate
        )

        for value in [
            mean(
                group.map {
                    $0.spectral.centroidHz
                }
            ) / Double(sampleRate),
            mean(
                group.map {
                    $0.spectral.spreadHz
                }
            ) / Double(sampleRate),
            mean(
                group.map {
                    $0.spectral.rolloffHz
                }
            ) / Double(sampleRate),
            mean(
                group.map {
                    $0.spectral.flatness
                }
            ),
        ] {
            values.append(
                value
            )
            weights.append(
                configuration.featureWeights.spectral
                    * viewWeight
            )
        }

        values.append(
            mean(
                group.map {
                    $0.signal.rms
                }
            )
        )
        weights.append(
            configuration.featureWeights.dynamics
                * viewWeight
        )

        values.append(
            mean(
                group.map {
                    $0.signal.zeroCrossingRate
                }
            )
        )
        weights.append(
            configuration.featureWeights.dynamics
                * viewWeight
        )

        values.append(
            mean(
                group.map {
                    $0.consistency.consistencyScore
                }
            )
        )
        weights.append(
            configuration.featureWeights.consistency
                * viewWeight
        )

        values.append(
            mean(
                group.map {
                    $0.consistency.transientLikelihood
                }
            )
        )
        weights.append(
            configuration.featureWeights.consistency
                * viewWeight
        )

        values.append(
            mean(
                group.map {
                    $0.quality.score
                }
            )
        )
        weights.append(
            configuration.featureWeights.quality
                * viewWeight
        )

        return .init(
            values,
            weights: weights
        )
    }

    func viewAgreement(
        raw: [AcousticObservation],
        enhanced: [AcousticObservation]
    ) -> Double {
        let enhancedByID = Dictionary(
            uniqueKeysWithValues: enhanced.map {
                (
                    $0.id,
                    $0
                )
            }
        )
        var distances: [Double] = []

        for rawObservation in raw {
            guard let enhancedObservation = enhancedByID[
                rawObservation.id
            ] else {
                continue
            }

            distances.append(
                normalizedDistance(
                    rawObservation.spectral.mfcc,
                    enhancedObservation.spectral.mfcc
                )
            )
        }

        guard !distances.isEmpty else {
            return 0
        }

        return exp(
            -mean(distances) / 8
        )
    }

    func normalizedDistance(
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

    func mean(
        _ values: [Double]
    ) -> Double {
        guard !values.isEmpty else {
            return 0
        }

        return values.reduce(0, +)
            / Double(values.count)
    }

    func standardDeviation(
        _ values: [Double]
    ) -> Double {
        guard values.count > 1 else {
            return 0
        }

        let average = mean(
            values
        )

        let variance = values.reduce(0) {
            partial,
            value in

            let delta = value - average
            return partial + delta * delta
        } / Double(values.count)

        return sqrt(
            variance
        )
    }

    func median(
        _ values: [Double]
    ) -> Double {
        guard !values.isEmpty else {
            return 0
        }

        let sorted = values.sorted()
        let middle = sorted.count / 2

        if sorted.count.isMultiple(of: 2) {
            return (
                sorted[middle - 1]
                + sorted[middle]
            ) / 2
        }

        return sorted[middle]
    }
}
