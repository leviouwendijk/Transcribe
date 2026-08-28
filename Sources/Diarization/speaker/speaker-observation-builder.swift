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

        public init(
            minimumDurationSeconds: Double = 0.35,
            maximumDurationSeconds: Double = 1.5,
            maximumGapSeconds: Double = 0.12
        ) {
            precondition(minimumDurationSeconds > 0)
            precondition(maximumDurationSeconds >= minimumDurationSeconds)
            precondition(maximumGapSeconds >= 0)

            self.minimumDurationSeconds = minimumDurationSeconds
            self.maximumDurationSeconds = maximumDurationSeconds
            self.maximumGapSeconds = maximumGapSeconds
        }
    }

    public let configuration: Configuration

    public init(
        configuration: Configuration = .init()
    ) {
        self.configuration = configuration
    }

    public func build(
        from analysis: AcousticAnalysis
    ) -> [SpeakerObservation] {
        let usable = analysis.observations.filter {
            $0.quality.isUsableForSpeakerProfile
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
                sampleRate: analysis.sampleRate
            )
        }
    }
}

private extension SpeakerObservationBuilder {
    func observation(
        id: Int,
        group: [AcousticObservation],
        sampleRate: Int
    ) -> SpeakerObservation {
        let start = group[0].range.start
        let end = group.last!.range.end

        let mfccCount = group
            .map {
                $0.spectral.mfcc.count
            }
            .min()
            ?? 0

        var values: [Double] = []

        for coefficient in 0..<mfccCount {
            let coefficientValues = group.map {
                $0.spectral.mfcc[coefficient]
            }

            values.append(
                mean(
                    coefficientValues
                )
            )
        }

        for coefficient in 0..<mfccCount {
            let coefficientValues = group.map {
                $0.spectral.mfcc[coefficient]
            }

            values.append(
                standardDeviation(
                    coefficientValues
                )
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

        values.append(
            standardDeviation(
                pitches
            ) / 200
        )

        let sampleRate = max(
            1,
            sampleRate
        )

        values.append(
            mean(
                group.map {
                    $0.spectral.centroidHz
                }
            ) / Double(sampleRate)
        )

        values.append(
            mean(
                group.map {
                    $0.spectral.spreadHz
                }
            ) / Double(sampleRate)
        )

        values.append(
            mean(
                group.map {
                    $0.spectral.rolloffHz
                }
            ) / Double(sampleRate)
        )

        values.append(
            mean(
                group.map {
                    $0.spectral.flatness
                }
            )
        )

        values.append(
            mean(
                group.map {
                    $0.signal.zeroCrossingRate
                }
            )
        )

        values.append(
            mean(
                group.map {
                    $0.spectral.voicedProbability
                }
            )
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
                values
            ),
            qualityScore: mean(
                group.map {
                    $0.quality.score
                }
            )
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
