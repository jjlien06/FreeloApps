import CullCore
import SwiftUI

/// Loads and shows one image at the requested decode size.
struct AsyncPhoto: View {
    let url: URL
    let size: ImageLoader.Size
    var contentMode: ContentMode = .fit

    @State private var decoded: DecodedImage?
    @State private var didFail = false

    var body: some View {
        Group {
            if let decoded {
                Image(decorative: decoded.cgImage, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else if didFail {
                unreadablePlaceholder
            } else {
                ProgressView()
                    .controlSize(.small)
                    .tint(Theme.secondaryText)
            }
        }
        .task(id: url) {
            decoded = nil
            didFail = false
            let image = await ImageLoader.shared.image(for: url, size: size)
            guard !Task.isCancelled else { return }
            decoded = image
            didFail = image == nil
        }
    }

    /// A file ImageIO cannot decode stays visible and ratable rather than
    /// blanking the view.
    private var unreadablePlaceholder: some View {
        VStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 18))
            Text("Can't read")
                .font(.system(size: 10))
        }
        .foregroundStyle(Theme.secondaryText)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.elevated)
    }
}

/// Compact star readout used on thumbnails and in the status bar.
struct StarsRow: View {
    let stars: Int
    var size: CGFloat = 11

    var body: some View {
        HStack(spacing: 1.5) {
            ForEach(1...5, id: \.self) { index in
                Image(systemName: index <= stars ? "star.fill" : "star")
                    .font(.system(size: size))
                    .foregroundStyle(index <= stars ? Theme.star : Theme.secondaryText.opacity(0.45))
            }
        }
    }
}

struct VerdictChip: View {
    let verdict: Verdict?

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: verdict?.symbol ?? "circle.dashed")
                .font(.system(size: 10, weight: .bold))
            Text(verdict?.label ?? "Unrated")
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(verdict?.tint ?? Theme.secondaryText)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule().fill((verdict?.tint ?? Theme.secondaryText).opacity(0.14))
        )
    }
}

/// The badges drawn over a thumbnail in the filmstrip and grid.
struct ThumbnailOverlay: View {
    let rating: Rating

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let verdict = rating.verdict {
                HStack {
                    Image(systemName: verdict.symbol)
                        .font(.system(size: 8, weight: .black))
                        .foregroundStyle(.black.opacity(0.85))
                        .frame(width: 14, height: 14)
                        .background(Circle().fill(verdict.tint))
                    Spacer()
                }
            }
            Spacer()
            if rating.stars > 0 {
                StarsRow(stars: rating.stars, size: 7)
                    .padding(.horizontal, 3)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(.black.opacity(0.55)))
            }
        }
        .padding(4)
    }
}
