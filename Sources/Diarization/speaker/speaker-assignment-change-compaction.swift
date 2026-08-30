import MediaCore

public struct SpeakerAssignmentChangeSpan:
    Sendable,
    Codable,
    Hashable
{
    public let range: Audio.TimeRange
    public let baselineSpeaker: SpeakerID
    public let replaySpeaker: SpeakerID
    public let observationCount: Int

    public init(
        range: Audio.TimeRange,
        baselineSpeaker: SpeakerID,
        replaySpeaker: SpeakerID,
        observationCount: Int
    ) {
        self.range = range
        self.baselineSpeaker = baselineSpeaker
        self.replaySpeaker = replaySpeaker
        self.observationCount = max(
            0,
            observationCount
        )
    }
}

public extension SpeakerDiarizationReplayComparison {
    func compactedClusteringChanges(
        maximumGapSeconds: Double
    ) -> [SpeakerAssignmentChangeSpan] {
        compactedSpeakerChanges(
            clusteringChanges,
            maximumGapSeconds: maximumGapSeconds,
            baselineSpeaker: \.clusteringSpeaker,
            replaySpeaker: \.clusteringSpeaker
        )
    }

    func compactedResolvedChanges(
        maximumGapSeconds: Double
    ) -> [SpeakerAssignmentChangeSpan] {
        compactedSpeakerChanges(
            resolvedChanges,
            maximumGapSeconds: maximumGapSeconds,
            baselineSpeaker: \.resolvedSpeaker,
            replaySpeaker: \.resolvedSpeaker
        )
    }
}

private func compactedSpeakerChanges(
    _ changes: [SpeakerDiarizationAssignmentChange],
    maximumGapSeconds: Double,
    baselineSpeaker: KeyPath<SpeakerObservationAssignment, SpeakerID>,
    replaySpeaker: KeyPath<SpeakerObservationAssignment, SpeakerID>
) -> [SpeakerAssignmentChangeSpan] {
    precondition(maximumGapSeconds >= 0)

    let ordered = changes.sorted {
        if $0.range.start == $1.range.start {
            return $0.range.end
                < $1.range.end
        }

        return $0.range.start
            < $1.range.start
    }

    guard let first = ordered.first else {
        return []
    }

    var current = SpeakerAssignmentChangeSpan(
        range: first.range,
        baselineSpeaker: first.baseline[keyPath: baselineSpeaker],
        replaySpeaker: first.replay[keyPath: replaySpeaker],
        observationCount: 1
    )
    var result: [SpeakerAssignmentChangeSpan] = []

    for change in ordered.dropFirst() {
        let nextBaseline = change.baseline[keyPath: baselineSpeaker]
        let nextReplay = change.replay[keyPath: replaySpeaker]
        let gap = max(
            0,
            change.range.start
                - current.range.end
        )

        if nextBaseline == current.baselineSpeaker,
           nextReplay == current.replaySpeaker,
           gap <= maximumGapSeconds {
            let end = max(
                current.range.end,
                change.range.end
            )

            current = .init(
                range: .init(
                    start: current.range.start,
                    duration: end
                        - current.range.start
                ),
                baselineSpeaker: current.baselineSpeaker,
                replaySpeaker: current.replaySpeaker,
                observationCount: current.observationCount
                    + 1
            )
        } else {
            result.append(
                current
            )

            current = .init(
                range: change.range,
                baselineSpeaker: nextBaseline,
                replaySpeaker: nextReplay,
                observationCount: 1
            )
        }
    }

    result.append(
        current
    )

    return result
}
