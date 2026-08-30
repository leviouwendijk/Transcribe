import Foundation

private struct SpeakerEmbeddingClusterResult {
    let assignments: [Int]
    let centroids: [[Double]]
    let cost: Double
}

public extension Diarizer {
    /// Reinterprets retained speaker observations using the requested identity
    /// representation. Embedding replay requires one compatible embedding for
    /// every retained speaker observation. Hybrid inference remains
    /// intentionally unsupported until acoustic and embedding calibration has
    /// been established independently.
    func replay(
        _ source: DiarizationResult,
        clusteringRepresentation: SpeakerClusteringRepresentation
    ) -> DiarizationResult? {
        switch clusteringRepresentation {
        case .acoustic:
            return replay(
                source
            )

        case .embedding:
            return embeddingReplay(
                source
            )

        case .hybrid:
            return nil
        }
    }
}

private extension Diarizer {
    func embeddingReplay(
        _ source: DiarizationResult
    ) -> DiarizationResult? {
        guard let analysis = source.acoustic,
              let method = source.method,
              let vectors = speakerEmbeddingClusteringVectors(
                source.observations
              ) else {
            return nil
        }

        let replayConfiguration = SpeakerDiarizationReplayConfiguration(
            method
        )
        let configuration = replayConfiguration.resolved(
            preservingNonReplayableFrom: method.configuration
        )
        let observations = source.observations

        guard !observations.isEmpty else {
            return .init(
                segments: [],
                profiles: [],
                observations: [],
                assignments: [],
                method: .init(
                    configuration: configuration,
                    clusteringRepresentation: .embedding,
                    featureWeighting: replayConfiguration.featureWeighting,
                    featureSpace: [],
                    standardization: .empty,
                    clustering: .init(
                        observationCount: 0,
                        selectedSpeakerCount: 0,
                        distanceMetric: .cosine,
                        reliabilityWeightedCost: 0
                    )
                ),
                acoustic: source.acoustic,
                enhancedAcoustic: source.enhancedAcoustic,
                noiseProfile: source.noiseProfile,
                noiseEvidence: source.noiseEvidence,
                enhancement: source.enhancement
            )
        }

        let reliabilityEvaluations = speakerObservationReliabilityEvaluations(
            observations: observations,
            noiseEvidence: source.noiseEvidence,
            configuration: configuration.speakerReliability
        )
        let reliabilities = reliabilityEvaluations.map(
            \.reliability
        )

        let clustering: SpeakerEmbeddingClusterResult

        if let expected = configuration.expectedSpeakerCount {
            clustering = embeddingKMeans(
                vectors: vectors,
                reliabilities: reliabilities,
                count: min(
                    max(
                        1,
                        expected
                    ),
                    observations.count
                ),
                maximumIterations: configuration.maximumIterations
            )
        } else {
            clustering = automaticEmbeddingClustering(
                vectors: vectors,
                reliabilities: reliabilities,
                configuration: configuration
            )
        }

        let speakerIDs = embeddingSpeakerIDs(
            source: source,
            observations: observations,
            assignments: clustering.assignments,
            clusterCount: clustering.centroids.count
        )
        let clusteringConfidences = embeddingAssignmentConfidences(
            vectors: vectors,
            centroids: clustering.centroids
        )
        let clusteringAssignments = embeddingObservationAssignments(
            observations: observations,
            vectors: vectors,
            clustering: clustering,
            clusteringConfidences: clusteringConfidences,
            reliabilityEvaluations: reliabilityEvaluations,
            speakerIDs: speakerIDs
        )
        let resolvedAssignments = SpeakerTemporalCoherence(
            configuration: configuration.temporalCoherence
        ).resolve(
            observations: observations,
            assignments: clusteringAssignments
        )
        let resolvedClusters = resolvedClusterAssignments(
            resolvedAssignments,
            speakerIDs: speakerIDs
        )
        let resolvedConfidences = resolvedAssignments.map {
            $0.resolvedConfidence
                ?? 0
        }
        let profileAssignments = resolvedAssignments.indices.map {
            resolvedAssignments[$0].changedByContinuity
                ? nil
                : Optional(
                    clustering.assignments[$0]
                )
        }

        let segments = speakerSegments(
            observations: observations,
            assignments: resolvedClusters,
            confidences: resolvedConfidences,
            speakerIDs: speakerIDs,
            mergeGapSeconds: configuration.segmentMergeGapSeconds
        )
        let profiles = speakerProfiles(
            observations: observations,
            originalVectors: observations.map {
                $0.features.values
            },
            assignments: profileAssignments,
            reliabilities: reliabilities,
            speakerIDs: speakerIDs,
            analysis: analysis,
            enhanced: source.enhancedAcoustic
        )

        return .init(
            segments: segments,
            profiles: profiles,
            observations: observations,
            assignments: resolvedAssignments,
            method: .init(
                configuration: configuration,
                clusteringRepresentation: .embedding,
                featureWeighting: replayConfiguration.featureWeighting,
                featureSpace: [],
                standardization: .empty,
                clustering: .init(
                    observationCount: observations.count,
                    selectedSpeakerCount: clustering.centroids.count,
                    distanceMetric: .cosine,
                    reliabilityWeightedCost: clustering.cost
                )
            ),
            acoustic: source.acoustic,
            enhancedAcoustic: source.enhancedAcoustic,
            noiseProfile: source.noiseProfile,
            noiseEvidence: source.noiseEvidence,
            enhancement: source.enhancement
        )
    }

    func automaticEmbeddingClustering(
        vectors: [[Double]],
        reliabilities: [Double],
        configuration: DiarizationConfiguration
    ) -> SpeakerEmbeddingClusterResult {
        var selected = embeddingKMeans(
            vectors: vectors,
            reliabilities: reliabilities,
            count: 1,
            maximumIterations: configuration.maximumIterations
        )

        let possibleByPopulation = max(
            1,
            vectors.count
                / configuration.minimumSpeakerObservationsPerCluster
        )
        let maximum = min(
            configuration.maximumSpeakerCount,
            possibleByPopulation,
            vectors.count
        )

        guard maximum > 1 else {
            return selected
        }

        for count in 2...maximum {
            let candidate = embeddingKMeans(
                vectors: vectors,
                reliabilities: reliabilities,
                count: count,
                maximumIterations: configuration.maximumIterations
            )
            let clusterCounts = counts(
                assignments: candidate.assignments,
                clusterCount: count
            )

            guard clusterCounts.allSatisfy({
                $0 >= configuration.minimumSpeakerObservationsPerCluster
            }) else {
                break
            }

            let denominator = max(
                selected.cost,
                1e-12
            )
            let improvement = (
                selected.cost
                    - candidate.cost
            ) / denominator

            guard improvement
                >= configuration.minimumSplitImprovement else {
                break
            }

            selected = candidate
        }

        return selected
    }

    func embeddingKMeans(
        vectors: [[Double]],
        reliabilities: [Double],
        count requestedCount: Int,
        maximumIterations: Int
    ) -> SpeakerEmbeddingClusterResult {
        guard !vectors.isEmpty else {
            return .init(
                assignments: [],
                centroids: [],
                cost: 0
            )
        }

        let count = min(
            max(
                1,
                requestedCount
            ),
            vectors.count
        )
        let effectiveReliabilities = vectors.indices.map { index in
            index < reliabilities.count
                ? max(
                    0,
                    reliabilities[index]
                )
                : 1
        }

        let firstIndex = vectors.indices.max {
            effectiveReliabilities[$0]
                < effectiveReliabilities[$1]
        } ?? 0

        var centroids = [
            vectors[firstIndex],
        ]

        while centroids.count < count {
            var bestIndex = 0
            var bestScore = -Double.infinity

            for index in vectors.indices {
                let nearest = centroids.map {
                    speakerClusteringDistance(
                        vectors[index],
                        $0,
                        metric: .cosine
                    )
                }.min() ?? 0
                let score = nearest
                    * max(
                        effectiveReliabilities[index],
                        1e-9
                    )

                if score > bestScore {
                    bestScore = score
                    bestIndex = index
                }
            }

            centroids.append(
                vectors[bestIndex]
            )
        }

        var assignments = Array(
            repeating: 0,
            count: vectors.count
        )

        for _ in 0..<maximumIterations {
            let previous = assignments

            for index in vectors.indices {
                assignments[index] = nearestEmbeddingCentroid(
                    vector: vectors[index],
                    centroids: centroids
                )
            }

            centroids = embeddingCentroids(
                vectors: vectors,
                assignments: assignments,
                reliabilities: effectiveReliabilities,
                previous: centroids
            )

            if assignments == previous {
                break
            }
        }

        var cost = 0.0

        for index in vectors.indices {
            cost += effectiveReliabilities[index]
                * speakerClusteringDistance(
                    vectors[index],
                    centroids[assignments[index]],
                    metric: .cosine
                )
        }

        return .init(
            assignments: assignments,
            centroids: centroids,
            cost: cost
        )
    }

    func nearestEmbeddingCentroid(
        vector: [Double],
        centroids: [[Double]]
    ) -> Int {
        var bestIndex = 0
        var bestDistance = Double.infinity

        for index in centroids.indices {
            let distance = speakerClusteringDistance(
                vector,
                centroids[index],
                metric: .cosine
            )

            if distance < bestDistance {
                bestDistance = distance
                bestIndex = index
            }
        }

        return bestIndex
    }

    func embeddingCentroids(
        vectors: [[Double]],
        assignments: [Int],
        reliabilities: [Double],
        previous: [[Double]]
    ) -> [[Double]] {
        reliabilityRecomputedCentroids(
            vectors: vectors,
            assignments: assignments,
            reliabilities: reliabilities,
            previous: previous
        ).enumerated().map {
            index,
            vector in

            normalizedSpeakerClusteringVector(
                vector
            ) ?? previous[index]
        }
    }

    func embeddingAssignmentConfidences(
        vectors: [[Double]],
        centroids: [[Double]]
    ) -> [Double] {
        guard centroids.count > 1 else {
            return Array(
                repeating: 1,
                count: vectors.count
            )
        }

        return vectors.map { vector in
            let distances = centroids.map {
                speakerClusteringDistance(
                    vector,
                    $0,
                    metric: .cosine
                )
            }.sorted()

            guard distances.count >= 2 else {
                return 1
            }

            let nearest = distances[0]
            let second = distances[1]

            return min(
                1,
                max(
                    0,
                    1 - nearest
                        / max(
                            second,
                            1e-12
                        )
                )
            )
        }
    }

    func embeddingObservationAssignments(
        observations: [SpeakerObservation],
        vectors: [[Double]],
        clustering: SpeakerEmbeddingClusterResult,
        clusteringConfidences: [Double],
        reliabilityEvaluations: [SpeakerEvidenceReliabilityEvaluation],
        speakerIDs: [SpeakerID]
    ) -> [SpeakerObservationAssignment] {
        observations.indices.map { index in
            let distances = clustering.centroids.map {
                speakerClusteringDistance(
                    vectors[index],
                    $0,
                    metric: .cosine
                )
            }
            let ordered = distances.sorted()
            let scale = ordered.count >= 2
                ? max(
                    ordered[1],
                    1e-12
                )
                : 1

            let candidates = speakerIDs.indices.map { speakerIndex in
                SpeakerAssignmentCandidate(
                    speaker: speakerIDs[speakerIndex],
                    clusteringRepresentation: .embedding,
                    clusteringCost: speakerIDs.count > 1
                        ? distances[speakerIndex] / scale
                        : 0,
                    distance: distances[speakerIndex]
                )
            }
            let reliabilityEvaluation = reliabilityEvaluations[index]

            return .init(
                observationID: observations[index].id,
                clusteringRepresentation: .embedding,
                clusteringSpeaker: speakerIDs[
                    clustering.assignments[index]
                ],
                clusteringConfidence: clusteringConfidences[index],
                reliability: reliabilityEvaluation.reliability,
                reliabilityEvaluation: reliabilityEvaluation,
                candidates: candidates
            )
        }
    }

    func embeddingSpeakerIDs(
        source: DiarizationResult,
        observations: [SpeakerObservation],
        assignments: [Int],
        clusterCount: Int
    ) -> [SpeakerID] {
        guard clusterCount > 0 else {
            return []
        }

        let sourceAssignmentByID = Dictionary(
            uniqueKeysWithValues: source.assignments.map {
                (
                    $0.observationID,
                    $0
                )
            }
        )
        let baselineSpeakers = Array(
            Set(
                source.assignments.map(
                    \.resolvedSpeaker
                )
            )
        ).sorted {
            $0.rawValue < $1.rawValue
        }

        guard !baselineSpeakers.isEmpty else {
            return (0..<clusterCount).map {
                SpeakerID(
                    rawValue: "speaker_\($0 + 1)"
                )
            }
        }

        struct Match {
            let cluster: Int
            let speaker: SpeakerID
            let overlap: Int
        }

        var matches: [Match] = []

        for cluster in 0..<clusterCount {
            var overlapBySpeaker: [SpeakerID: Int] = [:]

            for index in observations.indices
            where assignments[index] == cluster {
                guard let baseline = sourceAssignmentByID[
                    observations[index].id
                ] else {
                    continue
                }

                overlapBySpeaker[
                    baseline.resolvedSpeaker,
                    default: 0
                ] += 1
            }

            for speaker in baselineSpeakers {
                matches.append(
                    .init(
                        cluster: cluster,
                        speaker: speaker,
                        overlap: overlapBySpeaker[speaker] ?? 0
                    )
                )
            }
        }

        matches.sort { lhs, rhs in
            if lhs.overlap != rhs.overlap {
                return lhs.overlap > rhs.overlap
            }

            if lhs.cluster != rhs.cluster {
                return lhs.cluster < rhs.cluster
            }

            return lhs.speaker.rawValue
                < rhs.speaker.rawValue
        }

        var speakerByCluster: [Int: SpeakerID] = [:]
        var usedSpeakers = Set<SpeakerID>()

        for match in matches
        where match.overlap > 0 {
            guard speakerByCluster[match.cluster] == nil,
                  !usedSpeakers.contains(match.speaker) else {
                continue
            }

            speakerByCluster[match.cluster] = match.speaker
            usedSpeakers.insert(
                match.speaker
            )
        }

        var nextGeneratedIndex = 1

        for cluster in 0..<clusterCount
        where speakerByCluster[cluster] == nil {
            if let available = baselineSpeakers.first(
                where: {
                    !usedSpeakers.contains($0)
                }
            ) {
                speakerByCluster[cluster] = available
                usedSpeakers.insert(
                    available
                )
                continue
            }

            var generated: SpeakerID

            repeat {
                generated = SpeakerID(
                    rawValue: "speaker_\(nextGeneratedIndex)"
                )
                nextGeneratedIndex += 1
            } while usedSpeakers.contains(
                generated
            )

            speakerByCluster[cluster] = generated
            usedSpeakers.insert(
                generated
            )
        }

        return (0..<clusterCount).map {
            speakerByCluster[$0]
                ?? SpeakerID(
                    rawValue: "speaker_\($0 + 1)"
                )
        }
    }
}
