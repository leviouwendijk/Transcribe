import MediaCore

/// One timed run of a transcription segment, usually a single word.
/// Untimed punctuation stays attached to the word it follows.
public struct TranscriptionWord:
    Sendable,
    Codable,
    Hashable
{
    public let text: String
    public let range: Audio.TimeRange
    public let confidence: Double?

    public init(
        text: String,
        range: Audio.TimeRange,
        confidence: Double? = nil
    ) {
        self.text = text
        self.range = range
        self.confidence = confidence
    }
}

public struct TranscriptionSegment:
    Sendable,
    Codable,
    Hashable
{
    public let text: String
    public let range: Audio.TimeRange?
    public let confidence: Double?
    public let alternatives: [String]
    public let isFinal: Bool
    /// Timed words in order; empty when the transcriber reported no word timing.
    public let words: [TranscriptionWord]

    public init(
        text: String,
        range: Audio.TimeRange? = nil,
        confidence: Double? = nil,
        alternatives: [String] = [],
        isFinal: Bool = true,
        words: [TranscriptionWord] = []
    ) {
        self.text = text
        self.range = range
        self.confidence = confidence
        self.alternatives = alternatives
        self.isFinal = isFinal
        self.words = words
    }
}

public struct Transcription:
    Sendable,
    Codable,
    Hashable
{
    public let localeIdentifier: String?
    public let segments: [TranscriptionSegment]

    public init(
        localeIdentifier: String? = nil,
        segments: [TranscriptionSegment]
    ) {
        self.localeIdentifier = localeIdentifier
        self.segments = segments
    }

    public var text: String {
        segments
            .map(\.text)
            .joined()
    }
}
