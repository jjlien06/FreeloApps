import CullCore
import SwiftUI

/// The strip of thumbnails under the loupe, showing where you are in the pass.
struct FilmstripView: View {
    @Bindable var session: CullSession

    private let height: CGFloat = 72

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 6) {
                    ForEach(Array(session.items.enumerated()), id: \.element.id) { index, item in
                        thumbnail(item, isCurrent: index == session.cursor)
                            .id(item.id)
                            .onTapGesture { session.select(item) }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
            .onChange(of: session.cursor) { _, _ in
                guard let current = session.current else { return }
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(current.id, anchor: .center)
                }
            }
        }
        .frame(height: height + 16)
        .background(Theme.chrome)
    }

    private func thumbnail(_ item: PhotoItem, isCurrent: Bool) -> some View {
        AsyncPhoto(url: item.url, size: .filmstrip, contentMode: .fill)
            .frame(width: height, height: height)
            .clipped()
            .overlay { ThumbnailOverlay(rating: session.rating(for: item.filename)) }
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .overlay {
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(isCurrent ? Color.white : Theme.hairline, lineWidth: isCurrent ? 2 : 1)
            }
            .opacity(isCurrent ? 1 : 0.72)
    }
}
