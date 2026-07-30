public enum TextPostProcessor {
    /// Turns OCR lines into clipboard-ready text.
    /// OCR returns a hard break wherever a visual line ended (justified columns,
    /// slides), which is rarely wanted when pasting into prose — so joining with
    /// spaces is the default; `joinLines: false` preserves the visual breaks.
    public static func process(lines: [String], joinLines: Bool) -> String {
        let cleaned = lines
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return cleaned.joined(separator: joinLines ? " " : "\n")
    }
}
