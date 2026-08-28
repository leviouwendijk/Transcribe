import Diarization
import Foundation
import MediaAV
import SpeechAnalysis
import Transcribe

public struct AppleSpeechAnalysisResult: Sendable {
    public let appleTranscription: AppleTranscriptionResult
    public let analysis: SpeechAnalysisResult

    public init(
        appleTranscription: AppleTranscriptionResult,
        analysis: SpeechAnalysisResult
    ) {
        self.appleTranscription = appleTranscription
        self.analysis = analysis
    }
}

public struct AppleSpeechAnalysisRunner: Sendable {
    public init() {}

    public func analyze(
        file: URL,
        localeIdentifier: String,
        model: AppleTranscriptionModel = .speech,
        trackID: Int32? = nil,
        diarizationConfiguration: DiarizationConfiguration = .init()
    ) async throws -> AppleSpeechAnalysisResult {
        let file = file.standardizedFileURL

        async let transcriptionTask = AppleTranscriber().transcribe(
            file: file,
            localeIdentifier: localeIdentifier,
            model: model
        )

        async let diarizationTask = diarize(
            file: file,
            trackID: trackID,
            configuration: diarizationConfiguration
        )

        let (
            appleTranscription,
            diarization
        ) = try await (
            transcriptionTask,
            diarizationTask
        )

        let alignment = SpeakerTranscriptAligner().align(
            transcription: appleTranscription.transcription,
            diarization: diarization
        )

        return .init(
            appleTranscription: appleTranscription,
            analysis: .init(
                transcription: appleTranscription.transcription,
                diarization: diarization,
                alignment: alignment
            )
        )
    }
}

private extension AppleSpeechAnalysisRunner {
    func diarize(
        file: URL,
        trackID: Int32?,
        configuration: DiarizationConfiguration
    ) async throws -> DiarizationResult {
        let accumulator = AcousticAnalysisAccumulator(
            configuration: configuration.acoustic
        )

        try await MediaAssetAudioReader().read(
            file,
            trackID: trackID
        ) { chunk in
            try accumulator.consume(
                chunk
            )
        }

        let acoustic = try accumulator.finish()

        return Diarizer().diarize(
            acoustic,
            configuration: configuration
        )
    }
}
