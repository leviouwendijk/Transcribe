import Diarization
import TestFlows

extension TranscribeFlowSuite {
    static var parallelAcousticFlow: TestFlow {
        TestFlow(
            "parallel-acoustic-evidence",
            tags: [
                "diarization",
                "acoustic",
                "enhancement",
                "noise",
            ]
        ) {
            Step("parallel analysis retains raw and enhanced views on one timeline") {
                let samples = AudioTestFixture.sine(
                    frequency: 180,
                    duration: 0.8,
                    amplitude: 0.02
                )
                let accumulator = ParallelAcousticAnalysisAccumulator(
                    batchDurationSeconds: 1
                )

                try accumulator.consume(
                    .init(
                        trackID: 1,
                        buffer: AudioTestFixture.buffer(
                            samples: samples
                        ),
                        presentationTimeSeconds: 0,
                        durationSeconds: 0.8
                    )
                )

                let evidence = try accumulator.finish()

                try Expect.equal(
                    evidence.raw.observations.count,
                    evidence.enhanced.observations.count,
                    "parallel-acoustic.aligned-count"
                )
                try Expect.equal(
                    evidence.raw.sampleRate,
                    evidence.enhanced.sampleRate,
                    "parallel-acoustic.aligned-rate"
                )
                try Expect.equal(
                    evidence.enhancement.blockCount,
                    1,
                    "parallel-acoustic.telemetry"
                )
            }

            Step("enhanced branch can recover low-level voiced evidence without replacing raw evidence") {
                let samples = AudioTestFixture.sine(
                    frequency: 180,
                    duration: 0.8,
                    amplitude: 0.003
                )
                let accumulator = ParallelAcousticAnalysisAccumulator(
                    batchDurationSeconds: 1
                )

                try accumulator.consume(
                    .init(
                        trackID: 1,
                        buffer: AudioTestFixture.buffer(
                            samples: samples
                        ),
                        presentationTimeSeconds: 0,
                        durationSeconds: 0.8
                    )
                )

                let evidence = try accumulator.finish()

                try Expect.equal(
                    evidence.enhancement.appliedGainDB.mean > 0,
                    true,
                    "parallel-acoustic.gain-applied"
                )
                try Expect.equal(
                    evidence.enhancement.recoveredUsableObservationCount >= 0,
                    true,
                    "parallel-acoustic.recovery-measured"
                )
                try Expect.equal(
                    evidence.raw.observations.isEmpty,
                    false,
                    "parallel-acoustic.raw-retained"
                )
            }

            Step("noise profile is derived from retained non-speech evidence") {
                let samples = AudioTestFixture.silence(
                    duration: 0.4
                ) + AudioTestFixture.alternating(
                    duration: 0.4,
                    amplitude: 0.04
                )
                let analysis = try AcousticAnalyzer().analyze(
                    AudioTestFixture.buffer(
                        samples: samples
                    )
                )
                let profile = AcousticNoiseProfile(
                    analysis: analysis
                )

                try Expect.equal(
                    profile.observationCount > 0,
                    true,
                    "parallel-acoustic.noise-observations"
                )
                try Expect.equal(
                    profile.logMelMean.count,
                    24,
                    "parallel-acoustic.noise-log-mel"
                )
            }
        }
    }
}
