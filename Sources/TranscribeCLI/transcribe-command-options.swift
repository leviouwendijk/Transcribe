import Arguments
import Foundation
import SpeechAnalysisContext
import TranscribeApple

enum TranscribeCommandOptionsError: Error, LocalizedError, Sendable {
    case missingAudioFile
    case invalidModel(String)
    case invalidSpeakerCount(String)

    var errorDescription: String? {
        switch self {
        case .missingAudioFile:
            "audio-file is required"
        case .invalidModel(let value):
            "model must be speech or dictation, not '\(value)'"
        case .invalidSpeakerCount(let value):
            "speaker-count must be a positive integer, not '\(value)'"
        }
    }
}

enum TranscribeModelArgument: String, Sendable, ArgumentValue {
    case speech
    case dictation

    var model: AppleTranscriptionModel {
        switch self {
        case .speech: .speech
        case .dictation: .dictation
        }
    }
}

enum TranscribeContextDetailArgument: String, Sendable, ArgumentValue {
    case conversation
    case diagnostic
    case complete

    var detail: SpeechAnalysisContextDetail {
        switch self {
        case .conversation: .conversation
        case .diagnostic: .diagnostic
        case .complete: .complete
        }
    }
}

struct TranscribeCommandOptions: Sendable, ArgumentParsed {
    typealias ArgumentPayload = Payload

    let file: URL
    let localeIdentifier: String
    let model: AppleTranscriptionModel
    let expectedSpeakerCount: Int?
    let traceOutput: URL?
    let contextOutput: URL?
    let contextDetail: SpeechAnalysisContextDetail
    let speakerAblation: Bool
    let speakerAblationDetail: Bool

    init(arguments: Payload) throws {
        let audioFile = clean(arguments.audioFile)
        guard !audioFile.isEmpty else {
            throw TranscribeCommandOptionsError.missingAudioFile
        }

        file = url(audioFile)

        let locale = arguments.locale.map(clean)
            ?? clean(arguments.legacyLocale)
        localeIdentifier = locale.isEmpty ? "nl-NL" : locale

        if let requested = arguments.model {
            model = requested.model
        } else {
            let legacy = clean(arguments.legacyModel)
            guard legacy.isEmpty
                || TranscribeModelArgument(rawValue: legacy) != nil
            else {
                throw TranscribeCommandOptionsError.invalidModel(legacy)
            }
            model = TranscribeModelArgument(rawValue: legacy)?.model
                ?? .speech
        }

        if let requested = arguments.speakerCount {
            guard requested > 0 else {
                throw TranscribeCommandOptionsError.invalidSpeakerCount(
                    String(requested)
                )
            }
            expectedSpeakerCount = requested
        } else {
            let legacy = clean(arguments.legacySpeakerCount)
            if legacy.isEmpty {
                expectedSpeakerCount = nil
            } else if let requested = Int(legacy), requested > 0 {
                expectedSpeakerCount = requested
            } else {
                throw TranscribeCommandOptionsError.invalidSpeakerCount(legacy)
            }
        }

        traceOutput = outputURL(
            arguments.traceOutput ?? arguments.legacyTraceOutput
        )
        contextOutput = arguments.contextOutput.flatMap(outputURL)
        contextDetail = arguments.contextDetail.detail
        speakerAblation = arguments.speakerAblation
        speakerAblationDetail = arguments.speakerAblationDetail
    }

    struct Payload: ArgumentGroup {
        @Arg(
            "audio-file",
            help: "Audio file to transcribe and analyze.",
            default: ""
        )
        var audioFile: String

        @Arg(
            "locale-argument",
            help: "Legacy positional locale identifier.",
            default: ""
        )
        var legacyLocale: String

        @Arg(
            "model-argument",
            help: "Legacy positional Apple model: speech or dictation.",
            default: ""
        )
        var legacyModel: String

        @Arg(
            "speaker-count-argument",
            help: "Legacy positional expected speaker count.",
            default: ""
        )
        var legacySpeakerCount: String

        @Arg(
            "trace-output-argument",
            help: "Legacy positional acoustic trace CSV output path.",
            default: ""
        )
        var legacyTraceOutput: String

        @Opt("locale", short: "l", help: "Locale identifier. Defaults to nl-NL.")
        var locale: String?

        @Opt("model", short: "m", help: "Apple model: speech or dictation.")
        var model: TranscribeModelArgument?

        @Opt("speaker-count", short: "s", help: "Expected positive speaker count.")
        var speakerCount: Int?

        @Opt("trace-output", short: "t", help: "Write acoustic trace CSV to this path.")
        var traceOutput: String?

        @Opt("context", short: "c", help: "Write SpeechAnalysisContext JSON to this path.")
        var contextOutput: String?

        @Opt(
            "context-detail",
            default: .conversation,
            help: "Context detail: conversation, diagnostic, or complete."
        )
        var contextDetail: TranscribeContextDetailArgument

        @Flag(
            "speaker-ablation",
            help: "Replay diarization once per feature family and report sensitivity."
        )
        var speakerAblation: Bool

        @Flag(
            "speaker-ablation-detail",
            help: "Include localized assignment changes for each speaker-feature ablation."
        )
        var speakerAblationDetail: Bool

        init() {}
    }
}

private func clean(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines)
}

private func url(_ value: String) -> URL {
    URL(
        fileURLWithPath: NSString(string: value).expandingTildeInPath
    )
}

private func outputURL(_ value: String) -> URL? {
    let value = clean(value)
    return value.isEmpty ? nil : url(value)
}
