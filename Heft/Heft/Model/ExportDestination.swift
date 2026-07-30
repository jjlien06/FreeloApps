import Foundation
import SwiftUI

/// Remembers where exports go, across launches.
///
/// iOS has no API for enumerating mounted volumes — a sandboxed app can only reach
/// external storage through a URL the user handed it via the document picker. So
/// "is the drive connected?" is answered indirectly: we keep a security-scoped
/// bookmark to the chosen folder and test whether it still resolves and is writable.
@MainActor
@Observable
final class ExportDestination {
    private static let bookmarkKey = "heft.exportDestinationBookmark"
    private static let nameKey = "heft.exportDestinationName"

    /// Resolves only while the destination is actually present.
    private(set) var url: URL?
    private(set) var isReachable = false
    /// Survives the drive being unplugged, so the UI can name what to reconnect.
    private(set) var savedName: String?
    private(set) var lastError: String?

    var displayName: String? { url?.lastPathComponent ?? savedName }

    /// A destination has been chosen at some point — regardless of whether it's here now.
    var isConfigured: Bool {
        UserDefaults.standard.data(forKey: Self.bookmarkKey) != nil
    }

    /// Chosen AND present AND writable right now.
    var isUsable: Bool { url != nil && isReachable }

    init() {
        refresh()
    }

    /// Records a folder the user just picked.
    func adopt(_ picked: URL) {
        // A folder URL from the document picker has to be opened before it will yield
        // bookmark data that survives a relaunch. Skipping this is why a chosen
        // destination could silently fail to persist.
        let granted = picked.startAccessingSecurityScopedResource()
        defer { if granted { picked.stopAccessingSecurityScopedResource() } }

        do {
            let data = try picked.bookmarkData(
                options: .minimalBookmark,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            UserDefaults.standard.set(data, forKey: Self.bookmarkKey)
            UserDefaults.standard.set(picked.lastPathComponent, forKey: Self.nameKey)
            savedName = picked.lastPathComponent
            url = picked
            isReachable = check(picked)   // access is open right now, so check directly
            lastError = nil
        } catch {
            lastError = "Couldn't remember that folder: \(error.localizedDescription)"
            isReachable = false
        }
    }

    func forget() {
        UserDefaults.standard.removeObject(forKey: Self.bookmarkKey)
        UserDefaults.standard.removeObject(forKey: Self.nameKey)
        url = nil
        savedName = nil
        isReachable = false
        lastError = nil
    }

    /// Re-resolves the bookmark and re-tests reachability. Cheap — safe to call on
    /// foreground, on grid appear, and on a slow poll while selecting.
    func refresh() {
        savedName = UserDefaults.standard.string(forKey: Self.nameKey)

        guard let data = UserDefaults.standard.data(forKey: Self.bookmarkKey) else {
            url = nil
            isReachable = false
            return
        }

        var isStale = false
        guard let resolved = try? URL(
            resolvingBookmarkData: data,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            // Drive unplugged or folder removed. Keep the bookmark and the name so it
            // lights up again by itself once the drive is back — no re-picking needed.
            url = nil
            isReachable = false
            return
        }

        url = resolved
        isReachable = probe(resolved)

        if isStale, isReachable {
            if let fresh = try? resolved.bookmarkData(
                options: .minimalBookmark,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            ) {
                UserDefaults.standard.set(fresh, forKey: Self.bookmarkKey)
            }
        }
    }

    /// Runs `body` inside a security-scoped access window.
    /// Returns nil without invoking `body` if access can't be obtained.
    func withAccess<T>(_ body: (URL) async -> T) async -> T? {
        guard let url else { return nil }
        let granted = url.startAccessingSecurityScopedResource()
        defer { if granted { url.stopAccessingSecurityScopedResource() } }
        // `check`, not `probe` — probe opens its own scope and its `defer` would
        // close the window we just opened here.
        guard granted, check(url) else {
            isReachable = false
            return nil
        }
        return await body(url)
    }

    private func probe(_ candidate: URL) -> Bool {
        let granted = candidate.startAccessingSecurityScopedResource()
        defer { if granted { candidate.stopAccessingSecurityScopedResource() } }
        return check(candidate)
    }

    /// Assumes a security-scoped window is already open for `candidate`.
    private func check(_ candidate: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDirectory)
        return exists && isDirectory.boolValue
            && FileManager.default.isWritableFile(atPath: candidate.path)
    }
}
