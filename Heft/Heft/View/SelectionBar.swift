import SwiftUI

struct SelectionBar: View {
    @Environment(LibraryModel.self) private var model
    @State private var isConfirmingDelete = false
    @State private var isConfirmingExport = false
    @State private var isConfirmingConvert = false
    @State private var isDeleting = false

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            VStack(spacing: 10) {
                HStack {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(countLabel)
                            .font(.subheadline.weight(.semibold))
                        Text(ByteFormatting.compact(model.selectedBytes))
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button("Select All") { model.selectAllVisible() }
                        .font(.subheadline)

                    Button(role: .destructive) {
                        isConfirmingDelete = true
                    } label: {
                        if isDeleting {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .disabled(model.selection.isEmpty || isDeleting)
                }

                // Shown whenever the remembered destination answers right now. The
                // bookmark persists, so this reappears on its own after a reconnect —
                // no re-picking required.
                if model.destination.isUsable {
                    Button {
                        isConfirmingExport = true
                    } label: {
                        Label(
                            "Export to \(model.destination.displayName ?? "drive")",
                            systemImage: "externaldrive.badge.timemachine"
                        )
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(model.selection.isEmpty || isDeleting)
                }

                // Appears only when the selection actually contains RAW files.
                if !model.selectedRawItems.isEmpty {
                    Button {
                        isConfirmingConvert = true
                    } label: {
                        Label(
                            "Convert \(rawCountLabel) to \(RawConverter.Format.heic.label)",
                            systemImage: "wand.and.sparkles"
                        )
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .disabled(isDeleting)
                }

                if model.destination.isConfigured, !model.destination.isUsable {
                    // Destination is remembered but absent. Say so instead of silently
                    // hiding, so an unplugged drive doesn't look like a missing feature.
                    Label(
                        "Reconnect “\(model.destination.savedName ?? "drive")” to export",
                        systemImage: "externaldrive.badge.questionmark"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(.bar)
        // iOS emits no volume-mount notification an app can observe, so a slow poll is
        // the only way for the button to appear on its own when a drive is attached
        // mid-session. Bounded to Select mode, so it costs nothing the rest of the time.
        .task {
            while !Task.isCancelled {
                model.destination.refresh()
                try? await Task.sleep(for: .seconds(3))
            }
        }
        .confirmationDialog(
            "Delete \(countLabel)?",
            isPresented: $isConfirmingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete \(ByteFormatting.compact(model.selectedBytes))", role: .destructive) {
                Task {
                    isDeleting = true
                    await model.deleteSelected()
                    isDeleting = false
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("They move to Recently Deleted and stay recoverable for 30 days.")
        }
        .confirmationDialog(
            "Export \(countLabel)?",
            isPresented: $isConfirmingExport,
            titleVisibility: .visible
        ) {
            // Keep-originals first: it is the non-destructive choice, and putting it
            // ahead of the destructive one makes a mis-tap harmless.
            Button("Export \(ByteFormatting.compact(model.selectedBytes)) & Keep") {
                model.startExport(deletingOriginals: false)
            }
            Button("Export \(ByteFormatting.compact(model.selectedBytes)) & Delete", role: .destructive) {
                model.startExport(deletingOriginals: true)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Originals are copied to “\(AssetExporter.folderName)” on "
                 + "\(model.destination.displayName ?? "the drive") and verified. "
                 + "“Keep” leaves your library untouched. "
                 + "“Delete” removes only the copies that verified.")
        }
        .confirmationDialog(
            "Convert \(rawCountLabel) to \(RawConverter.Format.heic.label)?",
            isPresented: $isConfirmingConvert,
            titleVisibility: .visible
        ) {
            Button("Convert & Delete RAW originals", role: .destructive) {
                model.startRawConversion(to: .heic, deletingOriginals: true)
            }
            Button("Convert & Keep RAW originals") {
                model.startRawConversion(to: .heic, deletingOriginals: false)
            }
            Button("Convert to JPEG instead & Keep RAW") {
                model.startRawConversion(to: .jpeg, deletingOriginals: false)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("A compressed copy is added to your library first, with the original's "
                 + "date, location, and favourite status. Deleting only happens for RAW "
                 + "files whose replacement is confirmed present. "
                 + "Currently \(ByteFormatting.compact(model.selectedRawBytes)) of RAW.")
        }
    }

    private var countLabel: String {
        let count = model.selection.count
        return count == 1 ? "1 item" : "\(count.formatted(.number)) items"
    }

    private var rawCountLabel: String {
        let count = model.selectedRawItems.count
        return count == 1 ? "1 RAW" : "\(count.formatted(.number)) RAW"
    }
}
