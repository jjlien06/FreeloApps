import AVKit
import Photos
import SwiftUI

struct AssetDetailView: View {
    let item: AssetItem

    @Environment(\.dismiss) private var dismiss
    @State private var image: UIImage?
    @State private var player: AVPlayer?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                content
            }
            .safeAreaInset(edge: .bottom, spacing: 0) { metadata }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .toolbarBackground(.visible, for: .navigationBar)
        }
        .task { await load() }
        .onDisappear { player?.pause() }
    }

    @ViewBuilder
    private var content: some View {
        if item.isVideo {
            if let player {
                VideoPlayer(player: player)
            } else {
                ProgressView().controlSize(.large).tint(.white)
            }
        } else if let image {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
        } else {
            ProgressView().controlSize(.large).tint(.white)
        }
    }

    private var metadata: some View {
        VStack(spacing: 0) {
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                row("Size", ByteFormatting.compactOrDash(item.bytes))
                row("Dimensions", item.pixelDescription)
                if item.isVideo {
                    row("Duration", ByteFormatting.duration(item.duration))
                }
                if let date = item.creationDate {
                    row("Created", date.formatted(date: .abbreviated, time: .shortened))
                }
                if let name = originalFilename {
                    row("File", name)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(.bar)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 84, alignment: .leading)
            Text(value)
                .font(.caption.weight(.medium))
                .monospacedDigit()
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private var originalFilename: String? {
        PHAssetResource.assetResources(for: item.asset).first?.originalFilename
    }

    private func load() async {
        if item.isVideo {
            let options = PHVideoRequestOptions()
            options.deliveryMode = .automatic
            options.isNetworkAccessAllowed = true

            let playerItem: AVPlayerItem? = await withCheckedContinuation { continuation in
                PHImageManager.default().requestPlayerItem(
                    forVideo: item.asset,
                    options: options
                ) { playerItem, _ in
                    continuation.resume(returning: playerItem)
                }
            }
            guard let playerItem else { return }
            player = AVPlayer(playerItem: playerItem)
        } else {
            let options = PHImageRequestOptions()
            options.deliveryMode = .highQualityFormat
            options.isNetworkAccessAllowed = true
            options.resizeMode = PHImageRequestOptionsResizeMode.none

            PHImageManager.default().requestImage(
                for: item.asset,
                targetSize: PHImageManagerMaximumSize,
                contentMode: .aspectFit,
                options: options
            ) { result, _ in
                if let result { image = result }
            }
        }
    }
}
