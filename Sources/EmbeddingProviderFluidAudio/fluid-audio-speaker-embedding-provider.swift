import Diarization
import FluidAudio
import Foundation
import MediaAudio
import MediaCore

public enum FluidAudioEmbeddingModel:
    String,
    Sendable,
    Codable,
    Hashable
{
    case weSpeakerV2 = "wespeaker_v2"

    public var dimension: Int {
        switch self {
        case .weSpeakerV2:
            256
        }
    }
}

public enum FluidAudioEmbeddingModelSource:
    Sendable,
    Hashable
{
    /// Uses FluidAudio's model cache and downloads the required model assets
    /// when they are not already available locally.
    case automatic

    /// Uses a pre-staged `speaker-diarization-coreml` directory and never
    /// requests model acquisition from FluidAudio.
    case directory(URL)
}

public actor FluidAudioSpeakerEmbeddingProvider:
    SpeakerEmbeddingProvider
{
    public static let providerIdentifier = "FluidAudio"

    public let model: FluidAudioEmbeddingModel
    public let modelSource: FluidAudioEmbeddingModelSource

    private var diarizer: DiarizerManager?

    public init(
        model: FluidAudioEmbeddingModel = .weSpeakerV2,
        modelSource: FluidAudioEmbeddingModelSource = .automatic
    ) {
        self.model = model
        self.modelSource = modelSource
    }

    public func embeddings(
        for request: SpeakerEmbeddingRequest
    ) async throws -> SpeakerEmbeddingBatch {
        guard !request.windows.isEmpty else {
            return .empty
        }

        var converter = Audio.Processing.AnalysisFormatConverter(
            targetSampleRate: 16_000
        )
        let conversion = converter.process(
            request.audio
        )
        let samples = conversion.buffer.monoFloatSamples()

        guard !samples.isEmpty,
              conversion.buffer.sampleRate > 0 else {
            return .empty
        }

        let audioStartingAt = request.startingAt
            + conversion.sourceOffsetSeconds
        let sampleRate = conversion.buffer.sampleRate

        let requestedWindows = request.windows.compactMap { window -> (
            SpeakerObservationID,
            Range<Int>
        )? in
            guard let sampleRange = FluidAudioSpeakerEmbeddingSupport.sampleRange(
                for: window.range,
                audioStartingAt: audioStartingAt,
                sampleRate: sampleRate,
                sampleCount: samples.count
            ) else {
                return nil
            }

            return (
                window.observationID,
                sampleRange
            )
        }

        guard !requestedWindows.isEmpty else {
            return .empty
        }

        let diarizer = try await resolvedDiarizer()
        var embeddings: [SpeakerObservationID: SpeakerEmbedding] = [:]
        embeddings.reserveCapacity(
            requestedWindows.count
        )

        for (
            observationID,
            sampleRange
        ) in requestedWindows {
            let values = try diarizer.extractSpeakerEmbedding(
                from: samples[sampleRange]
            )

            guard let embedding = FluidAudioSpeakerEmbeddingSupport.embedding(
                values,
                model: model
            ) else {
                continue
            }

            embeddings[observationID] = embedding
        }

        return .init(
            embeddings: embeddings
        )
    }
}

private extension FluidAudioSpeakerEmbeddingProvider {
    func resolvedDiarizer() async throws -> DiarizerManager {
        if let diarizer {
            return diarizer
        }

        let models: DiarizerModels

        switch modelSource {
        case .automatic:
            models = try await DiarizerModels.downloadIfNeeded()

        case .directory:
            guard let urls = FluidAudioSpeakerEmbeddingSupport.localModelURLs(
                for: modelSource
            ) else {
                preconditionFailure(
                    "Local FluidAudio model source did not resolve model URLs."
                )
            }

            models = try DiarizerModels.load(
                localSegmentationModel: urls.segmentation,
                localEmbeddingModel: urls.embedding
            )
        }

        let diarizer = DiarizerManager()
        diarizer.initialize(
            models: models
        )
        self.diarizer = diarizer

        return diarizer
    }
}

package enum FluidAudioSpeakerEmbeddingSupport {
    package static let segmentationModelBundleName = "pyannote_segmentation.mlmodelc"
    package static let embeddingModelBundleName = "wespeaker_v2.mlmodelc"

    package static func localModelURLs(
        for source: FluidAudioEmbeddingModelSource
    ) -> (
        segmentation: URL,
        embedding: URL
    )? {
        guard case .directory(let directory) = source else {
            return nil
        }

        return (
            segmentation: directory.appendingPathComponent(
                segmentationModelBundleName,
                isDirectory: true
            ),
            embedding: directory.appendingPathComponent(
                embeddingModelBundleName,
                isDirectory: true
            )
        )
    }

    package static func sampleRange(
        for range: Audio.TimeRange,
        audioStartingAt: TimeInterval,
        sampleRate: Int,
        sampleCount: Int
    ) -> Range<Int>? {
        guard sampleRate > 0,
              sampleCount > 0,
              range.duration > 0 else {
            return nil
        }

        let sampleRate = Double(sampleRate)
        let audioDuration = Double(sampleCount)
            / sampleRate
        let relativeStart = max(
            0,
            range.start - audioStartingAt
        )
        let relativeEnd = min(
            audioDuration,
            range.end - audioStartingAt
        )

        guard relativeEnd > relativeStart else {
            return nil
        }

        let lowerBound = max(
            0,
            min(
                sampleCount,
                Int(
                    floor(
                        relativeStart * sampleRate
                    )
                )
            )
        )
        let upperBound = max(
            lowerBound,
            min(
                sampleCount,
                Int(
                    ceil(
                        relativeEnd * sampleRate
                    )
                )
            )
        )

        guard upperBound > lowerBound else {
            return nil
        }

        return lowerBound..<upperBound
    }

    package static func embedding(
        _ values: [Float],
        model: FluidAudioEmbeddingModel
    ) -> SpeakerEmbedding? {
        guard values.count == model.dimension else {
            return nil
        }

        return SpeakerEmbedding(
            values,
            provenance: .init(
                providerIdentifier: FluidAudioSpeakerEmbeddingProvider.providerIdentifier,
                modelIdentifier: model.rawValue,
                normalization: .l2
            )
        ).l2Normalized
    }
}
