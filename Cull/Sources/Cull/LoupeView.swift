import CullCore
import SwiftUI

/// The single-photo view: one frame, as large as the window allows.
struct LoupeView: View {
    @Bindable var session: CullSession
    let item: PhotoItem

    private let zoomFactor: CGFloat = 2.5

    var body: some View {
        GeometryReader { geometry in
            if session.isZoomed {
                ScrollView([.horizontal, .vertical]) {
                    AsyncPhoto(url: item.url, size: .zoom)
                        .frame(
                            width: geometry.size.width * zoomFactor,
                            height: geometry.size.height * zoomFactor
                        )
                }
                .defaultScrollAnchor(.center)
            } else {
                AsyncPhoto(url: item.url, size: .loupe)
                    .frame(width: geometry.size.width, height: geometry.size.height)
            }
        }
        .background(Theme.background)
        .overlay(alignment: .topTrailing) {
            if session.isZoomed {
                Text("Zoom \(zoomFactor, specifier: "%.1f")×")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(Theme.secondaryText)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(.black.opacity(0.6)))
                    .padding(12)
            }
        }
        .onTapGesture { session.isZoomed.toggle() }
    }
}
