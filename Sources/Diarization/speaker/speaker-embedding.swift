public enum SpeakerEmbeddingNormalization:
    String,
    Sendable,
    Codable,
    Hashable
{
    case none
    case l2
}

public struct SpeakerEmbeddingProvenance:
    Sendable,
    Codable,
    Hashable
{
    public let modelIdentifier: String?
    public let normalization: SpeakerEmbeddingNormalization

    public init(
        modelIdentifier: String? = nil,
        normalization: SpeakerEmbeddingNormalization = .none
    ) {
        self.modelIdentifier = modelIdentifier
        self.normalization = normalization
    }
}

public struct SpeakerEmbedding:
    Sendable,
    Codable,
    Hashable
{
    public let values: [Float]
    public let provenance: SpeakerEmbeddingProvenance?

    public init(
        _ values: [Float],
        provenance: SpeakerEmbeddingProvenance? = nil
    ) {
        self.values = values
        self.provenance = provenance
    }

    public var dimension: Int {
        values.count
    }

    public var l2Norm: Double {
        values.reduce(0.0) {
            $0 + Double($1) * Double($1)
        }.squareRoot()
    }

    public var l2Normalized: Self? {
        let norm = l2Norm

        guard norm > 1e-12 else {
            return nil
        }

        return .init(
            values.map {
                Float(
                    Double($0) / norm
                )
            },
            provenance: .init(
                modelIdentifier: provenance?.modelIdentifier,
                normalization: .l2
            )
        )
    }
}

public struct SpeakerEmbeddingDistance:
    Sendable,
    Codable,
    Hashable
{
    public let cosineSimilarity: Double
    public let cosineDistance: Double

    public init?(
        _ lhs: SpeakerEmbedding,
        _ rhs: SpeakerEmbedding
    ) {
        guard !lhs.values.isEmpty,
              lhs.values.count == rhs.values.count else {
            return nil
        }

        var dot = 0.0
        var lhsSquared = 0.0
        var rhsSquared = 0.0

        for index in lhs.values.indices {
            let lhsValue = Double(
                lhs.values[index]
            )
            let rhsValue = Double(
                rhs.values[index]
            )

            dot += lhsValue * rhsValue
            lhsSquared += lhsValue * lhsValue
            rhsSquared += rhsValue * rhsValue
        }

        let denominator = lhsSquared.squareRoot()
            * rhsSquared.squareRoot()

        guard denominator > 1e-12 else {
            return nil
        }

        let similarity = min(
            1,
            max(
                -1,
                dot / denominator
            )
        )

        cosineSimilarity = similarity
        cosineDistance = 1 - similarity
    }
}

public struct SpeakerEmbeddingProfile:
    Sendable,
    Codable,
    Hashable
{
    public let centroid: SpeakerEmbedding
    public let dispersion: Double
    public let evidenceCount: Int

    public init(
        centroid: SpeakerEmbedding,
        dispersion: Double,
        evidenceCount: Int
    ) {
        self.centroid = centroid
        self.dispersion = max(
            0,
            dispersion
        )
        self.evidenceCount = max(
            0,
            evidenceCount
        )
    }

    public init?(
        embeddings: [SpeakerEmbedding]
    ) {
        guard let dimension = embeddings.first?.dimension,
              dimension > 0,
              embeddings.allSatisfy({
                  $0.dimension == dimension
              }) else {
            return nil
        }

        let normalized = embeddings.compactMap {
            $0.l2Normalized
        }

        guard normalized.count == embeddings.count else {
            return nil
        }

        var mean = Array(
            repeating: 0.0,
            count: dimension
        )

        for embedding in normalized {
            for index in 0..<dimension {
                mean[index] += Double(
                    embedding.values[index]
                )
            }
        }

        for index in mean.indices {
            mean[index] /= Double(
                normalized.count
            )
        }

        let commonModelIdentifier = embeddings
            .map {
                $0.provenance?.modelIdentifier
            }
            .allSatisfy({
                $0 == embeddings.first?.provenance?.modelIdentifier
            })
            ? embeddings.first?.provenance?.modelIdentifier
            : nil

        guard let centroid = SpeakerEmbedding(
            mean.map(Float.init),
            provenance: .init(
                modelIdentifier: commonModelIdentifier,
                normalization: .none
            )
        ).l2Normalized else {
            return nil
        }

        let distances = normalized.compactMap {
            SpeakerEmbeddingDistance(
                $0,
                centroid
            )?.cosineDistance
        }

        guard distances.count == normalized.count else {
            return nil
        }

        let dispersion = (
            distances.reduce(0.0) {
                $0 + $1 * $1
            }
                / Double(distances.count)
        ).squareRoot()

        self.init(
            centroid: centroid,
            dispersion: dispersion,
            evidenceCount: normalized.count
        )
    }
}

public enum SpeakerClusteringEvidence:
    Sendable,
    Codable,
    Hashable
{
    case acoustic(SpeakerFeatureVector)
    case embedding(SpeakerEmbedding)
    case hybrid(
        acoustic: SpeakerFeatureVector,
        embedding: SpeakerEmbedding
    )
}

public extension SpeakerObservation {
    func clusteringEvidence(
        for representation: SpeakerClusteringRepresentation
    ) -> SpeakerClusteringEvidence? {
        switch representation {
        case .acoustic:
            .acoustic(
                features
            )

        case .embedding:
            embedding.map(
                SpeakerClusteringEvidence.embedding
            )

        case .hybrid:
            embedding.map {
                .hybrid(
                    acoustic: features,
                    embedding: $0
                )
            }
        }
    }
}
