import Foundation
import SnipTextCore

extension HistoryStore {
    static var `default`: HistoryStore {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return HistoryStore(directory: appSupport.appendingPathComponent("SnipText", isDirectory: true))
    }
}
