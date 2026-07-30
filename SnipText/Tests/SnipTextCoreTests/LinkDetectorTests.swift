import Foundation
import Testing
@testable import SnipTextCore

@Suite struct LinkDetectorTests {
    @Test func findsHTTPSLinks() {
        let urls = LinkDetector.urls(in: "check https://example.com/page and http://foo.dev too")
        #expect(urls.map(\.absoluteString) == ["https://example.com/page", "http://foo.dev"])
    }

    @Test func ignoresNonWebSchemes() {
        let urls = LinkDetector.urls(in: "mail me at someone@example.com or open file:///etc/passwd")
        #expect(urls.allSatisfy { $0.scheme == "http" || $0.scheme == "https" })
        #expect(!urls.contains { $0.scheme == "file" || $0.scheme == "mailto" })
    }

    @Test func noLinksInPlainText() {
        #expect(LinkDetector.urls(in: "just some ordinary words").isEmpty)
    }
}
