import Foundation
import Testing
@testable import SnipTextCore

@Suite struct HistoryStoreTests {
    private func makeTempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SnipTextTests-\(UUID().uuidString)", isDirectory: true)
        return dir
    }

    @Test func appendsCapturesSeparatedByBlankLine() throws {
        let store = HistoryStore(directory: makeTempDir())
        try store.append("first capture")
        try store.append("second capture")
        #expect(store.loadAll() == "first capture\n\nsecond capture")
    }

    @Test func persistsAcrossInstances() throws {
        let dir = makeTempDir()
        try HistoryStore(directory: dir).append("survives restarts")
        let reopened = HistoryStore(directory: dir)
        #expect(reopened.loadAll() == "survives restarts")
    }

    @Test func clearEmptiesTheBuffer() throws {
        let store = HistoryStore(directory: makeTempDir())
        try store.append("something")
        try store.clear()
        #expect(store.isEmpty)
        #expect(store.loadAll() == "")
    }

    @Test func clearOnEmptyStoreDoesNotThrow() throws {
        let store = HistoryStore(directory: makeTempDir())
        try store.clear()
        #expect(store.isEmpty)
    }
}
