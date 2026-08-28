import Diarization
import TestFlows

extension TranscribeFlowSuite {
    static var acousticObservationFlow: TestFlow {
        TestFlow(
            "acoustic-observations",
            tags: [
                "diarization",
                "acoustic",
                "dsp",
            ]
        ) {
            Step("voiced tone produces retained spectral observations") {
                let buffer = AudioTestFixture.buffer(
                    samples: AudioTestFixture.sine(
                        frequency: 180,
                        duration: 0.5
                    )
                )

                let analysis = try AcousticAnalyzer().analyze(
                    buffer
                )

                try Expect.equal(
                    analysis.observations.isEmpty,
                    false,
                    "acoustic.observations.non-empty"
                )

                let voiced = analysis.observations.filter {
                    $0.activity == .voicedSpeech
                }

                try Expect.equal(
                    voiced.isEmpty,
                    false,
                    "acoustic.observations.voiced"
                )

                try Expect.equal(
                    voiced.allSatisfy {
                        $0.spectral.pitchHz != nil
                            && $0.spectral.mfcc.count == 13
                    },
                    true,
                    "acoustic.observations.features"
                )

                try Expect.equal(
                    voiced.allSatisfy {
                        $0.range.duration > 0
                    },
                    true,
                    "acoustic.observations.ranges"
                )
            }
        }
    }

    static var acousticActivityFlow: TestFlow {
        TestFlow(
            "acoustic-activity",
            tags: [
                "diarization",
                "activity",
                "quality",
            ]
        ) {
            Step("silence remains retained and classified as silence") {
                let analysis = try AcousticAnalyzer().analyze(
                    AudioTestFixture.buffer(
                        samples: AudioTestFixture.silence(
                            duration: 0.25
                        )
                    )
                )

                try Expect.equal(
                    analysis.observations.isEmpty,
                    false,
                    "acoustic.activity.silence-retained"
                )

                try Expect.equal(
                    analysis.observations.allSatisfy {
                        $0.activity == .silence
                    },
                    true,
                    "acoustic.activity.silence"
                )

                try Expect.equal(
                    analysis.usableObservations.isEmpty,
                    true,
                    "acoustic.activity.silence-not-profiled"
                )
            }

            Step("high-frequency alternating signal is not admitted as voiced speech") {
                let analysis = try AcousticAnalyzer().analyze(
                    AudioTestFixture.buffer(
                        samples: AudioTestFixture.alternating(
                            duration: 0.25
                        )
                    )
                )

                try Expect.equal(
                    analysis.observations.contains {
                        $0.activity == .noise
                    },
                    true,
                    "acoustic.activity.noise"
                )

                try Expect.equal(
                    analysis.usableObservations.isEmpty,
                    true,
                    "acoustic.activity.noise-not-profiled"
                )
            }

            Step("voiced evidence is admitted without discarding observations") {
                let samples = AudioTestFixture.silence(
                    duration: 0.15
                ) + AudioTestFixture.sine(
                    frequency: 190,
                    duration: 0.4
                )

                let analysis = try AcousticAnalyzer().analyze(
                    AudioTestFixture.buffer(
                        samples: samples
                    )
                )

                try Expect.equal(
                    analysis.observations.contains {
                        $0.activity == .silence
                    },
                    true,
                    "acoustic.activity.retains-silence"
                )

                try Expect.equal(
                    analysis.usableObservations.isEmpty,
                    false,
                    "acoustic.activity.retains-usable-speech"
                )
            }
        }
    }
}
