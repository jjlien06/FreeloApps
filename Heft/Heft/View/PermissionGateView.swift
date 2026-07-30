import SwiftUI

struct PermissionGateView: View {
    var body: some View {
        ContentUnavailableView {
            Label("No photo access", systemImage: "lock.fill")
        } description: {
            Text("Heft needs access to your photo library to measure file sizes. "
                 + "Grant access in Settings, then come back.")
        } actions: {
            Button("Open Settings") {
                PhotoLibraryAuthorizer.openSettings()
            }
            .buttonStyle(.borderedProminent)
        }
    }
}

/// Shown above the grid when only a hand-picked subset of the library is visible.
struct LimitedAccessBanner: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.circle.fill")
                .foregroundStyle(.orange)
            Text("Only selected photos are visible.")
                .font(.footnote)
            Spacer(minLength: 0)
            Button("Manage") {
                PhotoLibraryAuthorizer.presentLimitedPicker()
            }
            .font(.footnote.weight(.semibold))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.thinMaterial)
    }
}
