import TestFlows

enum TranscribeFlowSuite: TestFlowRegistry {
    static let title = "Transcribe"

    static let flows: [TestFlow] = [
        transcriptionFlow,
        acousticObservationFlow,
        acousticActivityFlow,
        speakerObservationFlow,
        sessionClusteringFlow,
        diarizationFlow,
        alignmentFlow,
        appleContractFlow,
    ]
}
