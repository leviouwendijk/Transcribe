import Foundation
import Speech
import Transcribe

public enum AppleTranscriptionModel:
    String,
    Sendable,
    Codable,
    Hashable,
    CaseIterable
{
    case speech
    case dictation
}

public enum AppleTranscriptionError:
    Error,
    Sendable,
    LocalizedError
{
    case speechTranscriberUnavailable
    case unsupportedSpeechLocale(String)
    case unsupportedDictationLocale(String)

    public var errorDescription: String? {
        switch self {
        case .speechTranscriberUnavailable:
            return "SpeechTranscriber is unavailable on this Mac."

        case .unsupportedSpeechLocale(let locale):
            return "SpeechTranscriber does not support locale: \(locale)"

        case .unsupportedDictationLocale(let locale):
            return "DictationTranscriber does not support locale: \(locale)"
        }
    }
}

public enum AppleNativeTranscriptionResult: Sendable {
    case speech(SpeechTranscriber.Result)
    case dictation(DictationTranscriber.Result)
}

public struct AppleTranscriptionResult: Sendable {
    public let transcription: Transcription
    public let nativeResults: [AppleNativeTranscriptionResult]

    public init(
        transcription: Transcription,
        nativeResults: [AppleNativeTranscriptionResult]
    ) {
        self.transcription = transcription
        self.nativeResults = nativeResults
    }
}
