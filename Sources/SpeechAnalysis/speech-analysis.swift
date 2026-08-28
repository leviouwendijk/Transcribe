import Diarization
import MediaCore
import Transcribe

public struct SpeakerAssignment:
    Sendable,
    Codable,
    Hashable
{
    public let segmentIndex: Int
    public let speaker: SpeakerID
    public let confidence: Double?

    public init(
        segmentIndex: Int,
        speaker: SpeakerID,
        confidence: Double? = nil
    ) {
        self.segmentIndex = segmentIndex
        self.speaker = speaker
        self.confidence = confidence
    }
}

public struct SpeakerTranscriptAlignment:
    Sendable,
    Codable,
    Hashable
{
    public let assignments: [SpeakerAssignment]

    public init(
        assignments: [SpeakerAssignment]
    ) {
        self.assignments = assignments
    }

    public func assignment(
        forSegmentAt index: Int
    ) -> SpeakerAssignment? {
        assignments.first {
            $0.segmentIndex == index
        }
    }
}

public struct AttributedTranscriptionSegment:
    Sendable,
    Codable,
    Hashable
{
    public let segment: TranscriptionSegment
    public let speaker: SpeakerID?
    public let speakerConfidence: Double?

    public init(
        segment: TranscriptionSegment,
        speaker: SpeakerID?,
        speakerConfidence: Double?
    ) {
        self.segment = segment
        self.speaker = speaker
        self.speakerConfidence = speakerConfidence
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

    public var attributedSegments: [AttributedTranscriptionSegment] {
        guard let transcription else {
            return []
        }

        return transcription.segments.enumerated().map {
            index,
            segment in

            let assignment = alignment?.assignment(
                forSegmentAt: index
            )

            return .init(
                segment: segment,
                speaker: assignment?.speaker,
                speakerConfidence: assignment?.confidence
            )
        }
    }
}

public struct SpeakerTranscriptAligner: Sendable {
    public init() {}

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

            let match = diarization.segments
                .map { speakerSegment in
                    (
                        segment: speakerSegment,
                        overlap: overlap(
                            transcriptionRange,
                            speakerSegment.range
                        )
                    )
                }
                .filter {
                    $0.overlap > 0
                }
                .max {
                    $0.overlap < $1.overlap
                }

            guard let match else {
                continue
            }

            assignments.append(
                .init(
                    segmentIndex: index,
                    speaker: match.segment.speaker,
                    confidence: match.segment.confidence
                )
            )
        }

        return .init(
            assignments: assignments
        )
    }
}

private extension SpeakerTranscriptAligner {
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
}
