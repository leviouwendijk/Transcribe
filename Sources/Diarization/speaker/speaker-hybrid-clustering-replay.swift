import Foundation

public struct SpeakerHybridCandidate:
    Sendable,
    Codable,
    Hashable
{
    public let name: String
    public let weights: SpeakerHybridClusteringWeights

    public init(
        name: String,
        weights: SpeakerHybridClusteringWeights
    ) {
        self.name = name
        self.weights = weights
    }
}

public struct SpeakerHybridReplayResult:
    Sendable,
    Codable,
    Hashable
{
    public let candidate: SpeakerHybridCandidate
    public let result: DiarizationResult
    public let comparison: SpeakerDiarizationReplayComparison

    public init(
        candidate: SpeakerHybridCandidate,
        result: DiarizationResult,
        comparison: SpeakerDiarizationReplayComparison
    ) {
        self.candidate = candidate
        self.result = result
        self.comparison = comparison
    }
}

public extension Diarizer {
    func replayHybridExperiment(
        _ source: DiarizationResult,
        candidates: [SpeakerHybridCandidate]
    ) -> [SpeakerHybridReplayResult] {
        candidates.compactMap { candidate in
            guard let result = replay(
                source,
                clusteringRepresentation: .hybrid,
                hybridWeights: candidate.weights
            ) else {
                return nil
            }

            return .init(
                candidate: candidate,
                result: result,
                comparison: compare(
                    source,
                    to: result
                )
            )
        }
    }
}

extension Diarizer {
    func hybridReplay(
        _ source: DiarizationResult,
        weights: SpeakerHybridClusteringWeights
    ) -> DiarizationResult? {
        guard let analysis = source.acoustic,
              let method = source.method,
              method.clusteringRepresentation == .acoustic else {
            return nil
        }

        let observations = source.observations

        guard !observations.isEmpty else {
            return .init(
                segments: [],
                profiles: [],
                observations: [],
                assignments: [],
                method: .init(
                    configuration: method.configuration,
                    clusteringRepresentation: .hybrid,
                    hybridWeights: weights,
                    featureWeighting: method.featureWeighting,
                    featureSpace: method.featureSpace,
                    standardization: method.standardization,
                    clustering: .init(
                        observationCount: 0,
                        selectedSpeakerCount: 0,
                        distanceMetric: .fusedNormalizedCandidateCost,
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

        guard source.assignments.count == observations.count,
              let embedding = embeddingReplay(
                source
              ),
              embedding.assignments.count == observations.count,
              let firstAssignment = source.assignments.first,
              !firstAssignment.candidates.isEmpty else {
            return nil
        }

        let speakerIDs = firstAssignment.candidates.map(
            \.speaker
        )
        let speakerSet = Set(
            speakerIDs
        )

        guard speakerSet.count == speakerIDs.count,
              source.assignments.allSatisfy({ assignment in
                Set(
                    assignment.candidates.map(\.speaker)
                ) == speakerSet
              }),
              embedding.assignments.allSatisfy({ assignment in
                Set(
                    assignment.candidates.map(\.speaker)
                ) == speakerSet
              }) else {
            return nil
        }

        let acousticByObservationID = Dictionary(
            uniqueKeysWithValues: source.assignments.map {
                (
                    $0.observationID,
                    $0
                )
            }
        )
        let embeddingByObservationID = Dictionary(
            uniqueKeysWithValues: embedding.assignments.map {
                (
                    $0.observationID,
                    $0
                )
            }
        )

        guard let clusteringAssignments = hybridObservationAssignments(
            observations: observations,
            acousticByObservationID: acousticByObservationID,
            embeddingByObservationID: embeddingByObservationID,
            speakerIDs: speakerIDs,
            weights: weights
        ) else {
            return nil
        }

        let resolvedAssignments = SpeakerTemporalCoherence(
            configuration: method.configuration.temporalCoherence
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
        let indexBySpeaker = Dictionary(
            uniqueKeysWithValues: speakerIDs.enumerated().map {
                (
                    $0.element,
                    $0.offset
                )
            }
        )
        let profileAssignments = resolvedAssignments.map { assignment in
            assignment.changedByContinuity
                ? nil
                : indexBySpeaker[
                    assignment.clusteringSpeaker
                ]
        }
        let reliabilities = clusteringAssignments.map(
            \.reliability
        )

        let segments = speakerSegments(
            observations: observations,
            assignments: resolvedClusters,
            confidences: resolvedConfidences,
            speakerIDs: speakerIDs,
            mergeGapSeconds: method.configuration.segmentMergeGapSeconds
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
        let reliabilityWeightedCost = clusteringAssignments.reduce(
            0.0
        ) { partial, assignment in
            let selectedCost = assignment.candidates.first {
                $0.speaker == assignment.clusteringSpeaker
            }?.clusteringCost ?? 0

            return partial
                + selectedCost
                    * assignment.reliability
        }

        return .init(
            segments: segments,
            profiles: profiles,
            observations: observations,
            assignments: resolvedAssignments,
            method: .init(
                configuration: method.configuration,
                clusteringRepresentation: .hybrid,
                hybridWeights: weights,
                featureWeighting: method.featureWeighting,
                featureSpace: method.featureSpace,
                standardization: method.standardization,
                clustering: .init(
                    observationCount: observations.count,
                    selectedSpeakerCount: speakerIDs.count,
                    distanceMetric: .fusedNormalizedCandidateCost,
                    reliabilityWeightedCost: reliabilityWeightedCost
                )
            ),
            acoustic: source.acoustic,
            enhancedAcoustic: source.enhancedAcoustic,
            noiseProfile: source.noiseProfile,
            noiseEvidence: source.noiseEvidence,
            enhancement: source.enhancement
        )
    }

    func hybridObservationAssignments(
        observations: [SpeakerObservation],
        acousticByObservationID: [SpeakerObservationID: SpeakerObservationAssignment],
        embeddingByObservationID: [SpeakerObservationID: SpeakerObservationAssignment],
        speakerIDs: [SpeakerID],
        weights: SpeakerHybridClusteringWeights
    ) -> [SpeakerObservationAssignment]? {
        var result: [SpeakerObservationAssignment] = []
        result.reserveCapacity(
            observations.count
        )

        for observation in observations {
            guard let acoustic = acousticByObservationID[
                observation.id
            ],
                  let embedding = embeddingByObservationID[
                    observation.id
                  ] else {
                return nil
            }

            let acousticCandidates = Dictionary(
                uniqueKeysWithValues: acoustic.candidates.map {
                    (
                        $0.speaker,
                        $0
                    )
                }
            )
            let embeddingCandidates = Dictionary(
                uniqueKeysWithValues: embedding.candidates.map {
                    (
                        $0.speaker,
                        $0
                    )
                }
            )

            var rawCosts: [Double] = []
            rawCosts.reserveCapacity(
                speakerIDs.count
            )

            for speaker in speakerIDs {
                guard let acousticCandidate = acousticCandidates[
                    speaker
                ],
                      let embeddingCandidate = embeddingCandidates[
                        speaker
                      ] else {
                    return nil
                }

                rawCosts.append(
                    weights.acoustic
                        * acousticCandidate.clusteringCost
                        + weights.embedding
                            * embeddingCandidate.clusteringCost
                )
            }

            guard !rawCosts.isEmpty else {
                return nil
            }

            let bestIndex = rawCosts.indices.min {
                rawCosts[$0]
                    < rawCosts[$1]
            } ?? 0
            let ordered = rawCosts.sorted()
            let nearest = ordered[0]
            let second = ordered.count >= 2
                ? ordered[1]
                : nearest
            let scale = ordered.count >= 2
                ? max(
                    second,
                    1e-12
                )
                : 1
            let confidence: Double

            if ordered.count < 2 {
                confidence = 1
            } else if second <= 1e-12 {
                confidence = 0
            } else {
                confidence = min(
                    1,
                    max(
                        0,
                        1 - nearest / second
                    )
                )
            }

            let candidates = speakerIDs.indices.map { index in
                SpeakerAssignmentCandidate(
                    speaker: speakerIDs[index],
                    clusteringRepresentation: .hybrid,
                    clusteringCost: speakerIDs.count > 1
                        ? rawCosts[index] / scale
                        : 0,
                    distance: rawCosts[index]
                )
            }

            result.append(
                .init(
                    observationID: observation.id,
                    clusteringRepresentation: .hybrid,
                    clusteringSpeaker: speakerIDs[bestIndex],
                    clusteringConfidence: confidence,
                    reliability: acoustic.reliability,
                    reliabilityEvaluation: acoustic.reliabilityEvaluation,
                    candidates: candidates
                )
            )
        }

        return result
    }
}
