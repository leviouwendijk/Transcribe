import Diarization

/// Selects the evidence that is authoritative for speaker clustering.
/// Unknown speaker count remains supported through DiarizationConfiguration.expectedSpeakerCount == nil.
public enum AppleSpeakerEvidenceMode: Sendable, Codable, Hashable {
    case acoustic
    case embedding
    case hybrid(SpeakerHybridClusteringWeights)
}

/// Selects who decides the speakers: the acoustic `Diarizer` (configured by
/// `DiarizationConfiguration`), or an audio diarization backend.
public enum AppleSpeakerDiarizer: Sendable {
    case acoustic
    case backend(
        any AudioDiarizationBackend,
        speakerCount: SpeakerCountBounds = .automatic
    )
}

public enum AppleSpeakerEvidenceModeError: Error, Sendable, Equatable {
    case embeddingProviderRequired
    case embeddingEvidenceUnavailable
    /// Embedding providers and evidence modes refine the acoustic diarizer
    /// and do not combine with a backend.
    case backendExcludesSpeakerEvidence
}
