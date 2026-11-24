import Diarization
import FluidAudio
import Foundation
import MediaAudio
import MediaCore

/// FluidAudio's offline pipeline: pyannote community-1 segmentation,
/// WeSpeaker embeddings with PLDA, and VBx clustering. It decides the
/// speaker count itself unless the request carries bounds.
///
/// Models download into FluidAudio's cache on first use; each call loads
/// them from there (FluidAudio's manager is not `Sendable`, so none is kept).
public struct FluidAudioDiarizationBackend:
    AudioDiarizationBackend
{
    public static let identifier = "FluidAudio.offline"
    public static let model = "pyannote-community-1+vbx"

    public init() {}

    public func diarize(
        _ request: AudioDiarizationRequest
    ) async throws -> Diarization.DiarizationResult {
        let identity = DiarizationBackendIdentity(
            identifier: Self.identifier,
            model: Self.model,
            speakerCount: request.speakerCount
        )

        var converter = Audio.Processing.AnalysisFormatConverter(
            targetSampleRate: 16_000
        )
        let conversion = converter.process(
            request.audio
        )
        let samples = conversion.buffer.monoFloatSamples()

        guard !samples.isEmpty,
              conversion.buffer.sampleRate > 0 else {
            return FluidAudioDiarizationMapping.result(
                segments: [],
                startingAt: request.startingAt,
                identity: identity
            )
        }

        var clustering = OfflineDiarizerConfig.Clustering.community
        clustering.numSpeakers = request.speakerCount.exact
        clustering.minSpeakers = request.speakerCount.minimum
        clustering.maxSpeakers = request.speakerCount.maximum

        let manager = OfflineDiarizerManager(
            config: .init(
                clustering: clustering
            )
        )
        try await manager.prepareModels()

        let output = try await manager.process(
            audio: samples
        )

        return FluidAudioDiarizationMapping.result(
            segments: output.segments.map {
                .init(
                    speaker: $0.speakerId,
                    start: Double(
                        $0.startTimeSeconds
                    ),
                    end: Double(
                        $0.endTimeSeconds
                    ),
                    quality: Double(
                        $0.qualityScore
                    ),
                    embedding: $0.embedding
                )
            },
            startingAt: request.startingAt
                + conversion.sourceOffsetSeconds,
            identity: identity
        )
    }
}

/// Turns FluidAudio segments into a `DiarizationResult`. Speakers are
/// renamed `speaker_1`, `speaker_2`, … in order of first appearance.
@_spi(Testing)
public enum FluidAudioDiarizationMapping {
    public struct Segment: Sendable {
        public let speaker: String
        public let start: TimeInterval
        public let end: TimeInterval
        public let quality: Double
        public let embedding: [Float]

        public init(
            speaker: String,
            start: TimeInterval,
            end: TimeInterval,
            quality: Double,
            embedding: [Float] = []
        ) {
            self.speaker = speaker
            self.start = start
            self.end = end
            self.quality = quality
            self.embedding = embedding
        }
    }

    public static func result(
        segments: [Segment],
        startingAt: TimeInterval,
        identity: DiarizationBackendIdentity
    ) -> Diarization.DiarizationResult {
        let ordered = segments
            .filter {
                $0.start.isFinite
                    && $0.end.isFinite
                    && $0.end > $0.start
            }
            .sorted {
                ($0.start, $0.end) < ($1.start, $1.end)
            }

        var names: [String: SpeakerID] = [:]
        var speakerSegments: [SpeakerSegment] = []
        var durations: [SpeakerID: TimeInterval] = [:]
        var counts: [SpeakerID: Int] = [:]
        var embeddings: [SpeakerID: [SpeakerEmbedding]] = [:]

        for segment in ordered {
            let speaker: SpeakerID

            if let known = names[segment.speaker] {
                speaker = known
            } else {
                speaker = SpeakerID(
                    rawValue: "speaker_\(names.count + 1)"
                )
                names[segment.speaker] = speaker
            }

            speakerSegments.append(
                .init(
                    range: .init(
                        start: startingAt + segment.start,
                        duration: segment.end - segment.start
                    ),
                    speaker: speaker,
                    confidence: min(
                        1,
                        max(
                            0,
                            segment.quality
                        )
                    )
                )
            )

            durations[speaker, default: 0] += segment.end - segment.start
            counts[speaker, default: 0] += 1

            if !segment.embedding.isEmpty {
                embeddings[speaker, default: []].append(
                    SpeakerEmbedding(
                        segment.embedding,
                        provenance: .init(
                            providerIdentifier: identity.identifier,
                            modelIdentifier: identity.model
                        )
                    )
                )
            }
        }

        let profiles = names.values
            .sorted {
                $0.rawValue < $1.rawValue
            }
            .map { speaker in
                let embeddingProfile = embeddings[speaker].flatMap {
                    SpeakerEmbeddingProfile(
                        embeddings: $0
                    )
                }

                return SpeakerProfile(
                    speaker: speaker,
                    observationCount: counts[speaker] ?? 0,
                    observedDurationSeconds: durations[speaker] ?? 0,
                    embeddingProfile: embeddingProfile,
                    embeddingCentroid: embeddingProfile?.centroid
                )
            }

        return .init(
            segments: speakerSegments,
            profiles: profiles,
            backend: identity
        )
    }
}
