import Diarization
import EmbeddingProviderFluidAudio
import Foundation
import MediaCore
import TestFlows

extension TranscribeFlowSuite {
    static var fluidAudioEmbeddingProviderFlow: TestFlow {
        TestFlow(
            "fluid-audio-embedding-provider",
            tags: [
                "diarization",
                "embedding",
                "fluid-audio",
                "provider",
                "speaker",
            ]
        ) {
            Step("FluidAudio adapter conforms without acquiring models during construction") {
                let provider = FluidAudioSpeakerEmbeddingProvider()

                acceptSpeakerEmbeddingProvider(
                    provider
                )

                try Expect.equal(
                    FluidAudioEmbeddingModel.weSpeakerV2.rawValue,
                    "wespeaker_v2",
                    "fluid-audio-embedding.model-identifier"
                )
                try Expect.equal(
                    FluidAudioEmbeddingModel.weSpeakerV2.dimension,
                    256,
                    "fluid-audio-embedding.model-dimension"
                )
            }

            Step("local model source resolves the documented FluidAudio bundles") {
                let directory = URL(
                    fileURLWithPath: "/tmp/speaker-diarization-coreml",
                    isDirectory: true
                )

                guard let urls = FluidAudioSpeakerEmbeddingSupport.localModelURLs(
                    for: .directory(
                        directory
                    )
                ) else {
                    throw FluidAudioEmbeddingProviderFlowError.modelURLsMissing
                }

                try Expect.equal(
                    urls.segmentation.lastPathComponent,
                    "pyannote_segmentation.mlmodelc",
                    "fluid-audio-embedding.segmentation-model-path"
                )
                try Expect.equal(
                    urls.embedding.lastPathComponent,
                    "wespeaker_v2.mlmodelc",
                    "fluid-audio-embedding.embedding-model-path"
                )
            }

            Step("semantic observation ranges project onto normalized 16 kHz audio") {
                let range = Audio.TimeRange(
                    start: 12.25,
                    duration: 0.5
                )

                let projected = FluidAudioSpeakerEmbeddingSupport.sampleRange(
                    for: range,
                    audioStartingAt: 12,
                    sampleRate: 16_000,
                    sampleCount: 16_000
                )

                try Expect.equal(
                    projected,
                    4_000..<12_000,
                    "fluid-audio-embedding.sample-range"
                )

                let outside = FluidAudioSpeakerEmbeddingSupport.sampleRange(
                    for: .init(
                        start: 20,
                        duration: 1
                    ),
                    audioStartingAt: 12,
                    sampleRate: 16_000,
                    sampleCount: 16_000
                )

                try Expect.equal(
                    outside,
                    nil,
                    "fluid-audio-embedding.outside-window-omitted"
                )
            }

            Step("FluidAudio vectors lower to normalized semantic embeddings with provenance") {
                var values = Array(
                    repeating: Float(0),
                    count: FluidAudioEmbeddingModel.weSpeakerV2.dimension
                )
                values[0] = 3
                values[1] = 4

                guard let embedding = FluidAudioSpeakerEmbeddingSupport.embedding(
                    values,
                    model: .weSpeakerV2
                ) else {
                    throw FluidAudioEmbeddingProviderFlowError.embeddingMissing
                }

                try Expect.equal(
                    embedding.dimension,
                    256,
                    "fluid-audio-embedding.semantic-dimension"
                )
                try Expect.equal(
                    abs(embedding.l2Norm - 1) < 1e-6,
                    true,
                    "fluid-audio-embedding.semantic-normalization"
                )
                try Expect.equal(
                    embedding.provenance?.providerIdentifier,
                    "FluidAudio",
                    "fluid-audio-embedding.provider-provenance"
                )
                try Expect.equal(
                    embedding.provenance?.modelIdentifier,
                    "wespeaker_v2",
                    "fluid-audio-embedding.model-provenance"
                )
                try Expect.equal(
                    embedding.provenance?.normalization,
                    .l2,
                    "fluid-audio-embedding.normalization-provenance"
                )

                try Expect.equal(
                    FluidAudioSpeakerEmbeddingSupport.embedding(
                        [1, 0],
                        model: .weSpeakerV2
                    ),
                    nil,
                    "fluid-audio-embedding.invalid-dimension-omitted"
                )
            }
        }
    }
}

private func acceptSpeakerEmbeddingProvider<Provider: SpeakerEmbeddingProvider>(
    _ provider: Provider
) {}

private enum FluidAudioEmbeddingProviderFlowError:
    Error,
    Sendable
{
    case modelURLsMissing
    case embeddingMissing
}
