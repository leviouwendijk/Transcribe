import MediaCore

public struct SpeakerDiarizationAssignmentChange:
    Sendable,
    Codable,
    Hashable
{
    public let observationID: SpeakerObservationID
    public let range: Audio.TimeRange
    public let baseline: SpeakerObservationAssignment
    public let replay: SpeakerObservationAssignment

    public init(
        observationID: SpeakerObservationID,
        range: Audio.TimeRange,
        baseline: SpeakerObservationAssignment,
        replay: SpeakerObservationAssignment
    ) {
        self.observationID = observationID
        self.range = range
        self.baseline = baseline
        self.replay = replay
    }
}

public struct SpeakerDiarizationReplayComparison:
    Sendable,
    Codable,
    Hashable
{
    public let acousticChanges: [SpeakerDiarizationAssignmentChange]
    public let resolvedChanges: [SpeakerDiarizationAssignmentChange]
    public let speakerCount: Int
    public let segmentCount: Int
    public let reliabilityWeightedSquaredError: Double?

    public init(
        acousticChanges: [SpeakerDiarizationAssignmentChange],
        resolvedChanges: [SpeakerDiarizationAssignmentChange],
        speakerCount: Int,
        segmentCount: Int,
        reliabilityWeightedSquaredError: Double?
    ) {
        self.acousticChanges = acousticChanges
        self.resolvedChanges = resolvedChanges
        self.speakerCount = speakerCount
        self.segmentCount = segmentCount
        self.reliabilityWeightedSquaredError = reliabilityWeightedSquaredError
    }
}

public struct SpeakerDiarizationAblationReport:
    Sendable,
    Codable,
    Hashable
{
    public let ablation: SpeakerFeatureAblationTarget
    public let comparison: SpeakerDiarizationReplayComparison

    public init(
        ablation: SpeakerFeatureAblationTarget,
        comparison: SpeakerDiarizationReplayComparison
    ) {
        self.ablation = ablation
        self.comparison = comparison
    }

    public var summary: SpeakerDiarizationReplaySummary {
        .init(
            ablation: ablation,
            speakerCount: comparison.speakerCount,
            segmentCount: comparison.segmentCount,
            changedAcousticAssignmentCount: comparison.acousticChanges.count,
            changedResolvedAssignmentCount: comparison.resolvedChanges.count,
            reliabilityWeightedSquaredError: comparison.reliabilityWeightedSquaredError
        )
    }
}

public extension Diarizer {
    func compare(
        _ baseline: DiarizationResult,
        to replay: DiarizationResult
    ) -> SpeakerDiarizationReplayComparison {
        let observationsByID = Dictionary(
            uniqueKeysWithValues: baseline.observations.map {
                (
                    $0.id,
                    $0
                )
            }
        )
        let replayByObservationID = Dictionary(
            uniqueKeysWithValues: replay.assignments.map {
                (
                    $0.observationID,
                    $0
                )
            }
        )

        var acousticChanges: [SpeakerDiarizationAssignmentChange] = []
        var resolvedChanges: [SpeakerDiarizationAssignmentChange] = []

        for baselineAssignment in baseline.assignments {
            guard
                let replayAssignment = replayByObservationID[
                    baselineAssignment.observationID
                ],
                let observation = observationsByID[
                    baselineAssignment.observationID
                ]
            else {
                continue
            }

            let change = SpeakerDiarizationAssignmentChange(
                observationID: baselineAssignment.observationID,
                range: observation.range,
                baseline: baselineAssignment,
                replay: replayAssignment
            )

            if baselineAssignment.acousticSpeaker
                != replayAssignment.acousticSpeaker {
                acousticChanges.append(
                    change
                )
            }

            if baselineAssignment.resolvedSpeaker
                != replayAssignment.resolvedSpeaker {
                resolvedChanges.append(
                    change
                )
            }
        }

        return .init(
            acousticChanges: acousticChanges,
            resolvedChanges: resolvedChanges,
            speakerCount: replay.profiles.count,
            segmentCount: replay.segments.count,
            reliabilityWeightedSquaredError: replay.method?
                .clustering?
                .reliabilityWeightedSquaredError
        )
    }

    func leaveOneOutReports(
        _ source: DiarizationResult
    ) -> [SpeakerDiarizationAblationReport] {
        guard source.method != nil else {
            return []
        }

        return SpeakerFeatureAblationTarget.allCases.map { target in
            let replayed = replay(
                source,
                ablating: target
            )

            return .init(
                ablation: target,
                comparison: compare(
                    source,
                    to: replayed
                )
            )
        }
    }
}
