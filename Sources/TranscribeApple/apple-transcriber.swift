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
}
