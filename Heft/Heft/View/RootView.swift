import Photos
import SwiftUI
import UniformTypeIdentifiers

struct RootView: View {
    @Environment(LibraryModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    @State private var isPickingFolder = false

    private var hasAccess: Bool {
        model.status == .authorized || model.status == .limited
    }

    var body: some View {
        NavigationStack {
            Group {
                switch model.status {
                case .authorized, .limited:
                    PhotoGridView()
                case .notDetermined:
                    ProgressView().controlSize(.large)
                default:
                    PermissionGateView()
                }
            }
            .navigationTitle("Heft")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
        }
        .task { await model.start() }
        // A drive can be pulled while the app is backgrounded, so re-test on return.
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { model.destination.refresh() }
        }
        .fileImporter(
            isPresented: $isPickingFolder,
            allowedContentTypes: [.folder]
        ) { result in
            if case let .success(url) = result {
                model.destination.adopt(url)
            }
        }
        .sheet(isPresented: exportSheetBinding) {
            ExportSheet()
        }
        .sheet(isPresented: conversionSheetBinding) {
            ConversionSheet()
        }
        .alert("Something went wrong", isPresented: errorBinding) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            if hasAccess { optionsMenu }
        }
        ToolbarItem(placement: .topBarTrailing) {
            if hasAccess { selectionButton }
        }
    }

    private var optionsMenu: some View {
        Menu {
            Picker("Sort", selection: sortBinding) {
                ForEach(SortOrder.allCases) { order in
                    Label(order.label, systemImage: order.symbol).tag(order)
                }
            }
            Divider()
            Picker("Show", selection: filterBinding) {
                ForEach(MediaFilter.allCases) { media in
                    Text(media.label).tag(media)
                }
            }
            Divider()
            Section("Export destination") {
                Button(
                    model.destination.url == nil ? "Choose folder…" : "Change folder…",
                    systemImage: "folder.badge.plus"
                ) {
                    isPickingFolder = true
                }
                if let name = model.destination.displayName {
                    Button(
                        "Forget “\(name)”",
                        systemImage: "xmark.circle",
                        role: .destructive
                    ) {
                        model.destination.forget()
                    }
                }
            }
            Divider()
            Button("Rescan sizes", systemImage: "arrow.clockwise") {
                Task { await model.rescan() }
            }
        } label: {
            Label("Options", systemImage: "line.3.horizontal.decrease.circle")
        }
    }

    private var selectionButton: some View {
        Button(model.isSelecting ? "Done" : "Select") {
            withAnimation {
                if model.isSelecting { model.exitSelection() } else { model.beginSelection() }
            }
        }
    }

    private var sortBinding: Binding<SortOrder> {
        Binding(get: { model.sort }, set: { model.setSort($0) })
    }

    private var filterBinding: Binding<MediaFilter> {
        Binding(get: { model.filter }, set: { model.setFilter($0) })
    }

    private var exportSheetBinding: Binding<Bool> {
        Binding(
            get: { model.exportRun != nil },
            set: { if !$0 { model.dismissExportSummary() } }
        )
    }

    private var conversionSheetBinding: Binding<Bool> {
        Binding(
            get: { model.conversionRun != nil },
            set: { if !$0 { model.dismissConversionSummary() } }
        )
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )
    }
}
