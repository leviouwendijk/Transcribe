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
    public let acoustic: AcousticAnalyzerConfiguration
    public let speakerObservation: SpeakerObservationBuilder.Configuration

    public init(
        expectedSpeakerCount: Int? = nil,
        maximumSpeakerCount: Int = 4,
        minimumSpeakerObservationsPerCluster: Int = 2,
        minimumSplitImprovement: Double = 0.35,
        maximumIterations: Int = 32,
        segmentMergeGapSeconds: Double = 0.15,
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
            configuration: configuration
        )

        return .init(
            segments: result.segments,
            profiles: result.profiles,
            observations: result.observations,
            acoustic: evidence.raw,
            enhancedAcoustic: evidence.enhanced,
            noiseProfile: evidence.noise,
            enhancement: evidence.enhancement
        )
    }

    public func diarize(
        _ analysis: AcousticAnalysis,
        enhanced: AcousticAnalysis? = nil,
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
                acoustic: analysis
            )
        }

        let originalVectors = observations.map {
            $0.features.values
        }

        let standardizedVectors = standardized(
            originalVectors
        )

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
                configuration: configuration
            )
        }

        let speakerIDs = (0..<clustering.centroids.count).map {
            SpeakerID(
                rawValue: "speaker_\($0 + 1)"
            )
        }

        let confidences = assignmentConfidences(
            vectors: vectors,
            clustering: clustering
        )

        let segments = speakerSegments(
            observations: observations,
            assignments: clustering.assignments,
            confidences: confidences,
            speakerIDs: speakerIDs,
            mergeGapSeconds: configuration.segmentMergeGapSeconds
        )

        let profiles = speakerProfiles(
            observations: observations,
            originalVectors: originalVectors,
            assignments: clustering.assignments,
            speakerIDs: speakerIDs,
            analysis: analysis,
            enhanced: enhanced
        )

        return .init(
            segments: segments,
            profiles: profiles,
            observations: observations,
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
        configuration: DiarizationConfiguration
    ) -> ClusterResult {
        var selected = kMeans(
            vectors: vectors,
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

        let count = min(
            max(
                1,
                count
            ),
            vectors.count
        )

        var centroids: [[Double]] = [
            vectors[0],
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

                if nearest > bestDistance {
                    bestDistance = nearest
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

            centroids = recomputedCentroids(
                vectors: vectors,
                assignments: assignments,
                previous: centroids
            )

            if assignments == previous {
                break
            }
        }

        var squaredError = 0.0

        for index in vectors.indices {
            squaredError += distanceSquared(
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

    func speakerSegments(
        observations: [SpeakerObservation],
        assignments: [Int],
        confidences: [Double],
        speakerIDs: [SpeakerID],
        mergeGapSeconds: Double
    ) -> [SpeakerSegment] {
        var output: [SpeakerSegment] = []

        for index in observations.indices {
            let observation = observations[index]
            let speaker = speakerIDs[
                assignments[index]
            ]

            let segment = SpeakerSegment(
                range: observation.range,
                speaker: speaker,
                confidence: confidences[index],
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

            output[output.count - 1] = .init(
                range: .init(
                    start: previous.range.start,
                    duration: end
                        - previous.range.start
                ),
                speaker: speaker,
                confidence: average(
                    previous.confidence,
                    segment.confidence
                ),
                observationIDs: previous.observationIDs
                    + segment.observationIDs
            )
        }

        return output
    }

    func speakerProfiles(
        observations: [SpeakerObservation],
        originalVectors: [[Double]],
        assignments: [Int],
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

        return speakerIDs.indices.map { cluster in
            let indices = observations.indices.filter {
                assignments[$0] == cluster
            }

            let vectors = indices.map {
                originalVectors[$0]
            }

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
                    meanVector(
                        vectors
                    )
                ),
                acousticDispersion: .init(
                    dispersionVector(
                        vectors
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

    func average(
        _ lhs: Double?,
        _ rhs: Double?
    ) -> Double? {
        switch (
            lhs,
            rhs
        ) {
        case let (.some(lhs), .some(rhs)):
            return (
                lhs + rhs
            ) / 2

        case let (.some(value), .none),
             let (.none, .some(value)):
            return value

        case (.none, .none):
            return nil
        }
    }
}
