import AppKit

enum SpeechService {
    private static let synthesizer = NSSpeechSynthesizer()

    static func speak(_ text: String) {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking()
        }
        synthesizer.startSpeaking(text)
    }
}
