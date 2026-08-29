import Diarization
import TestFlows

extension TranscribeFlowSuite {
    static var noiseEvidenceFlow: TestFlow {
        TestFlow(
            "acoustic-noise-evidence",
            tags: [
                "acoustic",
                "diarization",
                "noise",
                "trace",
            ]
        ) {
            Step("session noise interpretation remains retained and observational") {
                let sampleRate = 16_000
                let speechDuration = 0.6
                let noiseDuration = 0.6

                let speech = AudioTestFixture.sine(
                    frequency: 181,
                    duration: speechDuration,
                    amplitude: 0.12,
                    sampleRate: sampleRate
                )

                let noiseCount = Int(
                    noiseDuration
                        * Double(sampleRate)
                )

                let noise = (0..<noiseCount).map { index in
                    let value = (
                        index * 37
                            + index * index * 13
                    ) % 101

                    return Float(value - 50)
                        / 50
                        * 0.01
                }

                let accumulator = ParallelAcousticAnalysisAccumulator(
                    batchDurationSeconds: 2
                )

                try accumulator.consume(
                    .init(
                        trackID: 1,
                        buffer: AudioTestFixture.buffer(
                            samples: speech + noise,
                            sampleRate: sampleRate
                        ),
                        presentationTimeSeconds: 0,
                        durationSeconds: speechDuration
                            + noiseDuration
                    )
                )

                let evidence = try accumulator.finish()

                try Expect.equal(
                    evidence.noiseEvidence.count,
                    evidence.raw.observations.count,
                    "noise-evidence.retained-per-observation"
                )

                let rawByID = Dictionary(
                    uniqueKeysWithValues: evidence.raw.observations.map {
                        (
                            $0.id,
                            $0
                        )
                    }
                )

                let voicedScores = evidence.noiseEvidence.compactMap {
                    evidence -> Double? in

                    guard rawByID[evidence.observationID]?.activity
                        == .voicedSpeech else {
                        return nil
                    }

                    return evidence.likelihood
                }

                let noiseScores = evidence.noiseEvidence.compactMap {
                    evidence -> Double? in

                    guard rawByID[evidence.observationID]?.activity
                        == .noise else {
                        return nil
                    }

                    return evidence.likelihood
                }

                try Expect.equal(
                    voicedScores.isEmpty,
                    false,
                    "noise-evidence.voiced-reference"
                )

                try Expect.equal(
                    noiseScores.isEmpty,
                    false,
                    "noise-evidence.noise-reference"
                )

                let voicedMean = voicedScores.reduce(
                    0,
                    +
                ) / Double(voicedScores.count)

                let noiseMean = noiseScores.reduce(
                    0,
                    +
                ) / Double(noiseScores.count)

                try Expect.equal(
                    noiseMean > voicedMean,
                    true,
                    "noise-evidence.noise-ranks-higher"
                )

                try Expect.equal(
                    evidence.noiseEvidence.allSatisfy {
                        $0.likelihood >= 0
                            && $0.likelihood <= 1
                            && $0.lowEnergy >= 0
                            && $0.lowEnergy <= 1
                            && $0.flatness >= 0
                            && $0.flatness <= 1
                            && $0.stationarity >= 0
                            && $0.stationarity <= 1
                            && $0.pitchUnreliability >= 0
                            && $0.pitchUnreliability <= 1
                            && $0.transient >= 0
                            && $0.transient <= 1
                    },
                    true,
                    "noise-evidence.bounded-components"
                )

                let diarization = Diarizer().diarize(
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

                try Expect.equal(
                    diarization.noiseEvidence,
                    evidence.noiseEvidence,
                    "noise-evidence.retained-through-diarization"
                )

                let rows = diarization.acousticTraceRows()

                try Expect.equal(
                    rows.count,
                    evidence.raw.observations.count,
                    "noise-evidence.trace-row-count"
                )

                try Expect.equal(
                    rows.allSatisfy {
                        $0.noiseLikelihood != nil
                            && $0.noiseFlatness != nil
                            && $0.noisePitchUnreliability != nil
                    },
                    true,
                    "noise-evidence.trace-components"
                )
            }
        }
    }
}
