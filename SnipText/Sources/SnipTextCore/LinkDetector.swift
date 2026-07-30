import Foundation

public enum LinkDetector {
    /// Extracts web links (http/https only — never file:, mailto:, etc.) so
    /// auto-open can't be tricked into launching something local.
    public static func urls(in text: String) -> [URL] {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
            return []
        }
        let range = NSRange(text.startIndex..., in: text)
        return detector.matches(in: text, options: [], range: range)
            .compactMap(\.url)
            .filter { ["http", "https"].contains($0.scheme?.lowercased() ?? "") }
    }
}
