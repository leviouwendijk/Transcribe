import Diarization
import MediaCore
import SpeechAnalysis
import TestFlows
import Transcribe
import TranscribeApple

extension TranscribeFlowSuite {
    static var transcriptionFlow: TestFlow {
        TestFlow(
            "transcription-semantics",
            tags: [
                "transcription",
                "semantics",
            ]
        ) {
            Step("raw text lowers from retained segments") {
                let transcription = Transcription(
                    localeIdentifier: "en-US",
                    segments: [
                        .init(
                            text: "Hello"
                        ),
                        .init(
                            text: " world."
                        ),
                    ]
                )

                try Expect.equal(
                    transcription.text,
                    "Hello world.",
                    "transcription.text"
                )
            }
        }
    }

    static var diarizationFlow: TestFlow {
        TestFlow(
            "diarization-semantics",
            tags: [
                "diarization",
                "speaker",
            ]
        ) {
            Step("speaker timeline retains distinct speakers") {
                let first = SpeakerID(
                    rawValue: "speaker_1"
                )

                let second = SpeakerID(
                    rawValue: "speaker_2"
                )

                let result = DiarizationResult(
                    segments: [
                        .init(
                            range: .init(
                                start: 0,
                                duration: 1
                            ),
                            speaker: second
                        ),
                        .init(
                            range: .init(
                                start: 1,
                                duration: 1
                            ),
                            speaker: first
                        ),
                    ]
                )

                try Expect.equal(
                    result.speakers,
                    [
                        first,
                        second,
                    ],
                    "diarization.speakers"
                )
            }
        }
    }

    static var alignmentFlow: TestFlow {
        TestFlow(
            "speech-alignment",
            tags: [
                "transcription",
                "diarization",
                "alignment",
            ]
        ) {
            Step("maximum temporal overlap assigns speakers without mutating transcript evidence") {
                let first = SpeakerID(
                    rawValue: "speaker_1"
                )

                let second = SpeakerID(
                    rawValue: "speaker_2"
                )

                let transcription = Transcription(
                    segments: [
                        .init(
                            text: "first",
                            range: .init(
                                start: 0,
                                duration: 2
                            )
                        ),
                        .init(
                            text: "second",
                            range: .init(
                                start: 2,
                                duration: 2
                            )
                        ),
                    ]
                )

                let diarization = DiarizationResult(
                    segments: [
                        .init(
                            range: .init(
                                start: 0,
                                duration: 2.1
                            ),
                            speaker: first,
                            confidence: 0.95
                        ),
                        .init(
                            range: .init(
                                start: 2.1,
                                duration: 1.9
                            ),
                            speaker: second,
                            confidence: 0.91
                        ),
                    ]
                )

                let alignment = SpeakerTranscriptAligner().align(
                    transcription: transcription,
                    diarization: diarization
                )

                let analysis = SpeechAnalysisResult(
                    transcription: transcription,
                    diarization: diarization,
                    alignment: alignment
                )

                let attributed = analysis.attributedSegments

                try Expect.equal(
                    attributed.count,
                    2,
                    "speech-analysis.segment-count"
                )

                try Expect.equal(
                    attributed[0].speaker,
                    first,
                    "speech-analysis.first-speaker"
                )

                try Expect.equal(
                    attributed[1].speaker,
                    second,
                    "speech-analysis.second-speaker"
                )

                try Expect.equal(
                    analysis.transcription?.text,
                    "firstsecond",
                    "speech-analysis.transcription-preserved"
                )
            }
        }
    }

    static var appleContractFlow: TestFlow {
        TestFlow(
            "apple-provider-contract",
            tags: [
                "apple",
                "speech",
                "provider",
            ]
        ) {
            Step("Apple provider exposes explicit model choices") {
                try Expect.equal(
                    AppleTranscriptionModel.allCases,
                    [
                        .speech,
                        .dictation,
                    ],
                    "apple-provider.models"
                )
            }
        }
    }
}
