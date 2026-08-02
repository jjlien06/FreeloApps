import Foundation

/// A throwaway directory that cleans itself up, so tests never touch real photos.
final class TempFolder {
    let url: URL

    init() throws {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CullTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    @discardableResult
    func write(_ name: String, contents: String = "x") throws -> URL {
        let file = url.appendingPathComponent(name)
        try Data(contents.utf8).write(to: file)
        return file
    }

    func makeSubfolder(_ name: String) throws -> URL {
        let sub = url.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        return sub
    }

    func exists(_ relativePath: String) -> Bool {
        FileManager.default.fileExists(atPath: url.appendingPathComponent(relativePath).path)
    }
}
