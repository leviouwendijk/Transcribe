import AVFAudio
import CoreMedia
import Foundation
import MediaCore
import Speech
import Transcribe

public struct AppleTranscriber: Sendable {
    public init() {}

    public func transcribe(
        file: URL,
        localeIdentifier: String,
        model: AppleTranscriptionModel = .speech
    ) async throws -> AppleTranscriptionResult {
        switch model {
        case .speech:
            return try await transcribeSpeech(
                file: file,
                localeIdentifier: localeIdentifier
            )

        case .dictation:
            return try await transcribeDictation(
                file: file,
                localeIdentifier: localeIdentifier
            )
        }
    }

    public func transcribe(
        buffer: MediaAudioBuffer,
        localeIdentifier: String,
        model: AppleTranscriptionModel = .speech
    ) async throws -> AppleTranscriptionResult {
        try await transcribe(
            buffers: [
                buffer,
            ],
            localeIdentifier: localeIdentifier,
            model: model
        )
    }

    public func transcribe(
        buffers: [MediaAudioBuffer],
        localeIdentifier: String,
        model: AppleTranscriptionModel = .speech
    ) async throws -> AppleTranscriptionResult {
        switch model {
        case .speech:
            return try await transcribeSpeech(
                buffers: buffers,
                localeIdentifier: localeIdentifier
            )

        case .dictation:
            return try await transcribeDictation(
                buffers: buffers,
                localeIdentifier: localeIdentifier
            )
        }
    }
}

private extension AppleTranscriber {
    func transcribeSpeech(
        file: URL,
        localeIdentifier: String
    ) async throws -> AppleTranscriptionResult {
        guard SpeechTranscriber.isAvailable else {
            throw AppleTranscriptionError.speechTranscriberUnavailable
        }

        let requestedLocale = Locale(
            identifier: localeIdentifier
        )

        guard let locale = await SpeechTranscriber.supportedLocale(
            equivalentTo: requestedLocale
        ) else {
            throw AppleTranscriptionError.unsupportedSpeechLocale(
                localeIdentifier
            )
        }

        let transcriber = SpeechTranscriber(
            locale: locale,
            preset: .timeIndexedTranscriptionWithAlternatives
        )

        try await ensureAssets(
            supporting: [
                transcriber,
            ]
        )

        let audioFile = try AVAudioFile(
            forReading: file
        )

        let analyzer = SpeechAnalyzer(
            modules: [
                transcriber,
            ]
        )

        async let resultTask = collectSpeechResults(
            from: transcriber
        )

        if let lastSample = try await analyzer.analyzeSequence(
            from: audioFile
        ) {
            try await analyzer.finalizeAndFinish(
                through: lastSample
            )
        } else {
            await analyzer.cancelAndFinishNow()
        }

        let results = try await resultTask

        return .init(
            transcription: .init(
                localeIdentifier: locale.identifier,
                segments: results.map(
                    segment
                )
            ),
            nativeResults: results.map {
                .speech(
                    $0
                )
            }
        )
    }

    func transcribeDictation(
        file: URL,
        localeIdentifier: String
    ) async throws -> AppleTranscriptionResult {
        let requestedLocale = Locale(
            identifier: localeIdentifier
        )

        guard let locale = await DictationTranscriber.supportedLocale(
            equivalentTo: requestedLocale
        ) else {
            throw AppleTranscriptionError.unsupportedDictationLocale(
                localeIdentifier
            )
        }

        let transcriber = DictationTranscriber(
            locale: locale,
            preset: .timeIndexedLongDictation
        )

        try await ensureAssets(
            supporting: [
                transcriber,
            ]
        )

        let audioFile = try AVAudioFile(
            forReading: file
        )

        let analyzer = SpeechAnalyzer(
            modules: [
                transcriber,
            ]
        )

        async let resultTask = collectDictationResults(
            from: transcriber
        )

        if let lastSample = try await analyzer.analyzeSequence(
            from: audioFile
        ) {
            try await analyzer.finalizeAndFinish(
                through: lastSample
            )
        } else {
            await analyzer.cancelAndFinishNow()
        }

        let results = try await resultTask

        return .init(
            transcription: .init(
                localeIdentifier: locale.identifier,
                segments: results.map(
                    segment
                )
            ),
            nativeResults: results.map {
                .dictation(
                    $0
                )
            }
        )
    }

    func ensureAssets(
        supporting modules: [any SpeechModule]
    ) async throws {
        guard let request = try await AssetInventory
            .assetInstallationRequest(
                supporting: modules
            )
        else {
            return
        }

        try await request.downloadAndInstall()
    }

    func collectSpeechResults(
        from transcriber: SpeechTranscriber
    ) async throws -> [SpeechTranscriber.Result] {
        var results: [SpeechTranscriber.Result] = []

        for try await result in transcriber.results {
            results.append(
                result
            )
        }

        return results
    }

    func collectDictationResults(
        from transcriber: DictationTranscriber
    ) async throws -> [DictationTranscriber.Result] {
        var results: [DictationTranscriber.Result] = []

        for try await result in transcriber.results {
            results.append(
                result
            )
        }

        return results
    }

    func segment(
        _ result: SpeechTranscriber.Result
    ) -> TranscriptionSegment {
        .init(
            text: String(
                result.text.characters
            ),
            range: audioTimeRange(
                result.range
            ),
            confidence: nil,
            alternatives: result.alternatives.map {
                String(
                    $0.characters
                )
            },
            isFinal: result.isFinal
        )
    }

    func segment(
        _ result: DictationTranscriber.Result
    ) -> TranscriptionSegment {
        .init(
            text: String(
                result.text.characters
            ),
            range: audioTimeRange(
                result.range
            ),
            confidence: nil,
            alternatives: result.alternatives.map {
                String(
                    $0.characters
                )
            },
            isFinal: result.isFinal
        )
    }

    func audioTimeRange(
        _ range: CMTimeRange
    ) -> Audio.TimeRange? {
        let start = CMTimeGetSeconds(
            range.start
        )

        let duration = CMTimeGetSeconds(
            range.duration
        )

        guard start.isFinite,
              duration.isFinite
        else {
            return nil
        }

        return .init(
            start: start,
            duration: duration
        )
    }

    func transcribeSpeech(
        buffers: [MediaAudioBuffer],
        localeIdentifier: String
    ) async throws -> AppleTranscriptionResult {
        guard SpeechTranscriber.isAvailable else {
            throw AppleTranscriptionError.speechTranscriberUnavailable
        }

        let requestedLocale = Locale(
            identifier: localeIdentifier
        )

        guard let locale = await SpeechTranscriber.supportedLocale(
            equivalentTo: requestedLocale
        ) else {
            throw AppleTranscriptionError.unsupportedSpeechLocale(
                localeIdentifier
            )
        }

        let transcriber = SpeechTranscriber(
            locale: locale,
            preset: .timeIndexedTranscriptionWithAlternatives
        )

        try await ensureAssets(
            supporting: [
                transcriber,
            ]
        )

        let analyzer = SpeechAnalyzer(
            modules: [
                transcriber,
            ]
        )

        async let resultTask = collectSpeechResults(
            from: transcriber
        )

        let lastSample = try await analyze(
            buffers: buffers,
            modules: [
                transcriber,
            ],
            analyzer: analyzer
        )

        if let lastSample {
            try await analyzer.finalizeAndFinish(
                through: lastSample
            )
        } else {
            await analyzer.cancelAndFinishNow()
        }

        let results = try await resultTask

        return .init(
            transcription: .init(
                localeIdentifier: locale.identifier,
                segments: results.map(
                    segment
                )
            ),
            nativeResults: results.map {
                .speech(
                    $0
                )
            }
        )
    }

    func transcribeDictation(
        buffers: [MediaAudioBuffer],
        localeIdentifier: String
    ) async throws -> AppleTranscriptionResult {
        let requestedLocale = Locale(
            identifier: localeIdentifier
        )

        guard let locale = await DictationTranscriber.supportedLocale(
            equivalentTo: requestedLocale
        ) else {
            throw AppleTranscriptionError.unsupportedDictationLocale(
                localeIdentifier
            )
        }

        let transcriber = DictationTranscriber(
            locale: locale,
            preset: .timeIndexedLongDictation
        )

        try await ensureAssets(
            supporting: [
                transcriber,
            ]
        )

        let analyzer = SpeechAnalyzer(
            modules: [
                transcriber,
            ]
        )

        async let resultTask = collectDictationResults(
            from: transcriber
        )

        let lastSample = try await analyze(
            buffers: buffers,
            modules: [
                transcriber,
            ],
            analyzer: analyzer
        )

        if let lastSample {
            try await analyzer.finalizeAndFinish(
                through: lastSample
            )
        } else {
            await analyzer.cancelAndFinishNow()
        }

        let results = try await resultTask

        return .init(
            transcription: .init(
                localeIdentifier: locale.identifier,
                segments: results.map(
                    segment
                )
            ),
            nativeResults: results.map {
                .dictation(
                    $0
                )
            }
        )
    }

    func analyze(
        buffers: [MediaAudioBuffer],
        modules: [any SpeechModule],
        analyzer: SpeechAnalyzer
    ) async throws -> CMTime? {
        guard let analyzerFormat = await SpeechAnalyzer.bestAvailableAudioFormat(
            compatibleWith: modules
        ) else {
            throw AppleTranscriptionMediaBufferError.noCompatibleAnalyzerFormat
        }

        let pcmBuffers = try buffers.compactMap(
            makePCMBuffer
        )

        let (
            inputSequence,
            continuation
        ) = AsyncStream.makeStream(
            of: AnalyzerInput.self
        )

        for buffer in pcmBuffers {
            let converted = try convert(
                buffer,
                to: analyzerFormat
            )

            continuation.yield(
                AnalyzerInput(
                    buffer: converted
                )
            )
        }

        continuation.finish()

        return try await analyzer.analyzeSequence(
            inputSequence
        )
    }

    func convert(
        _ buffer: AVAudioPCMBuffer,
        to outputFormat: AVAudioFormat
    ) throws -> AVAudioPCMBuffer {
        guard buffer.format != outputFormat else {
            return buffer
        }

        guard let converter = AVAudioConverter(
            from: buffer.format,
            to: outputFormat
        ) else {
            throw AppleTranscriptionMediaBufferError.cannotCreateConverter
        }

        converter.primeMethod = .none

        let sampleRateRatio = outputFormat.sampleRate
            / buffer.format.sampleRate

        let scaledFrameCount = Double(
            buffer.frameLength
        ) * sampleRateRatio

        let frameCapacity = AVAudioFrameCount(
            max(
                1,
                scaledFrameCount.rounded(.up) + 64
            )
        )

        guard let converted = AVAudioPCMBuffer(
            pcmFormat: outputFormat,
            frameCapacity: frameCapacity
        ) else {
            throw AppleTranscriptionMediaBufferError.cannotCreateConversionBuffer
        }

        var conversionError: NSError?
        var suppliedInput = false

        let status = converter.convert(
            to: converted,
            error: &conversionError
        ) { _, inputStatus in
            guard !suppliedInput else {
                inputStatus.pointee = .noDataNow
                return nil
            }

            suppliedInput = true
            inputStatus.pointee = .haveData
            return buffer
        }

        switch status {
        case .haveData,
             .inputRanDry,
             .endOfStream:
            return converted

        case .error:
            throw AppleTranscriptionMediaBufferError.conversionFailed(
                conversionError?.localizedDescription
            )

        @unknown default:
            throw AppleTranscriptionMediaBufferError.conversionFailed(
                conversionError?.localizedDescription
            )
        }
    }

    func makePCMBuffer(
        _ buffer: MediaAudioBuffer
    ) throws -> AVAudioPCMBuffer? {
        guard buffer.sampleRate > 0 else {
            throw AppleTranscriptionMediaBufferError.invalidSampleRate(
                buffer.sampleRate
            )
        }

        let samples = buffer.monoFloatSamples()

        guard !samples.isEmpty else {
            return nil
        }

        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Double(
                buffer.sampleRate
            ),
            channels: 1,
            interleaved: false
        ) else {
            throw AppleTranscriptionMediaBufferError.cannotCreateFormat
        }

        guard let audioBuffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(
                clamping: samples.count
            )
        ) else {
            throw AppleTranscriptionMediaBufferError.cannotCreateBuffer
        }

        guard let channel = audioBuffer.floatChannelData?.pointee else {
            throw AppleTranscriptionMediaBufferError.missingFloatChannel
        }

        audioBuffer.frameLength = AVAudioFrameCount(
            clamping: samples.count
        )

        samples.withUnsafeBufferPointer { source in
            guard let baseAddress = source.baseAddress else {
                return
            }

            channel.update(
                from: baseAddress,
                count: samples.count
            )
        }

        return audioBuffer
    }
}

private enum AppleTranscriptionMediaBufferError:
    Error,
    LocalizedError
{
    case invalidSampleRate(Int)
    case cannotCreateFormat
    case cannotCreateBuffer
    case missingFloatChannel
    case noCompatibleAnalyzerFormat
    case cannotCreateConverter
    case cannotCreateConversionBuffer
    case conversionFailed(String?)

    var errorDescription: String? {
        switch self {
        case .invalidSampleRate(let sampleRate):
            return "Media audio buffer has invalid sample rate: \(sampleRate)."

        case .cannotCreateFormat:
            return "Could not create the mono Float32 AVAudioFormat required for transcription."

        case .cannotCreateBuffer:
            return "Could not create an AVAudioPCMBuffer for Media audio transcription."

        case .missingFloatChannel:
            return "Created transcription audio buffer has no Float32 channel storage."

        case .noCompatibleAnalyzerFormat:
            return "SpeechAnalyzer reported no compatible audio format for the configured transcription modules."

        case .cannotCreateConverter:
            return "Could not create an AVAudioConverter for the SpeechAnalyzer input format."

        case .cannotCreateConversionBuffer:
            return "Could not allocate the converted SpeechAnalyzer audio buffer."

        case .conversionFailed(let message):
            if let message,
               !message.isEmpty {
                return "Could not convert Media audio for SpeechAnalyzer: \(message)"
            }

            return "Could not convert Media audio for SpeechAnalyzer."
        }
    }
}
