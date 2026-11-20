import Diarization
import Foundation
import MediaCore
import Schema
import SpeechAnalysis
import SpeechAnalysisContext
import TestFlows
import Transcribe

extension TranscribeFlowSuite {
    static var speechAnalysisContextFlow: TestFlow {
        TestFlow(
            "speech-analysis-context",
            tags: [
                "context",
                "llm",
                "projection",
                "schema",
                "speech-analysis",
            ]
        ) {
            Step("context detail levels project one authoritative analysis without mutating it") {
                let speaker = SpeakerID(
                    rawValue: "speaker_1"
                )
                let acousticID = AcousticObservationID(
                    rawValue: 0
                )
                let acousticObservation = AcousticObservation(
                    id: acousticID,
                    range: .init(
                        start: 1,
                        duration: 0.4
                    ),
                    signal: .init(
                        rms: 0.02,
                        peak: 0.10,
                        zeroCrossingRate: 0.08,
                        clippingFraction: 0
                    ),
                    spectral: .init(
                        centroidHz: 1_200,
                        spreadHz: 500,
                        rolloffHz: 2_400,
                        flatness: 0.12,
                        pitchHz: 180,
                        pitchConfidence: 0.8,
                        voicedProbability: 0.7,
                        logMelEnergies: [
                            -2,
                            -1,
                        ],
                        mfcc: [
                            0.3,
                            -0.2,
                        ]
                    ),
                    activity: .voicedSpeech,
                    quality: .init(
                        score: 0.9,
                        isUsableForSpeakerProfile: true,
                        issues: []
                    )
                )
                let acoustic = AcousticAnalysis(
                    sampleRate: 16_000,
                    noiseFloorRMS: 0.001,
                    observations: [
                        acousticObservation,
                    ]
                )
                let coordinate = SpeakerFeatureCoordinate(
                    view: .raw,
                    family: .mfcc,
                    weight: 1
                )
                let speakerObservation = SpeakerObservation(
                    id: .init(
                        rawValue: 0
                    ),
                    range: .init(
                        start: 1,
                        duration: 0.4
                    ),
                    acousticObservationIDs: [
                        acousticID,
                    ],
                    features: .init(
                        [
                            0.3,
                        ],
                        weights: [
                            1,
                        ],
                        coordinates: [
                            coordinate,
                        ]
                    ),
                    qualityScore: 0.9
                )
                let reliability = SpeakerEvidenceReliabilityEvaluation(
                    noiseLikelihood: 0.2,
                    sourceObservationCount: 1,
                    taper: 0,
                    reliability: 1
                )
                let assignment = SpeakerObservationAssignment(
                    observationID: speakerObservation.id,
                    acousticSpeaker: speaker,
                    acousticConfidence: 0.8,
                    reliability: 1,
                    reliabilityEvaluation: reliability,
                    candidates: [
                        .init(
                            speaker: speaker,
                            acousticCost: 0,
                            squaredDistance: 0.1,
                            featureContributions: [
                                .init(
                                    view: .raw,
                                    family: .mfcc,
                                    weight: 1,
                                    squaredDistance: 0.1,
                                    fractionOfSquaredDistance: 1
                                ),
                            ]
                        ),
                    ]
                )
                let profile = SpeakerProfile(
                    speaker: speaker,
                    observationCount: 1,
                    observedDurationSeconds: 0.4,
                    acousticCentroid: .init(
                        [
                            0.3,
                        ],
                        weights: [
                            1,
                        ],
                        coordinates: [
                            coordinate,
                        ]
                    )
                )
                let diarizationConfiguration = DiarizationConfiguration(
                    expectedSpeakerCount: 1
                )
                let diarization = DiarizationResult(
                    segments: [
                        .init(
                            range: speakerObservation.range,
                            speaker: speaker,
                            confidence: 0.8,
                            observationIDs: [
                                speakerObservation.id,
                            ]
                        ),
                    ],
                    profiles: [
                        profile,
                    ],
                    observations: [
                        speakerObservation,
                    ],
                    assignments: [
                        assignment,
                    ],
                    method: .init(
                        configuration: diarizationConfiguration,
                        featureSpace: [
                            coordinate,
                        ],
                        standardization: .init(
                            means: [
                                0.3,
                            ],
                            deviations: [
                                1,
                            ],
                            totalReliabilityWeight: 1
                        ),
                        clustering: .init(
                            observationCount: 1,
                            selectedSpeakerCount: 1,
                            reliabilityWeightedSquaredError: 0.1
                        )
                    ),
                    acoustic: acoustic,
                    noiseProfile: .init(
                        analysis: acoustic
                    ),
                    noiseEvidence: [
                        .init(
                            observationID: acousticID,
                            likelihood: 0.2,
                            lowEnergy: 0.1,
                            flatness: 0.2,
                            stationarity: 0.3,
                            pitchUnreliability: 0.2,
                            transient: 0.1
                        ),
                    ]
                )
                let transcription = Transcription(
                    localeIdentifier: "en-US",
                    segments: [
                        .init(
                            text: "Hello.",
                            range: speakerObservation.range,
                            confidence: 0.95,
                            alternatives: [
                                "Hallo.",
                            ]
                        ),
                    ]
                )
                let alignmentConfiguration = SpeakerTranscriptAligner.Configuration()
                let result = SpeechAnalysisResult(
                    transcription: transcription,
                    diarization: diarization,
                    alignment: .init(
                        assignments: [
                            .init(
                                segmentIndex: 0,
                                speaker: speaker,
                                confidence: 0.8,
                                speakerSegmentIndices: [
                                    0,
                                ]
                            ),
                        ],
                        configuration: alignmentConfiguration
                    )
                )
                let projector = SpeechAnalysisContextProjector()
                let conversation = projector.project(
                    result,
                    detail: .conversation
                )
                let diagnostic = projector.project(
                    result,
                    detail: .diagnostic
                )
                let complete = projector.project(
                    result,
                    detail: .complete
                )

                try Expect.equal(
                    conversation.transcript?.segments[0].speaker,
                    speaker.rawValue,
                    "speech-context.conversation-speaker"
                )
                try Expect.equal(
                    conversation.inference == nil
                        && conversation.speakerDecisions.isEmpty
                        && conversation.acousticEvidence == nil,
                    true,
                    "speech-context.conversation-is-compact"
                )
                try Expect.equal(
                    diagnostic.inference != nil
                        && diagnostic.speakerObservations.count == 1
                        && diagnostic.speakerDecisions.count == 1
                        && diagnostic.acousticEvidence == nil,
                    true,
                    "speech-context.diagnostic-retains-decisions"
                )
                try Expect.equal(
                    complete.acousticEvidence?.raw?.observations.count,
                    1,
                    "speech-context.complete-retains-acoustics"
                )
                try Expect.equal(
                    complete.speakerDecisions[0].candidates[0]
                        .featureContributions[0]
                        .family,
                    SpeakerFeatureFamily.mfcc.rawValue,
                    "speech-context.feature-contribution-semantics"
                )
            }

            Step("context schema is derived from the typed projection") {
                let schemaData = try JSONEncoder().encode(
                    SpeechAnalysisContext.jsonschema.jsonvalue
                )
                let schemaText = String(
                    decoding: schemaData,
                    as: UTF8.self
                )

                try Expect.contains(
                    schemaText,
                    "speakerDecisions",
                    "speech-context.schema-decisions"
                )
                try Expect.contains(
                    schemaText,
                    "acousticEvidence",
                    "speech-context.schema-acoustics"
                )
                try Expect.contains(
                    schemaText,
                    "Controls projection breadth",
                    "speech-context.schema-source-documentation"
                )
            }
        }
    }
}
