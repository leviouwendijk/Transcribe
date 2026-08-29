import TestFlows

enum TranscribeFlowSuite: TestFlowRegistry {
    static let title = "Transcribe"

    static let flows: [TestFlow] = [
        transcriptionFlow,
        acousticObservationFlow,
        acousticActivityFlow,
        acousticTraceFlow,
        acousticTraceExportFlow,
        pitchInferenceFlow,
        noiseEvidenceFlow,
        parallelAcousticFlow,
        acousticPerformanceFlow,
        sessionAcousticFlow,
        speakerObservationFlow,
        multiViewSpeakerFlow,
        multiViewCalibrationFlow,
        sessionClusteringFlow,
        diarizationFlow,
        alignmentFlow,
        alignmentInferenceFlow,
        appleContractFlow,
    ]
}
