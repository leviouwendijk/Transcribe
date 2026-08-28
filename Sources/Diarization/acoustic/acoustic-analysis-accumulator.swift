import Foundation
import MediaCore

public enum AcousticAnalysisAccumulatorError:
    Error,
    Sendable,
    LocalizedError
{
    case alreadyFinished
    case inconsistentSampleRate(
        expected: Int,
        actual: Int
    )

    public var errorDescription: String? {
        switch self {
        case .alreadyFinished:
            return "Acoustic analysis accumulator has already been finished."

        case .inconsistentSampleRate(
            let expected,
            let actual
        ):
            return "Acoustic session changed sample rate from \(expected) Hz to \(actual) Hz."
        }
    }
}

public final class AcousticAnalysisAccumulator:
    @unchecked Sendable
{
    private let lock = NSLock()
    private let configuration: AcousticAnalyzerConfiguration
    private let batchDurationSeconds: Double

    private var sampleRate: Int?
    private var pendingSamples: [Float] = []
    private var pendingStartTime: TimeInterval?
    private var nextImplicitStartTime: TimeInterval = 0

    private var observations: [AcousticObservation] = []
    private var weightedNoiseFloor = 0.0
    private var noiseFloorObservationCount = 0
    private var acousticAnalysisSeconds: TimeInterval = 0
    private var finished = false

    public init(
        configuration: AcousticAnalyzerConfiguration = .init(),
        batchDurationSeconds: Double = 4
    ) {
        precondition(batchDurationSeconds > 0)

        self.configuration = configuration
        self.batchDurationSeconds = batchDurationSeconds
    }

    public var acousticAnalysisDurationSeconds: TimeInterval {
        lock.lock()

        defer {
            lock.unlock()
        }

        return acousticAnalysisSeconds
    }

    public func consume(
        _ chunk: MediaAudioChunk
    ) throws {
        lock.lock()

        defer {
            lock.unlock()
        }

        guard !finished else {
            throw AcousticAnalysisAccumulatorError.alreadyFinished
        }

        let actualSampleRate = chunk.buffer.sampleRate

        if let sampleRate,
           sampleRate != actualSampleRate {
            throw AcousticAnalysisAccumulatorError.inconsistentSampleRate(
                expected: sampleRate,
                actual: actualSampleRate
            )
        }

        guard actualSampleRate > 0 else {
            return
        }

        if sampleRate == nil {
            sampleRate = actualSampleRate
        }

        let samples = chunk.buffer.monoFloatSamples()

        guard !samples.isEmpty else {
            return
        }

        let explicitStart = chunk.timeRange?.start
            ?? chunk.presentationTimeSeconds
            ?? chunk.buffer.hostTimeSeconds

        let chunkStart = explicitStart
            ?? nextImplicitStartTime

        if pendingSamples.isEmpty {
            pendingStartTime = chunkStart
        } else if let pendingStartTime {
            let expectedStart = pendingStartTime
                + Double(pendingSamples.count)
                / Double(actualSampleRate)

            let discontinuityTolerance = max(
                0.1,
                configuration.frameDurationSeconds * 2
            )

            if abs(
                chunkStart - expectedStart
            ) > discontinuityTolerance {
                try flushLocked()
                self.pendingStartTime = chunkStart
            }
        }

        pendingSamples.append(
            contentsOf: samples
        )

        nextImplicitStartTime = chunkStart
            + Double(samples.count)
            / Double(actualSampleRate)

        let batchSampleCount = max(
            1,
            Int(
                (
                    Double(actualSampleRate)
                    * batchDurationSeconds
                ).rounded()
            )
        )

        while pendingSamples.count >= batchSampleCount {
            try flushLocked(
                sampleCount: batchSampleCount
            )
        }
    }

    public func finish() throws -> AcousticAnalysis {
        lock.lock()

        defer {
            lock.unlock()
        }

        guard !finished else {
            throw AcousticAnalysisAccumulatorError.alreadyFinished
        }

        try flushLocked()
        finished = true

        let ordered = observations.sorted {
            if $0.range.start == $1.range.start {
                return $0.id < $1.id
            }

            return $0.range.start < $1.range.start
        }

        let rebased = ordered.enumerated().map {
            index,
            observation in

            AcousticObservation(
                id: .init(
                    rawValue: index
                ),
                range: observation.range,
                signal: observation.signal,
                spectral: observation.spectral,
                activity: observation.activity,
                quality: observation.quality
            )
        }

        let noiseFloor = noiseFloorObservationCount > 0
            ? weightedNoiseFloor
                / Double(noiseFloorObservationCount)
            : 0

        return .init(
            sampleRate: sampleRate ?? 0,
            noiseFloorRMS: noiseFloor,
            observations: rebased
        )
    }
}

private extension AcousticAnalysisAccumulator {
    func flushLocked(
        sampleCount requestedSampleCount: Int? = nil
    ) throws {
        guard let sampleRate,
              sampleRate > 0,
              let startTime = pendingStartTime,
              !pendingSamples.isEmpty
        else {
            return
        }

        let sampleCount = min(
            requestedSampleCount
                ?? pendingSamples.count,
            pendingSamples.count
        )

        guard sampleCount > 0 else {
            return
        }

        let samples = Array(
            pendingSamples.prefix(
                sampleCount
            )
        )

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

        let analysisStarted = ProcessInfo
            .processInfo
            .systemUptime

        let analysis = try AcousticAnalyzer(
            configuration: configuration
        ).analyze(
            buffer,
            startingAt: startTime
        )

        acousticAnalysisSeconds += ProcessInfo
            .processInfo
            .systemUptime
            - analysisStarted

        observations.append(
            contentsOf: analysis.observations
        )

        weightedNoiseFloor += analysis.noiseFloorRMS
            * Double(analysis.observations.count)

        noiseFloorObservationCount += analysis.observations.count

        pendingSamples.removeFirst(
            sampleCount
        )

        if pendingSamples.isEmpty {
            pendingStartTime = nil
        } else {
            pendingStartTime = startTime
                + Double(sampleCount)
                / Double(sampleRate)
        }
    }
}
