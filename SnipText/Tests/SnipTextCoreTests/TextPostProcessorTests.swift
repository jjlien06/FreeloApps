import Testing
@testable import SnipTextCore

@Suite struct TextPostProcessorTests {
    @Test func joinsLinesWithSpaces() {
        let out = TextPostProcessor.process(lines: ["hello", "world"], joinLines: true)
        #expect(out == "hello world")
    }

    @Test func preservesLineBreaks() {
        let out = TextPostProcessor.process(lines: ["hello", "world"], joinLines: false)
        #expect(out == "hello\nworld")
    }

    @Test func trimsWhitespaceAndDropsEmptyLines() {
        let out = TextPostProcessor.process(lines: ["  hello  ", "", "   ", "world"], joinLines: true)
        #expect(out == "hello world")
    }

    @Test func emptyInputGivesEmptyString() {
        #expect(TextPostProcessor.process(lines: [], joinLines: true) == "")
        #expect(TextPostProcessor.process(lines: ["", "  "], joinLines: false) == "")
    }

    @Test func singleLineUnaffectedByMode() {
        #expect(TextPostProcessor.process(lines: ["only line"], joinLines: true) == "only line")
        #expect(TextPostProcessor.process(lines: ["only line"], joinLines: false) == "only line")
    }
}
