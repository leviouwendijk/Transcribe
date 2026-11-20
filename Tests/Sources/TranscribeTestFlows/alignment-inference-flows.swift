import Diarization
import SpeechAnalysis
import TestFlows
import Transcribe

extension TranscribeFlowSuite {
    static var alignmentInferenceFlow: TestFlow {
        TestFlow(
            "speech-alignment-inference",
            tags: [
                "transcription",
                "diarization",
                "alignment",
                "inference",
            ]
        ) {
            Step("direct overlap aggregates support by speaker") {
                let first = SpeakerID(
                    rawValue: "speaker_1"
                )
                let second = SpeakerID(
                    rawValue: "speaker_2"
                )

                let transcription = Transcription(
                    segments: [
                        .init(
                            text: "test",
                            range: .init(
                                start: 0,
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
                                duration: 0.45
                            ),
                            speaker: first,
                            confidence: 0.8
                        ),
                        .init(
                            range: .init(
                                start: 0.55,
                                duration: 0.45
                            ),
                            speaker: first,
                            confidence: 0.8
                        ),
                        .init(
                            range: .init(
                                start: 1.05,
                                duration: 0.7
                            ),
                            speaker: second,
                            confidence: 0.8
                        ),
                    ]
                )

                let assignment = SpeakerTranscriptAligner()
                    .align(
                        transcription: transcription,
                        diarization: diarization
                    )
                    .assignment(
                        forSegmentAt: 0
                    )

                try Expect.equal(
                    assignment?.speaker,
                    first,
                    "alignment.inference.aggregate-speaker"
                )

                try Expect.equal(
                    assignment?.method,
                    .temporalOverlap,
                    "alignment.inference.aggregate-method"
                )

                try Expect.equal(
                    assignment?.speakerSegmentIndices,
                    [
                        0,
                        1,
                    ],
                    "alignment.inference.aggregate-provenance"
                )
            }

            Step("short same-speaker evidence gap is bridged") {
                let speaker = SpeakerID(
                    rawValue: "speaker_1"
                )

                let transcription = Transcription(
                    segments: [
                        .init(
                            text: "bridge",
                            range: .init(
                                start: 1.05,
                                duration: 0.4
                            )
                        ),
                    ]
                )

                let diarization = DiarizationResult(
                    segments: [
                        .init(
                            range: .init(
                                start: 0,
                                duration: 1
                            ),
                            speaker: speaker,
                            confidence: 0.8
                        ),
                        .init(
                            range: .init(
                                start: 1.5,
                                duration: 1
                            ),
                            speaker: speaker,
                            confidence: 0.75
                        ),
                    ]
                )

                let assignment = SpeakerTranscriptAligner()
                    .align(
                        transcription: transcription,
                        diarization: diarization
                    )
                    .assignment(
                        forSegmentAt: 0
                    )

                try Expect.equal(
                    assignment?.speaker,
                    speaker,
                    "alignment.inference.bridge-speaker"
                )

                try Expect.equal(
                    assignment?.method,
                    .bridgedGap,
                    "alignment.inference.bridge-method"
                )
            }

            Step("gap between different speakers remains unassigned") {
                let first = SpeakerID(
                    rawValue: "speaker_1"
                )
                let second = SpeakerID(
                    rawValue: "speaker_2"
                )

                let transcription = Transcription(
                    segments: [
                        .init(
                            text: "turn",
                            range: .init(
                                start: 1.05,
                                duration: 0.35
                            )
                        ),
                    ]
                )

                let diarization = DiarizationResult(
                    segments: [
                        .init(
                            range: .init(
                                start: 0,
                                duration: 1
                            ),
                            speaker: first,
                            confidence: 0.8
                        ),
                        .init(
                            range: .init(
                                start: 1.45,
                                duration: 1
                            ),
                            speaker: second,
                            confidence: 0.8
                        ),
                    ]
                )

                let assignment = SpeakerTranscriptAligner()
                    .align(
                        transcription: transcription,
                        diarization: diarization
                    )
                    .assignment(
                        forSegmentAt: 0
                    )

                try Expect.equal(
                    assignment == nil,
                    true,
                    "alignment.inference.ambiguous-gap-unassigned"
                )
            }

            Step("tiny one-sided gap can use nearest evidence") {
                let speaker = SpeakerID(
                    rawValue: "speaker_1"
                )

                let transcription = Transcription(
                    segments: [
                        .init(
                            text: "near",
                            range: .init(
                                start: 1.04,
                                duration: 0.06
                            )
                        ),
                    ]
                )

                let diarization = DiarizationResult(
                    segments: [
                        .init(
                            range: .init(
                                start: 0,
                                duration: 1
                            ),
                            speaker: speaker,
                            confidence: 0.9
                        ),
                    ]
                )

                let assignment = SpeakerTranscriptAligner()
                    .align(
                        transcription: transcription,
                        diarization: diarization
                    )
                    .assignment(
                        forSegmentAt: 0
                    )

                try Expect.equal(
                    assignment?.speaker,
                    speaker,
                    "alignment.inference.nearest-speaker"
                )

                try Expect.equal(
                    assignment?.method,
                    .nearestEvidence,
                    "alignment.inference.nearest-method"
                )
            }

            Step("distant evidence remains unassigned") {
                let speaker = SpeakerID(
                    rawValue: "speaker_1"
                )

                let transcription = Transcription(
                    segments: [
                        .init(
                            text: "noise",
                            range: .init(
                                start: 2,
                                duration: 0.2
                            )
                        ),
                    ]
                )

                let diarization = DiarizationResult(
                    segments: [
                        .init(
                            range: .init(
                                start: 0,
                                duration: 1
                            ),
                            speaker: speaker,
                            confidence: 0.9
                        ),
                    ]
                )

                let assignment = SpeakerTranscriptAligner()
                    .align(
                        transcription: transcription,
                        diarization: diarization
                    )
                    .assignment(
                        forSegmentAt: 0
                    )

                try Expect.equal(
                    assignment == nil,
                    true,
                    "alignment.inference.distant-unassigned"
                )
            }
        }
    }
}
