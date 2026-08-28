import TestFlows

enum TranscribeFlowSuite: TestFlowRegistry {
    static let title = "Transcribe"

    static let flows: [TestFlow] = [
        transcriptionFlow,
        acousticObservationFlow,
        acousticActivityFlow,
        acousticPerformanceFlow,
        sessionAcousticFlow,
        speakerObservationFlow,
        sessionClusteringFlow,
        diarizationFlow,
        alignmentFlow,
        appleContractFlow,
    ]
}
