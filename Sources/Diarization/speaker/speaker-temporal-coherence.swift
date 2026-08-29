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

    public init(
        speaker: SpeakerID,
        acousticCost: Double
    ) {
        self.speaker = speaker
        self.acousticCost = max(
            0,
            acousticCost
        )
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
    public let reliability: Double
    public let candidates: [SpeakerAssignmentCandidate]

    public init(
        observationID: SpeakerObservationID,
        acousticSpeaker: SpeakerID,
        resolvedSpeaker: SpeakerID? = nil,
        acousticConfidence: Double,
        reliability: Double,
        candidates: [SpeakerAssignmentCandidate]
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
        self.reliability = min(
            1,
            max(
                0,
                reliability
            )
        )
        self.candidates = candidates
    }

    public var changedByContinuity: Bool {
        acousticSpeaker != resolvedSpeaker
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
                            + transitionCost(
                                from: previousSpeaker,
                                to: speaker,
                                previousObservation: previousObservation,
                                observation: observation
                            )
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

            return .init(
                observationID: assignment.observationID,
                acousticSpeaker: assignment.acousticSpeaker,
                resolvedSpeaker: speakers[
                    resolvedSpeakerIndices[index]
                ],
                acousticConfidence: assignment.acousticConfidence,
                reliability: assignment.reliability,
                candidates: assignment.candidates
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

    func transitionCost(
        from previousSpeaker: SpeakerID,
        to speaker: SpeakerID,
        previousObservation: SpeakerObservation,
        observation: SpeakerObservation
    ) -> Double {
        guard previousSpeaker != speaker,
              configuration.switchPenalty > 0,
              configuration.maximumContinuityGapSeconds > 0 else {
            return 0
        }

        let gap = max(
            0,
            observation.range.start
                - previousObservation.range.end
        )

        guard gap < configuration.maximumContinuityGapSeconds else {
            return 0
        }

        return configuration.switchPenalty
            * (
                1
                    - gap
                    / configuration.maximumContinuityGapSeconds
            )
    }
}
