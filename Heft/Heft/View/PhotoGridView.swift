import Photos
import SwiftUI

struct PhotoGridView: View {
    @Environment(LibraryModel.self) private var model
    @State private var detailItem: AssetItem?

    private let columnCount = 3
    private let spacing: CGFloat = 2

    var body: some View {
        Group {
            if model.isLoading {
                ProgressView("Reading library…").controlSize(.large)
            } else if model.visibleItems.isEmpty {
                ContentUnavailableView(
                    "Nothing here",
                    systemImage: "photo.on.rectangle.angled",
                    description: Text("No \(model.filter.label.lowercased()) in this library.")
                )
            } else {
                grid
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .safeAreaInset(edge: .top, spacing: 0) { header }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if model.isSelecting {
                SelectionBar().transition(.move(edge: .bottom))
            }
        }
        .fullScreenCover(item: $detailItem) { item in
            AssetDetailView(item: item)
        }
    }

    private var grid: some View {
        GeometryReader { proxy in
            // `side` only picks a decode resolution. Column widths are left to
            // `.flexible()` — hand-computed `.fixed()` widths can round a pixel past
            // the available width and wrap the last column onto the next row.
            let side = (proxy.size.width - spacing * CGFloat(columnCount - 1))
                / CGFloat(columnCount)
            let columns = Array(
                repeating: GridItem(.flexible(), spacing: spacing),
                count: columnCount
            )

            ScrollView {
                LazyVGrid(columns: columns, spacing: spacing) {
                    ForEach(model.visibleItems) { item in
                        AssetCell(
                            item: item,
                            side: side,
                            isSelecting: model.isSelecting,
                            isSelected: model.selection.contains(item.id)
                        )
                        .onTapGesture { handleTap(item) }
                    }
                }
            }
        }
    }

    private var header: some View {
        VStack(spacing: 0) {
            if model.status == .limited {
                LimitedAccessBanner()
            }

            HStack(spacing: 6) {
                Text(countLabel)
                Text("·")
                Text(ByteFormatting.compact(model.resolvedBytes))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Spacer(minLength: 0)
                if model.isIndexing {
                    scanStatus
                }
            }
            .font(.footnote)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)

            if model.fastPassProgress < 1 {
                ProgressView(value: model.fastPassProgress)
                    .progressViewStyle(.linear)
                    .frame(height: 2)
            }

            Divider()
        }
        .background(.bar)
        .animation(.default, value: model.resolvedBytes)
    }

    private var scanStatus: some View {
        HStack(spacing: 5) {
            ProgressView().controlSize(.mini)
            Text(
                model.fastPassProgress < 1
                    ? "Measuring…"
                    : "\(model.deepScanRemaining) left"
            )
        }
    }

    private var countLabel: String {
        let count = model.visibleItems.count
        let formatted = count.formatted(.number)
        return count == 1 ? "1 item" : "\(formatted) items"
    }

    private func handleTap(_ item: AssetItem) {
        if model.isSelecting {
            model.toggleSelection(item.id)
        } else {
            detailItem = item
        }
    }
}
