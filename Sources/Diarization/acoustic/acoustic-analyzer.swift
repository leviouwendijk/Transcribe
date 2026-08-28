import Accelerate
import Foundation
import MediaCore

public struct AcousticAnalyzer: Sendable {
    public let configuration: AcousticAnalyzerConfiguration

    public init(
        configuration: AcousticAnalyzerConfiguration = .init()
    ) {
        self.configuration = configuration
    }

    public func analyze(
        _ buffer: MediaAudioBuffer,
        startingAt startTime: TimeInterval = 0
    ) throws -> AcousticAnalysis {
        guard buffer.sampleRate > 0 else {
            return .init(
                sampleRate: buffer.sampleRate,
                noiseFloorRMS: 0,
                observations: []
            )
        }

        let samples = buffer.monoFloatSamples()

        guard !samples.isEmpty else {
            return .init(
                sampleRate: buffer.sampleRate,
                noiseFloorRMS: 0,
                observations: []
            )
        }

        let frameLength = max(
            1,
            Int(
                (
                    Double(buffer.sampleRate)
                    * configuration.frameDurationSeconds
                ).rounded()
            )
        )

        let hopLength = max(
            1,
            Int(
                (
                    Double(buffer.sampleRate)
                    * configuration.hopDurationSeconds
                ).rounded()
            )
        )

        let fftSize = nextPowerOfTwo(
            max(
                frameLength,
                configuration.minimumFFTSize
            )
        )

        let transform = try vDSP.DiscreteFourierTransform(
            previous: nil,
            count: fftSize,
            direction: .forward,
            transformType: .complexComplex,
            ofType: Float.self
        )

        var unclassified: [UnclassifiedObservation] = []
        var frameStart = 0

        while frameStart < samples.count {
            let frameEnd = min(
                samples.count,
                frameStart + frameLength
            )

            let available = frameEnd - frameStart

            if available < frameLength / 2,
               !unclassified.isEmpty {
                break
            }

            let frame = Array(
                samples[frameStart..<frameEnd]
            )

            let signal = signalFeatures(
                frame
            )

            let spectral = spectralFeatures(
                frame,
                sampleRate: buffer.sampleRate,
                fftSize: fftSize,
                transform: transform
            )

            let range = Audio.TimeRange(
                start: startTime
                    + Double(frameStart)
                    / Double(buffer.sampleRate),
                duration: Double(available)
                    / Double(buffer.sampleRate)
            )

            unclassified.append(
                .init(
                    range: range,
                    signal: signal,
                    spectral: spectral
                )
            )

            frameStart += hopLength
        }

        let noiseFloor = estimatedNoiseFloor(
            unclassified.map {
                $0.signal.rms
            }
        )

        let observations = unclassified.enumerated().map {
            index,
            raw in

            let activity = activity(
                signal: raw.signal,
                spectral: raw.spectral,
                noiseFloorRMS: noiseFloor
            )

            let quality = quality(
                signal: raw.signal,
                spectral: raw.spectral,
                activity: activity,
                noiseFloorRMS: noiseFloor
            )

            return AcousticObservation(
                id: .init(
                    rawValue: index
                ),
                range: raw.range,
                signal: raw.signal,
                spectral: raw.spectral,
                activity: activity,
                quality: quality
            )
        }

        return .init(
            sampleRate: buffer.sampleRate,
            noiseFloorRMS: noiseFloor,
            observations: observations
        )
    }

    public func analyze(
        _ chunk: MediaAudioChunk
    ) throws -> AcousticAnalysis {
        let start = chunk.timeRange?.start
            ?? chunk.presentationTimeSeconds
            ?? chunk.buffer.hostTimeSeconds
            ?? 0

        return try analyze(
            chunk.buffer,
            startingAt: start
        )
    }
}

private struct UnclassifiedObservation {
    let range: Audio.TimeRange
    let signal: AcousticSignalFeatures
    let spectral: AcousticSpectralFeatures
}

private extension AcousticAnalyzer {
    func signalFeatures(
        _ samples: [Float]
    ) -> AcousticSignalFeatures {
        guard !samples.isEmpty else {
            return .init(
                rms: 0,
                peak: 0,
                zeroCrossingRate: 0,
                clippingFraction: 0
            )
        }

        var squaredSum = 0.0
        var peak = 0.0
        var crossings = 0
        var clipped = 0

        for index in samples.indices {
            let value = Double(
                samples[index]
            )

            squaredSum += value * value
            peak = max(
                peak,
                abs(value)
            )

            if abs(value) >= configuration.clippingThreshold {
                clipped += 1
            }

            if index > samples.startIndex {
                let previous = samples[
                    samples.index(before: index)
                ]

                if (previous >= 0) != (samples[index] >= 0) {
                    crossings += 1
                }
            }
        }

        let count = Double(
            samples.count
        )

        return .init(
            rms: sqrt(
                squaredSum / count
            ),
            peak: peak,
            zeroCrossingRate: samples.count > 1
                ? Double(crossings)
                    / Double(samples.count - 1)
                : 0,
            clippingFraction: Double(clipped)
                / count
        )
    }

    func spectralFeatures(
        _ samples: [Float],
        sampleRate: Int,
        fftSize: Int,
        transform: vDSP.DiscreteFourierTransform<Float>
    ) -> AcousticSpectralFeatures {
        guard !samples.isEmpty else {
            return emptySpectralFeatures()
        }

        var real = Array(
            repeating: Float(0),
            count: fftSize
        )

        for index in samples.indices {
            let weight: Double

            if samples.count <= 1 {
                weight = 1
            } else {
                weight = 0.5 - 0.5 * cos(
                    2 * Double.pi
                    * Double(index)
                    / Double(samples.count - 1)
                )
            }

            real[index] = samples[index]
                * Float(weight)
        }

        let imaginary = Array(
            repeating: Float(0),
            count: fftSize
        )

        let transformed = transform.transform(
            real: real,
            imaginary: imaginary
        )

        let spectrumCount = fftSize / 2 + 1
        var power = Array(
            repeating: 0.0,
            count: spectrumCount
        )

        for index in 0..<spectrumCount {
            let real = Double(
                transformed.real[index]
            )

            let imaginary = Double(
                transformed.imaginary[index]
            )

            power[index] = real * real
                + imaginary * imaginary
        }

        let totalPower = power.reduce(
            0,
            +
        )

        guard totalPower > 1e-20 else {
            return emptySpectralFeatures()
        }

        let binWidth = Double(sampleRate)
            / Double(fftSize)

        var weightedFrequency = 0.0

        for index in power.indices {
            weightedFrequency += Double(index)
                * binWidth
                * power[index]
        }

        let centroid = weightedFrequency
            / totalPower

        var spreadAccumulator = 0.0

        for index in power.indices {
            let frequency = Double(index)
                * binWidth

            let delta = frequency
                - centroid

            spreadAccumulator += delta
                * delta
                * power[index]
        }

        let spread = sqrt(
            spreadAccumulator
                / totalPower
        )

        let rolloffTarget = totalPower
            * configuration.rolloffFraction

        var cumulative = 0.0
        var rolloff = 0.0

        for index in power.indices {
            cumulative += power[index]

            if cumulative >= rolloffTarget {
                rolloff = Double(index)
                    * binWidth
                break
            }
        }

        let magnitudes = power
            .dropFirst()
            .map {
                sqrt(
                    max(
                        $0,
                        1e-20
                    )
                )
            }

        let arithmeticMean = magnitudes.isEmpty
            ? 0
            : magnitudes.reduce(0, +)
                / Double(magnitudes.count)

        let geometricMean: Double

        if magnitudes.isEmpty {
            geometricMean = 0
        } else {
            geometricMean = exp(
                magnitudes
                    .map {
                        log(
                            max(
                                $0,
                                1e-20
                            )
                        )
                    }
                    .reduce(0, +)
                    / Double(magnitudes.count)
            )
        }

        let flatness = arithmeticMean > 0
            ? min(
                1,
                geometricMean / arithmeticMean
            )
            : 0

        let minimumBin = max(
            1,
            Int(
                ceil(
                    configuration.minimumPitchHz
                    / binWidth
                )
            )
        )

        let maximumBin = min(
            power.count - 1,
            Int(
                floor(
                    configuration.maximumPitchHz
                    / binWidth
                )
            )
        )

        var pitch: Double?
        var voicedProbability = 0.0

        if minimumBin <= maximumBin {
            var dominantBin = minimumBin
            var dominantPower = 0.0
            var bandPower = 0.0

            for index in minimumBin...maximumBin {
                let value = power[index]
                bandPower += value

                if value > dominantPower {
                    dominantPower = value
                    dominantBin = index
                }
            }

            if bandPower > 1e-20 {
                voicedProbability = min(
                    1,
                    dominantPower / bandPower
                )
            }

            if voicedProbability >= configuration.minimumPitchEvidence {
                pitch = Double(dominantBin)
                    * binWidth
            }
        }

        return .init(
            centroidHz: centroid,
            spreadHz: spread,
            rolloffHz: rolloff,
            flatness: flatness,
            pitchHz: pitch,
            voicedProbability: voicedProbability,
            mfcc: mfcc(
                power: power,
                sampleRate: sampleRate,
                fftSize: fftSize
            )
        )
    }

    func mfcc(
        power: [Double],
        sampleRate: Int,
        fftSize: Int
    ) -> [Double] {
        guard power.reduce(0, +) > 1e-20 else {
            return Array(
                repeating: 0,
                count: configuration.mfccCount
            )
        }

        let nyquist = Double(sampleRate) / 2
        let lowerFrequency = min(
            80,
            nyquist
        )

        let upperFrequency = min(
            8_000,
            nyquist
        )

        guard upperFrequency > lowerFrequency else {
            return Array(
                repeating: 0,
                count: configuration.mfccCount
            )
        }

        let lowerMel = mel(
            lowerFrequency
        )

        let upperMel = mel(
            upperFrequency
        )

        let pointCount = configuration.melFilterCount
            + 2

        let melPoints = (0..<pointCount).map { index in
            lowerMel
                + Double(index)
                / Double(pointCount - 1)
                * (upperMel - lowerMel)
        }

        let bins = melPoints.map { value in
            min(
                power.count - 1,
                max(
                    0,
                    Int(
                        floor(
                            hz(value)
                            * Double(fftSize)
                            / Double(sampleRate)
                        )
                    )
                )
            )
        }

        var logEnergies: [Double] = []
        logEnergies.reserveCapacity(
            configuration.melFilterCount
        )

        for filter in 0..<configuration.melFilterCount {
            let left = bins[filter]
            let center = bins[filter + 1]
            let right = bins[filter + 2]

            var energy = 0.0

            if center > left {
                for bin in left..<center {
                    let weight = Double(bin - left)
                        / Double(center - left)

                    energy += power[bin]
                        * weight
                }
            }

            if right > center {
                for bin in center..<right {
                    let weight = Double(right - bin)
                        / Double(right - center)

                    energy += power[bin]
                        * weight
                }
            }

            logEnergies.append(
                log(
                    max(
                        energy,
                        1e-20
                    )
                )
            )
        }

        return (0..<configuration.mfccCount).map { coefficient in
            var value = 0.0

            for filter in 0..<logEnergies.count {
                value += logEnergies[filter]
                    * cos(
                        Double.pi
                        * Double(coefficient)
                        * (
                            Double(filter)
                            + 0.5
                        )
                        / Double(logEnergies.count)
                    )
            }

            return value
        }
    }

    func activity(
        signal: AcousticSignalFeatures,
        spectral: AcousticSpectralFeatures,
        noiseFloorRMS: Double
    ) -> AcousticActivity {
        let silenceThreshold = max(
            configuration.silenceRMS,
            noiseFloorRMS
                * configuration.adaptiveNoiseMultiplier
        )

        if signal.rms < silenceThreshold {
            return .silence
        }

        if signal.clippingFraction
            > configuration.maximumClippingFraction {
            return .uncertain
        }

        if spectral.pitchHz != nil,
           spectral.voicedProbability
            >= configuration.minimumPitchEvidence,
           spectral.flatness
            <= configuration.maximumSpeechFlatness,
           signal.zeroCrossingRate
            <= configuration.maximumSpeechZeroCrossingRate {
            return .voicedSpeech
        }

        if spectral.flatness
            > configuration.maximumSpeechFlatness
            || signal.zeroCrossingRate
            > configuration.maximumSpeechZeroCrossingRate {
            return .noise
        }

        return .uncertain
    }

    func quality(
        signal: AcousticSignalFeatures,
        spectral: AcousticSpectralFeatures,
        activity: AcousticActivity,
        noiseFloorRMS: Double
    ) -> AcousticQuality {
        let silenceThreshold = max(
            configuration.silenceRMS,
            noiseFloorRMS
                * configuration.adaptiveNoiseMultiplier
        )

        var issues: [AcousticQualityIssue] = []
        var score = 1.0

        if signal.rms < silenceThreshold {
            issues.append(
                .lowEnergy
            )
            score = 0
        }

        if signal.clippingFraction
            > configuration.maximumClippingFraction {
            issues.append(
                .clipping
            )

            score -= min(
                0.6,
                signal.clippingFraction * 5
            )
        }

        if spectral.pitchHz == nil {
            issues.append(
                .unvoiced
            )
            score -= 0.25
        }

        if activity == .noise {
            issues.append(
                .noiseLike
            )
            score -= 0.4
        }

        if spectral.flatness
            > configuration.maximumSpeechFlatness {
            score -= 0.15
        }

        if signal.zeroCrossingRate
            > configuration.maximumSpeechZeroCrossingRate {
            score -= 0.15
        }

        score = min(
            1,
            max(
                0,
                score
            )
        )

        return .init(
            score: score,
            isUsableForSpeakerProfile: activity == .voicedSpeech
                && score >= configuration.minimumProfileQuality,
            issues: issues
        )
    }

    func estimatedNoiseFloor(
        _ rmsValues: [Double]
    ) -> Double {
        guard rmsValues.count >= 4 else {
            return 0
        }

        let sorted = rmsValues.sorted()

        let lowIndex = min(
            sorted.count - 1,
            Int(
                Double(sorted.count - 1)
                    * 0.10
            )
        )

        let highIndex = min(
            sorted.count - 1,
            Int(
                Double(sorted.count - 1)
                    * 0.90
            )
        )

        let low = sorted[lowIndex]
        let high = sorted[highIndex]

        guard high > max(
            configuration.silenceRMS * 2,
            low * 1.5
        ) else {
            return 0
        }

        return low
    }

    func emptySpectralFeatures() -> AcousticSpectralFeatures {
        .init(
            centroidHz: 0,
            spreadHz: 0,
            rolloffHz: 0,
            flatness: 0,
            pitchHz: nil,
            voicedProbability: 0,
            mfcc: Array(
                repeating: 0,
                count: configuration.mfccCount
            )
        )
    }

    func nextPowerOfTwo(
        _ value: Int
    ) -> Int {
        var result = 1

        while result < value {
            result <<= 1
        }

        return result
    }

    func mel(
        _ frequency: Double
    ) -> Double {
        2_595
            * log10(
                1 + frequency / 700
            )
    }

    func hz(
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
