import Foundation
import Photos
// `presentLimitedLibraryPicker(from:)` is declared in PhotosUI, not Photos.
import PhotosUI
import UIKit

enum PhotoLibraryAuthorizer {
    static var status: PHAuthorizationStatus {
        PHPhotoLibrary.authorizationStatus(for: .readWrite)
    }

    /// Read-write, because the whole point is being able to delete.
    static func request() async -> PHAuthorizationStatus {
        await PHPhotoLibrary.requestAuthorization(for: .readWrite)
    }

    static func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    /// Lets someone on limited access add more assets to the selection.
    @MainActor
    static func presentLimitedPicker() {
        guard let controller = topViewController() else { return }
        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: controller)
    }

    @MainActor
    private static func topViewController() -> UIViewController? {
        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        var controller = scene?.windows.first { $0.isKeyWindow }?.rootViewController
        while let presented = controller?.presentedViewController {
            controller = presented
        }
        return controller
    }
}

/// Bridges `PHPhotoLibraryChangeObserver` (which needs NSObject) to a closure so the
/// model can stay a plain observable type.
final class LibraryChangeObserver: NSObject, PHPhotoLibraryChangeObserver {
    private let onChange: () -> Void

    init(onChange: @escaping () -> Void) {
        self.onChange = onChange
        super.init()
        PHPhotoLibrary.shared().register(self)
    }

    deinit {
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
    }

    func photoLibraryDidChange(_ changeInstance: PHChange) {
        DispatchQueue.main.async { [onChange] in onChange() }
    }
}
