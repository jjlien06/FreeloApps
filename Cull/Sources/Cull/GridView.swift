import CullCore
import SwiftUI

/// Contact-sheet view of the whole folder, for spotting the run of keepers.
struct GridView: View {
    @Bindable var session: CullSession

    private let columns = [GridItem(.adaptive(minimum: 170, maximum: 260), spacing: 10)]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(Array(session.items.enumerated()), id: \.element.id) { index, item in
                        cell(item, isCurrent: index == session.cursor)
                            .id(item.id)
                            .onTapGesture(count: 2) {
                                session.select(item)
                                session.viewMode = .loupe
                            }
                            .onTapGesture { session.select(item) }
                    }
                }
                .padding(14)
            }
            .background(Theme.background)
            .onChange(of: session.cursor) { _, _ in
                guard let current = session.current else { return }
                proxy.scrollTo(current.id, anchor: .center)
            }
        }
    }

    private func cell(_ item: PhotoItem, isCurrent: Bool) -> some View {
        VStack(spacing: 0) {
            AsyncPhoto(url: item.url, size: .grid, contentMode: .fill)
                .frame(height: 150)
                .frame(maxWidth: .infinity)
                .clipped()
                .overlay { ThumbnailOverlay(rating: session.rating(for: item.filename)) }

            Text(item.filename)
                .font(.system(size: 10))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(isCurrent ? Theme.primaryText : Theme.secondaryText)
                .padding(.horizontal, 6)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.chrome)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay {
            RoundedRectangle(cornerRadius: 6)
                .strokeBorder(isCurrent ? Color.white : Theme.hairline, lineWidth: isCurrent ? 2 : 1)
        }
    }
}
