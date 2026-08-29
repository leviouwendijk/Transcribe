import Diarization
import TestFlows

extension TranscribeFlowSuite {
    static var speakerDiarizationReplayCalibrationFlow: TestFlow {
        TestFlow(
            "speaker-diarization-replay-calibration",
            tags: [
                "calibration",
                "clustering",
                "diarization",
                "replay",
                "speaker",
            ]
        ) {
            Step("arbitrary feature-weight candidates replay retained evidence and retain comparable clustering scale") {
                let samples = AudioTestFixture.sine(
                    frequency: 150,
                    duration: 0.8
                )
                    + AudioTestFixture.silence(
                        duration: 0.2
                    )
                    + AudioTestFixture.sine(
                        frequency: 290,
                        duration: 0.8
                    )
                    + AudioTestFixture.silence(
                        duration: 0.2
                    )
                    + AudioTestFixture.sine(
                        frequency: 150,
                        duration: 0.8
                    )
                    + AudioTestFixture.silence(
                        duration: 0.2
                    )
                    + AudioTestFixture.sine(
                        frequency: 290,
                        duration: 0.8
                    )

                let diarizer = Diarizer()
                let source = try diarizer.diarize(
                    AudioTestFixture.buffer(
                        samples: samples
                    ),
                    configuration: .init(
                        expectedSpeakerCount: 2,
                        speakerObservation: .init(
                            minimumDurationSeconds: 0.25,
                            maximumDurationSeconds: 1,
                            maximumGapSeconds: 0.08
                        )
                    )
                )

                guard let method = source.method else {
                    throw SpeakerDiarizationReplayCalibrationFlowError
                        .missingMethod
                }

                let baselineWeights = method
                    .configuration
                    .speakerObservation
                    .featureWeights
                let candidates = [
                    SpeakerDiarizationReplayCandidate(
                        name: "candidate-a",
                        featureWeights: baselineWeights.replacing(
                            mfcc: 0.75,
                            logMel: 0.50,
                            spectral: 0.45
                        )
                    ),
                    SpeakerDiarizationReplayCandidate(
                        name: "candidate-b",
                        featureWeights: baselineWeights.replacing(
                            mfcc: 0.50,
                            logMel: 0.25,
                            spectral: 0.60
                        )
                    ),
                ]
                let experiment = diarizer.replayExperiment(
                    source,
                    candidates: candidates
                )

                try Expect.equal(
                    experiment.results.map(\.candidate),
                    candidates,
                    "speaker-calibration.candidate-order"
                )
                try Expect.equal(
                    experiment.results.allSatisfy {
                        $0.result.observations.map(\.id)
                            == source.observations.map(\.id)
                            && $0.result.acoustic == source.acoustic
                    },
                    true,
                    "speaker-calibration.retained-evidence-reused"
                )
                try Expect.equal(
                    experiment.results.allSatisfy { result in
                        result.result.method?
                            .configuration
                            .speakerObservation
                            .featureWeights
                            == result.candidate.featureWeights
                    },
                    true,
                    "speaker-calibration.exact-candidate-weights"
                )
                try Expect.equal(
                    experiment.results.allSatisfy { result in
                        result.comparison
                            == diarizer.compare(
                                source,
                                to: result.result
                            )
                    },
                    true,
                    "speaker-calibration.comparison-derived"
                )

                guard let baselineClustering =
                    experiment.baselineClustering
                else {
                    throw SpeakerDiarizationReplayCalibrationFlowError
                        .missingNormalizedClustering
                }

                try Expect.equal(
                    baselineClustering
                        .normalizedReliabilityWeightedSquaredError,
                    baselineClustering
                        .clustering
                        .reliabilityWeightedSquaredError
                        / (
                            baselineClustering.totalReliabilityWeight
                                * baselineClustering.effectiveFeatureWeight
                        ),
                    "speaker-calibration.normalized-baseline-formula"
                )

                try Expect.equal(
                    experiment.results.allSatisfy { result in
                        guard let clustering = result.clustering else {
                            return false
                        }

                        let expected = clustering
                            .clustering
                            .reliabilityWeightedSquaredError
                            / (
                                clustering.totalReliabilityWeight
                                    * clustering.effectiveFeatureWeight
                            )

                        return clustering
                            .normalizedReliabilityWeightedSquaredError
                            == expected
                    },
                    true,
                    "speaker-calibration.normalized-candidate-formula"
                )
            }
        }
    }
}

enum SpeakerDiarizationReplayCalibrationFlowError:
    Error,
    Sendable
{
    case missingMethod
    case missingNormalizedClustering
}
