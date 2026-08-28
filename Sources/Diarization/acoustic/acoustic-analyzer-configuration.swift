public struct AcousticAnalyzerConfiguration:
    Sendable,
    Codable,
    Hashable
{
    public let frameDurationSeconds: Double
    public let hopDurationSeconds: Double
    public let minimumFFTSize: Int
    public let rolloffFraction: Double
    public let minimumPitchHz: Double
    public let maximumPitchHz: Double
    public let minimumPitchEvidence: Double
    public let silenceRMS: Double
    public let adaptiveNoiseMultiplier: Double
    public let clippingThreshold: Double
    public let maximumClippingFraction: Double
    public let maximumSpeechFlatness: Double
    public let maximumSpeechZeroCrossingRate: Double
    public let minimumProfileQuality: Double
    public let melFilterCount: Int
    public let mfccCount: Int

    public init(
        frameDurationSeconds: Double = 0.032,
        hopDurationSeconds: Double = 0.016,
        minimumFFTSize: Int = 1024,
        rolloffFraction: Double = 0.85,
        minimumPitchHz: Double = 70,
        maximumPitchHz: Double = 350,
        minimumPitchEvidence: Double = 0.12,
        silenceRMS: Double = 0.006,
        adaptiveNoiseMultiplier: Double = 2.5,
        clippingThreshold: Double = 0.995,
        maximumClippingFraction: Double = 0.01,
        maximumSpeechFlatness: Double = 0.65,
        maximumSpeechZeroCrossingRate: Double = 0.35,
        minimumProfileQuality: Double = 0.55,
        melFilterCount: Int = 24,
        mfccCount: Int = 13
    ) {
        precondition(frameDurationSeconds > 0)
        precondition(hopDurationSeconds > 0)
        precondition(minimumFFTSize > 0)
        precondition(rolloffFraction > 0 && rolloffFraction <= 1)
        precondition(minimumPitchHz > 0)
        precondition(maximumPitchHz > minimumPitchHz)
        precondition(melFilterCount > 0)
        precondition(mfccCount > 0)
        precondition(mfccCount <= melFilterCount)

        self.frameDurationSeconds = frameDurationSeconds
        self.hopDurationSeconds = hopDurationSeconds
        self.minimumFFTSize = minimumFFTSize
        self.rolloffFraction = rolloffFraction
        self.minimumPitchHz = minimumPitchHz
        self.maximumPitchHz = maximumPitchHz
        self.minimumPitchEvidence = minimumPitchEvidence
        self.silenceRMS = silenceRMS
        self.adaptiveNoiseMultiplier = adaptiveNoiseMultiplier
        self.clippingThreshold = clippingThreshold
        self.maximumClippingFraction = maximumClippingFraction
        self.maximumSpeechFlatness = maximumSpeechFlatness
        self.maximumSpeechZeroCrossingRate = maximumSpeechZeroCrossingRate
        self.minimumProfileQuality = minimumProfileQuality
        self.melFilterCount = melFilterCount
        self.mfccCount = mfccCount
    }
}
