import AppKit
import CullCore
import SwiftUI

@main
struct CullApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var session = CullSession()

    var body: some Scene {
        // A single window, not a WindowGroup: one folder is culled at a time, and
        // opening a folder from Finder would otherwise spawn a second window
        // sharing the same session.
        Window("Cull", id: "cull") {
            ContentView(session: session)
                .frame(minWidth: 900, minHeight: 620)
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 1400, height: 900)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .newItem) {
                Button("Open Folder…") { NotificationCenter.default.post(name: .cullOpenFolder, object: nil) }
                    .keyboardShortcut("o")
                Button("Export Selects") { NotificationCenter.default.post(name: .cullExport, object: nil) }
                    .keyboardShortcut("e")
            }
        }
    }
}

extension Notification.Name {
    /// The menu bar and the in-window buttons drive the same two actions; the
    /// window owns the state, so the menu asks rather than acts.
    static let cullOpenFolder = Notification.Name("cull.openFolder")
    static let cullExport = Notification.Name("cull.export")
    /// Posted with the folder URL as the object, from outside the window.
    static let cullOpenSpecificFolder = Notification.Name("cull.openSpecificFolder")
}
