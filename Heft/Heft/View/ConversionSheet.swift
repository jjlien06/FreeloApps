import SwiftUI

/// Progress while converting RAW files, then a summary of what changed and what it saved.
/// Reads the model directly rather than taking a snapshot value, for the same reason
/// `ExportSheet` does.
struct ConversionSheet: View {
    @Environment(LibraryModel.self) private var model

    private var run: ConversionRun? { model.conversionRun }

    var body: some View {
        NavigationStack {
            Group {
                if let run {
                    if run.isFinished { summary(run) } else { progress(run) }
                } else {
                    ProgressView()
                }
            }
            .navigationTitle((run?.isFinished ?? false) ? "Conversion complete" : "Converting")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if run?.isFinished ?? false {
                        Button("Done") { model.dismissConversionSummary() }
                    } else if let run, !run.wasCancelled {
                        Button("Cancel", role: .cancel) { model.cancelConversion() }
                    }
                }
            }
        }
        .interactiveDismissDisabled(!(run?.isFinished ?? true))
    }

    private func progress(_ run: ConversionRun) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(spacing: 18) {
                Spacer()

                ProgressView(value: run.fraction)
                    .progressViewStyle(.linear)
                    .padding(.horizontal, 28)

                VStack(spacing: 5) {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.mini)
                        Text(run.phase == .deleting
                             ? "Removing RAW originals…"
                             : "Rendering to \(run.format.label)…")
                            .font(.subheadline.weight(.medium))
                    }
                    Text("\(min(run.completed + 1, run.totalItems)) of \(run.totalItems)")
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    if !run.currentLabel.isEmpty {
                        Text(run.currentLabel)
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }

                Text("Elapsed "
                     + ByteFormatting.duration(context.date.timeIntervalSince(run.startedAt)))
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)

                Text(run.wasCancelled
                     ? "Cancelling — finishing the current image first."
                     : "Full-size RAW rendering is CPU-heavy; large files take a moment.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)

                Spacer()
            }
            .padding()
        }
    }

    private func summary(_ run: ConversionRun) -> some View {
        List {
            Section {
                row(
                    "Converted",
                    "\(run.converted.count) → \(run.format.label)",
                    "wand.and.sparkles",
                    .blue
                )
                row(
                    "New copies",
                    ByteFormatting.compact(run.newBytes),
                    "photo.stack",
                    .green
                )
                row(
                    "RAW originals",
                    ByteFormatting.compact(run.originalBytes),
                    "doc.badge.gearshape",
                    .orange
                )
                if run.deletingOriginals, run.deletedCount > 0 {
                    row("Deleted", "\(run.deletedCount)", "trash.fill", .red)
                    row(
                        "Space reclaimed",
                        ByteFormatting.compact(run.reclaimed),
                        "internaldrive",
                        .teal
                    )
                }
                if !run.failed.isEmpty {
                    row(
                        "Kept (conversion failed)",
                        "\(run.failed.count)",
                        "exclamationmark.triangle.fill",
                        .orange
                    )
                }
            } footer: {
                Text(footerText(run))
            }

            if let error = run.deleteError {
                Section("Originals") {
                    Text(error).font(.footnote).foregroundStyle(.secondary)
                }
            }

            if !run.failed.isEmpty {
                Section("Not converted") {
                    ForEach(run.failed) { outcome in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(outcome.label).font(.footnote.weight(.medium))
                            Text(outcome.failure ?? "Unknown problem")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private func footerText(_ run: ConversionRun) -> String {
        if run.wasCancelled {
            return "Cancelled. Nothing was deleted — whatever finished converting is in "
                + "your library alongside its RAW original."
        }
        if run.deletingOriginals {
            return "Deleted RAW files are in Recently Deleted for 30 days. Anything that "
                + "failed to convert kept its original untouched."
        }
        return "RAW originals were kept, so both copies now exist and your library grew. "
            + "Delete the RAW files to actually reclaim space."
    }

    private func row(
        _ title: String,
        _ value: String,
        _ symbol: String,
        _ tint: Color
    ) -> some View {
        HStack {
            Image(systemName: symbol).foregroundStyle(tint)
            Text(title)
            Spacer()
            Text(value).monospacedDigit().foregroundStyle(.secondary)
        }
    }
}
