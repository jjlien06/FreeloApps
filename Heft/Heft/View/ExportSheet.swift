import SwiftUI

/// Progress while copying, then a summary of what was exported, deleted, and kept.
///
/// Reads `model.exportRun` from the environment rather than taking an `ExportRun` value
/// as a parameter. A value handed in at presentation time is a snapshot, and any doubt
/// about whether a sheet's content closure re-evaluates becomes a frozen progress bar.
/// Observing the model here removes that failure mode entirely.
struct ExportSheet: View {
    @Environment(LibraryModel.self) private var model

    private var run: ExportRun? { model.exportRun }

    var body: some View {
        NavigationStack {
            Group {
                if let run {
                    if run.isFinished {
                        summary(run)
                    } else {
                        progress(run)
                    }
                } else {
                    ProgressView()
                }
            }
            .navigationTitle((run?.isFinished ?? false) ? "Export complete" : "Exporting")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if run?.isFinished ?? false {
                        Button("Done") { model.dismissExportSummary() }
                    } else if let run, !run.wasCancelled {
                        Button("Cancel", role: .cancel) { model.cancelExport() }
                    }
                }
            }
        }
        .interactiveDismissDisabled(!(run?.isFinished ?? true))
    }

    // MARK: Copying

    private func progress(_ run: ExportRun) -> some View {
        // A 1-second tick guarantees the elapsed clock keeps moving even when a single
        // enormous file reports no byte progress for a while — so the screen is never
        // indistinguishable from a hang.
        TimelineView(.periodic(from: .now, by: 1)) { context in
            VStack(spacing: 20) {
                Spacer()

                VStack(spacing: 10) {
                    ProgressView(value: run.fraction)
                        .progressViewStyle(.linear)

                    HStack {
                        Text("\(Int(run.fraction * 100))%")
                            .monospacedDigit()
                        Spacer()
                        if run.totalBytes > 0 {
                            Text("\(ByteFormatting.compact(run.bytesDone)) of "
                                 + "\(ByteFormatting.compact(run.totalBytes))")
                                .monospacedDigit()
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 28)

                VStack(spacing: 5) {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.mini)
                        Text(run.phase == .deleting
                             ? "Deleting verified items…"
                             : "Copying originals…")
                            .font(.subheadline.weight(.medium))
                    }

                    Text("Item \(min(run.completedItems + 1, run.totalItems)) of \(run.totalItems)")
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

                VStack(spacing: 3) {
                    Text(elapsedText(run, now: context.date))
                        .monospacedDigit()
                    if let rate = run.bytesPerSecond(asOf: context.date) {
                        Text("\(ByteFormatting.compact(Int64(rate)))/s"
                             + remainingSuffix(run, now: context.date))
                            .monospacedDigit()
                    }
                }
                .font(.caption2)
                .foregroundStyle(.tertiary)

                Text(run.wasCancelled
                     ? "Cancelling — finishing the current file first."
                     : "Keep the drive connected until this finishes.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)

                Spacer()
            }
            .padding()
        }
    }

    private func elapsedText(_ run: ExportRun, now: Date) -> String {
        "Elapsed " + ByteFormatting.duration(now.timeIntervalSince(run.startedAt))
    }

    private func remainingSuffix(_ run: ExportRun, now: Date) -> String {
        guard let remaining = run.estimatedRemaining(asOf: now) else { return "" }
        return " · about \(ByteFormatting.duration(remaining)) left"
    }

    // MARK: Summary

    private func summary(_ run: ExportRun) -> some View {
        List {
            Section {
                row(
                    "Exported",
                    "\(run.exported.count) · \(ByteFormatting.compact(run.bytesExported))",
                    "checkmark.circle.fill",
                    .green
                )
                row("Deleted from library", "\(run.deletedCount)", "trash.fill", .red)
                if !run.failed.isEmpty {
                    row(
                        "Kept (export failed)",
                        "\(run.failed.count)",
                        "exclamationmark.triangle.fill",
                        .orange
                    )
                }
            } footer: {
                Text(run.wasCancelled
                     ? "Cancelled, so nothing was deleted. The copies already written are "
                        + "on the drive and safe to keep or discard."
                     : "Deleted items are in Recently Deleted for 30 days. "
                        + "Anything that failed to export was left in your library untouched.")
            }

            if let error = run.deleteError {
                Section("Deletion") {
                    Text(error).font(.footnote).foregroundStyle(.secondary)
                }
            }

            if !run.failed.isEmpty {
                Section("Not exported") {
                    ForEach(run.failed) { outcome in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(outcome.label)
                                .font(.footnote.weight(.medium))
                            Text(outcome.failure ?? "Unknown problem")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
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
            Text(value)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }
}
