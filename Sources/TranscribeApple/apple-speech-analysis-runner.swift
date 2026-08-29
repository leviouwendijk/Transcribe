import Diarization
import Foundation
import MediaAV
import SpeechAnalysis
import Transcribe

public struct AppleSpeechAnalysisTiming: Sendable {
    public let transcriptionSeconds: TimeInterval
    public let mediaInputAndAccumulationSeconds: TimeInterval
    public let acousticDSPSeconds: TimeInterval
    public let speakerDiarizationSeconds: TimeInterval
    public let speakerEmbeddingSeconds: TimeInterval
    public let alignmentSeconds: TimeInterval
    public let totalSeconds: TimeInterval

    public init(
        transcriptionSeconds: TimeInterval,
        mediaInputAndAccumulationSeconds: TimeInterval,
        acousticDSPSeconds: TimeInterval,
        speakerDiarizationSeconds: TimeInterval,
        speakerEmbeddingSeconds: TimeInterval = 0,
        alignmentSeconds: TimeInterval,
        totalSeconds: TimeInterval
    ) {
        self.transcriptionSeconds = transcriptionSeconds
        self.mediaInputAndAccumulationSeconds = mediaInputAndAccumulationSeconds
        self.acousticDSPSeconds = acousticDSPSeconds
        self.speakerDiarizationSeconds = speakerDiarizationSeconds
        self.speakerEmbeddingSeconds = speakerEmbeddingSeconds
        self.alignmentSeconds = alignmentSeconds
        self.totalSeconds = totalSeconds
    }

    public var diarizationSeconds: TimeInterval {
        mediaInputAndAccumulationSeconds
            + acousticDSPSeconds
            + speakerDiarizationSeconds
            + speakerEmbeddingSeconds
    }
}

public struct AppleSpeechAnalysisResult: Sendable {
    public let appleTranscription: AppleTranscriptionResult
    public let analysis: SpeechAnalysisResult
    public let timing: AppleSpeechAnalysisTiming

    public init(
        appleTranscription: AppleTranscriptionResult,
        analysis: SpeechAnalysisResult,
        timing: AppleSpeechAnalysisTiming
    ) {
        self.appleTranscription = appleTranscription
        self.analysis = analysis
        self.timing = timing
    }
}

public struct AppleSpeechAnalysisRunner: Sendable {
    public init() {}

    public func analyze(
        file: URL,
        localeIdentifier: String,
        model: AppleTranscriptionModel = .speech,
        trackID: Int32? = nil,
        diarizationConfiguration: DiarizationConfiguration = .init(),
        speakerEmbeddingProvider: (any SpeakerEmbeddingProvider)? = nil
    ) async throws -> AppleSpeechAnalysisResult {
        let file = file.standardizedFileURL
        let totalStarted = uptime()

        async let transcriptionTask = transcribe(
            file: file,
            localeIdentifier: localeIdentifier,
            model: model
        )

        async let diarizationTask = diarize(
            file: file,
            trackID: trackID,
            configuration: diarizationConfiguration,
            retainEmbeddingAudio: speakerEmbeddingProvider != nil
        )

        let (
            transcription,
            diarization
        ) = try await (
            transcriptionTask,
            diarizationTask
        )

        var diarizationResult = diarization.result
        var speakerEmbeddingSeconds: TimeInterval = 0

        if let speakerEmbeddingProvider,
           let embeddingAudio = diarization.embeddingAudio,
           !diarizationResult.observations.isEmpty {
            let embeddingStarted = uptime()
            let enrichedObservations = try await SpeakerEmbeddingEnricher().enrich(
                diarizationResult.observations,
                audio: embeddingAudio.buffer,
                startingAt: embeddingAudio.startingAt,
                using: speakerEmbeddingProvider
            )
            let enrichedSource = DiarizationResult(
                segments: diarizationResult.segments,
                profiles: diarizationResult.profiles,
                observations: enrichedObservations,
                assignments: diarizationResult.assignments,
                method: diarizationResult.method,
                acoustic: diarizationResult.acoustic,
                enhancedAcoustic: diarizationResult.enhancedAcoustic,
                noiseProfile: diarizationResult.noiseProfile,
                noiseEvidence: diarizationResult.noiseEvidence,
                enhancement: diarizationResult.enhancement
            )

            diarizationResult = Diarizer().replay(
                enrichedSource
            )
            speakerEmbeddingSeconds = uptime()
                - embeddingStarted
        }

        let alignmentStarted = uptime()

        let alignment = SpeakerTranscriptAligner().align(
            transcription: transcription.result.transcription,
            diarization: diarizationResult
        )

        let alignmentSeconds = uptime()
            - alignmentStarted

        return .init(
            appleTranscription: transcription.result,
            analysis: .init(
                transcription: transcription.result.transcription,
                diarization: diarizationResult,
                alignment: alignment
            ),
            timing: .init(
                transcriptionSeconds: transcription.seconds,
                mediaInputAndAccumulationSeconds: diarization.mediaInputAndAccumulationSeconds,
                acousticDSPSeconds: diarization.acousticDSPSeconds,
                speakerDiarizationSeconds: diarization.speakerDiarizationSeconds,
                speakerEmbeddingSeconds: speakerEmbeddingSeconds,
                alignmentSeconds: alignmentSeconds,
                totalSeconds: uptime()
                    - totalStarted
            )
        )
    }
}

private struct TimedAppleTranscription: Sendable {
    let result: AppleTranscriptionResult
    let seconds: TimeInterval
}

private struct TimedDiarization: Sendable {
    let result: DiarizationResult
    let embeddingAudio: SpeakerEmbeddingAudio?
    let mediaInputAndAccumulationSeconds: TimeInterval
    let acousticDSPSeconds: TimeInterval
    let speakerDiarizationSeconds: TimeInterval
}

private extension AppleSpeechAnalysisRunner {
    func transcribe(
        file: URL,
        localeIdentifier: String,
        model: AppleTranscriptionModel
    ) async throws -> TimedAppleTranscription {
        let started = uptime()

        let result = try await AppleTranscriber().transcribe(
            file: file,
            localeIdentifier: localeIdentifier,
            model: model
        )

        return .init(
            result: result,
            seconds: uptime()
                - started
        )
    }

    func diarize(
        file: URL,
        trackID: Int32?,
        configuration: DiarizationConfiguration,
        retainEmbeddingAudio: Bool
    ) async throws -> TimedDiarization {
        let accumulator = ParallelAcousticAnalysisAccumulator(
            configuration: configuration.acoustic
        )
        let embeddingAudioAccumulator = retainEmbeddingAudio
            ? SpeakerEmbeddingAudioAccumulator()
            : nil

        let inputStarted = uptime()

        try await MediaAssetAudioReader().read(
            file,
            trackID: trackID
        ) { chunk in
            try accumulator.consume(
                chunk
            )
            embeddingAudioAccumulator?.consume(
                chunk
            )
        }

        let evidence = try accumulator.finish()
        let embeddingAudio = embeddingAudioAccumulator?.finish()
        let inputTotalSeconds = uptime()
            - inputStarted
        let acousticDSPSeconds = accumulator
            .acousticAnalysisDurationSeconds

        let speakerStarted = uptime()

        let result = Diarizer().diarize(
            evidence,
            configuration: configuration
        )

        let speakerSeconds = uptime()
            - speakerStarted

        return .init(
            result: result,
            embeddingAudio: embeddingAudio,
            mediaInputAndAccumulationSeconds: max(
                0,
                inputTotalSeconds
                    - acousticDSPSeconds
            ),
            acousticDSPSeconds: acousticDSPSeconds,
            speakerDiarizationSeconds: speakerSeconds
        )
    }

    func uptime() -> TimeInterval {
        ProcessInfo.processInfo.systemUptime
    }
}
