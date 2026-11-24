import Diarization
@_spi(Testing) import DiarizationFluidAudio
import Foundation
import MediaCore
import SpeechAnalysis
import SpeechAnalysisContext
import TestFlows
import Transcribe

extension TranscribeFlowSuite {
    static var fluidAudioDiarizationBackendFlow: TestFlow {
        TestFlow(
            "fluid-audio-diarization-backend",
            tags: [
                "diarization",
                "fluid-audio",
                "backend",
                "speaker",
            ]
        ) {
            Step("backend conforms without loading models during construction") {
                acceptAudioDiarizationBackend(
                    FluidAudioDiarizationBackend()
                )
            }

            Step("segments map to speakers in order of first appearance, offset to media time") {
                let result = FluidAudioDiarizationBackendFixture.result

                try Expect.equal(
                    result.segments.map(\.speaker.rawValue),
                    [
                        "speaker_1",
                        "speaker_2",
                        "speaker_1",
                    ],
                    "fluid-audio-diarization.speakers"
                )

                try Expect.equal(
                    result.segments.map(\.range.start),
                    [
                        10,
                        12,
                        14,
                    ],
                    "fluid-audio-diarization.media-time"
                )

                try Expect.equal(
                    result.segments.map(\.confidence),
                    [
                        0.9,
                        1,
                        0.5,
                    ],
                    "fluid-audio-diarization.confidence-clamped"
                )

                try Expect.equal(
                    result.backend?.identifier,
                    FluidAudioDiarizationBackend.identifier,
                    "fluid-audio-diarization.backend-identity"
                )

                try Expect.equal(
                    result.backend?.speakerCount,
                    .automatic,
                    "fluid-audio-diarization.automatic-count"
                )

                try Expect.equal(
                    result.acoustic == nil && result.method == nil,
                    true,
                    "fluid-audio-diarization.no-acoustic-evidence"
                )
            }

            Step("profiles carry segment counts, durations and an embedding centroid") {
                let profiles = FluidAudioDiarizationBackendFixture.result.profiles

                try Expect.equal(
                    profiles.map(\.speaker.rawValue),
                    [
                        "speaker_1",
                        "speaker_2",
                    ],
                    "fluid-audio-diarization.profile-speakers"
                )

                try Expect.equal(
                    profiles.map(\.observationCount),
                    [
                        2,
                        1,
                    ],
                    "fluid-audio-diarization.profile-counts"
                )

                try Expect.equal(
                    profiles.map(\.observedDurationSeconds),
                    [
                        3,
                        2,
                    ],
                    "fluid-audio-diarization.profile-durations"
                )

                try Expect.equal(
                    profiles.first?.embeddingProfile?.evidenceCount,
                    2,
                    "fluid-audio-diarization.embedding-evidence"
                )

                try Expect.equal(
                    profiles.last?.embeddingProfile,
                    nil,
                    "fluid-audio-diarization.no-embedding-without-vectors"
                )
            }

            Step("empty and inverted segments are dropped") {
                let result = FluidAudioDiarizationMapping.result(
                    segments: [
                        .init(
                            speaker: "S1",
                            start: 3,
                            end: 3,
                            quality: 1
                        ),
                        .init(
                            speaker: "S1",
                            start: 5,
                            end: 4,
                            quality: 1
                        ),
                    ],
                    startingAt: 0,
                    identity: .init(
                        identifier: FluidAudioDiarizationBackend.identifier
                    )
                )

                try Expect.equal(
                    result.segments.count + result.profiles.count,
                    0,
                    "fluid-audio-diarization.invalid-dropped"
                )
            }

            Step("words align against backend speakers and the context names the backend") {
                let diarization = FluidAudioDiarizationBackendFixture.result
                let words = [
                    ("goed", 10.2, 0.5),
                    ("zo", 10.9, 0.4),
                    ("ja", 12.3, 0.3),
                    ("verder", 14.5, 0.6),
                ].map {
                    TranscriptionWord(
                        text: $0.0,
                        range: .init(
                            start: $0.1,
                            duration: $0.2
                        )
                    )
                }
                let transcription = Transcription(
                    segments: [
                        .init(
                            text: words
                                .map(\.text)
                                .joined(separator: " "),
                            range: .init(
                                start: 10.2,
                                duration: 4.9
                            ),
                            words: words
                        ),
                    ]
                )
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
                        "goed zo",
                        "ja",
                        "verder",
                    ],
                    "fluid-audio-diarization.turn-text"
                )

                try Expect.equal(
                    turns.map {
                        $0.speaker?.rawValue
                    },
                    [
                        "speaker_1",
                        "speaker_2",
                        "speaker_1",
                    ],
                    "fluid-audio-diarization.turn-speakers"
                )

                let context = SpeechAnalysisContextProjector().project(
                    analysis,
                    detail: .diagnostic
                )

                try Expect.equal(
                    context.inference?.backend?.identifier,
                    FluidAudioDiarizationBackend.identifier,
                    "fluid-audio-diarization.context-backend"
                )

                try Expect.equal(
                    context.inference?.backend?.maximumSpeakerCount,
                    nil,
                    "fluid-audio-diarization.context-no-bounds"
                )
            }
        }
    }
}

private func acceptAudioDiarizationBackend<Backend: AudioDiarizationBackend>(
    _ backend: Backend
) {}

private enum FluidAudioDiarizationBackendFixture {
    /// Media starts at 10 s. S2 opens before S1 in the raw output order but
    /// S1 speaks first, so S1 becomes speaker_1.
    static var result: DiarizationResult {
        FluidAudioDiarizationMapping.result(
            segments: [
                .init(
                    speaker: "S2",
                    start: 2,
                    end: 4,
                    quality: 1.4
                ),
                .init(
                    speaker: "S1",
                    start: 0,
                    end: 2,
                    quality: 0.9,
                    embedding: [
                        1,
                        0,
                    ]
                ),
                .init(
                    speaker: "S1",
                    start: 4,
                    end: 5,
                    quality: 0.5,
                    embedding: [
                        0,
                        1,
                    ]
                ),
            ],
            startingAt: 10,
            identity: .init(
                identifier: FluidAudioDiarizationBackend.identifier,
                model: FluidAudioDiarizationBackend.model
            )
        )
    }
}
