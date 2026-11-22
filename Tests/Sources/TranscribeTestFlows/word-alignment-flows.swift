import CoreMedia
import Diarization
import Foundation
import MediaCore
import Speech
import SpeechAnalysis
import SpeechAnalysisContext
import TestFlows
import Transcribe
@_spi(Testing) import TranscribeApple

extension TranscribeFlowSuite {
    static var wordAlignmentFlow: TestFlow {
        TestFlow(
            "speech-word-alignment",
            tags: [
                "transcription",
                "diarization",
                "alignment",
                "words",
            ]
        ) {
            Step("a segment spanning a turn change splits into two turns") {
                let analysis = WordAlignmentFixture.analysis(
                    words: [
                        ("hallo", 0.0, 0.8),
                        ("hoe", 1.0, 0.8),
                        ("gaat", 2.2, 0.8),
                        ("het", 3.2, 0.8),
                    ]
                )

                let words = analysis.alignment?.words ?? []

                try Expect.equal(
                    words.map(\.state),
                    [
                        .attributed,
                        .attributed,
                        .attributed,
                        .attributed,
                    ],
                    "words.turn-change.states"
                )

                try Expect.equal(
                    words.map(\.speaker),
                    [
                        WordAlignmentFixture.first,
                        WordAlignmentFixture.first,
                        WordAlignmentFixture.second,
                        WordAlignmentFixture.second,
                    ],
                    "words.turn-change.speakers"
                )

                let turns = analysis.attributedTranscription?.turns ?? []

                try Expect.equal(
                    turns.map(\.text),
                    [
                        "hallo hoe",
                        "gaat het",
                    ],
                    "words.turn-change.turn-text"
                )

                try Expect.equal(
                    turns.map(\.speaker),
                    [
                        WordAlignmentFixture.first,
                        WordAlignmentFixture.second,
                    ],
                    "words.turn-change.turn-speakers"
                )

                try Expect.equal(
                    turns.map(\.wordCount),
                    [
                        2,
                        2,
                    ],
                    "words.turn-change.word-counts"
                )

                try Expect.equal(
                    turns.last?.range?.start,
                    2.2,
                    "words.turn-change.second-turn-start"
                )

                try Expect.notNil(
                    analysis.alignment?.assignment(
                        forSegmentAt: 0
                    ),
                    "words.turn-change.segment-assignment-kept"
                )
            }

            Step("a word straddling the change is an overlap, not given to the larger share") {
                let analysis = WordAlignmentFixture.analysis(
                    words: [
                        ("hallo", 0.2, 0.8),
                        ("ja", 1.6, 0.8),
                        ("precies", 2.6, 0.8),
                    ]
                )

                let words = analysis.alignment?.words ?? []

                try Expect.equal(
                    words.map(\.state),
                    [
                        .attributed,
                        .overlap,
                        .attributed,
                    ],
                    "words.overlap.states"
                )

                try Expect.equal(
                    words[1].speaker,
                    nil,
                    "words.overlap.no-speaker"
                )

                let turns = analysis.attributedTranscription?.turns ?? []

                try Expect.equal(
                    turns.map(\.state),
                    [
                        .attributed,
                        .overlap,
                        .attributed,
                    ],
                    "words.overlap.turn-states"
                )

                try Expect.equal(
                    turns[1].candidates,
                    [
                        WordAlignmentFixture.first,
                        WordAlignmentFixture.second,
                    ],
                    "words.overlap.candidates"
                )

                try Expect.equal(
                    turns[1].confidence,
                    nil,
                    "words.overlap.no-confidence"
                )
            }

            Step("a word mostly inside one speaker stays attributed") {
                let analysis = WordAlignmentFixture.analysis(
                    words: [
                        ("goed", 1.2, 0.9),
                    ]
                )

                let word = analysis.alignment?.words.first

                try Expect.equal(
                    word?.state,
                    .attributed,
                    "words.dominant.state"
                )

                try Expect.equal(
                    word?.speaker,
                    WordAlignmentFixture.first,
                    "words.dominant.speaker"
                )
            }

            Step("a word with no speaker evidence nearby is uncertain") {
                let analysis = WordAlignmentFixture.analysis(
                    words: [
                        ("later", 6.0, 0.5),
                    ]
                )

                try Expect.equal(
                    analysis.alignment?.words.first?.state,
                    .uncertain,
                    "words.uncertain.state"
                )

                let turn = analysis.attributedTranscription?.turns.first

                try Expect.equal(
                    turn?.state,
                    .uncertain,
                    "words.uncertain.turn-state"
                )

                try Expect.equal(
                    turn?.speaker,
                    nil,
                    "words.uncertain.turn-speaker"
                )
            }

            Step("segments without words keep segment-level turns") {
                let transcription = Transcription(
                    segments: [
                        .init(
                            text: "first",
                            range: .init(
                                start: 0,
                                duration: 1.9
                            )
                        ),
                        .init(
                            text: " second",
                            range: .init(
                                start: 2.1,
                                duration: 1.9
                            )
                        ),
                    ]
                )

                let diarization = WordAlignmentFixture.diarization

                let analysis = SpeechAnalysisResult(
                    transcription: transcription,
                    diarization: diarization,
                    alignment: SpeakerTranscriptAligner().align(
                        transcription: transcription,
                        diarization: diarization
                    )
                )

                let turns = analysis.attributedTranscription?.turns ?? []

                try Expect.equal(
                    turns.map(\.text),
                    [
                        "first",
                        "second",
                    ],
                    "words.segment-fallback.text"
                )

                try Expect.equal(
                    turns.map(\.wordCount),
                    [
                        0,
                        0,
                    ],
                    "words.segment-fallback.word-counts"
                )

                let unaligned = SpeechAnalysisResult(
                    transcription: transcription
                )

                try Expect.equal(
                    unaligned.attributedTranscription?.turns.count,
                    0,
                    "words.segment-fallback.no-alignment-no-turns"
                )
            }

            Step("Apple runs become words; untimed punctuation joins its neighbour") {
                let quote = AttributedString("\"")

                var hallo = AttributedString("Hallo")
                hallo.audioTimeRange = WordAlignmentFixture.cmRange(
                    start: 0,
                    duration: 0.4
                )
                hallo.transcriptionConfidence = 0.9

                let space = AttributedString(" ")

                var wereld = AttributedString("wereld")
                wereld.audioTimeRange = WordAlignmentFixture.cmRange(
                    start: 0.5,
                    duration: 0.5
                )
                wereld.transcriptionConfidence = 0.7

                let period = AttributedString(".")

                let words = AppleTranscriptionWords.words(
                    from: quote + hallo + space + wereld + period
                )

                try Expect.equal(
                    words.map(\.text),
                    [
                        "\"Hallo",
                        "wereld.",
                    ],
                    "words.apple.text"
                )

                try Expect.equal(
                    words.map(\.range.start),
                    [
                        0,
                        0.5,
                    ],
                    "words.apple.starts"
                )

                try Expect.equal(
                    words.map(\.confidence),
                    [
                        0.9,
                        0.7,
                    ],
                    "words.apple.confidence"
                )

                let confidence = AppleTranscriptionWords.confidence(
                    of: words
                ) ?? 0

                try Expect.true(
                    abs(confidence - (0.9 * 0.4 + 0.7 * 0.5) / 0.9) < 1e-9,
                    "words.apple.segment-confidence"
                )

                try Expect.equal(
                    AppleTranscriptionWords.words(
                        from: AttributedString("no timing")
                    ).count,
                    0,
                    "words.apple.untimed-text-has-no-words"
                )
            }

            Step("context projects turns and word counts") {
                let analysis = WordAlignmentFixture.analysis(
                    words: [
                        ("hallo", 0.2, 0.8),
                        ("ja", 1.6, 0.8),
                        ("precies", 2.6, 0.8),
                    ]
                )

                let transcript = SpeechAnalysisContextProjector()
                    .project(
                        analysis
                    )
                    .transcript

                try Expect.equal(
                    transcript?.turns.map(\.state),
                    [
                        "attributed",
                        "overlap",
                        "attributed",
                    ],
                    "words.context.turn-states"
                )

                try Expect.equal(
                    transcript?.turns[1].candidates,
                    [
                        "speaker_1",
                        "speaker_2",
                    ],
                    "words.context.candidates"
                )

                try Expect.equal(
                    transcript?.wordCount,
                    3,
                    "words.context.word-count"
                )

                try Expect.equal(
                    transcript?.overlapWordCount,
                    1,
                    "words.context.overlap-count"
                )

                try Expect.equal(
                    transcript?.uncertainWordCount,
                    0,
                    "words.context.uncertain-count"
                )
            }
        }
    }
}

private enum WordAlignmentFixture {
    static let first = SpeakerID(
        rawValue: "speaker_1"
    )

    static let second = SpeakerID(
        rawValue: "speaker_2"
    )

    /// speaker_1 from 0 to 2 s, speaker_2 from 2 to 4 s.
    static var diarization: DiarizationResult {
        .init(
            segments: [
                .init(
                    range: .init(
                        start: 0,
                        duration: 2
                    ),
                    speaker: first,
                    confidence: 0.9
                ),
                .init(
                    range: .init(
                        start: 2,
                        duration: 2
                    ),
                    speaker: second,
                    confidence: 0.9
                ),
            ]
        )
    }

    /// One transcription segment holding the given words (text, start, duration).
    static func analysis(
        words: [(String, Double, Double)]
    ) -> SpeechAnalysisResult {
        let timed = words.map {
            TranscriptionWord(
                text: $0.0,
                range: .init(
                    start: $0.1,
                    duration: $0.2
                )
            )
        }

        let start = timed.map(\.range.start).min() ?? 0
        let end = timed.map(\.range.end).max() ?? 0

        let transcription = Transcription(
            segments: [
                .init(
                    text: timed
                        .map(\.text)
                        .joined(separator: " "),
                    range: .init(
                        start: start,
                        duration: end - start
                    ),
                    words: timed
                ),
            ]
        )

        return .init(
            transcription: transcription,
            diarization: diarization,
            alignment: SpeakerTranscriptAligner().align(
                transcription: transcription,
                diarization: diarization
            )
        )
    }

    static func cmRange(
        start: Double,
        duration: Double
    ) -> CMTimeRange {
        CMTimeRange(
            start: CMTime(
                seconds: start,
                preferredTimescale: 1_000
            ),
            duration: CMTime(
                seconds: duration,
                preferredTimescale: 1_000
            )
        )
    }
}
