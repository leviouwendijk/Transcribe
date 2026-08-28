import Foundation
import MediaAudio
import MediaCore

public final class ParallelAcousticAnalysisAccumulator:
    @unchecked Sendable
{
    private let lock = NSLock()
    private let raw: AcousticAnalysisAccumulator
    private let enhanced: AcousticAnalysisAccumulator
    private var converter: Audio.Processing.AnalysisFormatConverter
    private var enhancer: Audio.Processing.AnalysisEnhancer
    private var telemetry: [Audio.Processing.Telemetry] = []
    private var finished = false

    public init(
        configuration: AcousticAnalyzerConfiguration = .init(),
        enhancement: Audio.Processing.AnalysisEnhancer.Configuration = .init(),
        analysisSampleRate: Int = 16_000,
        batchDurationSeconds: Double = 4
    ) {
        raw = .init(
            configuration: configuration,
            batchDurationSeconds: batchDurationSeconds
        )
        enhanced = .init(
            configuration: configuration,
            batchDurationSeconds: batchDurationSeconds
        )
        converter = .init(
            targetSampleRate: analysisSampleRate
        )
        enhancer = .init(
            configuration: enhancement
        )
    }

    public var acousticAnalysisDurationSeconds: TimeInterval {
        raw.acousticAnalysisDurationSeconds
            + enhanced.acousticAnalysisDurationSeconds
    }

    public func consume(
        _ chunk: MediaAudioChunk
    ) throws {
        lock.lock()

        defer {
            lock.unlock()
        }

        precondition(!finished)

        let conversion = converter.process(
            chunk.buffer
        )

        guard conversion.buffer.frameCount > 0 else {
            return
        }

        let originalStart = chunk.timeRange?.start
            ?? chunk.presentationTimeSeconds
            ?? chunk.buffer.hostTimeSeconds

        let normalizedStart = originalStart.map {
            $0 + conversion.sourceOffsetSeconds
        }

        let normalizedDuration = Double(
            conversion.buffer.frameCount
        ) / Double(
            conversion.buffer.sampleRate
        )

        let normalized = MediaAudioChunk(
            trackID: chunk.trackID,
            buffer: conversion.buffer,
            presentationTimeSeconds: normalizedStart,
            durationSeconds: normalizedDuration
        )

        try raw.consume(
            normalized
        )

        let result = enhancer.process(
            normalized.buffer
        )

        telemetry.append(
            result.telemetry
        )

        try enhanced.consume(
            .init(
                trackID: normalized.trackID,
                buffer: result.buffer,
                presentationTimeSeconds: normalized.presentationTimeSeconds,
                durationSeconds: normalized.durationSeconds
            )
        )
    }

    public func finish() throws -> ParallelAcousticEvidence {
        lock.lock()

        defer {
            lock.unlock()
        }

        precondition(!finished)
        finished = true

        let rawAnalysis = try raw.finish()
        let enhancedAnalysis = try enhanced.finish()
        let rawUsable = Set(
            rawAnalysis.usableObservations.map(
                \.id
            )
        )
        let enhancedUsable = Set(
            enhancedAnalysis.usableObservations.map(
                \.id
            )
        )

        return .init(
            raw: rawAnalysis,
            enhanced: enhancedAnalysis,
            noise: .init(
                analysis: rawAnalysis
            ),
            enhancement: .init(
                appliedGainDB: telemetry.map(
                    \.appliedGainDB
                ),
                inputRMSDB: telemetry.map(
                    \.inputRMSDB
                ),
                outputRMSDB: telemetry.map(
                    \.outputRMSDB
                ),
                recoveredUsableObservationCount: enhancedUsable
                    .subtracting(rawUsable)
                    .count
            )
        )
    }
}
