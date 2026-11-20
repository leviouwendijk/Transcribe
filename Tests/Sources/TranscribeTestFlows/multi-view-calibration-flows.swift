import Diarization
import TestFlows

extension TranscribeFlowSuite {
    static var multiViewCalibrationFlow: TestFlow {
        TestFlow(
            "multi-view-calibration",
            tags: [
                "diarization",
                "speaker",
                "multi-view",
                "calibration",
            ]
        ) {
            Step("gain changes preserve spectral-shape agreement") {
                let source = AudioTestFixture.sine(
                    frequency: 181,
                    duration: 0.9,
                    amplitude: 0.18
                )

                let raw = try AcousticAnalyzer().analyze(
                    AudioTestFixture.buffer(
                        samples: source
                    )
                )

                let enhanced = try AcousticAnalyzer().analyze(
                    AudioTestFixture.buffer(
                        samples: source.map {
                            $0 * 0.35
                        }
                    )
                )

                let result = Diarizer().diarize(
                    raw,
                    enhanced: enhanced,
                    configuration: .init(
                        expectedSpeakerCount: 1,
                        speakerObservation: .init(
                            minimumDurationSeconds: 0.25,
                            maximumDurationSeconds: 1,
                            maximumGapSeconds: 0.08
                        )
                    )
                )

                let profile = try Expect.notNil(
                    result.profiles.first?.acousticProfile,
                    "multi-view-calibration.profile"
                )

                try Expect.equal(
                    profile.mfccShapeAgreement.median > 0.85,
                    true,
                    "multi-view-calibration.mfcc-shape"
                )

                try Expect.equal(
                    profile.logMelShapeAgreement.median > 0.85,
                    true,
                    "multi-view-calibration.log-mel-shape"
                )
            }

            Step("raw and enhanced quality remain independently visible") {
                let samples = AudioTestFixture.sine(
                    frequency: 180,
                    duration: 0.9,
                    amplitude: 0.0035
                )

                let accumulator = ParallelAcousticAnalysisAccumulator(
                    batchDurationSeconds: 1
                )

                for index in 0..<4 {
                    try accumulator.consume(
                        .init(
                            trackID: 1,
                            buffer: AudioTestFixture.buffer(
                                samples: samples
                            ),
                            presentationTimeSeconds: Double(index) * 0.9,
                            durationSeconds: 0.9
                        )
                    )
                }

                let evidence = try accumulator.finish()

                try Expect.equal(
                    evidence.raw.usableObservations.count
                        < evidence.enhanced.usableObservations.count,
                    true,
                    "multi-view-calibration.enhanced-recovers-evidence"
                )

                let result = Diarizer().diarize(
                    evidence,
                    configuration: .init(
                        expectedSpeakerCount: 1,
                        speakerObservation: .init(
                            minimumDurationSeconds: 0.25,
                            maximumDurationSeconds: 1,
                            maximumGapSeconds: 0.08
                        )
                    )
                )

                let profile = try Expect.notNil(
                    result.profiles.first?.acousticProfile,
                    "multi-view-calibration.recovered-profile"
                )

                try Expect.equal(
                    profile.rawQuality.count > 0,
                    true,
                    "multi-view-calibration.raw-quality"
                )

                try Expect.equal(
                    profile.enhancedQuality.count > 0,
                    true,
                    "multi-view-calibration.enhanced-quality"
                )

                try Expect.equal(
                    profile.recoveredObservationFraction > 0,
                    true,
                    "multi-view-calibration.recovered-fraction"
                )
            }
        }
    }
}
