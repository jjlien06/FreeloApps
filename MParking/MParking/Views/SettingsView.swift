import SwiftUI
import ParkingKit

struct SettingsView: View {
    @Bindable var model: AppModel

    var body: some View {
        NavigationStack {
            settingsForm
        }
    }

    private var settingsForm: some View {
        Form {
            Section {
                Picker("Your permit", selection: $model.permit) {
                    ForEach(PermitClass.allCases) { permit in
                        Text(permit.label).tag(permit)
                    }
                }
            } header: {
                Text("Permit")
            } footer: {
                Text(model.permit == .afterHours
                     ? "After Hours permits are honoured in Blue, Yellow and Orange areas "
                       + "— never Gold — from 3pm to 5am on weekdays and all weekend."
                     : "Changes what counts as usable. A lot that needs a permit is still "
                       + "not free — it just stops being a dead end for you.")
            }

            Section {
                Toggle("Hide lots that are never free", isOn: $model.hideNeverFree)
            } footer: {
                Text("\(model.neverFreeCount) lots are enforced 24 hours a day, every day, "
                     + "so they never open up to anyone without a permit.")
            }

            Section {
                ForEach(model.availableTiers, id: \.self) { tier in
                    Toggle(isOn: Binding(
                        get: { model.includesTier(tier) },
                        set: { _ in model.toggleTier(tier) })) {
                            HStack {
                                Label {
                                    Text(tier.label)
                                } icon: {
                                    Image(systemName: "circle.fill")
                                        .foregroundStyle(tier.colour)
                                }
                                Spacer()
                                Text("\(model.count(of: tier))")
                                    .foregroundStyle(.secondary)
                            }
                        }
                }
            } header: {
                Text("Pass colours")
            } footer: {
                Text(model.tierFilter.isEmpty
                     ? "Showing every colour."
                     : "Showing \(model.tierFilter.count) of \(model.availableTiers.count) colours.")
            }

            Section("Parking systems") {
                ForEach(ParkingSystem.allCases, id: \.self) { system in
                    Toggle(system == .umich ? "U-M lots and structures"
                                            : "Downtown city parking",
                           isOn: Binding(
                            get: { model.systemFilter.contains(system) },
                            set: { on in
                                var next = model.systemFilter
                                if on { next.insert(system) } else { next.remove(system) }
                                // Never let every system be switched off - an empty
                                // screen is not a useful state to be able to reach.
                                if !next.isEmpty { model.systemFilter = next }
                            }))
                }
            }

            Section("Campuses") {
                ForEach(Campus.allCases, id: \.self) { campus in
                    Toggle(campus.label, isOn: Binding(
                        get: { model.campusFilter.contains(campus) },
                        set: { on in
                            var next = model.campusFilter
                            if on { next.insert(campus) } else { next.remove(campus) }
                            if !next.isEmpty { model.campusFilter = next }
                        }))
                }
            }

            Section {
                Button("Reset filters") { model.resetFilters() }
                    .disabled(!model.isFiltering)
            }

            Section {
                if let d = model.dataset {
                    LabeledContent("Facilities", value: "\(d.facilities.count)")
                    LabeledContent("Hours transcribed", value: d.generated)
                    LabeledContent("Time zone", value: d.timeZone)
                }
                Link(destination: URL(string: "https://ltp.umich.edu/parking/locations-and-enforcement/")!) {
                    Label("U-M enforcement hours", systemImage: "safari")
                }
                Link(destination: URL(string: "https://www.a2dda.org/parking-rates/")!) {
                    Label("Ann Arbor DDA rates", systemImage: "safari")
                }
            } header: {
                Text("Data")
            } footer: {
                Text("Enforcement hours ship with the app, so it works without a signal — "
                     + "but they go stale when U-M changes a lot. Occupancy is fetched live "
                     + "and is U-M's own estimate from permit activity, not a count of cars.")
            }
        }
        .navigationTitle("Settings")
    }
}
