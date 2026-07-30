import SwiftUI
import MapKit
import ParkingKit

/// One facility in full. Provenance is a real section, not fine print: if the app
/// says a lot is free, it should show what that is based on.
struct FacilityDetailView: View {
    let facility: Facility
    @Bindable var model: AppModel

    private var status: ParkingStatus { model.status(of: facility) }

    var body: some View {
        List {
            Section {
                HStack(spacing: 12) {
                    Image(systemName: status.symbol)
                        .font(.system(size: 34))
                        .foregroundStyle(status.tint)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(status.headline)
                            .font(.title2.weight(.semibold))
                        if let line = boundaryLine {
                            Text(line)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Details") {
                LabeledContent("Permit") {
                    HStack(spacing: 6) {
                        TierDot(tier: facility.tier)
                        Text(facility.tier.label)
                    }
                }
                if let lotId = facility.lotId {
                    LabeledContent("Lot number", value: lotId)
                }
                LabeledContent("Campus", value: facility.campus.label)
                if let address = facility.address, !address.isEmpty {
                    LabeledContent("Address", value: address)
                }
                if let cap = facility.capacity {
                    LabeledContent("Spaces", value: "\(cap)")
                }
                LabeledContent("Posted hours", value: facility.enforcement.raw)
            }

            Section {
                ForEach(weekDays, id: \.timeIntervalSince1970) { day in
                    HStack(spacing: 10) {
                        Text(Clock.weekday(day))
                            .font(.caption.monospaced())
                            .foregroundStyle(isSelectedDay(day) ? .primary : .secondary)
                            .frame(width: 34, alignment: .leading)
                        EnforcementRibbon(facility: facility, date: day,
                                          rules: model.rules, height: 14)
                    }
                }
            } header: {
                Text("The week")
            } footer: {
                HStack(spacing: 14) {
                    LegendSwatch(colour: .green.opacity(0.75), text: "free to all")
                    LegendSwatch(colour: .red.opacity(0.55), text: "permit or pay")
                }
            }

            if let occ = model.occupancy[facility.id] {
                Section {
                    LabeledContent("\(occ.tier.label) occupancy") {
                        Text("\(occ.percent)%")
                    }
                    ProgressView(value: Double(occ.percent), total: 100)
                        .tint(occ.percent < 60 ? .green : occ.percent < 85 ? .orange : .red)
                } header: {
                    Text("How full")
                } footer: {
                    Text("U-M estimates this from permit activity, not from counting cars, "
                         + "and says it drifts during events."
                         + (model.occupancyUpdated.map { " Updated \($0)." } ?? ""))
                }
            }

            if let lat = facility.lat, let lon = facility.lon {
                Section {
                    let centre = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                    Map(initialPosition: .region(MKCoordinateRegion(
                        center: centre,
                        span: MKCoordinateSpan(latitudeDelta: 0.004, longitudeDelta: 0.004)))) {
                            Marker(facility.lotId ?? facility.name, coordinate: centre)
                                .tint(status.tint)
                        }
                        .frame(height: 180)
                        .listRowInsets(EdgeInsets())
                    Button {
                        openInMaps(centre)
                    } label: {
                        Label("Directions", systemImage: "arrow.triangle.turn.up.right.circle")
                    }
                }
            }

            Section {
                ForEach(facility.notes, id: \.self) { note in
                    Text(note)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                LabeledContent("Transcribed", value: facility.verifiedOn)
                if let url = URL(string: facility.source) {
                    Link(destination: url) {
                        Label("Published hours", systemImage: "safari")
                    }
                }
            } header: {
                Text("Where this comes from")
            } footer: {
                Text("Signs at the entrance are the authority. Enforcement is suspended or "
                     + "changed for football games, move-in and commencement.")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(facility.lotId ?? facility.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func openInMaps(_ coordinate: CLLocationCoordinate2D) {
        let item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        item.name = facility.name
        item.openInMaps()
    }

    private var boundaryLine: String? {
        switch status {
        case .freeToAll(let until):
            guard let until else { return "No upcoming enforcement" }
            return "Until \(Clock.dayAndTime(until))"
        case .restricted(let freeAt):
            guard let freeAt else { return nil }
            return "Free at \(Clock.dayAndTime(freeAt))"
        case .allowedWithPermit(let p): return "\(p.label) permit honoured here"
        case .alwaysRestricted: return "Enforced 24 hours, every day"
        case .unknown: return "No published hours"
        }
    }

    /// The seven days of the week containing the selected date, Monday first.
    private var weekDays: [Date] {
        let weekday = model.rules.isoWeekday(model.targetDate)
        guard let monday = Clock.calendar.date(byAdding: .day, value: -(weekday - 1),
                                               to: Clock.calendar.startOfDay(for: model.targetDate))
        else { return [] }
        return (0..<7).compactMap { Clock.calendar.date(byAdding: .day, value: $0, to: monday) }
    }

    private func isSelectedDay(_ day: Date) -> Bool {
        Clock.calendar.isDate(day, inSameDayAs: model.targetDate)
    }
}

struct LegendSwatch: View {
    let colour: Color
    let text: String

    var body: some View {
        HStack(spacing: 5) {
            Capsule().fill(colour).frame(width: 10, height: 10)
            Text(text)
        }
    }
}
