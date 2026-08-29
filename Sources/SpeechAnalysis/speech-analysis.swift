import Diarization
import MediaCore
import Transcribe

public enum SpeakerAssignmentMethod:
    String,
    Sendable,
    Codable,
    Hashable
{
    case temporalOverlap
    case bridgedGap
    case nearestEvidence
}

public struct SpeakerAssignment:
    Sendable,
    Codable,
    Hashable
{
    public let segmentIndex: Int
    public let speaker: SpeakerID
    public let confidence: Double?
    public let method: SpeakerAssignmentMethod
    public let speakerSegmentIndices: [Int]

    public init(
        segmentIndex: Int,
        speaker: SpeakerID,
        confidence: Double? = nil,
        method: SpeakerAssignmentMethod = .temporalOverlap,
        speakerSegmentIndices: [Int] = []
    ) {
        self.segmentIndex = segmentIndex
        self.speaker = speaker
        self.confidence = confidence
        self.method = method
        self.speakerSegmentIndices = speakerSegmentIndices
    }
}

public struct SpeakerTranscriptAlignment:
    Sendable,
    Codable,
    Hashable
{
    public let assignments: [SpeakerAssignment]
    public let configuration: SpeakerTranscriptAligner.Configuration?

    public init(
        assignments: [SpeakerAssignment],
        configuration: SpeakerTranscriptAligner.Configuration? = nil
    ) {
        self.assignments = assignments
        self.configuration = configuration
    }

    public func assignment(
        forSegmentAt index: Int
    ) -> SpeakerAssignment? {
        assignments.first {
            $0.segmentIndex == index
        }
    }

    public func assignments(
        using method: SpeakerAssignmentMethod
    ) -> [SpeakerAssignment] {
        assignments.filter {
            $0.method == method
        }
    }
}

public struct AttributedTranscriptionSegment:
    Sendable,
    Codable,
    Hashable
{
    public let segmentIndex: Int
    public let segment: TranscriptionSegment
    public let assignment: SpeakerAssignment?

    public init(
        segmentIndex: Int,
        segment: TranscriptionSegment,
        assignment: SpeakerAssignment?
    ) {
        self.segmentIndex = segmentIndex
        self.segment = segment
        self.assignment = assignment
    }

    public var speaker: SpeakerID? {
        assignment?.speaker
    }

    public var speakerConfidence: Double? {
        assignment?.confidence
    }

    public var assignmentMethod: SpeakerAssignmentMethod? {
        assignment?.method
    }

    public var speakerSegmentIndices: [Int] {
        assignment?.speakerSegmentIndices
            ?? []
    }
}

public struct AttributedTranscription:
    Sendable,
    Codable,
    Hashable
{
    public let localeIdentifier: String?
    public let segments: [AttributedTranscriptionSegment]

    public init(
        localeIdentifier: String? = nil,
        segments: [AttributedTranscriptionSegment]
    ) {
        self.localeIdentifier = localeIdentifier
        self.segments = segments
    }

    public var text: String {
        segments
            .map {
                $0.segment.text
            }
            .joined()
    }
}

public struct SpeechAnalysisResult:
    Sendable,
    Codable,
    Hashable
{
    public let transcription: Transcription?
    public let diarization: DiarizationResult?
    public let alignment: SpeakerTranscriptAlignment?

    public init(
        transcription: Transcription? = nil,
        diarization: DiarizationResult? = nil,
        alignment: SpeakerTranscriptAlignment? = nil
    ) {
        self.transcription = transcription
        self.diarization = diarization
        self.alignment = alignment
    }

    public var attributedTranscription: AttributedTranscription? {
        guard let transcription else {
            return nil
        }

        return .init(
            localeIdentifier: transcription.localeIdentifier,
            segments: transcription.segments.enumerated().map {
                index,
                segment in

                .init(
                    segmentIndex: index,
                    segment: segment,
                    assignment: alignment?.assignment(
                        forSegmentAt: index
                    )
                )
            }
        )
    }

    public var attributedSegments: [AttributedTranscriptionSegment] {
        attributedTranscription?.segments
            ?? []
    }
}

public struct SpeakerTranscriptAligner: Sendable {
    public struct Configuration:
        Sendable,
        Codable,
        Hashable
    {
        public let maximumBridgeGapSeconds: Double
        public let maximumNearestEvidenceDistanceSeconds: Double
        public let minimumBridgedConfidence: Double
        public let minimumNearestConfidence: Double

        public init(
            maximumBridgeGapSeconds: Double = 0.9,
            maximumNearestEvidenceDistanceSeconds: Double = 0.12,
            minimumBridgedConfidence: Double = 0.10,
            minimumNearestConfidence: Double = 0.10
        ) {
            precondition(maximumBridgeGapSeconds >= 0)
            precondition(maximumNearestEvidenceDistanceSeconds >= 0)
            precondition(minimumBridgedConfidence >= 0 && minimumBridgedConfidence <= 1)
            precondition(minimumNearestConfidence >= 0 && minimumNearestConfidence <= 1)

            self.maximumBridgeGapSeconds = maximumBridgeGapSeconds
            self.maximumNearestEvidenceDistanceSeconds = maximumNearestEvidenceDistanceSeconds
            self.minimumBridgedConfidence = minimumBridgedConfidence
            self.minimumNearestConfidence = minimumNearestConfidence
        }
    }

    public let configuration: Configuration

    public init(
        configuration: Configuration = .init()
    ) {
        self.configuration = configuration
    }

    public func align(
        transcription: Transcription,
        diarization: DiarizationResult
    ) -> SpeakerTranscriptAlignment {
        var assignments: [SpeakerAssignment] = []

        for (
            index,
            transcriptionSegment
        ) in transcription.segments.enumerated() {
            guard let transcriptionRange = transcriptionSegment.range else {
                continue
            }

            if let direct = directAssignment(
                segmentIndex: index,
                range: transcriptionRange,
                diarization: diarization
            ) {
                assignments.append(
                    direct
                )
                continue
            }

            if let bridged = bridgedAssignment(
                segmentIndex: index,
                range: transcriptionRange,
                diarization: diarization
            ) {
                assignments.append(
                    bridged
                )
                continue
            }

            if let nearest = nearestAssignment(
                segmentIndex: index,
                range: transcriptionRange,
                diarization: diarization
            ) {
                assignments.append(
                    nearest
                )
            }
        }

        return .init(
            assignments: assignments,
            configuration: configuration
        )
    }
}

private struct IndexedSpeakerSegment {
    let index: Int
    let segment: SpeakerSegment
}

private struct SpeakerTemporalSupport {
    var overlapSeconds: Double = 0
    var weightedConfidence: Double = 0
    var confidenceWeight: Double = 0
    var segmentIndices: [Int] = []
}

private extension SpeakerTranscriptAligner {
    func directAssignment(
        segmentIndex: Int,
        range: Audio.TimeRange,
        diarization: DiarizationResult
    ) -> SpeakerAssignment? {
        var supportBySpeaker: [SpeakerID: SpeakerTemporalSupport] = [:]
        var totalOverlap = 0.0

        for (
            speakerSegmentIndex,
            speakerSegment
        ) in diarization.segments.enumerated() {
            let overlapSeconds = overlap(
                range,
                speakerSegment.range
            )

            guard overlapSeconds > 0 else {
                continue
            }

            var support = supportBySpeaker[
                speakerSegment.speaker
            ] ?? .init()

            support.overlapSeconds += overlapSeconds

            if let confidence = speakerSegment.confidence {
                support.weightedConfidence += confidence
                    * overlapSeconds
                support.confidenceWeight += overlapSeconds
            }

            support.segmentIndices.append(
                speakerSegmentIndex
            )

            supportBySpeaker[
                speakerSegment.speaker
            ] = support

            totalOverlap += overlapSeconds
        }

        guard let winner = supportBySpeaker.max(by: {
            lhs,
            rhs in

            if lhs.value.overlapSeconds == rhs.value.overlapSeconds {
                return lhs.key.rawValue > rhs.key.rawValue
            }

            return lhs.value.overlapSeconds
                < rhs.value.overlapSeconds
        }) else {
            return nil
        }

        let sourceConfidence = winner.value.confidenceWeight > 0
            ? winner.value.weightedConfidence
                / winner.value.confidenceWeight
            : 0.5

        let dominance = winner.value.overlapSeconds
            / max(
                totalOverlap,
                1e-12
            )

        return .init(
            segmentIndex: segmentIndex,
            speaker: winner.key,
            confidence: bounded(
                sourceConfidence
                    * dominance
            ),
            method: .temporalOverlap,
            speakerSegmentIndices: winner.value.segmentIndices
        )
    }

    func bridgedAssignment(
        segmentIndex: Int,
        range: Audio.TimeRange,
        diarization: DiarizationResult
    ) -> SpeakerAssignment? {
        guard let before = nearestBefore(
            range,
            diarization: diarization
        ),
              let after = nearestAfter(
                range,
                diarization: diarization
              ),
              before.segment.speaker == after.segment.speaker
        else {
            return nil
        }

        let evidenceGap = after.segment.range.start
            - before.segment.range.end

        guard evidenceGap >= 0,
              evidenceGap <= configuration.maximumBridgeGapSeconds else {
            return nil
        }

        let proximity: Double

        if configuration.maximumBridgeGapSeconds > 0 {
            proximity = 1
                - 0.5
                    * evidenceGap
                    / configuration.maximumBridgeGapSeconds
        } else {
            proximity = 1
        }

        let sourceConfidence = min(
            before.segment.confidence ?? 0.5,
            after.segment.confidence ?? 0.5
        )

        let confidence = bounded(
            sourceConfidence
                * proximity
        )

        guard confidence >= configuration.minimumBridgedConfidence else {
            return nil
        }

        return .init(
            segmentIndex: segmentIndex,
            speaker: before.segment.speaker,
            confidence: confidence,
            method: .bridgedGap,
            speakerSegmentIndices: [
                before.index,
                after.index,
            ]
        )
    }

    func nearestAssignment(
        segmentIndex: Int,
        range: Audio.TimeRange,
        diarization: DiarizationResult
    ) -> SpeakerAssignment? {
        let before = nearestBefore(
            range,
            diarization: diarization
        )

        let after = nearestAfter(
            range,
            diarization: diarization
        )

        let beforeDistance = before.map {
            max(
                0,
                range.start
                    - $0.segment.range.end
            )
        }

        let afterDistance = after.map {
            max(
                0,
                $0.segment.range.start
                    - range.end
            )
        }

        let beforeIsNear = beforeDistance.map {
            $0 <= configuration.maximumNearestEvidenceDistanceSeconds
        } ?? false

        let afterIsNear = afterDistance.map {
            $0 <= configuration.maximumNearestEvidenceDistanceSeconds
        } ?? false

        if beforeIsNear,
           afterIsNear {
            return nil
        }

        let selected: IndexedSpeakerSegment
        let distance: Double

        if beforeIsNear,
           let before,
           let beforeDistance {
            selected = before
            distance = beforeDistance
        } else if afterIsNear,
                  let after,
                  let afterDistance {
            selected = after
            distance = afterDistance
        } else {
            return nil
        }

        let proximity: Double

        if configuration.maximumNearestEvidenceDistanceSeconds > 0 {
            proximity = 1
                - distance
                    / configuration.maximumNearestEvidenceDistanceSeconds
        } else {
            proximity = 1
        }

        let confidence = bounded(
            (selected.segment.confidence ?? 0.5)
                * (
                    0.5
                        + 0.5 * proximity
                )
                * 0.75
        )

        guard confidence >= configuration.minimumNearestConfidence else {
            return nil
        }

        return .init(
            segmentIndex: segmentIndex,
            speaker: selected.segment.speaker,
            confidence: confidence,
            method: .nearestEvidence,
            speakerSegmentIndices: [
                selected.index,
            ]
        )
    }

    func nearestBefore(
        _ range: Audio.TimeRange,
        diarization: DiarizationResult
    ) -> IndexedSpeakerSegment? {
        var selected: IndexedSpeakerSegment?

        for (
            index,
            segment
        ) in diarization.segments.enumerated() {
            guard segment.range.end <= range.start else {
                continue
            }

            if selected == nil
                || segment.range.end > selected!.segment.range.end {
                selected = .init(
                    index: index,
                    segment: segment
                )
            }
        }

        return selected
    }

    func nearestAfter(
        _ range: Audio.TimeRange,
        diarization: DiarizationResult
    ) -> IndexedSpeakerSegment? {
        var selected: IndexedSpeakerSegment?

        for (
            index,
            segment
        ) in diarization.segments.enumerated() {
            guard segment.range.start >= range.end else {
                continue
            }

            if selected == nil
                || segment.range.start < selected!.segment.range.start {
                selected = .init(
                    index: index,
                    segment: segment
                )
            }
        }

        return selected
    }

    func overlap(
        _ lhs: Audio.TimeRange,
        _ rhs: Audio.TimeRange
    ) -> Double {
        max(
            0,
            min(
                lhs.end,
                rhs.end
            ) - max(
                lhs.start,
                rhs.start
            )
        )
    }

    func bounded(
        _ value: Double
    ) -> Double {
        min(
            1,
            max(
                0,
                value
            )
        )
    }
}
