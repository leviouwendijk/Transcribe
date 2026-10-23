import Diarization

/// Selects the evidence that is authoritative for speaker clustering.
/// Unknown speaker count remains supported through DiarizationConfiguration.expectedSpeakerCount == nil.
public enum AppleSpeakerEvidenceMode: Sendable, Codable, Hashable {
    case acoustic
    case embedding
    case hybrid(SpeakerHybridClusteringWeights)
}

public enum AppleSpeakerEvidenceModeError: Error, Sendable, Equatable {
    case embeddingProviderRequired
    case embeddingEvidenceUnavailable
}
