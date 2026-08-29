import Foundation

func speakerObservationReliabilities(
    observations: [SpeakerObservation],
    noiseEvidence: [AcousticNoiseEvidence]
) -> [Double] {
    guard !noiseEvidence.isEmpty else {
        return Array(
            repeating: 1,
            count: observations.count
        )
    }

    let noiseByID = Dictionary(
        uniqueKeysWithValues: noiseEvidence.map {
            (
                $0.observationID,
                $0.likelihood
            )
        }
    )

    return observations.map { observation in
        let likelihoods = observation
            .acousticObservationIDs
            .compactMap {
                noiseByID[$0]
            }
            .sorted()

        guard !likelihoods.isEmpty else {
            return 1
        }

        let middle = likelihoods.count / 2
        let likelihood = likelihoods.count.isMultiple(of: 2)
            ? (
                likelihoods[middle - 1]
                    + likelihoods[middle]
            ) / 2
            : likelihoods[middle]

        return speakerEvidenceReliability(
            noiseLikelihood: likelihood
        )
    }
}

func speakerEvidenceReliability(
    noiseLikelihood: Double
) -> Double {
    let t = min(
        1,
        max(
            0,
            (noiseLikelihood - 0.55)
                / 0.25
        )
    )

    let smooth = t
        * t
        * (3 - 2 * t)

    return 1
        - 0.80 * smooth
}

func reliabilityStandardized(
    _ vectors: [[Double]],
    weights: [Double]
) -> [[Double]] {
    guard let dimension = vectors
        .map(\.count)
        .min(),
          dimension > 0,
          vectors.count == weights.count else {
        return vectors
    }

    let totalWeight = weights.reduce(
        0,
        +
    )

    guard totalWeight > 1e-12 else {
        return vectors
    }

    var means = Array(
        repeating: 0.0,
        count: dimension
    )

    for index in vectors.indices {
        let weight = weights[index]

        for dimensionIndex in 0..<dimension {
            means[dimensionIndex] += vectors[index][dimensionIndex]
                * weight
        }
    }

    for index in means.indices {
        means[index] /= totalWeight
    }

    var deviations = Array(
        repeating: 0.0,
        count: dimension
    )

    for index in vectors.indices {
        let weight = weights[index]

        for dimensionIndex in 0..<dimension {
            let delta = vectors[index][dimensionIndex]
                - means[dimensionIndex]

            deviations[dimensionIndex] += weight
                * delta
                * delta
        }
    }

    for index in deviations.indices {
        deviations[index] = sqrt(
            deviations[index]
                / totalWeight
        )
    }

    return vectors.map { vector in
        (0..<dimension).map { index in
            let deviation = deviations[index]

            guard deviation > 1e-9 else {
                return 0
            }

            return (
                vector[index]
                    - means[index]
            ) / deviation
        }
    }
}

func reliabilityRecomputedCentroids(
    vectors: [[Double]],
    assignments: [Int],
    reliabilities: [Double],
    previous: [[Double]]
) -> [[Double]] {
    guard let dimension = previous.first?.count,
          vectors.count == reliabilities.count else {
        return previous
    }

    var sums = Array(
        repeating: Array(
            repeating: 0.0,
            count: dimension
        ),
        count: previous.count
    )

    var weightTotals = Array(
        repeating: 0.0,
        count: previous.count
    )

    for index in vectors.indices {
        let cluster = assignments[index]
        let reliability = reliabilities[index]

        weightTotals[cluster] += reliability

        for dimensionIndex in 0..<dimension {
            sums[cluster][dimensionIndex] += vectors[index][dimensionIndex]
                * reliability
        }
    }

    return previous.indices.map { cluster in
        guard weightTotals[cluster] > 1e-12 else {
            return previous[cluster]
        }

        return sums[cluster].map {
            $0 / weightTotals[cluster]
        }
    }
}

func reliabilityWeightedMeanVector(
    _ vectors: [[Double]],
    weights: [Double]
) -> [Double] {
    guard let dimension = vectors
        .map(\.count)
        .min(),
          dimension > 0,
          vectors.count == weights.count else {
        return []
    }

    var result = Array(
        repeating: 0.0,
        count: dimension
    )

    var totalWeight = 0.0

    for index in vectors.indices {
        let weight = weights[index]
        totalWeight += weight

        for dimensionIndex in 0..<dimension {
            result[dimensionIndex] += vectors[index][dimensionIndex]
                * weight
        }
    }

    guard totalWeight > 1e-12 else {
        return result
    }

    return result.map {
        $0 / totalWeight
    }
}

func reliabilityWeightedDispersionVector(
    _ vectors: [[Double]],
    weights: [Double],
    mean: [Double]
) -> [Double] {
    guard !mean.isEmpty,
          vectors.count == weights.count else {
        return []
    }

    var result = Array(
        repeating: 0.0,
        count: mean.count
    )

    var totalWeight = 0.0

    for index in vectors.indices {
        let weight = weights[index]
        totalWeight += weight

        for dimensionIndex in 0..<min(
            mean.count,
            vectors[index].count
        ) {
            let delta = vectors[index][dimensionIndex]
                - mean[dimensionIndex]

            result[dimensionIndex] += weight
                * delta
                * delta
        }
    }

    guard totalWeight > 1e-12 else {
        return result
    }

    return result.map {
        sqrt(
            $0 / totalWeight
        )
    }
}
