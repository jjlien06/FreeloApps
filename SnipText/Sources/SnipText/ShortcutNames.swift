import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let captureText = Self("captureText", default: .init(.two, modifiers: [.command, .shift]))
    static let captureAndSpeak = Self("captureAndSpeak", default: .init(.two, modifiers: [.command, .shift, .option]))
}
