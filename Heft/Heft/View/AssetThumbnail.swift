import Photos
import SwiftUI

/// Grid thumbnail backed by `PHImageManager`. Requests are cancelled on scroll-off so
/// a fast flick through a large library doesn't queue thousands of decodes.
struct AssetThumbnail: View {
    let asset: PHAsset
    /// Only used to pick a decode resolution — layout size comes from the parent.
    let side: CGFloat

    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?
    @State private var requestID: PHImageRequestID?
    @State private var isRequesting = false

    var body: some View {
        // The image MUST be an overlay, not a ZStack sibling. `scaledToFill` overflows
        // whatever size it's proposed, and a ZStack adopts its largest child's size —
        // so a ZStack would grow to the scaled image and spill onto neighbouring cells.
        // Overlay content cannot influence its parent's size, so the shape stays put
        // and `clipped()` trims the overflow.
        Rectangle()
            .fill(.fill.tertiary)
            .overlay {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                }
            }
            .clipped()
            .onAppear(perform: load)
            .onDisappear(perform: cancel)
    }

    private func load() {
        guard !isRequesting, image == nil else { return }
        isRequesting = true

        let target = CGSize(width: side * displayScale, height: side * displayScale)
        let options = PHImageRequestOptions()
        options.deliveryMode = .opportunistic
        options.resizeMode = .fast
        options.isNetworkAccessAllowed = false

        // `.opportunistic` can hand back a cached thumbnail synchronously, before
        // `requestImage` returns. Stashing the ID unconditionally would then overwrite
        // the handler's `nil` with a dead ID — leaving the cell permanently "pending".
        var finishedSynchronously = false

        let id = PHImageManager.default().requestImage(
            for: asset,
            targetSize: target,
            contentMode: .aspectFill,
            options: options
        ) { result, info in
            if let result { image = result }
            let isDegraded = (info?[PHImageResultIsDegradedKey] as? Bool) ?? false
            guard !isDegraded else { return }
            finishedSynchronously = true
            requestID = nil
            isRequesting = false
        }

        if !finishedSynchronously { requestID = id }
    }

    private func cancel() {
        if let requestID {
            PHImageManager.default().cancelImageRequest(requestID)
        }
        requestID = nil
        isRequesting = false
    }
}
