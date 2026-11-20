import MediaCore
import TestFlows
import TranscribeApple

extension TranscribeFlowSuite {
    static var speakerEmbeddingRuntimeFlow: TestFlow {
        TestFlow(
            "speaker-embedding-runtime",
            tags: [
                "embedding",
                "media",
                "runtime",
                "speaker",
            ]
        ) {
            Step("embedding runtime assembles normalized audio from the existing timed media stream") {
                let firstSamples = AudioTestFixture.sine(
                    frequency: 150,
                    duration: 0.5
                )
                let secondSamples = AudioTestFixture.sine(
                    frequency: 220,
                    duration: 0.5
                )
                let accumulator = SpeakerEmbeddingAudioAccumulator()

                accumulator.consume(
                    MediaAudioChunk(
                        trackID: 1,
                        buffer: AudioTestFixture.buffer(
                            samples: firstSamples
                        ),
                        presentationTimeSeconds: 12,
                        durationSeconds: 0.5
                    )
                )
                accumulator.consume(
                    MediaAudioChunk(
                        trackID: 1,
                        buffer: AudioTestFixture.buffer(
                            samples: secondSamples
                        ),
                        presentationTimeSeconds: 12.5,
                        durationSeconds: 0.5
                    )
                )

                guard let audio = accumulator.finish() else {
                    throw SpeakerEmbeddingRuntimeFlowError.missingAudio
                }

                try Expect.equal(
                    audio.startingAt,
                    12,
                    "speaker-embedding-runtime.starting-at"
                )
                try Expect.equal(
                    audio.buffer.sampleRate,
                    16_000,
                    "speaker-embedding-runtime.sample-rate"
                )
                try Expect.equal(
                    audio.buffer.channelCount,
                    1,
                    "speaker-embedding-runtime.mono"
                )
                try Expect.equal(
                    audio.buffer.frameCount,
                    firstSamples.count + secondSamples.count,
                    "speaker-embedding-runtime.frames-retained"
                )
            }
        }
    }
}

private enum SpeakerEmbeddingRuntimeFlowError:
    Error,
    Sendable
{
    case missingAudio
}
