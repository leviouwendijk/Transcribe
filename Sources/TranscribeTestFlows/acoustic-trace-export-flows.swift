import Diarization
import TestFlows

extension TranscribeFlowSuite {
    static var acousticTraceExportFlow: TestFlow {
        TestFlow(
            "acoustic-trace-export",
            tags: [
                "diarization",
                "trace",
                "export",
            ]
        ) {
            Step("trace export joins raw enhanced speaker and gain evidence") {
                let sampleRate = 48_000
                let samples = AudioTestFixture.sine(
                    frequency: 181,
                    duration: 0.9,
                    amplitude: 0.04,
                    sampleRate: sampleRate
                )

                let accumulator = ParallelAcousticAnalysisAccumulator(
                    batchDurationSeconds: 1
                )

                try accumulator.consume(
                    .init(
                        trackID: 1,
                        buffer: AudioTestFixture.buffer(
                            samples: samples,
                            sampleRate: sampleRate
                        ),
                        presentationTimeSeconds: 4,
                        durationSeconds: 0.9
                    )
                )

                let evidence = try accumulator.finish()
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

                let rows = result.acousticTraceRows()

                try Expect.equal(
                    rows.count,
                    evidence.raw.observations.count,
                    "trace-export.row-count"
                )

                try Expect.equal(
                    rows.isEmpty,
                    false,
                    "trace-export.non-empty"
                )

                try Expect.equal(
                    rows.allSatisfy {
                        $0.startSeconds >= 4
                            && $0.endSeconds <= 4.91
                    },
                    true,
                    "trace-export.timeline"
                )

                try Expect.equal(
                    rows.contains {
                        $0.enhancedRMS != nil
                    },
                    true,
                    "trace-export.enhanced"
                )

                try Expect.equal(
                    rows.contains {
                        $0.enhancementGainDB != nil
                    },
                    true,
                    "trace-export.gain"
                )

                try Expect.equal(
                    rows.contains {
                        $0.speaker != nil
                    },
                    true,
                    "trace-export.speaker"
                )

                let speakerRows = rows.filter {
                    $0.speaker != nil
                }

                try Expect.equal(
                    speakerRows.allSatisfy {
                        $0.speakerAcousticConfidence != nil
                            && $0.speakerReliability != nil
                            && $0.speakerEvidenceStrength != nil
                            && $0.speakerResolvedConfidence != nil
                    },
                    true,
                    "trace-export.speaker-assignment-diagnostics"
                )

                let csv = result.acousticTraceCSV()

                try Expect.equal(
                    csv.hasPrefix(
                        "start_seconds,end_seconds,speaker,"
                    ),
                    true,
                    "trace-export.header"
                )

                try Expect.equal(
                    csv.contains(
                        "speaker_acoustic_confidence,speaker_reliability,speaker_evidence_strength,speaker_resolved_confidence"
                    ),
                    true,
                    "trace-export.speaker-diagnostic-header"
                )

                try Expect.equal(
                    csv.split(
                        separator: "\n"
                    ).count,
                    rows.count + 1,
                    "trace-export.csv-row-count"
                )
            }
        }
    }
}
