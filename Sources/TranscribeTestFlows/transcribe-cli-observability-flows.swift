import Diarization
import Foundation
import MediaCore
import TestFlows

extension TranscribeFlowSuite {
    static var transcribeCLIObservabilityFlow: TestFlow {
        TestFlow(
            "transcribe-cli-observability",
            tags: [
                "ablation",
                "cli",
                "observability",
                "replay",
            ]
        ) {
            Step("localized ablation reports retain the assignments and ranges from which summaries derive") {
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
                let reports = diarizer.leaveOneOutReports(
                    source
                )
                let summaries = diarizer.leaveOneOutSummaries(
                    source
                )
                let sourceRanges = Dictionary(
                    uniqueKeysWithValues: source.observations.map {
                        (
                            $0.id,
                            $0.range
                        )
                    }
                )

                try Expect.equal(
                    reports.count,
                    SpeakerFeatureAblationTarget.allCases.count,
                    "cli-observability.report-count"
                )
                try Expect.equal(
                    reports.map(\.summary),
                    summaries,
                    "cli-observability.summary-derived-from-report"
                )
                try Expect.equal(
                    reports.allSatisfy { report in
                        report.summary.changedAcousticAssignmentCount
                            == report.comparison.acousticChanges.count
                            && report.summary.changedResolvedAssignmentCount
                                == report.comparison.resolvedChanges.count
                    },
                    true,
                    "cli-observability.summary-counts-derived"
                )
                try Expect.equal(
                    reports.allSatisfy { report in
                        (
                            report.comparison.acousticChanges
                                + report.comparison.resolvedChanges
                        ).allSatisfy { change in
                            change.baseline.observationID
                                == change.observationID
                                && change.replay.observationID
                                    == change.observationID
                                && sourceRanges[change.observationID]
                                    == change.range
                        }
                    },
                    true,
                    "cli-observability.localized-change-provenance"
                )
                try Expect.equal(
                    reports.allSatisfy { report in
                        report.comparison.acousticChanges.allSatisfy {
                            $0.baseline.acousticSpeaker
                                != $0.replay.acousticSpeaker
                        }
                            && report.comparison.resolvedChanges.allSatisfy {
                                $0.baseline.resolvedSpeaker
                                    != $0.replay.resolvedSpeaker
                            }
                    },
                    true,
                    "cli-observability.localized-change-semantics"
                )
            }

            Step("direct root parses observability flags before semantic validation without running analysis") {
                guard let executableDirectory = Bundle.main
                    .executableURL?
                    .deletingLastPathComponent()
                else {
                    throw TranscribeCLIObservabilityError.missingExecutableDirectory
                }

                let executable = executableDirectory
                    .appendingPathComponent(
                        "transcribe"
                    )

                guard FileManager.default.isExecutableFile(
                    atPath: executable.path
                ) else {
                    throw TranscribeCLIObservabilityError.missingTranscribeExecutable(
                        executable.path
                    )
                }

                let process = Process()
                let stdout = Pipe()
                let stderr = Pipe()

                process.executableURL = executable
                process.arguments = [
                    "audio.mp3",
                    "--speaker-count",
                    "0",
                    "--context",
                    "/tmp/transcribe-cli-observability.json",
                    "--context-detail",
                    "diagnostic",
                    "--speaker-ablation",
                    "--speaker-ablation-detail",
                    "--speaker-calibration",
                ]
                process.standardOutput = stdout
                process.standardError = stderr

                try process.run()
                process.waitUntilExit()

                let output = String(
                    decoding: stdout.fileHandleForReading.readDataToEndOfFile(),
                    as: UTF8.self
                ) + String(
                    decoding: stderr.fileHandleForReading.readDataToEndOfFile(),
                    as: UTF8.self
                )

                try Expect.equal(
                    process.terminationStatus == 0,
                    false,
                    "cli-observability.semantic-validation-exit"
                )
                try Expect.equal(
                    output.contains(
                        "speaker-count must be a positive integer"
                    ),
                    true,
                    "cli-observability.direct-root-options-parsed"
                )
                try Expect.equal(
                    output.contains(
                        "=== diagnostics ==="
                    ),
                    false,
                    "cli-observability.analysis-not-invoked"
                )
            }
        }
    }
}

enum TranscribeCLIObservabilityError:
    Error,
    Sendable
{
    case missingExecutableDirectory
    case missingTranscribeExecutable(String)
}
