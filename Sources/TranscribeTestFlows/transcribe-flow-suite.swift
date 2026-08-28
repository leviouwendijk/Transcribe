import TestFlows

enum TranscribeFlowSuite: TestFlowRegistry {
    static let title = "Transcribe"

    static let flows: [TestFlow] = [
        transcriptionFlow,
        diarizationFlow,
        alignmentFlow,
        appleContractFlow,
    ]
}
