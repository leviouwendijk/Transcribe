import MediaCore

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

    public init(
        text: String,
        range: Audio.TimeRange? = nil,
        confidence: Double? = nil,
        alternatives: [String] = [],
        isFinal: Bool = true
    ) {
        self.text = text
        self.range = range
        self.confidence = confidence
        self.alternatives = alternatives
        self.isFinal = isFinal
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
