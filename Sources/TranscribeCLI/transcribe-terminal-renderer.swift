import Diarization
import Foundation
import SpeechAnalysisContext
import Terminal

enum TranscribeTerminalRenderer {
    static func renderSpeakerEmbeddings(
        _ diarization: DiarizationResult?,
        requestedProvider: String
    ) {
        let observations = diarization?.observations ?? []
        let embeddings = observations.compactMap(\.embedding)
        let first = embeddings.first
        let profileCount = diarization?.profiles.filter {
            $0.embeddingProfile != nil
        }.count ?? 0
        var items: [TerminalDetailItem] = [
            .field(
                label: "requested provider",
                value: requestedProvider
            ),
            .field(
                label: "requested observations",
                value: String(observations.count)
            ),
            .field(
                label: "embedded observations",
                value: String(embeddings.count)
            ),
            .field(
                label: "missing observations",
                value: String(
                    max(
                        0,
                        observations.count - embeddings.count
                    )
                )
            ),
            .field(
                label: "profiles with embeddings",
                value: String(profileCount)
            ),
        ]

        if let first {
            items.append(
                .field(
                    label: "provider",
                    value: first.provenance?.providerIdentifier
                        ?? requestedProvider
                )
            )
            items.append(
                .field(
                    label: "model",
                    value: first.provenance?.modelIdentifier
                        ?? "unknown"
                )
            )
            items.append(
                .field(
                    label: "dimension",
                    value: String(first.dimension)
                )
            )
            items.append(
                .field(
                    label: "normalization",
                    value: first.provenance?.normalization.rawValue
                        ?? "unknown"
                )
            )
        }

        render(
            title: "Speaker embeddings",
            section: "acquisition",
            items: items
        )
    }

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

    static func renderSpeakerCalibration(
        _ experiment: SpeakerDiarizationReplayExperiment
    ) {
        var sections: [TerminalDetailSection] = []

        if let baseline = experiment.baselineClustering {
            sections.append(
                .init(
                    title: "baseline",
                    items: [
                        .field(
                            label: "weighting",
                            value: experiment.baselineFeatureWeighting?
                                .rawValue
                                ?? "unknown"
                        ),
                        .field(
                            label: "clustering",
                            value: clusteringDescription(
                                baseline
                            )
                        ),
                    ]
                )
            )
        }

        sections.append(
            contentsOf: experiment.results.map { result in
                var items: [TerminalDetailItem] = [
                    .field(
                        label: "weighting",
                        value: result.candidate.featureWeighting.rawValue
                    ),
                    .field(
                        label: "weights",
                        value: weightsDescription(
                            result.candidate.featureWeights
                        )
                    ),
                    .field(
                        label: "comparison",
                        value: comparisonDescription(
                            result.comparison,
                            clustering: result.clustering
                        )
                    ),
                ]

                if !result.comparison.acousticChanges.isEmpty {
                    items.append(
                        .list(
                            label: "acoustic changes",
                            values: result.comparison.acousticChanges.map(
                                acousticDescription
                            )
                        )
                    )
                }

                if !result.comparison.resolvedChanges.isEmpty {
                    items.append(
                        .list(
                            label: "resolved changes",
                            values: result.comparison.resolvedChanges.map(
                                resolvedDescription
                            )
                        )
                    )
                }

                return .init(
                    title: result.candidate.name,
                    items: items
                )
            }
        )

        render(
            title: "Speaker weight calibration",
            sections: sections
        )
    }
}

private extension TranscribeTerminalRenderer {
    static func description(
        _ summary: SpeakerDiarizationReplaySummary
    ) -> String {
        let error = optionalDescription(
            summary.reliabilityWeightedSquaredError
        )
        let normalized = optionalDescription(
            summary.normalizedReliabilityWeightedSquaredError
        )

        return "acoustic changes \(summary.changedAcousticAssignmentCount), resolved changes \(summary.changedResolvedAssignmentCount), segments \(summary.segmentCount), speakers \(summary.speakerCount), weighted SSE \(error), normalized SSE \(normalized)"
    }

    static func clusteringDescription(
        _ evaluation: SpeakerClusteringNormalizedEvaluation
    ) -> String {
        String(
            format: "weighted SSE %.4f, normalized SSE %.4f, effective feature weight %.4f, reliability weight %.4f",
            evaluation.clustering.reliabilityWeightedSquaredError,
            evaluation.normalizedReliabilityWeightedSquaredError,
            evaluation.effectiveFeatureWeight,
            evaluation.totalReliabilityWeight
        )
    }

    static func comparisonDescription(
        _ comparison: SpeakerDiarizationReplayComparison,
        clustering: SpeakerClusteringNormalizedEvaluation?
    ) -> String {
        let error = optionalDescription(
            comparison.reliabilityWeightedSquaredError
        )
        let normalized = optionalDescription(
            clustering?.normalizedReliabilityWeightedSquaredError
        )

        return "acoustic changes \(comparison.acousticChanges.count), resolved changes \(comparison.resolvedChanges.count), segments \(comparison.segmentCount), speakers \(comparison.speakerCount), weighted SSE \(error), normalized SSE \(normalized)"
    }

    static func weightsDescription(
        _ weights: SpeakerFeatureWeights
    ) -> String {
        String(
            format: "mfcc %.3f, logMel %.3f, pitch %.3f, spectral %.3f, dynamics %.3f, consistency %.3f, quality %.3f, enhancedView %.3f",
            weights.mfcc,
            weights.logMel,
            weights.pitch,
            weights.spectral,
            weights.dynamics,
            weights.consistency,
            weights.quality,
            weights.enhancedView
        )
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
