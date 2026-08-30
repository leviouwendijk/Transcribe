import Foundation

public enum SpeakerClusteringDistanceMetric:
    String,
    Sendable,
    Codable,
    Hashable
{
    case standardizedWeightedSquaredEuclidean = "standardized-weighted-squared-euclidean"
    case cosine
}

func speakerClusteringDistance(
    _ lhs: [Double],
    _ rhs: [Double],
    metric: SpeakerClusteringDistanceMetric
) -> Double {
    switch metric {
    case .standardizedWeightedSquaredEuclidean:
        let count = min(
            lhs.count,
            rhs.count
        )

        guard count > 0 else {
            return 0
        }

        var result = 0.0

        for index in 0..<count {
            let delta = lhs[index]
                - rhs[index]

            result += delta
                * delta
        }

        return result

    case .cosine:
        let count = min(
            lhs.count,
            rhs.count
        )

        guard count > 0,
              lhs.count == rhs.count else {
            return 1
        }

        var dot = 0.0
        var lhsSquared = 0.0
        var rhsSquared = 0.0

        for index in 0..<count {
            dot += lhs[index]
                * rhs[index]
            lhsSquared += lhs[index]
                * lhs[index]
            rhsSquared += rhs[index]
                * rhs[index]
        }

        let denominator = sqrt(lhsSquared)
            * sqrt(rhsSquared)

        guard denominator > 1e-12 else {
            return 1
        }

        let similarity = min(
            1,
            max(
                -1,
                dot / denominator
            )
        )

        return 1 - similarity
    }
}

func normalizedSpeakerClusteringVector(
    _ vector: [Double]
) -> [Double]? {
    guard !vector.isEmpty else {
        return nil
    }

    let norm = sqrt(
        vector.reduce(0) {
            $0 + $1 * $1
        }
    )

    guard norm > 1e-12 else {
        return nil
    }

    return vector.map {
        $0 / norm
    }
}

func speakerEmbeddingClusteringVectors(
    _ observations: [SpeakerObservation]
) -> [[Double]]? {
    guard !observations.isEmpty,
          let dimension = observations.first?.embedding?.dimension,
          dimension > 0 else {
        return nil
    }

    var vectors: [[Double]] = []
    vectors.reserveCapacity(
        observations.count
    )

    for observation in observations {
        guard let embedding = observation.embedding,
              embedding.dimension == dimension,
              let vector = normalizedSpeakerClusteringVector(
                embedding.values.map(Double.init)
              ) else {
            return nil
        }

        vectors.append(
            vector
        )
    }

    return vectors
}
