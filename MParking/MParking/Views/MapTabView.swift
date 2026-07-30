import SwiftUI
import MapKit
import ParkingKit

/// The map, coloured by status at the selected time. Uses a standard bottom sheet
/// for the selected lot, the way Maps itself does.
struct MapTabView: View {
    @Bindable var model: AppModel
    @State private var camera: MapCameraPosition = .region(Self.campus)
    @State private var selectedID: String?

    static let campus = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 42.2790, longitude: -83.7382),
        span: MKCoordinateSpan(latitudeDelta: 0.03, longitudeDelta: 0.03))

    private var pins: [AppModel.Row] {
        model.rows.filter { $0.facility.lat != nil }
    }

    private var selectedRow: AppModel.Row? {
        pins.first { $0.facility.id == selectedID }
    }

    var body: some View {
        NavigationStack {
            Map(position: $camera, selection: $selectedID) {
                ForEach(pins) { row in
                    if let lat = row.facility.lat, let lon = row.facility.lon {
                        Marker(row.facility.lotId ?? row.facility.name,
                               systemImage: row.status.symbol,
                               coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon))
                            .tint(row.status.tint)
                            .tag(row.facility.id)
                    }
                }
                UserAnnotation()
            }
            .mapStyle(.standard(pointsOfInterest: .excludingAll))
            .mapControls {
                MapUserLocationButton()
                MapCompass()
                MapScaleView()
            }
            .navigationTitle("\(model.freeRows.count) free")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .sheet(item: Binding(
                get: { selectedRow.map(SheetRow.init) },
                set: { if $0 == nil { selectedID = nil } })) { wrapper in
                    NavigationStack {
                        FacilityDetailView(facility: wrapper.row.facility, model: model)
                    }
                    .presentationDetents([.medium, .large])
                }
        }
    }

    /// `sheet(item:)` needs an Identifiable value; Row's id is the facility id.
    struct SheetRow: Identifiable {
        let row: AppModel.Row
        var id: String { row.id }
    }
}
