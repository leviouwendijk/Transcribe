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
        speakerReliabilityFlow,
        speakerTemporalCoherenceFlow,
        retainedInferenceProvenanceFlow,
        speechAnalysisContextFlow,
        speakerDiarizationReplayFlow,
        speakerDiarizationReplayCalibrationFlow,
        speakerEmbeddingFlow,
        speakerEmbeddingProviderFlow,
        transcribeCLIObservabilityFlow,
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
