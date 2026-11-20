import Foundation
import MediaCore

enum AudioTestFixture {
    static func buffer(
        samples: [Float],
        sampleRate: Int = 16_000
    ) -> MediaAudioBuffer {
        let data = samples.withUnsafeBytes {
            Data(
                $0
            )
        }

        return MediaAudioBuffer(
            data: data,
            frameCount: samples.count,
            packetCount: UInt32(
                clamping: samples.count
            ),
            sampleRate: sampleRate,
            channelCount: 1,
            sample: .float32,
            hostTimeSeconds: nil
        )
    }

    static func silence(
        duration: Double,
        sampleRate: Int = 16_000
    ) -> [Float] {
        Array(
            repeating: 0,
            count: max(
                0,
                Int(
                    duration
                    * Double(sampleRate)
                )
            )
        )
    }

    static func sine(
        frequency: Double,
        duration: Double,
        amplitude: Float = 0.25,
        sampleRate: Int = 16_000
    ) -> [Float] {
        let count = max(
            0,
            Int(
                duration
                * Double(sampleRate)
            )
        )

        return (0..<count).map { index in
            amplitude
                * Float(
                    sin(
                        2
                        * Double.pi
                        * frequency
                        * Double(index)
                        / Double(sampleRate)
                    )
                )
        }
    }

    static func alternating(
        duration: Double,
        amplitude: Float = 0.25,
        sampleRate: Int = 16_000
    ) -> [Float] {
        let count = max(
            0,
            Int(
                duration
                * Double(sampleRate)
            )
        )

        return (0..<count).map { index in
            index.isMultiple(of: 2)
                ? amplitude
                : -amplitude
        }
    }
}
