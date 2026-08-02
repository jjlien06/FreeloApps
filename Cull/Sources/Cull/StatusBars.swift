import CullCore
import SwiftUI

/// Folder identity, running tallies, and the view controls.
struct TopBar: View {
    @Bindable var session: CullSession
    let onOpen: () -> Void
    let onExport: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(session.folderName)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.primaryText)
                Text("\(session.allItems.count) photo\(session.allItems.count == 1 ? "" : "s")")
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.secondaryText)
            }

            Spacer(minLength: 16)

            tally("checkmark", session.passCount, Theme.pass)
            tally("xmark", session.failCount, Theme.fail)
            tally("circle.dashed", session.unratedCount, Theme.secondaryText)

            Divider().frame(height: 18)

            Picker("Filter", selection: $session.filter) {
                ForEach(CullSession.Filter.allCases, id: \.self) { filter in
                    Text(filter.label).tag(filter)
                }
            }
            .labelsHidden()
            .frame(width: 108)

            Picker("View", selection: $session.viewMode) {
                Image(systemName: "photo").tag(CullSession.ViewMode.loupe)
                Image(systemName: "square.grid.2x2").tag(CullSession.ViewMode.grid)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 76)

            Button(action: onExport) {
                Label("Export", systemImage: "square.and.arrow.up")
            }
            .disabled(session.passCount == 0)
            .help("Copy every pass into a Selects folder (⌘E)")

            Button(action: onOpen) {
                Label("Open", systemImage: "folder")
            }
            .help("Open a folder of photos (⌘O)")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(Theme.chrome)
    }

    private func tally(_ symbol: String, _ count: Int, _ tint: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 9, weight: .bold))
            Text("\(count)").font(.system(size: 11, weight: .medium)).monospacedDigit()
        }
        .foregroundStyle(tint)
    }
}

/// Everything about the photo under the cursor, plus the controls that a mouse
/// user needs and a keyboard user does not.
struct BottomBar: View {
    @Bindable var session: CullSession
    @Binding var noteDraft: String
    var noteFocus: FocusState<ContentView.Field?>.Binding

    var body: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 1) {
                Text(session.current?.filename ?? "—")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Theme.primaryText)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(positionLabel)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.secondaryText)
                    .monospacedDigit()
            }
            .frame(width: 220, alignment: .leading)

            VerdictChip(verdict: session.currentRating.verdict)

            interactiveStars

            TextField("Note", text: $noteDraft)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11))
                .frame(maxWidth: 260)
                .focused(noteFocus, equals: .note)
                .onSubmit {
                    session.setNote(noteDraft)
                    noteFocus.wrappedValue = .viewer
                }

            Spacer(minLength: 8)

            Toggle("Auto-advance", isOn: $session.autoAdvance)
                .toggleStyle(.checkbox)
                .font(.system(size: 11))
                .foregroundStyle(Theme.secondaryText)

            ShortcutsButton()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Theme.chrome)
        .disabled(session.current == nil)
    }

    private var positionLabel: String {
        guard !session.items.isEmpty else { return "nothing to show" }
        return "\(session.cursor + 1) of \(session.items.count)"
    }

    private var interactiveStars: some View {
        HStack(spacing: 2) {
            ForEach(1...5, id: \.self) { index in
                Button {
                    // Clicking the current rating clears it, which is the only
                    // way to get back to zero with the mouse.
                    session.setStars(session.currentRating.stars == index ? 0 : index)
                } label: {
                    Image(systemName: index <= session.currentRating.stars ? "star.fill" : "star")
                        .font(.system(size: 13))
                        .foregroundStyle(
                            index <= session.currentRating.stars
                                ? Theme.star : Theme.secondaryText.opacity(0.5)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct ShortcutsButton: View {
    @State private var showing = false

    private let shortcuts: [(String, String)] = [
        ("← →", "Previous / next"),
        ("Space", "Next"),
        ("P", "Pass"),
        ("X", "Fail"),
        ("U", "Clear verdict"),
        ("1–5", "Set stars"),
        ("0", "Clear stars"),
        ("G", "Grid / loupe"),
        ("Z", "Zoom"),
        ("F", "Cycle filter"),
        ("N", "Edit note"),
        ("⌘O", "Open folder"),
        ("⌘E", "Export selects"),
    ]

    var body: some View {
        Button {
            showing.toggle()
        } label: {
            Image(systemName: "keyboard")
        }
        .buttonStyle(.plain)
        .foregroundStyle(Theme.secondaryText)
        .help("Keyboard shortcuts")
        .popover(isPresented: $showing, arrowEdge: .top) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Shortcuts")
                    .font(.system(size: 12, weight: .semibold))
                    .padding(.bottom, 2)
                ForEach(shortcuts, id: \.0) { key, action in
                    HStack(spacing: 10) {
                        Text(key)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .frame(width: 46, alignment: .leading)
                        Text(action).font(.system(size: 11))
                    }
                }
            }
            .padding(14)
        }
    }
}
