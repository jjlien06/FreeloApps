import SwiftUI
import ParkingKit

@main
struct MParkingApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
        }
    }
}

enum Tab: String {
    case free, map, settings
}

struct RootView: View {
    @Bindable var model: AppModel

    /// Honours `-mparking.startTab free|map|settings`, which UserDefaults picks up
    /// from launch arguments. Lets a screen be opened directly for a screenshot or
    /// a bug report without tapping through.
    @State private var tab: Tab = {
        let raw = UserDefaults.standard.string(forKey: "mparking.startTab") ?? ""
        return Tab(rawValue: raw) ?? .free
    }()

    var body: some View {
        if let error = model.loadError {
            // If the bundled dataset will not load there is nothing honest to
            // show, so say exactly that instead of an empty list.
            ContentUnavailableView {
                Label("Parking data did not load", systemImage: "exclamationmark.triangle")
            } description: {
                Text(error)
            }
        } else {
            TabView(selection: $tab) {
                FreeNowView(model: model)
                    .tabItem { Label("Free now", systemImage: "parkingsign.circle") }
                    .tag(Tab.free)
                MapTabView(model: model)
                    .tabItem { Label("Map", systemImage: "map") }
                    .tag(Tab.map)
                SettingsView(model: model)
                    .tabItem { Label("Settings", systemImage: "gearshape") }
                    .tag(Tab.settings)
            }

        }
    }
}
