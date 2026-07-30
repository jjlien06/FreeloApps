import SwiftUI

struct AssetCell: View {
    let item: AssetItem
    let side: CGFloat
    let isSelecting: Bool
    let isSelected: Bool

    var body: some View {
        AssetThumbnail(asset: item.asset, side: side)
            // Square, sized from the column width the grid hands down — never from
            // the image's own dimensions.
            .aspectRatio(1, contentMode: .fit)
            .overlay(alignment: .bottom) { scrim }
            .overlay(alignment: .bottomLeading) { sizeBadge }
            .overlay(alignment: .bottomTrailing) { rawBadge }
            .overlay(alignment: .topTrailing) { videoBadge }
            .overlay { selectionOverlay }
            .contentShape(Rectangle())
    }

    /// Photos are unpredictable backdrops; a gradient keeps the size legible over a
    /// bright sky without stamping a heavy box on every cell.
    private var scrim: some View {
        LinearGradient(
            colors: [.black.opacity(0), .black.opacity(0.5)],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(height: 30)
        .allowsHitTesting(false)
    }

    private var sizeBadge: some View {
        Text(ByteFormatting.compactOrDash(item.bytes))
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(.white)
            .shadow(color: .black.opacity(0.45), radius: 1, y: 0.5)
            .padding(.horizontal, 5)
            .padding(.vertical, 3)
    }

    @ViewBuilder
    private var rawBadge: some View {
        if item.isRaw {
            Text("RAW")
                .font(.system(size: 8, weight: .heavy, design: .rounded))
                .kerning(0.3)
                .foregroundStyle(.black)
                .padding(.horizontal, 4)
                .padding(.vertical, 1.5)
                .background(.yellow.opacity(0.9), in: RoundedRectangle(cornerRadius: 3))
                .padding(4)
        }
    }

    @ViewBuilder
    private var videoBadge: some View {
        if item.isVideo {
            HStack(spacing: 2) {
                Image(systemName: "play.fill").font(.system(size: 7))
                Text(ByteFormatting.duration(item.duration))
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
            .background(.black.opacity(0.4), in: Capsule())
            .padding(4)
        }
    }

    @ViewBuilder
    private var selectionOverlay: some View {
        if isSelecting {
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(.blue.opacity(isSelected ? 0.3 : 0.001))
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, isSelected ? .blue : .white.opacity(0.4))
                    .shadow(color: .black.opacity(0.3), radius: 1)
                    .padding(4)
            }
        }
    }
}
