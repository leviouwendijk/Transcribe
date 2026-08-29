import Foundation
import MediaCore

public struct DiarizationConfiguration:
    Sendable,
    Codable,
    Hashable
{
    public let expectedSpeakerCount: Int?
    public let maximumSpeakerCount: Int
    public let minimumSpeakerObservationsPerCluster: Int
    public let minimumSplitImprovement: Double
    public let maximumIterations: Int
    public let segmentMergeGapSeconds: Double
    public let temporalCoherence: SpeakerTemporalCoherenceConfiguration
    public let speakerReliability: SpeakerEvidenceReliabilityConfiguration
    public let acoustic: AcousticAnalyzerConfiguration
    public let speakerObservation: SpeakerObservationBuilder.Configuration

    public init(
        expectedSpeakerCount: Int? = nil,
        maximumSpeakerCount: Int = 4,
        minimumSpeakerObservationsPerCluster: Int = 2,
        minimumSplitImprovement: Double = 0.35,
        maximumIterations: Int = 32,
        segmentMergeGapSeconds: Double = 0.15,
        temporalCoherence: SpeakerTemporalCoherenceConfiguration = .init(),
        speakerReliability: SpeakerEvidenceReliabilityConfiguration = .init(),
        acoustic: AcousticAnalyzerConfiguration = .init(),
        speakerObservation: SpeakerObservationBuilder.Configuration = .init()
    ) {
        if let expectedSpeakerCount {
            precondition(expectedSpeakerCount > 0)
        }

        precondition(maximumSpeakerCount > 0)
        precondition(minimumSpeakerObservationsPerCluster > 0)
        precondition(minimumSplitImprovement >= 0)
        precondition(maximumIterations > 0)
        precondition(segmentMergeGapSeconds >= 0)

        self.expectedSpeakerCount = expectedSpeakerCount
        self.maximumSpeakerCount = maximumSpeakerCount
        self.minimumSpeakerObservationsPerCluster = minimumSpeakerObservationsPerCluster
        self.minimumSplitImprovement = minimumSplitImprovement
        self.maximumIterations = maximumIterations
        self.segmentMergeGapSeconds = segmentMergeGapSeconds
        self.temporalCoherence = temporalCoherence
        self.speakerReliability = speakerReliability
        self.acoustic = acoustic
        self.speakerObservation = speakerObservation
    }
}

public struct Diarizer: Sendable {
    public init() {}

    public func diarize(
        _ buffer: MediaAudioBuffer,
        startingAt startTime: TimeInterval = 0,
        configuration: DiarizationConfiguration = .init()
    ) throws -> DiarizationResult {
        let analysis = try AcousticAnalyzer(
            configuration: configuration.acoustic
        ).analyze(
            buffer,
            startingAt: startTime
        )

        return diarize(
            analysis,
            configuration: configuration
        )
    }

    public func diarize(
        _ chunk: MediaAudioChunk,
        configuration: DiarizationConfiguration = .init()
    ) throws -> DiarizationResult {
        let analysis = try AcousticAnalyzer(
            configuration: configuration.acoustic
        ).analyze(
            chunk
        )

        return diarize(
            analysis,
            configuration: configuration
        )
    }

    public func diarize(
        _ evidence: ParallelAcousticEvidence,
        configuration: DiarizationConfiguration = .init()
    ) -> DiarizationResult {
        let result = diarize(
            evidence.raw,
            enhanced: evidence.enhanced,
            noiseEvidence: evidence.noiseEvidence,
            configuration: configuration
        )

        return .init(
            segments: result.segments,
            profiles: result.profiles,
            observations: result.observations,
            assignments: result.assignments,
            method: result.method,
            acoustic: evidence.raw,
            enhancedAcoustic: evidence.enhanced,
            noiseProfile: evidence.noise,
            noiseEvidence: evidence.noiseEvidence,
            enhancement: evidence.enhancement
        )
    }

    public func diarize(
        _ analysis: AcousticAnalysis,
        enhanced: AcousticAnalysis? = nil,
        noiseEvidence: [AcousticNoiseEvidence] = [],
        configuration: DiarizationConfiguration = .init()
    ) -> DiarizationResult {
        let observations = SpeakerObservationBuilder(
            configuration: configuration.speakerObservation
        ).build(
            from: analysis,
            enhanced: enhanced
        )

        guard !observations.isEmpty else {
            return .init(
                segments: [],
                profiles: [],
                observations: [],
                method: .init(
                    configuration: configuration
                ),
                acoustic: analysis
            )
        }

        let reliabilityEvaluations = speakerObservationReliabilityEvaluations(
            observations: observations,
            noiseEvidence: noiseEvidence,
            configuration: configuration.speakerReliability
        )

        let reliabilities = reliabilityEvaluations.map(
            \.reliability
        )

        let originalVectors = observations.map {
            $0.features.values
        }

        let standardization = reliabilityStandardization(
            originalVectors,
            weights: reliabilities
        )

        let standardizedVectors = standardization.vectors

        let vectors = standardizedVectors.enumerated().map {
            index,
            vector in

            weighted(
                vector,
                weights: observations[index].features.weights
            )
        }

        let clustering: ClusterResult

        if let expected = configuration.expectedSpeakerCount {
            clustering = kMeans(
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
            clustering = automaticClustering(
                vectors: vectors,
                reliabilities: reliabilities,
                configuration: configuration
            )
        }

        let speakerIDs = (0..<clustering.centroids.count).map {
            SpeakerID(
                rawValue: "speaker_\($0 + 1)"
            )
        }

        let acousticConfidences = assignmentConfidences(
            vectors: vectors,
            clustering: clustering
        )

        let acousticAssignments = speakerObservationAssignments(
            observations: observations,
            vectors: vectors,
            clustering: clustering,
            acousticConfidences: acousticConfidences,
            reliabilityEvaluations: reliabilityEvaluations,
            speakerIDs: speakerIDs
        )

        let resolvedAssignments = SpeakerTemporalCoherence(
            configuration: configuration.temporalCoherence
        ).resolve(
            observations: observations,
            assignments: acousticAssignments
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
            originalVectors: originalVectors,
            assignments: profileAssignments,
            reliabilities: reliabilities,
            speakerIDs: speakerIDs,
            analysis: analysis,
            enhanced: enhanced
        )

        return .init(
            segments: segments,
            profiles: profiles,
            observations: observations,
            assignments: resolvedAssignments,
            method: .init(
                configuration: configuration,
                featureSpace: observations.first?.features.coordinates ?? [],
                standardization: standardization.model,
                clustering: .init(
                    observationCount: observations.count,
                    selectedSpeakerCount: clustering.centroids.count,
                    reliabilityWeightedSquaredError: clustering.squaredError
                )
            ),
            acoustic: analysis
        )
    }
}

private struct ClusterResult {
    let assignments: [Int]
    let centroids: [[Double]]
    let squaredError: Double
}

private extension Diarizer {
    func automaticClustering(
        vectors: [[Double]],
        reliabilities: [Double],
        configuration: DiarizationConfiguration
    ) -> ClusterResult {
        var selected = kMeans(
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

        guard maximum >= 2,
              selected.squaredError > 1e-12 else {
            return selected
        }

        for count in 2...maximum {
            let candidate = kMeans(
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

            let improvement = (
                selected.squaredError
                - candidate.squaredError
            ) / max(
                selected.squaredError,
                1e-12
            )

            guard improvement
                >= configuration.minimumSplitImprovement else {
                break
            }

            selected = candidate
        }

        return selected
    }

    func kMeans(
        vectors: [[Double]],
        reliabilities requestedReliabilities: [Double],
        count: Int,
        maximumIterations: Int
    ) -> ClusterResult {
        guard !vectors.isEmpty else {
            return .init(
                assignments: [],
                centroids: [],
                squaredError: 0
            )
        }

        let reliabilities = requestedReliabilities.count
            == vectors.count
            ? requestedReliabilities
            : Array(
                repeating: 1,
                count: vectors.count
            )

        let count = min(
            max(
                1,
                count
            ),
            vectors.count
        )

        var firstIndex = 0

        for index in vectors.indices.dropFirst() {
            if reliabilities[index]
                > reliabilities[firstIndex] {
                firstIndex = index
            }
        }

        var centroids: [[Double]] = [
            vectors[firstIndex],
        ]

        while centroids.count < count {
            var bestIndex = 0
            var bestDistance = -Double.infinity

            for index in vectors.indices {
                let nearest = centroids
                    .map {
                        distanceSquared(
                            vectors[index],
                            $0
                        )
                    }
                    .min()
                    ?? 0

                let score = nearest
                    * reliabilities[index]

                if score > bestDistance {
                    bestDistance = score
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
                assignments[index] = nearestCentroid(
                    vector: vectors[index],
                    centroids: centroids
                )
            }

            centroids = reliabilityRecomputedCentroids(
                vectors: vectors,
                assignments: assignments,
                reliabilities: reliabilities,
                previous: centroids
            )

            if assignments == previous {
                break
            }
        }

        var squaredError = 0.0

        for index in vectors.indices {
            squaredError += reliabilities[index]
                * distanceSquared(
                    vectors[index],
                    centroids[assignments[index]]
                )
        }

        return .init(
            assignments: assignments,
            centroids: centroids,
            squaredError: squaredError
        )
    }

    func standardized(
        _ vectors: [[Double]]
    ) -> [[Double]] {
        guard let dimension = vectors
            .map(\.count)
            .min(),
              dimension > 0 else {
            return vectors
        }

        var means = Array(
            repeating: 0.0,
            count: dimension
        )

        for vector in vectors {
            for index in 0..<dimension {
                means[index] += vector[index]
            }
        }

        for index in means.indices {
            means[index] /= Double(vectors.count)
        }

        var deviations = Array(
            repeating: 0.0,
            count: dimension
        )

        for vector in vectors {
            for index in 0..<dimension {
                let delta = vector[index]
                    - means[index]

                deviations[index] += delta
                    * delta
            }
        }

        for index in deviations.indices {
            deviations[index] = sqrt(
                deviations[index]
                    / Double(vectors.count)
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

    func nearestCentroid(
        vector: [Double],
        centroids: [[Double]]
    ) -> Int {
        var bestIndex = 0
        var bestDistance = Double.infinity

        for index in centroids.indices {
            let distance = distanceSquared(
                vector,
                centroids[index]
            )

            if distance < bestDistance {
                bestDistance = distance
                bestIndex = index
            }
        }

        return bestIndex
    }

    func recomputedCentroids(
        vectors: [[Double]],
        assignments: [Int],
        previous: [[Double]]
    ) -> [[Double]] {
        guard let dimension = previous.first?.count else {
            return previous
        }

        var sums = Array(
            repeating: Array(
                repeating: 0.0,
                count: dimension
            ),
            count: previous.count
        )

        var counts = Array(
            repeating: 0,
            count: previous.count
        )

        for index in vectors.indices {
            let cluster = assignments[index]
            counts[cluster] += 1

            for dimensionIndex in 0..<dimension {
                sums[cluster][dimensionIndex] += vectors[index][dimensionIndex]
            }
        }

        return previous.indices.map { cluster in
            guard counts[cluster] > 0 else {
                return previous[cluster]
            }

            return sums[cluster].map {
                $0 / Double(counts[cluster])
            }
        }
    }

    func assignmentConfidences(
        vectors: [[Double]],
        clustering: ClusterResult
    ) -> [Double] {
        guard clustering.centroids.count > 1 else {
            return Array(
                repeating: 1,
                count: vectors.count
            )
        }

        return vectors.map { vector in
            let distances = clustering.centroids
                .map {
                    distanceSquared(
                        vector,
                        $0
                    )
                }
                .sorted()

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

    func speakerObservationAssignments(
        observations: [SpeakerObservation],
        vectors: [[Double]],
        clustering: ClusterResult,
        acousticConfidences: [Double],
        reliabilityEvaluations: [SpeakerEvidenceReliabilityEvaluation],
        speakerIDs: [SpeakerID]
    ) -> [SpeakerObservationAssignment] {
        observations.indices.map { index in
            let distances = clustering.centroids.map {
                distanceSquared(
                    vectors[index],
                    $0
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
                let squaredDistance = distances[speakerIndex]

                return SpeakerAssignmentCandidate(
                    speaker: speakerIDs[speakerIndex],
                    acousticCost: speakerIDs.count > 1
                        ? squaredDistance / scale
                        : 0,
                    squaredDistance: squaredDistance,
                    featureContributions: speakerFeatureContributions(
                        vector: vectors[index],
                        centroid: clustering.centroids[speakerIndex],
                        coordinates: observations[index].features.coordinates
                    )
                )
            }

            let reliabilityEvaluation = reliabilityEvaluations[index]

            return .init(
                observationID: observations[index].id,
                acousticSpeaker: speakerIDs[
                    clustering.assignments[index]
                ],
                acousticConfidence: acousticConfidences[index],
                reliability: reliabilityEvaluation.reliability,
                reliabilityEvaluation: reliabilityEvaluation,
                candidates: candidates
            )
        }
    }

    func speakerFeatureContributions(
        vector: [Double],
        centroid: [Double],
        coordinates: [SpeakerFeatureCoordinate]
    ) -> [SpeakerFeatureContribution] {
        let count = min(
            vector.count,
            centroid.count,
            coordinates.count
        )

        guard count > 0 else {
            return []
        }

        struct Key: Hashable {
            let view: SpeakerFeatureView
            let family: SpeakerFeatureFamily
            let weight: Double
        }

        var distanceByKey: [Key: Double] = [:]

        for index in 0..<count {
            let coordinate = coordinates[index]
            let delta = vector[index]
                - centroid[index]
            let key = Key(
                view: coordinate.view,
                family: coordinate.family,
                weight: coordinate.weight
            )

            distanceByKey[key, default: 0] += delta * delta
        }

        let total = distanceByKey.values.reduce(
            0,
            +
        )

        return distanceByKey.map { key, distance in
            .init(
                view: key.view,
                family: key.family,
                weight: key.weight,
                squaredDistance: distance,
                fractionOfSquaredDistance: total > 1e-12
                    ? distance / total
                    : 0
            )
        }.sorted { lhs, rhs in
            if lhs.view.rawValue == rhs.view.rawValue {
                return lhs.family.rawValue < rhs.family.rawValue
            }

            return lhs.view.rawValue < rhs.view.rawValue
        }
    }

    func resolvedClusterAssignments(
        _ assignments: [SpeakerObservationAssignment],
        speakerIDs: [SpeakerID]
    ) -> [Int] {
        let indexBySpeaker = Dictionary(
            uniqueKeysWithValues: speakerIDs.enumerated().map {
                (
                    $0.element,
                    $0.offset
                )
            }
        )

        return assignments.map { assignment in
            indexBySpeaker[assignment.resolvedSpeaker]
                ?? indexBySpeaker[assignment.acousticSpeaker]
                ?? 0
        }
    }

    func speakerSegments(
        observations: [SpeakerObservation],
        assignments: [Int],
        confidences: [Double],
        speakerIDs: [SpeakerID],
        mergeGapSeconds: Double
    ) -> [SpeakerSegment] {
        let observationIndexByID = Dictionary(
            uniqueKeysWithValues: observations.indices.map {
                (
                    observations[$0].id,
                    $0
                )
            }
        )

        func confidence(
            for observationIDs: [SpeakerObservationID]
        ) -> Double? {
            var weightedConfidence = 0.0
            var totalWeight = 0.0

            for observationID in observationIDs {
                guard let index = observationIndexByID[observationID],
                      index < confidences.count else {
                    continue
                }

                let weight = max(
                    observations[index].range.duration,
                    1e-12
                )

                weightedConfidence += confidences[index]
                    * weight
                totalWeight += weight
            }

            guard totalWeight > 0 else {
                return nil
            }

            return weightedConfidence
                / totalWeight
        }

        var output: [SpeakerSegment] = []

        for index in observations.indices {
            let observation = observations[index]
            let speaker = speakerIDs[
                assignments[index]
            ]

            let segment = SpeakerSegment(
                range: observation.range,
                speaker: speaker,
                confidence: index < confidences.count
                    ? confidences[index]
                    : nil,
                observationIDs: [
                    observation.id,
                ]
            )

            guard let previous = output.last,
                  previous.speaker == speaker,
                  segment.range.start
                    - previous.range.end
                    <= mergeGapSeconds else {
                output.append(
                    segment
                )
                continue
            }

            let end = max(
                previous.range.end,
                segment.range.end
            )

            let observationIDs = previous.observationIDs
                + segment.observationIDs

            output[output.count - 1] = .init(
                range: .init(
                    start: previous.range.start,
                    duration: end
                        - previous.range.start
                ),
                speaker: speaker,
                confidence: confidence(
                    for: observationIDs
                ),
                observationIDs: observationIDs
            )
        }

        return output
    }

    func speakerProfiles(
        observations: [SpeakerObservation],
        originalVectors: [[Double]],
        assignments: [Int?],
        reliabilities: [Double],
        speakerIDs: [SpeakerID],
        analysis: AcousticAnalysis,
        enhanced: AcousticAnalysis?
    ) -> [SpeakerProfile] {
        let acousticByID = Dictionary(
            uniqueKeysWithValues: analysis.observations.map {
                (
                    $0.id,
                    $0
                )
            }
        )

        let enhancedByID = Dictionary(
            uniqueKeysWithValues: enhanced?.observations.map {
                (
                    $0.id,
                    $0
                )
            } ?? []
        )

        return speakerIDs.indices.compactMap { cluster in
            let indices = observations.indices.filter {
                assignments[$0] == .some(
                    cluster
                )
            }

            guard !indices.isEmpty else {
                return nil
            }

            let vectors = indices.map {
                originalVectors[$0]
            }

            let modelReliabilities = indices.map {
                reliabilities[$0]
            }

            let centroid = reliabilityWeightedMeanVector(
                vectors,
                weights: modelReliabilities
            )

            let acousticObservations = indices.flatMap { index in
                observations[index]
                    .acousticObservationIDs
                    .compactMap {
                        acousticByID[$0]
                    }
            }

            let enhancedObservations = indices.flatMap { index in
                observations[index]
                    .acousticObservationIDs
                    .compactMap {
                        enhancedByID[$0]
                    }
            }

            let agreements = indices.compactMap {
                observations[$0].viewAgreement
            }

            return SpeakerProfile(
                speaker: speakerIDs[cluster],
                observationCount: indices.count,
                observedDurationSeconds: indices.reduce(0) {
                    $0 + observations[$1].range.duration
                },
                acousticCentroid: .init(
                    centroid
                ),
                acousticDispersion: .init(
                    reliabilityWeightedDispersionVector(
                        vectors,
                        weights: modelReliabilities,
                        mean: centroid
                    )
                ),
                acousticProfile: .init(
                    rawObservations: acousticObservations,
                    enhancedObservations: enhancedObservations,
                    agreements: agreements
                )
            )
        }
    }

    func meanVector(
        _ vectors: [[Double]]
    ) -> [Double] {
        guard let dimension = vectors
            .map(\.count)
            .min(),
              dimension > 0 else {
            return []
        }

        var result = Array(
            repeating: 0.0,
            count: dimension
        )

        for vector in vectors {
            for index in 0..<dimension {
                result[index] += vector[index]
            }
        }

        guard !vectors.isEmpty else {
            return result
        }

        return result.map {
            $0 / Double(vectors.count)
        }
    }

    func dispersionVector(
        _ vectors: [[Double]]
    ) -> [Double] {
        let average = meanVector(
            vectors
        )

        guard !average.isEmpty,
              !vectors.isEmpty else {
            return []
        }

        var result = Array(
            repeating: 0.0,
            count: average.count
        )

        for vector in vectors {
            for index in average.indices {
                let delta = vector[index]
                    - average[index]

                result[index] += delta
                    * delta
            }
        }

        return result.map {
            sqrt(
                $0 / Double(vectors.count)
            )
        }
    }

    func weighted(
        _ vector: [Double],
        weights: [Double]
    ) -> [Double] {
        vector.indices.map { index in
            let weight = index < weights.count
                ? weights[index]
                : 1

            return vector[index]
                * sqrt(
                    max(
                        0,
                        weight
                    )
                )
        }
    }

    func distanceSquared(
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

        var result = 0.0

        for index in 0..<count {
            let delta = lhs[index]
                - rhs[index]

            result += delta
                * delta
        }

        return result
    }

    func counts(
        assignments: [Int],
        clusterCount: Int
    ) -> [Int] {
        var result = Array(
            repeating: 0,
            count: clusterCount
        )

        for assignment in assignments {
            result[assignment] += 1
        }

        return result
    }

}
