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
        _ summaries: [SpeakerDiarizationReplaySummary]
    ) {
        render(
            title: "Speaker feature ablation",
            section: "leave one family out",
            items: summaries.map { summary in
                .field(
                    label: summary.ablation.rawValue,
                    value: description(summary)
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

    static func render(
        title: String,
        section: String,
        items: [TerminalDetailItem]
    ) {
        guard !items.isEmpty else { return }

        let document = TerminalDetailDocument(
            title: title,
            sections: [.init(title: section, items: items)],
            layout: .agentic
        )
        Terminal.write(
            document.render(stream: .standardOutput),
            to: .standardOutput
        )
    }
}
