import Foundation
import MediaAudio
import MediaCore

public final class ParallelAcousticAnalysisAccumulator:
    @unchecked Sendable
{
    private let lock = NSLock()
    private let raw: AcousticAnalysisAccumulator
    private let enhanced: AcousticAnalysisAccumulator
    private var enhancer: Audio.Processing.AnalysisEnhancer
    private var telemetry: [Audio.Processing.Telemetry] = []
    private var finished = false

    public init(
        configuration: AcousticAnalyzerConfiguration = .init(),
        enhancement: Audio.Processing.AnalysisEnhancer.Configuration = .init(),
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

        try raw.consume(
            chunk
        )

        let result = enhancer.process(
            chunk.buffer
        )

        telemetry.append(
            result.telemetry
        )

        try enhanced.consume(
            .init(
                trackID: chunk.trackID,
                buffer: result.buffer,
                presentationTimeSeconds: chunk.presentationTimeSeconds,
                durationSeconds: chunk.durationSeconds
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
