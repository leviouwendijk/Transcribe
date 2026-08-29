import Diarization
import Foundation
import SpeechAnalysisContext
import TranscribeApple

enum TranscribeCommandRunner {
    static func run(_ options: TranscribeCommandOptions) async throws {
        let result = try await AppleSpeechAnalysisRunner().analyze(
            file: options.file,
            localeIdentifier: options.localeIdentifier,
            model: options.model,
            diarizationConfiguration: .init(
                expectedSpeakerCount: options.expectedSpeakerCount
            )
        )

        TranscribeCLI.renderDiagnostics(result.analysis)

        var traceOutput: URL?
        if let requested = options.traceOutput,
           let diarization = result.analysis.diarization {
            try diarization.acousticTraceCSV().write(
                to: requested,
                atomically: true,
                encoding: .utf8
            )
            traceOutput = requested
        }

        var contextOutput: URL?
        if let requested = options.contextOutput {
            let context = SpeechAnalysisContextProjector().project(
                result.analysis,
                detail: options.contextDetail
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            var data = try encoder.encode(context)
            data.append(0x0A)
            try data.write(to: requested, options: .atomic)
            contextOutput = requested
        }

        TranscribeTerminalRenderer.renderExports(
            trace: traceOutput,
            context: contextOutput,
            contextDetail: contextOutput == nil ? nil : options.contextDetail
        )

        TranscribeCLI.renderTiming(result.timing)

        if options.speakerAblation
            || options.speakerAblationDetail,
           let diarization = result.analysis.diarization {
            TranscribeTerminalRenderer.renderSpeakerAblation(
                Diarizer().leaveOneOutReports(diarization),
                detailed: options.speakerAblationDetail
            )
        }

        print("")
        print("=== attributed transcript ===")
        for attributed in result.analysis.attributedSegments {
            TranscribeCLI.render(attributed)
        }

        print("")
        print("=== raw transcript ===")
        print(result.appleTranscription.transcription.text)
    }
}
