import Foundation
import Diarization
import TestFlows
import TranscribeApple

extension TranscribeFlowSuite {
    static var speakerEvidenceModeFlow: TestFlow {
        TestFlow("speaker-evidence-mode", tags: ["speech", "diarization", "model", "acoustic"]) {
            Step("unknown speaker count is the default; mode is explicit") {
                let configuration = DiarizationConfiguration()
                try Expect.equal(configuration.expectedSpeakerCount, Optional<Int>.none, "evidence.unknown-speaker-count")
                try Expect.equal(configuration.maximumSpeakerCount, 4, "evidence.bounded-search")
                try Expect.equal(AppleSpeakerEvidenceMode.acoustic, .acoustic, "evidence.acoustic-default")
                let hybrid = AppleSpeakerEvidenceMode.hybrid(.init(acoustic: 0.4, embedding: 0.6))
                if case .hybrid(let weights) = hybrid {
                    try Expect.true(abs(weights.acoustic - 0.4) < 0.00001, "evidence.hybrid-acoustic")
                    try Expect.true(abs(weights.embedding - 0.6) < 0.00001, "evidence.hybrid-model")
                } else {
                    try Expect.true(false, "evidence.hybrid-mode")
                }
            }
            Step("model-based modes require explicit embedding provider") {
                let missing_file = URL(fileURLWithPath: "/nonexistent-speaker-evidence.wav")
                for mode in [
                    AppleSpeakerEvidenceMode.embedding,
                    .hybrid(.init(acoustic: 0.5, embedding: 0.5)),
                ] {
                    do {
                        _ = try await AppleSpeechAnalysisRunner().analyze(
                            file: missing_file,
                            localeIdentifier: "nl-NL",
                            speakerEvidenceMode: mode
                        )
                        try Expect.true(false, "evidence.reject-missing-provider")
                    } catch AppleSpeakerEvidenceModeError.embeddingProviderRequired {
                        try Expect.true(true, "evidence.reject-missing-provider")
                    }
                }
            }
        }
    }
}
