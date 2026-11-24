import CoreMedia
import Foundation
import MediaCore
import Speech
import Transcribe

/// Reads word timing from a Speech result's attributed text.
///
/// Time-indexed presets attach an `audioTimeRange` to each run; with
/// `transcriptionConfidence` requested, runs also carry a confidence.
/// Untimed runs (punctuation, mostly) join the word before them, or the
/// next word when nothing precedes them. Dictation also emits zero-length
/// ranges for punctuation and some repeated words; those count as untimed.
@_spi(Testing)
public enum AppleTranscriptionWords {
    public static func words(
        from text: AttributedString
    ) -> [TranscriptionWord] {
        var words: [TranscriptionWord] = []
        var pending = ""
        var gap = false

        for run in text.runs {
            let raw = String(
                text[run.range].characters
            )
            let fragment = raw.trimmingCharacters(
                in: .whitespacesAndNewlines
            )

            if raw.first?.isWhitespace == true {
                gap = true
            }

            guard !fragment.isEmpty else {
                continue
            }

            let separator = gap ? " " : ""

            if let timeRange = run.audioTimeRange,
               let range = Audio.TimeRange(
                   cmTimeRange: timeRange
               ),
               range.duration > 0 {
                words.append(
                    .init(
                        text: pending.isEmpty
                            ? fragment
                            : pending + separator + fragment,
                        range: range,
                        confidence: run.transcriptionConfidence
                    )
                )
                pending = ""
            } else if let last = words.popLast() {
                words.append(
                    .init(
                        text: last.text + separator + fragment,
                        range: last.range,
                        confidence: last.confidence
                    )
                )
            } else {
                pending = pending.isEmpty
                    ? fragment
                    : pending + separator + fragment
            }

            gap = raw.last?.isWhitespace == true
        }

        return words
    }

    /// Duration-weighted mean of the words' confidences; nil when none carry one.
    public static func confidence(
        of words: [TranscriptionWord]
    ) -> Double? {
        var weighted = 0.0
        var weight = 0.0

        for word in words {
            guard let confidence = word.confidence else {
                continue
            }

            let duration = max(
                word.range.duration,
                1e-3
            )

            weighted += confidence * duration
            weight += duration
        }

        guard weight > 0 else {
            return nil
        }

        return weighted / weight
    }
}

extension Audio.TimeRange {
    init?(
        cmTimeRange range: CMTimeRange
    ) {
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

        self.init(
            start: start,
            duration: duration
        )
    }
}

extension SpeechTranscriber.Preset {
    /// Time-indexed with alternatives, plus per-word confidence.
    static var timeIndexedWordTranscription: Self {
        var preset = Self.timeIndexedTranscriptionWithAlternatives
        preset.attributeOptions.insert(
            .transcriptionConfidence
        )
        return preset
    }
}

extension DictationTranscriber.Preset {
    /// Time-indexed long dictation, plus per-word confidence.
    static var timeIndexedWordDictation: Self {
        var preset = Self.timeIndexedLongDictation
        preset.attributeOptions.insert(
            .transcriptionConfidence
        )
        return preset
    }
}
