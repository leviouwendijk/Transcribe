import Foundation
import TranscribeApple

@main
enum TranscribeCLI {
    static func main() async throws {
        let arguments = CommandLine.arguments

        guard arguments.count >= 2 else {
            print(
                "usage: transcribe <audio-file> [locale] [speech|dictation]"
            )
            return
        }

        let path = NSString(
            string: arguments[1]
        ).expandingTildeInPath

        let localeIdentifier = arguments.count >= 3
            ? arguments[2]
            : "nl-NL"

        let model: AppleTranscriptionModel

        if arguments.count >= 4 {
            guard let requested = AppleTranscriptionModel(
                rawValue: arguments[3]
            ) else {
                print(
                    "model must be speech or dictation"
                )
                return
            }

            model = requested
        } else {
            model = .speech
        }

        let result = try await AppleTranscriber().transcribe(
            file: URL(
                fileURLWithPath: path
            ),
            localeIdentifier: localeIdentifier,
            model: model
        )

        for segment in result.transcription.segments {
            if let range = segment.range {
                print(
                    String(
                        format: "[%.2f ... %.2f] %@",
                        range.start,
                        range.end,
                        segment.text
                    )
                )
            } else {
                print(
                    segment.text
                )
            }
        }

        print("")
        print(
            result.transcription.text
        )
    }
}
