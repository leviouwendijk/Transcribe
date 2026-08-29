import Diarization
import Foundation
import SpeechAnalysisContext
import Terminal

enum TranscribeTerminalRenderer {
    static func renderExports(
        trace: URL?,
        context: URL?,
        contextDetail: SpeechAnalysisContextDetail?
    ) {
        var items: [TerminalDetailItem] = []
        if let trace {
            items.append(.field(label: "trace", value: trace.path))
        }
        if let context {
            items.append(.field(label: "context", value: context.path))
        }
        if let contextDetail {
            items.append(.field(label: "detail", value: contextDetail.rawValue))
        }
        render(title: "Analysis exports", section: "written", items: items)
    }

    static func renderSpeakerAblation(
        _ reports: [SpeakerDiarizationAblationReport],
        detailed: Bool
    ) {
        guard detailed else {
            render(
                title: "Speaker feature ablation",
                section: "leave one family out",
                items: reports.map { report in
                    .field(
                        label: report.ablation.rawValue,
                        value: description(report.summary)
                    )
                }
            )
            return
        }

        render(
            title: "Speaker feature ablation",
            sections: reports.map { report in
                var items: [TerminalDetailItem] = [
                    .field(
                        label: "summary",
                        value: description(report.summary)
                    ),
                ]

                if !report.comparison.acousticChanges.isEmpty {
                    items.append(
                        .list(
                            label: "acoustic changes",
                            values: report.comparison.acousticChanges.map(
                                acousticDescription
                            )
                        )
                    )
                }

                if !report.comparison.resolvedChanges.isEmpty {
                    items.append(
                        .list(
                            label: "resolved changes",
                            values: report.comparison.resolvedChanges.map(
                                resolvedDescription
                            )
                        )
                    )
                }

                return .init(
                    title: report.ablation.rawValue,
                    items: items
                )
            }
        )
    }
}

private extension TranscribeTerminalRenderer {
    static func description(
        _ summary: SpeakerDiarizationReplaySummary
    ) -> String {
        let error = summary.reliabilityWeightedSquaredError.map {
            String(format: "%.4f", $0)
        } ?? "n/a"

        return "acoustic changes \(summary.changedAcousticAssignmentCount), resolved changes \(summary.changedResolvedAssignmentCount), segments \(summary.segmentCount), speakers \(summary.speakerCount), weighted SSE \(error)"
    }

    static func acousticDescription(
        _ change: SpeakerDiarizationAssignmentChange
    ) -> String {
        String(
            format: "%.2f...%.2f %@ -> %@, confidence %.3f -> %.3f",
            change.range.start,
            change.range.end,
            change.baseline.acousticSpeaker.rawValue,
            change.replay.acousticSpeaker.rawValue,
            change.baseline.acousticConfidence,
            change.replay.acousticConfidence
        )
    }

    static func resolvedDescription(
        _ change: SpeakerDiarizationAssignmentChange
    ) -> String {
        let baselineConfidence = optionalDescription(
            change.baseline.resolvedConfidence
        )
        let replayConfidence = optionalDescription(
            change.replay.resolvedConfidence
        )

        return String(
            format: "%.2f...%.2f %@ -> %@, confidence %@ -> %@",
            change.range.start,
            change.range.end,
            change.baseline.resolvedSpeaker.rawValue,
            change.replay.resolvedSpeaker.rawValue,
            baselineConfidence,
            replayConfidence
        )
    }

    static func optionalDescription(
        _ value: Double?
    ) -> String {
        value.map {
            String(
                format: "%.3f",
                $0
            )
        } ?? "n/a"
    }

    static func render(
        title: String,
        section: String,
        items: [TerminalDetailItem]
    ) {
        render(
            title: title,
            sections: [
                .init(
                    title: section,
                    items: items
                ),
            ]
        )
    }

    static func render(
        title: String,
        sections: [TerminalDetailSection]
    ) {
        guard !sections.isEmpty else { return }

        let document = TerminalDetailDocument(
            title: title,
            sections: sections,
            layout: .agentic
        )
        Terminal.write(
            document.render(stream: .standardOutput),
            to: .standardOutput
        )
    }
}
