import SwiftUI

@main
struct HeftApp: App {
    @State private var model = LibraryModel()

    init() {
        #if DEBUG
        if let destination = ExportSmokeTest.requestedDestination {
            Task { await ExportSmokeTest.run(into: destination) }
        } else if ExportSmokeTest.requestedConversion {
            Task { await ExportSmokeTest.runConversion() }
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .preferredColorScheme(.dark)
        }
    }
}
