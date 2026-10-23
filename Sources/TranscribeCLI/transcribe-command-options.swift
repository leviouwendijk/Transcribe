import Arguments
import Foundation
import SpeechAnalysisContext
import TranscribeApple

enum TranscribeCommandOptionsError: Error, LocalizedError, Sendable {
    case missingAudioFile
    case invalidModel(String)
    case invalidSpeakerCount(String)
    case invalidMaximumSpeakerCount(String)
    case missingSpeakerEmbeddingProvider
    case invalidSpeakerEvidenceWeights
    case unexpectedSpeakerEvidenceWeights

    var errorDescription: String? {
        switch self {
        case .missingAudioFile:
            "audio-file is required"
        case .invalidModel(let value):
            "model must be speech or dictation, not '\(value)'"
        case .invalidSpeakerCount(let value):
            "speaker-count must be a positive integer, not '\(value)'"
        case .invalidMaximumSpeakerCount(let value):
            "max-speakers must be positive and at least the expected count, not '\(value)'"
        case .missingSpeakerEmbeddingProvider:
            "embedding or hybrid speaker evidence requires --speaker-embeddings fluid-audio"
        case .invalidSpeakerEvidenceWeights:
            "hybrid weights must be finite, nonnegative, and have a positive sum"
        case .unexpectedSpeakerEvidenceWeights:
            "speaker evidence weights are only valid with --speaker-evidence hybrid"
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

enum TranscribeSpeakerEmbeddingArgument: String, Sendable, ArgumentValue {
    case fluidAudio = "fluid-audio"
}

enum TranscribeSpeakerEvidenceArgument: String, Sendable, ArgumentValue {
    case acoustic
    case embedding
    case hybrid
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
    let maximumSpeakerCount: Int
    let traceOutput: URL?
    let contextOutput: URL?
    let contextDetail: SpeechAnalysisContextDetail
    let speakerAblation: Bool
    let speakerAblationDetail: Bool
    let speakerCalibration: Bool
    let speakerEmbeddings: TranscribeSpeakerEmbeddingArgument?
    let speakerEvidenceMode: AppleSpeakerEvidenceMode

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

        let ceiling = arguments.maxSpeakers ?? max(4, expectedSpeakerCount ?? 0)
        guard ceiling > 0, ceiling >= (expectedSpeakerCount ?? 0) else {
            throw TranscribeCommandOptionsError.invalidMaximumSpeakerCount(String(ceiling))
        }
        maximumSpeakerCount = ceiling

        traceOutput = outputURL(
            arguments.traceOutput ?? arguments.legacyTraceOutput
        )
        contextOutput = arguments.contextOutput.flatMap(outputURL)
        contextDetail = arguments.contextDetail.detail
        speakerAblation = arguments.speakerAblation
        speakerAblationDetail = arguments.speakerAblationDetail
        speakerCalibration = arguments.speakerCalibration
        speakerEmbeddings = arguments.speakerEmbeddings
        let selectedEvidence = arguments.speakerEvidence
        if selectedEvidence != .hybrid,
           arguments.acousticWeight != nil || arguments.embeddingWeight != nil {
            throw TranscribeCommandOptionsError.unexpectedSpeakerEvidenceWeights
        }
        switch selectedEvidence {
        case .acoustic:
            speakerEvidenceMode = .acoustic
        case .embedding:
            guard speakerEmbeddings != nil else {
                throw TranscribeCommandOptionsError.missingSpeakerEmbeddingProvider
            }
            speakerEvidenceMode = .embedding
        case .hybrid:
            guard speakerEmbeddings != nil else {
                throw TranscribeCommandOptionsError.missingSpeakerEmbeddingProvider
            }
            let acoustic = arguments.acousticWeight ?? 0.5
            let embedding = arguments.embeddingWeight ?? 0.5
            guard acoustic.isFinite, embedding.isFinite,
                  acoustic >= 0, embedding >= 0,
                  acoustic + embedding > 0 else {
                throw TranscribeCommandOptionsError.invalidSpeakerEvidenceWeights
            }
            speakerEvidenceMode = .hybrid(.init(acoustic: acoustic, embedding: embedding))
        }
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

        @Opt("max-speakers", help: "Upper bound for inferred speaker count; default 4.")
        var maxSpeakers: Int?

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

        @Flag(
            "speaker-calibration",
            help: "Replay experimental speaker feature weighting without changing production defaults."
        )
        var speakerCalibration: Bool

        @Opt(
            "speaker-embeddings",
            help: "Acquire retained speaker embeddings: fluid-audio."
        )
        var speakerEmbeddings: TranscribeSpeakerEmbeddingArgument?

        @Opt("speaker-evidence", default: .acoustic,
             help: "Speaker clustering evidence: acoustic, embedding, or hybrid.")
        var speakerEvidence: TranscribeSpeakerEvidenceArgument

        @Opt("acoustic-weight", help: "Hybrid acoustic evidence weight; default 0.5.")
        var acousticWeight: Double?

        @Opt("embedding-weight", help: "Hybrid embedding evidence weight; default 0.5.")
        var embeddingWeight: Double?

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
