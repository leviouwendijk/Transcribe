import Diarization
import EmbeddingProviderFluidAudio
import Foundation
import SpeechAnalysisContext
import TranscribeApple

enum TranscribeCommandRunner {
    static func run(_ options: TranscribeCommandOptions) async throws {
        let diarizationConfiguration = DiarizationConfiguration(
            expectedSpeakerCount: options.expectedSpeakerCount
        )
        let runner = AppleSpeechAnalysisRunner()
        let result: AppleSpeechAnalysisResult

        switch options.speakerEmbeddings {
        case .none:
            result = try await runner.analyze(
                file: options.file,
                localeIdentifier: options.localeIdentifier,
                model: options.model,
                diarizationConfiguration: diarizationConfiguration
            )

        case .some(.fluidAudio):
            result = try await runner.analyze(
                file: options.file,
                localeIdentifier: options.localeIdentifier,
                model: options.model,
                diarizationConfiguration: diarizationConfiguration,
                speakerEmbeddingProvider: FluidAudioSpeakerEmbeddingProvider()
            )
        }

        TranscribeCLI.renderDiagnostics(result.analysis)

        if let requestedProvider = options.speakerEmbeddings {
            TranscribeTerminalRenderer.renderSpeakerEmbeddings(
                result.analysis.diarization,
                requestedProvider: requestedProvider.rawValue
            )
        }

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

        if options.speakerCalibration,
           let diarization = result.analysis.diarization,
           let baselineWeights = diarization.method?
            .configuration
            .speakerObservation
            .featureWeights {
            let experiment = Diarizer().replayExperiment(
                diarization,
                candidates: speakerCalibrationCandidates(
                    baselineWeights
                )
            )

            TranscribeTerminalRenderer.renderSpeakerCalibration(
                experiment
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

private extension TranscribeCommandRunner {
    static func speakerCalibrationCandidates(
        _ baseline: SpeakerFeatureWeights
    ) -> [SpeakerDiarizationReplayCandidate] {
        [
            .init(
                name: "normalized-family-defaults",
                featureWeights: baseline,
                featureWeighting: .normalizedFamily
            ),
        ]
    }
}
