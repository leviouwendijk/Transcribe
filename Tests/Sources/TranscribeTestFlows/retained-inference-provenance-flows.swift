import Diarization
import MediaCore
import SpeechAnalysis
import TestFlows
import Transcribe

extension TranscribeFlowSuite {
    static var retainedInferenceProvenanceFlow: TestFlow {
        TestFlow(
            "retained-inference-provenance",
            tags: [
                "diarization",
                "evidence",
                "provenance",
                "speech-analysis",
            ]
        ) {
            Step("diarization retains the exact method and decision evidence it used") {
                let samples = AudioTestFixture.sine(
                    frequency: 181,
                    duration: 0.8
                )
                    + AudioTestFixture.silence(
                        duration: 0.2
                    )
                    + AudioTestFixture.sine(
                        frequency: 295,
                        duration: 0.8
                    )
                    + AudioTestFixture.silence(
                        duration: 0.2
                    )
                    + AudioTestFixture.sine(
                        frequency: 181,
                        duration: 0.8
                    )
                    + AudioTestFixture.silence(
                        duration: 0.2
                    )
                    + AudioTestFixture.sine(
                        frequency: 295,
                        duration: 0.8
                    )

                let buffer = AudioTestFixture.buffer(
                    samples: samples
                )

                let acoustic = try AcousticAnalyzer().analyze(
                    buffer
                )

                let noiseEvidence = acoustic.observations.map {
                    AcousticNoiseEvidence(
                        observationID: $0.id,
                        likelihood: 0.72,
                        lowEnergy: 0.25,
                        flatness: 0.20,
                        stationarity: 0.30,
                        pitchUnreliability: 0.15,
                        transient: 0.10
                    )
                }

                let reliability = SpeakerEvidenceReliabilityConfiguration(
                    fullAuthorityMaximumNoiseLikelihood: 0.50,
                    minimumAuthorityNoiseLikelihood: 0.90,
                    minimumReliability: 0.25
                )

                let configuration = DiarizationConfiguration(
                    expectedSpeakerCount: 2,
                    temporalCoherence: .init(
                        switchPenalty: 0.31,
                        maximumContinuityGapSeconds: 0.40
                    ),
                    speakerReliability: reliability,
                    speakerObservation: .init(
                        minimumDurationSeconds: 0.25,
                        maximumDurationSeconds: 1,
                        maximumGapSeconds: 0.08
                    )
                )

                let result = Diarizer().diarize(
                    acoustic,
                    noiseEvidence: noiseEvidence,
                    configuration: configuration
                )

                try Expect.equal(
                    result.method != nil,
                    true,
                    "provenance.method-retained"
                )

                let method = result.method
                    ?? .init(
                        configuration: configuration
                    )

                try Expect.equal(
                    method.configuration,
                    configuration,
                    "provenance.configuration"
                )

                try Expect.equal(
                    method.configuration.speakerReliability,
                    reliability,
                    "provenance.reliability-policy"
                )

                try Expect.equal(
                    method.featureSpace.isEmpty,
                    false,
                    "provenance.feature-space"
                )

                try Expect.equal(
                    method.featureSpace.count,
                    result.observations.first?.features.values.count ?? 0,
                    "provenance.feature-coordinate-count"
                )

                try Expect.equal(
                    method.standardization.means.count,
                    method.featureSpace.count,
                    "provenance.standardization-means"
                )

                try Expect.equal(
                    method.standardization.deviations.count,
                    method.featureSpace.count,
                    "provenance.standardization-deviations"
                )

                try Expect.equal(
                    method.clustering?.selectedSpeakerCount,
                    2,
                    "provenance.selected-speaker-count"
                )

                try Expect.equal(
                    result.assignments.count,
                    result.observations.count,
                    "provenance.assignment-count"
                )

                try Expect.equal(
                    result.assignments.allSatisfy {
                        $0.reliabilityEvaluation.noiseLikelihood != nil
                            && $0.reliabilityEvaluation.sourceObservationCount > 0
                    },
                    true,
                    "provenance.reliability-evaluation"
                )

                try Expect.equal(
                    result.assignments.allSatisfy { assignment in
                        assignment.candidates.allSatisfy { candidate in
                            guard !candidate.featureContributions.isEmpty else {
                                return false
                            }

                            let contributionTotal = candidate.featureContributions.reduce(
                                0
                            ) {
                                $0 + $1.squaredDistance
                            }

                            return abs(
                                contributionTotal
                                    - candidate.squaredDistance
                            ) < 1e-8
                        }
                    },
                    true,
                    "provenance.feature-contributions"
                )

                if result.assignments.count > 1 {
                    try Expect.equal(
                        result.assignments.dropFirst().allSatisfy {
                            $0.temporalTransition != nil
                        },
                        true,
                        "provenance.temporal-transition-evaluation"
                    )
                }
            }

            Step("attributed transcription retains the alignment assignment instead of lowering it") {
                let transcription = Transcription(
                    localeIdentifier: "en-US",
                    segments: [
                        .init(
                            text: "Hello.",
                            range: .init(
                                start: 1,
                                duration: 0.5
                            ),
                            confidence: 0.91,
                            alternatives: [
                                "Hallo.",
                            ]
                        )
                    ]
                )

                let speaker = SpeakerID(
                    rawValue: "speaker_2"
                )

                let assignment = SpeakerAssignment(
                    segmentIndex: 0,
                    speaker: speaker,
                    confidence: 0.77,
                    method: .nearestEvidence,
                    speakerSegmentIndices: [
                        4,
                        5,
                    ]
                )

                let alignmentConfiguration = SpeakerTranscriptAligner.Configuration(
                    maximumBridgeGapSeconds: 0.7,
                    maximumNearestEvidenceDistanceSeconds: 0.2,
                    minimumBridgedConfidence: 0.15,
                    minimumNearestConfidence: 0.20
                )

                let result = SpeechAnalysisResult(
                    transcription: transcription,
                    alignment: .init(
                        assignments: [
                            assignment,
                        ],
                        configuration: alignmentConfiguration
                    )
                )

                try Expect.equal(
                    result.attributedTranscription != nil,
                    true,
                    "provenance.attributed-transcription"
                )

                if let attributed = result.attributedTranscription {
                    try Expect.equal(
                        attributed.localeIdentifier,
                    transcription.localeIdentifier,
                    "provenance.attributed-locale"
                )

                try Expect.equal(
                    attributed.segments[0].segment,
                    transcription.segments[0],
                    "provenance.original-transcription-segment"
                )

                try Expect.equal(
                    attributed.segments[0].assignment,
                    assignment,
                    "provenance.full-alignment-assignment"
                )

                try Expect.equal(
                    result.alignment?.configuration,
                    alignmentConfiguration,
                    "provenance.alignment-configuration"
                )

                try Expect.equal(
                    attributed.segments[0].assignmentMethod,
                    .nearestEvidence,
                    "provenance.assignment-method"
                )

                    try Expect.equal(
                        attributed.segments[0].speakerSegmentIndices,
                        [
                            4,
                            5,
                        ],
                        "provenance.assignment-source-segments"
                    )
                }
            }
        }
    }
}
