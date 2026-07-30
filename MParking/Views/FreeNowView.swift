import SwiftUI
import ParkingKit

/// The main screen: a stock inset-grouped list, nearest free lot first.
struct FreeNowView: View {
    @Bindable var model: AppModel

    var body: some View {
        NavigationStack {
            List {
                timeSection
                noticeSection

                section("Free to all", model.freeRows, limit: 10,
                        footer: model.isViewingNow
                            ? "No permit, no payment. Gates are up."
                            : nil)

                section("Free within the hour", model.soonRows, limit: 5,
                        footer: model.soonRows.isEmpty ? nil : "Worth waiting for.")

                if !model.permitRows.isEmpty {
                    section("Open with your \(model.permit.label) permit",
                            model.permitRows, limit: 8, footer: nil)
                }

                section("Permit or payment", model.blockedRows, limit: 8, footer: nil)
                section("Check the sign", model.unknownRows, limit: 5,
                        footer: "U-M or the city publishes no usable hours for these.")

                aboutSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if model.isRefreshing {
                        ProgressView()
                    } else if !model.isViewingNow {
                        Button("Now") { model.returnToNow() }
                    }
                }
            }
            .refreshable { await model.refreshOccupancy() }
            .overlay {
                if model.rows.isEmpty {
                    ContentUnavailableView {
                        Label("Nothing to show", systemImage: "line.3.horizontal.decrease.circle")
                    } description: {
                        Text("Your filters in Settings are hiding every lot.")
                    }
                }
            }
        }
        .task {
            model.location.request()
            await model.refreshOccupancy()
        }
    }

    private var title: String {
        let n = model.freeRows.count
        return n == 1 ? "1 lot free" : "\(n) lots free"
    }

    // MARK: - When

    @ViewBuilder
    private var timeSection: some View {
        Section {
            DatePicker("Time",
                       selection: Binding(get: { model.targetDate },
                                          set: { model.scrub(to: $0) }),
                       in: model.scrubRange,
                       displayedComponents: [.date, .hourAndMinute])

            Picker("Jump to", selection: Binding(
                get: { model.preset },
                set: { model.apply(preset: $0) })) {
                    ForEach(AppModel.TimePreset.allCases) { preset in
                        Text(preset.label).tag(preset)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
        } header: {
            Text(model.isViewingNow ? "Now" : "Showing")
        } footer: {
            Text(model.isViewingNow
                 ? "Updating as the clock moves."
                 : "Showing \(Clock.dayAndTime(model.targetDate)).")
        }
    }

    // MARK: - Notices

    @ViewBuilder
    private var noticeSection: some View {
        if let notice {
            Section {
                switch notice {
                case .locationOff:
                    Button {
                        model.location.request()
                    } label: {
                        Label("Sort by distance", systemImage: "location.circle")
                    }
                case .locationDenied:
                    Label {
                        Text("Location is off, so lots are sorted by name. Turn it on in "
                             + "iOS Settings to sort by distance.")
                    } icon: {
                        Image(systemName: "location.slash").foregroundStyle(.secondary)
                    }
                    .font(.footnote)
                case .outOfArea:
                    Label("You are outside Ann Arbor, so distances are hidden.",
                          systemImage: "location.slash")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                case .gameDay:
                    Label {
                        Text("It's a Saturday. On a home football day, closures and "
                             + "special enforcement override everything here.")
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                    .font(.footnote)
                case .throttled(let message):
                    Label(message, systemImage: "wifi.exclamationmark")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private enum Notice: Equatable {
        case locationOff, locationDenied, outOfArea, gameDay
        case throttled(String)
    }

    private var notice: Notice? {
        if Clock.calendar.component(.weekday, from: model.targetDate) == 7 { return .gameDay }
        if model.location.isDenied { return .locationDenied }
        if model.location.isOutOfArea { return .outOfArea }
        if model.location.coordinate == nil { return .locationOff }
        if let note = model.occupancyNote { return .throttled(note) }
        return nil
    }

    // MARK: - Sections

    @ViewBuilder
    private func section(_ title: String, _ rows: [AppModel.Row],
                        limit: Int, footer: String?) -> some View {
        if !rows.isEmpty {
            Section {
                ForEach(rows.prefix(limit)) { row in
                    NavigationLink {
                        FacilityDetailView(facility: row.facility, model: model)
                    } label: {
                        FacilityRow(row: row, date: model.targetDate, rules: model.rules)
                    }
                }
                if rows.count > limit {
                    NavigationLink {
                        FacilityListView(title: title, rows: rows, model: model)
                    } label: {
                        Text("Show all \(rows.count)")
                    }
                }
            } header: {
                HStack {
                    Text(title)
                    Spacer()
                    Text("\(rows.count)")
                }
            } footer: {
                if let footer { Text(footer) }
            }
        }
    }

    // MARK: - About

    private var aboutSection: some View {
        Section {
            if model.isFiltering {
                Label(model.filterSummary, systemImage: "line.3.horizontal.decrease")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text("Entrance signs are the authority. Enforcement changes for football "
                     + "games, move-in and commencement.")
                if let d = model.dataset {
                    Text("Hours from U-M LTP and the Ann Arbor DDA, transcribed "
                         + "\(d.generated). \(d.facilities.count) facilities.")
                }
                if let updated = model.occupancyUpdated {
                    Text("Occupancy from U-M, updated \(updated).")
                }
            }
            .font(.footnote)
        }
    }
}

/// The full list behind a "Show all" row.
struct FacilityListView: View {
    let title: String
    let rows: [AppModel.Row]
    @Bindable var model: AppModel

    var body: some View {
        List(rows) { row in
            NavigationLink {
                FacilityDetailView(facility: row.facility, model: model)
            } label: {
                FacilityRow(row: row, date: model.targetDate, rules: model.rules)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
