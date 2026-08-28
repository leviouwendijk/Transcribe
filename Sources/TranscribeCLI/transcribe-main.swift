import Diarization
import Foundation
import SpeechAnalysis
import TranscribeApple

@main
enum TranscribeCLI {
    static func main() async throws {
        let arguments = CommandLine.arguments

        guard arguments.count >= 2 else {
            print(
                "usage: transcribe <audio-file> [locale] [speech|dictation] [speaker-count]"
            )
            return
        }

        let path = NSString(
            string: arguments[1]
        ).expandingTildeInPath

        let localeIdentifier = arguments.count >= 3
            ? arguments[2]
            : "nl-NL"

        let model: AppleTranscriptionModel

        if arguments.count >= 4 {
            guard let requested = AppleTranscriptionModel(
                rawValue: arguments[3]
            ) else {
                print(
                    "model must be speech or dictation"
                )
                return
            }

            model = requested
        } else {
            model = .speech
        }

        let expectedSpeakerCount: Int?

        if arguments.count >= 5 {
            guard let requested = Int(
                arguments[4]
            ),
                  requested > 0
            else {
                print(
                    "speaker-count must be a positive integer"
                )
                return
            }

            expectedSpeakerCount = requested
        } else {
            expectedSpeakerCount = nil
        }

        let result = try await AppleSpeechAnalysisRunner().analyze(
            file: URL(
                fileURLWithPath: path
            ),
            localeIdentifier: localeIdentifier,
            model: model,
            diarizationConfiguration: .init(
                expectedSpeakerCount: expectedSpeakerCount
            )
        )

        renderDiagnostics(
            result.analysis
        )

        renderTiming(
            result.timing
        )

        print("")
        print("=== attributed transcript ===")

        for attributed in result.analysis.attributedSegments {
            render(
                attributed
            )
        }

        print("")
        print("=== raw transcript ===")
        print(
            result.appleTranscription.transcription.text
        )
    }
}

private extension TranscribeCLI {
    static func renderTiming(
        _ timing: AppleSpeechAnalysisTiming
    ) {
        print("")
        print("=== timing ===")

        print(
            String(
                format: "apple transcription: %.3fs",
                timing.transcriptionSeconds
            )
        )

        print(
            String(
                format: "media input + accumulation: %.3fs",
                timing.mediaInputAndAccumulationSeconds
            )
        )

        print(
            String(
                format: "acoustic DSP: %.3fs",
                timing.acousticDSPSeconds
            )
        )

        print(
            String(
                format: "speaker diarization: %.3fs",
                timing.speakerDiarizationSeconds
            )
        )

        print(
            String(
                format: "alignment: %.3fs",
                timing.alignmentSeconds
            )
        )

        print(
            String(
                format: "total wall time: %.3fs",
                timing.totalSeconds
            )
        )
    }

    static func renderDiagnostics(
        _ analysis: SpeechAnalysisResult
    ) {
        print("=== diagnostics ===")

        guard let diarization = analysis.diarization else {
            print("diarization: unavailable")
            return
        }

        let acoustic = diarization.acoustic

        print(
            "acoustic observations: \(acoustic?.observations.count ?? 0)"
        )

        print(
            "usable acoustic observations: \(acoustic?.usableObservations.count ?? 0)"
        )

        print(
            "enhanced usable observations: \(diarization.enhancedAcoustic?.usableObservations.count ?? 0)"
        )

        print(
            "recovered enhanced observations: \(diarization.enhancement?.recoveredUsableObservationCount ?? 0)"
        )

        print(
            "noise profile observations: \(diarization.noiseProfile?.observationCount ?? 0)"
        )

        if let enhancement = diarization.enhancement {
            print(
                String(
                    format: "enhancement gain median=%.2fdB q10=%.2fdB q90=%.2fdB",
                    enhancement.appliedGainDB.median,
                    enhancement.appliedGainDB.q10,
                    enhancement.appliedGainDB.q90
                )
            )
        }

        print(
            "speaker observations: \(diarization.observations.count)"
        )

        print(
            "detected speakers: \(diarization.speakers.count)"
        )

        print(
            "speaker segments: \(diarization.segments.count)"
        )

        if let transcription = analysis.transcription,
           let alignment = analysis.alignment {
            let assigned = alignment.assignments.count
            let total = transcription.segments.count

            print(
                "transcript assignments: \(assigned)/\(total) assigned, \(max(0, total - assigned)) unassigned"
            )

            print(
                "direct assignments: \(alignment.assignments(using: .temporalOverlap).count)"
            )

            print(
                "bridged assignments: \(alignment.assignments(using: .bridgedGap).count)"
            )

            print(
                "nearest assignments: \(alignment.assignments(using: .nearestEvidence).count)"
            )
        }

        for profile in diarization.profiles.sorted(by: {
            $0.speaker.rawValue < $1.speaker.rawValue
        }) {
            let dispersion = dispersionMagnitude(
                profile.acousticDispersion
            )

            print(
                String(
                    format: "%@: observations=%d duration=%.2fs dispersion=%.4f",
                    profile.speaker.rawValue,
                    profile.observationCount,
                    profile.observedDurationSeconds,
                    dispersion
                )
            )

            if let acoustic = profile.acousticProfile {
                print(
                    String(
                        format: "  pitch median=%.1fHz q10=%.1f q90=%.1f confidence=%.3f consistency=%.3f raw-quality=%.3f enhanced-quality=%.3f recovered=%.1f%% mfcc-shape=%.3f mel-shape=%.3f view=%.3f",
                        acoustic.pitchHz.median,
                        acoustic.pitchHz.q10,
                        acoustic.pitchHz.q90,
                        acoustic.pitchConfidence.median,
                        acoustic.consistency.median,
                        acoustic.rawQuality.median,
                        acoustic.enhancedQuality.median,
                        acoustic.recoveredObservationFraction * 100,
                        acoustic.mfccShapeAgreement.median,
                        acoustic.logMelShapeAgreement.median,
                        acoustic.viewAgreement.median
                    )
                )
            }
        }
    }

    static func render(
        _ attributed: AttributedTranscriptionSegment
    ) {
        let speaker = attributed.speaker?.rawValue
            ?? "unassigned"

        let confidence = attributed.speakerConfidence.map {
            String(
                format: " %.2f",
                $0
            )
        } ?? ""

        if let range = attributed.segment.range {
            print(
                String(
                    format: "[%.2f ... %.2f] %@%@  %@",
                    range.start,
                    range.end,
                    speaker,
                    confidence,
                    attributed.segment.text
                )
            )
        } else {
            print(
                "[no-time] \(speaker)\(confidence)  \(attributed.segment.text)"
            )
        }
    }

    static func dispersionMagnitude(
        _ vector: SpeakerFeatureVector?
    ) -> Double {
        guard let values = vector?.values,
              !values.isEmpty
        else {
            return 0
        }

        let squareMean = values.reduce(0) {
            $0 + $1 * $1
        } / Double(values.count)

        return sqrt(
            squareMean
        )
    }
}
