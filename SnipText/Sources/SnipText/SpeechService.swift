import AVFoundation

final class SpeechService {
    // Long-lived on purpose: a deallocated synthesizer silently speaks nothing.
    private let synthesizer = AVSpeechSynthesizer()

    /// Speaks with the user's system default voice (utterance.voice stays nil).
    func speak(_ text: String) {
        synthesizer.stopSpeaking(at: .immediate)
        synthesizer.speak(AVSpeechUtterance(string: text))
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
    }
}
