import Foundation
import MediaAudio
import MediaCore

/// Speaker-count hints for a diarization backend. All nil means the backend
/// decides the count on its own.
public struct SpeakerCountBounds:
    Sendable,
    Codable,
    Hashable
{
    public let exact: Int?
    public let minimum: Int?
    public let maximum: Int?

    public init(
        exact: Int? = nil,
        minimum: Int? = nil,
        maximum: Int? = nil
    ) {
        precondition(
            exact.map { $0 > 0 } ?? true
        )
        precondition(
            minimum.map { $0 > 0 } ?? true
        )
        precondition(
            maximum.map { $0 > 0 } ?? true
        )
        if let minimum,
           let maximum {
            precondition(
                minimum <= maximum
            )
        }

        self.exact = exact
        self.minimum = minimum
        self.maximum = maximum
    }

    public static let automatic = SpeakerCountBounds()

    public var isAutomatic: Bool {
        exact == nil
            && minimum == nil
            && maximum == nil
    }
}

/// Which backend produced a diarization result, for provenance.
public struct DiarizationBackendIdentity:
    Sendable,
    Codable,
    Hashable
{
    public let identifier: String
    public let model: String?
    public let speakerCount: SpeakerCountBounds

    public init(
        identifier: String,
        model: String? = nil,
        speakerCount: SpeakerCountBounds = .automatic
    ) {
        self.identifier = identifier
        self.model = model
        self.speakerCount = speakerCount
    }
}

public struct AudioDiarizationRequest: Sendable {
    /// Audio to diarize; backends convert it to the format they need.
    public let audio: MediaAudioBuffer
    /// Media time of the buffer's first frame.
    public let startingAt: TimeInterval
    public let speakerCount: SpeakerCountBounds

    public init(
        audio: MediaAudioBuffer,
        startingAt: TimeInterval,
        speakerCount: SpeakerCountBounds = .automatic
    ) {
        self.audio = audio
        self.startingAt = startingAt
        self.speakerCount = speakerCount
    }
}

/// A diarizer that works from audio alone, in place of the acoustic
/// `Diarizer`. Results carry segments and profiles, no acoustic evidence,
/// and `backend` set.
public protocol AudioDiarizationBackend: Sendable {
    func diarize(
        _ request: AudioDiarizationRequest
    ) async throws -> DiarizationResult
}
