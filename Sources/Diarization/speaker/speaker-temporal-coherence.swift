import Foundation

public struct SpeakerTemporalCoherenceConfiguration:
    Sendable,
    Codable,
    Hashable
{
    public let switchPenalty: Double
    public let maximumContinuityGapSeconds: Double

    public init(
        switchPenalty: Double = 0.35,
        maximumContinuityGapSeconds: Double = 0.45
    ) {
        precondition(switchPenalty >= 0)
        precondition(maximumContinuityGapSeconds >= 0)

        self.switchPenalty = switchPenalty
        self.maximumContinuityGapSeconds = maximumContinuityGapSeconds
    }
}

public struct SpeakerAssignmentCandidate:
    Sendable,
    Codable,
    Hashable
{
    public let speaker: SpeakerID
    public let acousticCost: Double
    public let squaredDistance: Double
    public let featureContributions: [SpeakerFeatureContribution]

    public init(
        speaker: SpeakerID,
        acousticCost: Double,
        squaredDistance: Double = 0,
        featureContributions: [SpeakerFeatureContribution] = []
    ) {
        self.speaker = speaker
        self.acousticCost = max(
            0,
            acousticCost
        )
        self.squaredDistance = max(
            0,
            squaredDistance
        )
        self.featureContributions = featureContributions
    }
}

public struct SpeakerObservationAssignment:
    Sendable,
    Codable,
    Hashable
{
    public let observationID: SpeakerObservationID
    public let acousticSpeaker: SpeakerID
    public let resolvedSpeaker: SpeakerID
    public let acousticConfidence: Double
    public let reliabilityEvaluation: SpeakerEvidenceReliabilityEvaluation
    public let candidates: [SpeakerAssignmentCandidate]
    public let temporalTransition: SpeakerTransitionEvaluation?

    public init(
        observationID: SpeakerObservationID,
        acousticSpeaker: SpeakerID,
        resolvedSpeaker: SpeakerID? = nil,
        acousticConfidence: Double,
        reliability: Double,
        reliabilityEvaluation: SpeakerEvidenceReliabilityEvaluation? = nil,
        candidates: [SpeakerAssignmentCandidate],
        temporalTransition: SpeakerTransitionEvaluation? = nil
    ) {
        self.observationID = observationID
        self.acousticSpeaker = acousticSpeaker
        self.resolvedSpeaker = resolvedSpeaker
            ?? acousticSpeaker
        self.acousticConfidence = min(
            1,
            max(
                0,
                acousticConfidence
            )
        )
        self.reliabilityEvaluation = reliabilityEvaluation
            ?? .init(
                noiseLikelihood: nil,
                sourceObservationCount: 0,
                taper: 0,
                reliability: reliability
            )
        self.candidates = candidates
        self.temporalTransition = temporalTransition
    }

    public var reliability: Double {
        reliabilityEvaluation.reliability
    }

    public var changedByContinuity: Bool {
        acousticSpeaker != resolvedSpeaker
    }

    public var acousticEvidenceStrength: Double {
        acousticConfidence
            * reliability
    }

    public var resolvedConfidence: Double? {
        changedByContinuity
            ? nil
            : acousticEvidenceStrength
    }
}

public struct SpeakerTemporalCoherence: Sendable {
    public let configuration: SpeakerTemporalCoherenceConfiguration

    public init(
        configuration: SpeakerTemporalCoherenceConfiguration = .init()
    ) {
        self.configuration = configuration
    }

    public func resolve(
        observations: [SpeakerObservation],
        assignments: [SpeakerObservationAssignment]
    ) -> [SpeakerObservationAssignment] {
        guard !assignments.isEmpty,
              observations.count == assignments.count,
              zip(
                observations,
                assignments
              ).allSatisfy({
                  $0.0.id == $0.1.observationID
              }) else {
            return assignments
        }

        let speakers = Array(
            Set(
                assignments.flatMap {
                    $0.candidates.map(
                        \.speaker
                    )
                }
            )
        ).sorted {
            $0.rawValue < $1.rawValue
        }

        guard speakers.count > 1 else {
            return assignments
        }

        let observationCount = assignments.count
        let speakerCount = speakers.count

        var costs = Array(
            repeating: Array(
                repeating: Double.infinity,
                count: speakerCount
            ),
            count: observationCount
        )

        var predecessors = Array(
            repeating: Array(
                repeating: 0,
                count: speakerCount
            ),
            count: observationCount
        )

        for speakerIndex in speakers.indices {
            costs[0][speakerIndex] = emissionCost(
                assignment: assignments[0],
                speaker: speakers[speakerIndex]
            )
        }

        if observationCount > 1 {
            for observationIndex in 1..<observationCount {
                let previousObservation = observations[
                    observationIndex - 1
                ]
                let observation = observations[
                    observationIndex
                ]

                for speakerIndex in speakers.indices {
                    let speaker = speakers[speakerIndex]
                    let emission = emissionCost(
                        assignment: assignments[observationIndex],
                        speaker: speaker
                    )

                    var bestCost = Double.infinity
                    var bestPreviousSpeakerIndex = 0

                    for previousSpeakerIndex in speakers.indices {
                        let previousSpeaker = speakers[
                            previousSpeakerIndex
                        ]

                        let cost = costs[
                            observationIndex - 1
                        ][previousSpeakerIndex]
                            + transitionEvaluation(
                                from: previousSpeaker,
                                to: speaker,
                                previousObservation: previousObservation,
                                observation: observation,
                                assignment: assignments[observationIndex]
                            ).transitionCost
                            + emission

                        if cost < bestCost {
                            bestCost = cost
                            bestPreviousSpeakerIndex = previousSpeakerIndex
                        }
                    }

                    costs[observationIndex][speakerIndex] = bestCost
                    predecessors[observationIndex][speakerIndex] = bestPreviousSpeakerIndex
                }
            }
        }

        var resolvedSpeakerIndices = Array(
            repeating: 0,
            count: observationCount
        )

        resolvedSpeakerIndices[observationCount - 1] = costs[
            observationCount - 1
        ].indices.min {
            costs[observationCount - 1][$0]
                < costs[observationCount - 1][$1]
        } ?? 0

        if observationCount > 1 {
            for observationIndex in stride(
                from: observationCount - 1,
                through: 1,
                by: -1
            ) {
                resolvedSpeakerIndices[observationIndex - 1] = predecessors[
                    observationIndex
                ][resolvedSpeakerIndices[observationIndex]]
            }
        }

        return assignments.indices.map { index in
            let assignment = assignments[index]
            let resolvedSpeaker = speakers[
                resolvedSpeakerIndices[index]
            ]

            let temporalTransition: SpeakerTransitionEvaluation?

            if index == 0 {
                temporalTransition = nil
            } else {
                temporalTransition = transitionEvaluation(
                    from: speakers[
                        resolvedSpeakerIndices[index - 1]
                    ],
                    to: resolvedSpeaker,
                    previousObservation: observations[index - 1],
                    observation: observations[index],
                    assignment: assignment
                )
            }

            return .init(
                observationID: assignment.observationID,
                acousticSpeaker: assignment.acousticSpeaker,
                resolvedSpeaker: resolvedSpeaker,
                acousticConfidence: assignment.acousticConfidence,
                reliability: assignment.reliability,
                reliabilityEvaluation: assignment.reliabilityEvaluation,
                candidates: assignment.candidates,
                temporalTransition: temporalTransition
            )
        }
    }
}

private extension SpeakerTemporalCoherence {
    func emissionCost(
        assignment: SpeakerObservationAssignment,
        speaker: SpeakerID
    ) -> Double {
        let acousticCost = assignment.candidates.first {
            $0.speaker == speaker
        }?.acousticCost ?? 1_000_000

        return acousticCost
            * assignment.reliability
    }

    func transitionEvaluation(
        from previousSpeaker: SpeakerID,
        to speaker: SpeakerID,
        previousObservation: SpeakerObservation,
        observation: SpeakerObservation,
        assignment: SpeakerObservationAssignment
    ) -> SpeakerTransitionEvaluation {
        let gap = max(
            0,
            observation.range.start
                - previousObservation.range.end
        )

        let gapScale: Double

        if configuration.maximumContinuityGapSeconds > 0,
           gap < configuration.maximumContinuityGapSeconds {
            gapScale = 1
                - gap
                    / configuration.maximumContinuityGapSeconds
        } else {
            gapScale = 0
        }

        let switchingEvidence = previousSpeaker != speaker
            && assignment.acousticSpeaker == speaker
            ? assignment.acousticEvidenceStrength
            : 0

        let transitionCost = previousSpeaker != speaker
            ? configuration.switchPenalty
                * gapScale
                * (1 - switchingEvidence)
            : 0

        return .init(
            previousSpeaker: previousSpeaker,
            speaker: speaker,
            gapSeconds: gap,
            gapScale: gapScale,
            switchingEvidence: switchingEvidence,
            configuredSwitchPenalty: configuration.switchPenalty,
            transitionCost: transitionCost
        )
    }
}
