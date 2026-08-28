import Foundation

struct AcousticSpectralPlan {
    let frameWindow: [Float]
    let binWidth: Double
    let minimumPitchBin: Int
    let maximumPitchBin: Int
    let melBins: [Int]
    let dctWeights: [[Double]]
    let mfccCount: Int

    init(
        configuration: AcousticAnalyzerConfiguration,
        sampleRate: Int,
        frameLength: Int,
        fftSize: Int
    ) {
        frameWindow = Self.hannWindow(
            count: frameLength
        )

        binWidth = Double(sampleRate)
            / Double(fftSize)

        minimumPitchBin = max(
            1,
            Int(
                ceil(
                    configuration.minimumPitchHz
                        / binWidth
                )
            )
        )

        maximumPitchBin = min(
            fftSize / 2,
            Int(
                floor(
                    configuration.maximumPitchHz
                        / binWidth
                )
            )
        )

        let spectrumCount = fftSize / 2 + 1
        let nyquist = Double(sampleRate) / 2
        let lowerFrequency = min(
            80,
            nyquist
        )
        let upperFrequency = min(
            8_000,
            nyquist
        )

        if upperFrequency > lowerFrequency {
            let lowerMel = Self.mel(
                lowerFrequency
            )
            let upperMel = Self.mel(
                upperFrequency
            )
            let pointCount = configuration.melFilterCount
                + 2

            let melPoints = (0..<pointCount).map { index in
                lowerMel
                    + Double(index)
                        / Double(pointCount - 1)
                        * (
                            upperMel
                                - lowerMel
                        )
            }

            melBins = melPoints.map { value in
                min(
                    spectrumCount - 1,
                    max(
                        0,
                        Int(
                            floor(
                                Self.hz(value)
                                    * Double(fftSize)
                                    / Double(sampleRate)
                            )
                        )
                    )
                )
            }
        } else {
            melBins = Array(
                repeating: 0,
                count: configuration.melFilterCount + 2
            )
        }

        dctWeights = (0..<configuration.mfccCount).map { coefficient in
            (0..<configuration.melFilterCount).map { filter in
                cos(
                    Double.pi
                        * Double(coefficient)
                        * (
                            Double(filter)
                                + 0.5
                        )
                        / Double(configuration.melFilterCount)
                )
            }
        }

        mfccCount = configuration.mfccCount
    }

    func window(
        count: Int
    ) -> [Float] {
        guard count != frameWindow.count else {
            return frameWindow
        }

        return Self.hannWindow(
            count: count
        )
    }
}

private extension AcousticSpectralPlan {
    static func hannWindow(
        count: Int
    ) -> [Float] {
        guard count > 1 else {
            return Array(
                repeating: 1,
                count: max(
                    0,
                    count
                )
            )
        }

        return (0..<count).map { index in
            Float(
                0.5 - 0.5 * cos(
                    2 * Double.pi
                        * Double(index)
                        / Double(count - 1)
                )
            )
        }
    }

    static func mel(
        _ frequency: Double
    ) -> Double {
        2_595
            * log10(
                1 + frequency / 700
            )
    }

    static func hz(
        _ mel: Double
    ) -> Double {
        700
            * (
                pow(
                    10,
                    mel / 2_595
                ) - 1
            )
    }
}
