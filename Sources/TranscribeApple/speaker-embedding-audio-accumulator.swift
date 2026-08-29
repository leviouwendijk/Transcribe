import Foundation
import MediaAudio
import MediaCore

package struct SpeakerEmbeddingAudio: Sendable {
    package let buffer: MediaAudioBuffer
    package let startingAt: TimeInterval

    package init(
        buffer: MediaAudioBuffer,
        startingAt: TimeInterval
    ) {
        self.buffer = buffer
        self.startingAt = startingAt
    }
}

package final class SpeakerEmbeddingAudioAccumulator:
    @unchecked Sendable
{
    private let lock = NSLock()
    private var converter = Audio.Processing.AnalysisFormatConverter(
        targetSampleRate: 16_000
    )
    private var samples: [Float] = []
    private var startingAt: TimeInterval?
    private var sampleRate: Int?
    private var finished = false

    package init() {}

    package func consume(
        _ chunk: MediaAudioChunk
    ) {
        lock.lock()

        defer {
            lock.unlock()
        }

        precondition(!finished)

        let conversion = converter.process(
            chunk.buffer
        )
        let convertedSamples = conversion.buffer.monoFloatSamples()

        guard !convertedSamples.isEmpty,
              conversion.buffer.sampleRate > 0 else {
            return
        }

        let originalStart = chunk.timeRange?.start
            ?? chunk.presentationTimeSeconds
            ?? chunk.buffer.hostTimeSeconds
            ?? 0
        let convertedStart = originalStart
            + conversion.sourceOffsetSeconds

        if startingAt == nil {
            startingAt = convertedStart
        }

        if let sampleRate {
            precondition(
                sampleRate == conversion.buffer.sampleRate
            )
        } else {
            sampleRate = conversion.buffer.sampleRate
        }

        samples.append(
            contentsOf: convertedSamples
        )
    }

    package func finish() -> SpeakerEmbeddingAudio? {
        lock.lock()

        defer {
            lock.unlock()
        }

        precondition(!finished)
        finished = true

        guard !samples.isEmpty,
              let sampleRate,
              sampleRate > 0 else {
            return nil
        }

        let data = samples.withUnsafeBytes {
            Data(
                $0
            )
        }
        let buffer = MediaAudioBuffer(
            data: data,
            frameCount: samples.count,
            packetCount: UInt32(
                clamping: samples.count
            ),
            sampleRate: sampleRate,
            channelCount: 1,
            sample: .float32,
            hostTimeSeconds: nil
        )

        return .init(
            buffer: buffer,
            startingAt: startingAt ?? 0
        )
    }
}
