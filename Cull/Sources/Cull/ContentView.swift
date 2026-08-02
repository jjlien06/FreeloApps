import AppKit
import Combine
import CullCore
import SwiftUI

struct ContentView: View {
    enum Field: Hashable { case viewer, note }

    @Bindable var session: CullSession

    @FocusState private var focus: Field?
    @State private var noteDraft = ""
    @State private var exportSummary: ExportService.Summary?
    @State private var exportError: String?

    var body: some View {
        VStack(spacing: 0) {
            TopBar(session: session, onOpen: openFolder, onExport: exportPasses)
            hairline
            content
            if session.viewMode == .loupe && !session.items.isEmpty {
                hairline
                FilmstripView(session: session)
            }
            hairline
            BottomBar(session: session, noteDraft: $noteDraft, noteFocus: $focus)
        }
        .background(Theme.background)
        .focusable()
        .focusEffectDisabled()
        .focused($focus, equals: .viewer)
        .onKeyPress(phases: .down, action: handleKey)
        .onAppear { focus = .viewer }
        .onChange(of: session.cursor) { _, _ in currentPhotoChanged() }
        .onChange(of: session.filter) { _, _ in currentPhotoChanged() }
        .dropDestination(for: URL.self) { urls, _ in openDropped(urls) }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            session.flushSave()
        }
        .onReceive(NotificationCenter.default.publisher(for: .cullOpenFolder)) { _ in openFolder() }
        .onReceive(NotificationCenter.default.publisher(for: .cullExport)) { _ in exportPasses() }
        .onReceive(NotificationCenter.default.publisher(for: .cullOpenSpecificFolder)) { note in
            guard let url = note.object as? URL else { return }
            session.open(folder: url)
            currentPhotoChanged()
            focus = .viewer
        }
        .alert("Export finished", isPresented: showingExportSummary) {
            Button("Reveal in Finder") { revealSelects() }
            Button("Done", role: .cancel) {}
        } message: {
            Text(exportSummary.map(describe) ?? "")
        }
        .alert("Export failed", isPresented: showingExportError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(exportError ?? "")
        }
        .alert("Ratings file recovered", isPresented: showingRecoveryNotice) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(session.recoveryNotice ?? "")
        }
    }

    private var hairline: some View {
        Rectangle().fill(Theme.hairline).frame(height: 1)
    }

    @ViewBuilder
    private var content: some View {
        if session.folder == nil {
            emptyState
        } else if session.allItems.isEmpty {
            message(session.loadError ?? "No images in this folder.")
        } else if session.items.isEmpty {
            message("Nothing matches the “\(session.filter.label)” filter.")
        } else if let current = session.current, session.viewMode == .loupe {
            LoupeView(session: session, item: current)
        } else {
            GridView(session: session)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "photo.stack")
                .font(.system(size: 40, weight: .thin))
                .foregroundStyle(Theme.secondaryText)
            Text("Open a folder of photos")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.primaryText)
            Text("Or drop one here. Ratings are saved beside the photos and originals are never modified.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 340)
            Button("Choose Folder…", action: openFolder)
                .controlSize(.large)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
    }

    private func message(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(Theme.secondaryText)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.background)
    }

    // MARK: - Keyboard

    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        // Command-modified keys belong to the menu, not the viewer.
        guard press.modifiers.subtracting(.shift).isEmpty else { return .ignored }

        switch press.key.character {
        case KeyEquivalent.leftArrow.character:
            session.previous()
        case KeyEquivalent.rightArrow.character, " ":
            session.next()
        case KeyEquivalent.upArrow.character:
            session.previous()
        case KeyEquivalent.downArrow.character:
            session.next()
        case KeyEquivalent.escape.character:
            session.isZoomed = false
        case "p", "P":
            session.setVerdict(.pass)
        case "x", "X":
            session.setVerdict(.fail)
        case "u", "U":
            session.setVerdict(nil)
        case "0", "1", "2", "3", "4", "5":
            session.setStars(press.key.character.wholeNumberValue ?? 0)
        case "g", "G":
            session.viewMode = session.viewMode == .loupe ? .grid : .loupe
        case "z", "Z":
            session.isZoomed.toggle()
        case "f", "F":
            session.filter = session.filter.next
        case "n", "N":
            focus = .note
        default:
            return .ignored
        }
        return .handled
    }

    // MARK: - Actions

    private func openFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose a folder of photos to cull"
        panel.prompt = "Open"

        guard panel.runModal() == .OK, let url = panel.url else { return }
        session.open(folder: url)
        currentPhotoChanged()
        focus = .viewer
    }

    private func openDropped(_ urls: [URL]) -> Bool {
        guard let url = urls.first else { return false }
        var isDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        // Dropping a photo opens the folder that contains it.
        session.open(folder: isDirectory.boolValue ? url : url.deletingLastPathComponent())
        currentPhotoChanged()
        focus = .viewer
        return true
    }

    private func exportPasses() {
        do {
            exportSummary = try session.exportPasses()
        } catch {
            exportError = error.localizedDescription
        }
    }

    private func revealSelects() {
        guard let folder = session.folder else { return }
        let selects = folder.appendingPathComponent(ExportService.defaultSubfolderName, isDirectory: true)
        NSWorkspace.shared.activateFileViewerSelecting([selects])
    }

    private func describe(_ summary: ExportService.Summary) -> String {
        var lines = ["Copied \(summary.copied.count) photo\(summary.copied.count == 1 ? "" : "s") to \(ExportService.defaultSubfolderName)."]
        if !summary.skippedExisting.isEmpty {
            lines.append("Skipped \(summary.skippedExisting.count) already there.")
        }
        if !summary.failed.isEmpty {
            let names = summary.failed.prefix(3).map(\.filename).joined(separator: ", ")
            lines.append("Failed \(summary.failed.count): \(names)")
        }
        return lines.joined(separator: "\n")
    }

    /// Keeps the note field in step with the cursor and warms nearby frames.
    private func currentPhotoChanged() {
        noteDraft = session.currentRating.note ?? ""

        let items = session.items
        guard !items.isEmpty else { return }
        let lower = max(0, session.cursor - 2)
        let upper = min(items.count - 1, session.cursor + 3)
        let urls = (lower...upper).map { items[$0].url }
        Task { await ImageLoader.shared.prefetch(urls, size: .loupe) }
    }

    // MARK: - Alert plumbing

    private var showingExportSummary: Binding<Bool> {
        Binding(get: { exportSummary != nil }, set: { if !$0 { exportSummary = nil } })
    }

    private var showingExportError: Binding<Bool> {
        Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })
    }

    private var showingRecoveryNotice: Binding<Bool> {
        Binding(
            get: { session.recoveryNotice != nil },
            set: { if !$0 { session.recoveryNotice = nil } }
        )
    }
}
