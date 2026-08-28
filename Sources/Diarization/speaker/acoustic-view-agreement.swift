public struct AcousticViewAgreement:
    Sendable,
    Codable,
    Hashable
{
    public let mfccShape: Double
    public let logMelShape: Double
    public let combined: Double

    public init(
        mfccShape: Double,
        logMelShape: Double
    ) {
        self.mfccShape = min(
            1,
            max(
                0,
                mfccShape
            )
        )
        self.logMelShape = min(
            1,
            max(
                0,
                logMelShape
            )
        )
        combined = (
            self.mfccShape
                + self.logMelShape
        ) / 2
    }
}
