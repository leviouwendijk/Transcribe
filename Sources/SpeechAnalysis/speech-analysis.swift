import Diarization
import Foundation
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

/// How a word or turn is attributed.
public enum SpeakerAttributionState:
    String,
    Sendable,
    Codable,
    Hashable
{
    /// One speaker's evidence dominates.
    case attributed
    /// More than one speaker's evidence covers it and none dominates:
    /// overlapping speech, or a turn change inside the word.
    case overlap
    /// No usable speaker evidence.
    case uncertain
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

/// Speaker attribution of one timed word. `speaker` is set only when
/// `state` is `.attributed`; `candidates` lists the supporting speakers of
/// an `.overlap`, strongest first.
public struct WordSpeakerAssignment:
    Sendable,
    Codable,
    Hashable
{
    public let segmentIndex: Int
    public let wordIndex: Int
    public let state: SpeakerAttributionState
    public let speaker: SpeakerID?
    public let candidates: [SpeakerID]
    public let confidence: Double?
    public let method: SpeakerAssignmentMethod?
    public let speakerSegmentIndices: [Int]

    init(
        segmentIndex: Int,
        wordIndex: Int,
        state: SpeakerAttributionState,
        speaker: SpeakerID?,
        candidates: [SpeakerID],
        confidence: Double?,
        method: SpeakerAssignmentMethod?,
        speakerSegmentIndices: [Int]
    ) {
        self.segmentIndex = segmentIndex
        self.wordIndex = wordIndex
        self.state = state
        self.speaker = speaker
        self.candidates = candidates
        self.confidence = confidence
        self.method = method
        self.speakerSegmentIndices = speakerSegmentIndices
    }

    public static func attributed(
        segmentIndex: Int,
        wordIndex: Int,
        speaker: SpeakerID,
        confidence: Double?,
        method: SpeakerAssignmentMethod,
        speakerSegmentIndices: [Int] = []
    ) -> Self {
        .init(
            segmentIndex: segmentIndex,
            wordIndex: wordIndex,
            state: .attributed,
            speaker: speaker,
            candidates: [
                speaker,
            ],
            confidence: confidence,
            method: method,
            speakerSegmentIndices: speakerSegmentIndices
        )
    }

    public static func overlap(
        segmentIndex: Int,
        wordIndex: Int,
        candidates: [SpeakerID],
        speakerSegmentIndices: [Int] = []
    ) -> Self {
        .init(
            segmentIndex: segmentIndex,
            wordIndex: wordIndex,
            state: .overlap,
            speaker: nil,
            candidates: candidates,
            confidence: nil,
            method: .temporalOverlap,
            speakerSegmentIndices: speakerSegmentIndices
        )
    }

    public static func uncertain(
        segmentIndex: Int,
        wordIndex: Int
    ) -> Self {
        .init(
            segmentIndex: segmentIndex,
            wordIndex: wordIndex,
            state: .uncertain,
            speaker: nil,
            candidates: [],
            confidence: nil,
            method: nil,
            speakerSegmentIndices: []
        )
    }
}

public struct SpeakerTranscriptAlignment:
    Sendable,
    Codable,
    Hashable
{
    /// One per transcription segment with a time range, over the whole segment.
    public let assignments: [SpeakerAssignment]
    /// One per timed word, in transcript order.
    public let words: [WordSpeakerAssignment]
    public let configuration: SpeakerTranscriptAligner.Configuration?

    public init(
        assignments: [SpeakerAssignment],
        words: [WordSpeakerAssignment] = [],
        configuration: SpeakerTranscriptAligner.Configuration? = nil
    ) {
        self.assignments = assignments
        self.words = words
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

    public func words(
        in state: SpeakerAttributionState
    ) -> [WordSpeakerAssignment] {
        words.filter {
            $0.state == state
        }
    }
}

public struct AttributedTranscriptionWord:
    Sendable,
    Codable,
    Hashable
{
    public let wordIndex: Int
    public let word: TranscriptionWord
    public let assignment: WordSpeakerAssignment?

    public init(
        wordIndex: Int,
        word: TranscriptionWord,
        assignment: WordSpeakerAssignment?
    ) {
        self.wordIndex = wordIndex
        self.word = word
        self.assignment = assignment
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
    public let words: [AttributedTranscriptionWord]

    public init(
        segmentIndex: Int,
        segment: TranscriptionSegment,
        assignment: SpeakerAssignment?,
        words: [AttributedTranscriptionWord] = []
    ) {
        self.segmentIndex = segmentIndex
        self.segment = segment
        self.assignment = assignment
        self.words = words
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

/// Consecutive transcript attributed the same way: one speaker, the same
/// overlap candidates, or uncertain. Built from words where the segment has
/// them, otherwise from the whole segment.
public struct SpeakerTurn:
    Sendable,
    Codable,
    Hashable
{
    public let state: SpeakerAttributionState
    public let speaker: SpeakerID?
    public let candidates: [SpeakerID]
    public let text: String
    public let range: Audio.TimeRange?
    public let confidence: Double?
    public let segmentIndices: [Int]
    /// Timed words in the turn; 0 when it was attributed per segment.
    public let wordCount: Int

    public init(
        state: SpeakerAttributionState,
        speaker: SpeakerID?,
        candidates: [SpeakerID],
        text: String,
        range: Audio.TimeRange?,
        confidence: Double?,
        segmentIndices: [Int],
        wordCount: Int
    ) {
        self.state = state
        self.speaker = speaker
        self.candidates = candidates
        self.text = text
        self.range = range
        self.confidence = confidence
        self.segmentIndices = segmentIndices
        self.wordCount = wordCount
    }
}

public struct AttributedTranscription:
    Sendable,
    Codable,
    Hashable
{
    public let localeIdentifier: String?
    public let segments: [AttributedTranscriptionSegment]
    /// Empty when there was no speaker alignment.
    public let turns: [SpeakerTurn]

    public init(
        localeIdentifier: String? = nil,
        segments: [AttributedTranscriptionSegment],
        turns: [SpeakerTurn] = []
    ) {
        self.localeIdentifier = localeIdentifier
        self.segments = segments
        self.turns = turns
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

        let segmentAssignments = Dictionary(
            (alignment?.assignments ?? []).map {
                (
                    $0.segmentIndex,
                    $0
                )
            },
            uniquingKeysWith: { first, _ in
                first
            }
        )

        var wordAssignments: [Int: [Int: WordSpeakerAssignment]] = [:]

        for word in alignment?.words ?? [] {
            wordAssignments[
                word.segmentIndex,
                default: [:]
            ][
                word.wordIndex
            ] = word
        }

        let segments = transcription.segments.enumerated().map {
            index,
            segment in

            AttributedTranscriptionSegment(
                segmentIndex: index,
                segment: segment,
                assignment: segmentAssignments[index],
                words: segment.words.enumerated().map {
                    wordIndex,
                    word in

                    .init(
                        wordIndex: wordIndex,
                        word: word,
                        assignment: wordAssignments[index]?[wordIndex]
                    )
                }
            )
        }

        return .init(
            localeIdentifier: transcription.localeIdentifier,
            segments: segments,
            turns: alignment == nil
                ? []
                : SpeakerTurnBuilder.turns(
                    segments
                )
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
        /// Share of a word's covered duration the leading speaker needs;
        /// below it the word is an overlap.
        public let minimumWordDominance: Double

        public init(
            maximumBridgeGapSeconds: Double = 0.9,
            maximumNearestEvidenceDistanceSeconds: Double = 0.12,
            minimumBridgedConfidence: Double = 0.10,
            minimumNearestConfidence: Double = 0.10,
            minimumWordDominance: Double = 0.7
        ) {
            precondition(maximumBridgeGapSeconds >= 0)
            precondition(maximumNearestEvidenceDistanceSeconds >= 0)
            precondition(minimumBridgedConfidence >= 0 && minimumBridgedConfidence <= 1)
            precondition(minimumNearestConfidence >= 0 && minimumNearestConfidence <= 1)
            precondition(minimumWordDominance > 0.5 && minimumWordDominance <= 1)

            self.maximumBridgeGapSeconds = maximumBridgeGapSeconds
            self.maximumNearestEvidenceDistanceSeconds = maximumNearestEvidenceDistanceSeconds
            self.minimumBridgedConfidence = minimumBridgedConfidence
            self.minimumNearestConfidence = minimumNearestConfidence
            self.minimumWordDominance = minimumWordDominance
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
        var words: [WordSpeakerAssignment] = []

        for (
            index,
            transcriptionSegment
        ) in transcription.segments.enumerated() {
            for (
                wordIndex,
                word
            ) in transcriptionSegment.words.enumerated() {
                words.append(
                    wordAssignment(
                        segmentIndex: index,
                        wordIndex: wordIndex,
                        range: word.range,
                        diarization: diarization
                    )
                )
            }

            guard let transcriptionRange = transcriptionSegment.range,
                  let assignment = segmentAssignment(
                      segmentIndex: index,
                      range: transcriptionRange,
                      diarization: diarization
                  )
            else {
                continue
            }

            assignments.append(
                assignment
            )
        }

        return .init(
            assignments: assignments,
            words: words,
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

    var sourceConfidence: Double {
        confidenceWeight > 0
            ? weightedConfidence / confidenceWeight
            : 0.5
    }
}

private struct RankedSpeakerSupport {
    /// Strongest first; ties broken by speaker id.
    let ranked: [(speaker: SpeakerID, support: SpeakerTemporalSupport)]
    let totalOverlapSeconds: Double
}

private extension SpeakerTranscriptAligner {
    func segmentAssignment(
        segmentIndex: Int,
        range: Audio.TimeRange,
        diarization: DiarizationResult
    ) -> SpeakerAssignment? {
        directAssignment(
            segmentIndex: segmentIndex,
            range: range,
            diarization: diarization
        )
            ?? bridgedAssignment(
                segmentIndex: segmentIndex,
                range: range,
                diarization: diarization
            )
            ?? nearestAssignment(
                segmentIndex: segmentIndex,
                range: range,
                diarization: diarization
            )
    }

    func wordAssignment(
        segmentIndex: Int,
        wordIndex: Int,
        range: Audio.TimeRange,
        diarization: DiarizationResult
    ) -> WordSpeakerAssignment {
        let support = rankedSupport(
            range,
            diarization: diarization
        )

        if let winner = support.ranked.first {
            let dominance = winner.support.overlapSeconds
                / max(
                    support.totalOverlapSeconds,
                    1e-12
                )

            guard dominance >= configuration.minimumWordDominance else {
                return .overlap(
                    segmentIndex: segmentIndex,
                    wordIndex: wordIndex,
                    candidates: support.ranked.map {
                        $0.speaker
                    },
                    speakerSegmentIndices: support.ranked
                        .flatMap {
                            $0.support.segmentIndices
                        }
                        .sorted()
                )
            }

            return .attributed(
                segmentIndex: segmentIndex,
                wordIndex: wordIndex,
                speaker: winner.speaker,
                confidence: bounded(
                    winner.support.sourceConfidence
                        * dominance
                ),
                method: .temporalOverlap,
                speakerSegmentIndices: winner.support.segmentIndices
            )
        }

        let inferred = bridgedAssignment(
            segmentIndex: segmentIndex,
            range: range,
            diarization: diarization
        )
            ?? nearestAssignment(
                segmentIndex: segmentIndex,
                range: range,
                diarization: diarization
            )

        guard let inferred else {
            return .uncertain(
                segmentIndex: segmentIndex,
                wordIndex: wordIndex
            )
        }

        return .attributed(
            segmentIndex: segmentIndex,
            wordIndex: wordIndex,
            speaker: inferred.speaker,
            confidence: inferred.confidence,
            method: inferred.method,
            speakerSegmentIndices: inferred.speakerSegmentIndices
        )
    }

    func rankedSupport(
        _ range: Audio.TimeRange,
        diarization: DiarizationResult
    ) -> RankedSpeakerSupport {
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

        let ranked = supportBySpeaker
            .map {
                (
                    speaker: $0.key,
                    support: $0.value
                )
            }
            .sorted {
                if $0.support.overlapSeconds == $1.support.overlapSeconds {
                    return $0.speaker.rawValue < $1.speaker.rawValue
                }

                return $0.support.overlapSeconds
                    > $1.support.overlapSeconds
            }

        return .init(
            ranked: ranked,
            totalOverlapSeconds: totalOverlap
        )
    }

    func directAssignment(
        segmentIndex: Int,
        range: Audio.TimeRange,
        diarization: DiarizationResult
    ) -> SpeakerAssignment? {
        let support = rankedSupport(
            range,
            diarization: diarization
        )

        guard let winner = support.ranked.first else {
            return nil
        }

        let dominance = winner.support.overlapSeconds
            / max(
                support.totalOverlapSeconds,
                1e-12
            )

        return .init(
            segmentIndex: segmentIndex,
            speaker: winner.speaker,
            confidence: bounded(
                winner.support.sourceConfidence
                    * dominance
            ),
            method: .temporalOverlap,
            speakerSegmentIndices: winner.support.segmentIndices
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

private enum SpeakerTurnBuilder {
    enum Key: Equatable {
        case attributed(SpeakerID)
        case overlap(Set<SpeakerID>)
        case uncertain
    }

    struct Unit {
        let key: Key
        let candidates: [SpeakerID]
        let text: String
        let range: Audio.TimeRange?
        let confidence: Double?
        let segmentIndex: Int
        let isWord: Bool
    }

    static func turns(
        _ segments: [AttributedTranscriptionSegment]
    ) -> [SpeakerTurn] {
        var turns: [SpeakerTurn] = []
        var current: [Unit] = []

        for unit in segments.flatMap(units) {
            if let first = current.first,
               first.key != unit.key {
                turns.append(
                    turn(current)
                )
                current = []
            }

            current.append(
                unit
            )
        }

        if !current.isEmpty {
            turns.append(
                turn(current)
            )
        }

        return turns
    }

    static func units(
        _ segment: AttributedTranscriptionSegment
    ) -> [Unit] {
        guard !segment.words.isEmpty else {
            let text = segment.segment.text.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

            guard !text.isEmpty else {
                return []
            }

            return [
                .init(
                    key: segment.speaker.map(Key.attributed)
                        ?? .uncertain,
                    candidates: segment.speaker.map {
                        [
                            $0,
                        ]
                    } ?? [],
                    text: text,
                    range: segment.segment.range,
                    confidence: segment.speakerConfidence,
                    segmentIndex: segment.segmentIndex,
                    isWord: false
                ),
            ]
        }

        return segment.words.map { attributed in
            let assignment = attributed.assignment
            let key: Key

            switch assignment?.state {
            case .attributed:
                key = assignment?.speaker.map(Key.attributed)
                    ?? .uncertain
            case .overlap:
                key = .overlap(
                    Set(
                        assignment?.candidates ?? []
                    )
                )
            case .uncertain,
                 nil:
                key = .uncertain
            }

            return .init(
                key: key,
                candidates: assignment?.candidates ?? [],
                text: attributed.word.text,
                range: attributed.word.range,
                confidence: assignment?.confidence,
                segmentIndex: segment.segmentIndex,
                isWord: true
            )
        }
    }

    static func turn(
        _ units: [Unit]
    ) -> SpeakerTurn {
        let key = units[0].key
        let state: SpeakerAttributionState
        let speaker: SpeakerID?
        let candidates: [SpeakerID]

        switch key {
        case .attributed(let id):
            state = .attributed
            speaker = id
            candidates = [
                id,
            ]
        case .overlap(let ids):
            state = .overlap
            speaker = nil
            candidates = ids.sorted {
                $0.rawValue < $1.rawValue
            }
        case .uncertain:
            state = .uncertain
            speaker = nil
            candidates = []
        }

        let ranges = units.compactMap(\.range)
        let range = ranges.isEmpty
            ? nil
            : Audio.TimeRange(
                start: ranges.map(\.start).min()!,
                duration: ranges.map(\.end).max()!
                    - ranges.map(\.start).min()!
            )

        var segmentIndices: [Int] = []

        for unit in units where segmentIndices.last != unit.segmentIndex {
            segmentIndices.append(
                unit.segmentIndex
            )
        }

        return .init(
            state: state,
            speaker: speaker,
            candidates: candidates,
            text: units
                .map(\.text)
                .joined(separator: " "),
            range: range,
            confidence: state == .attributed
                ? confidence(units)
                : nil,
            segmentIndices: segmentIndices,
            wordCount: units.filter(\.isWord).count
        )
    }

    static func confidence(
        _ units: [Unit]
    ) -> Double? {
        var weighted = 0.0
        var weight = 0.0

        for unit in units {
            guard let confidence = unit.confidence else {
                continue
            }

            let duration = max(
                unit.range?.duration ?? 0,
                1e-3
            )

            weighted += confidence * duration
            weight += duration
        }

        guard weight > 0 else {
            return nil
        }

        return weighted / weight
    }
}
