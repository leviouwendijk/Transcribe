import Diarization
import TestFlows

extension TranscribeFlowSuite {
    static var speakerReliabilityFlow: TestFlow {
        TestFlow(
            "speaker-evidence-reliability",
            tags: [
                "clustering",
                "diarization",
                "noise",
                "speaker",
            ]
        ) {
            Step("speaker reliability downweights noisy model evidence without deleting it") {
                let sampleRate = 16_000
                let duration = 0.7

                let accumulator = ParallelAcousticAnalysisAccumulator(
                    batchDurationSeconds: 1
                )

                try accumulator.consume(
                    .init(
                        trackID: 1,
                        buffer: AudioTestFixture.buffer(
                            samples: AudioTestFixture.sine(
                                frequency: 181,
                                duration: duration,
                                amplitude: 0.14,
                                sampleRate: sampleRate
                            ),
                            sampleRate: sampleRate
                        ),
                        presentationTimeSeconds: 0,
                        durationSeconds: duration
                    )
                )

                try accumulator.consume(
                    .init(
                        trackID: 1,
                        buffer: AudioTestFixture.buffer(
                            samples: AudioTestFixture.sine(
                                frequency: 295,
                                duration: duration,
                                amplitude: 0.14,
                                sampleRate: sampleRate
                            ),
                            sampleRate: sampleRate
                        ),
                        presentationTimeSeconds: 1.5,
                        durationSeconds: duration
                    )
                )

                let evidence = try accumulator.finish()

                let cleanNoiseEvidence = evidence.raw.observations.map {
                    AcousticNoiseEvidence(
                        observationID: $0.id,
                        likelihood: 0,
                        lowEnergy: 0,
                        flatness: 0,
                        stationarity: 0,
                        pitchUnreliability: 0,
                        transient: 0
                    )
                }

                let cleanEvidence = ParallelAcousticEvidence(
                    raw: evidence.raw,
                    enhanced: evidence.enhanced,
                    noise: evidence.noise,
                    noiseEvidence: cleanNoiseEvidence,
                    enhancement: evidence.enhancement
                )

                let configuration = DiarizationConfiguration(
                    expectedSpeakerCount: 1,
                    segmentMergeGapSeconds: 0.15,
                    speakerObservation: .init(
                        minimumDurationSeconds: 0.25,
                        maximumDurationSeconds: 1,
                        maximumGapSeconds: 0.08
                    )
                )

                let baseline = Diarizer().diarize(
                    cleanEvidence,
                    configuration: configuration
                )

                try Expect.equal(
                    baseline.observations.count >= 2,
                    true,
                    "speaker-reliability.baseline-observations"
                )

                let targetObservation = baseline.observations.last
                let targetID = targetObservation?.id
                let targetAcousticIDs = Set(
                    targetObservation?.acousticObservationIDs
                        ?? []
                )

                try Expect.equal(
                    targetID == nil,
                    false,
                    "speaker-reliability.target-observation"
                )

                let weightedNoiseEvidence = evidence.raw.observations.map {
                    AcousticNoiseEvidence(
                        observationID: $0.id,
                        likelihood: targetAcousticIDs.contains($0.id)
                            ? 1
                            : 0,
                        lowEnergy: 0,
                        flatness: 0,
                        stationarity: 0,
                        pitchUnreliability: 0,
                        transient: 0
                    )
                }

                let weightedEvidence = ParallelAcousticEvidence(
                    raw: evidence.raw,
                    enhanced: evidence.enhanced,
                    noise: evidence.noise,
                    noiseEvidence: weightedNoiseEvidence,
                    enhancement: evidence.enhancement
                )

                let weighted = Diarizer().diarize(
                    weightedEvidence,
                    configuration: configuration
                )

                try Expect.equal(
                    weighted.observations.count,
                    baseline.observations.count,
                    "speaker-reliability.observations-retained"
                )

                try Expect.equal(
                    weighted.acoustic?.observations.count,
                    baseline.acoustic?.observations.count,
                    "speaker-reliability.acoustic-evidence-retained"
                )

                let baselineConfidence = baseline.segments.first { segment in
                    guard let targetID else {
                        return false
                    }

                    return segment.observationIDs.contains(
                        targetID
                    )
                }?.confidence ?? 0

                let weightedConfidence = weighted.segments.first { segment in
                    guard let targetID else {
                        return false
                    }

                    return segment.observationIDs.contains(
                        targetID
                    )
                }?.confidence ?? 0

                try Expect.equal(
                    weightedConfidence < baselineConfidence,
                    true,
                    "speaker-reliability.confidence-downweighted"
                )

                try Expect.equal(
                    weightedConfidence > 0,
                    true,
                    "speaker-reliability.not-hard-gated"
                )

                let baselineCentroid = baseline
                    .profiles
                    .first?
                    .acousticCentroid?
                    .values
                    ?? []

                let weightedCentroid = weighted
                    .profiles
                    .first?
                    .acousticCentroid?
                    .values
                    ?? []

                try Expect.equal(
                    baselineCentroid.isEmpty,
                    false,
                    "speaker-reliability.baseline-centroid"
                )

                try Expect.equal(
                    weightedCentroid.isEmpty,
                    false,
                    "speaker-reliability.weighted-centroid"
                )

                let centroidDelta = zip(
                    baselineCentroid,
                    weightedCentroid
                ).map {
                    abs($0.0 - $0.1)
                }.max() ?? 0

                try Expect.equal(
                    centroidDelta > 1e-6,
                    true,
                    "speaker-reliability.model-influence-changed"
                )

                try Expect.equal(
                    weighted.noiseEvidence,
                    weightedNoiseEvidence,
                    "speaker-reliability.noise-evidence-retained"
                )
            }
        }
    }
}
