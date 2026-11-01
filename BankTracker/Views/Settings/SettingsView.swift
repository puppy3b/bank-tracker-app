import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import BankTrackerCore

struct SettingsView: View {
    @AppStorage(SettingsKey.residenceState) private var residenceState = ""
    @Query(sort: \Offer.foundDate, order: .reverse) private var offers: [Offer]
    @Environment(\.modelContext) private var context
    @State private var exportDocument: BackupDocument?
    @State private var showingExporter = false
    @State private var showingImporter = false
    @State private var pendingImport: BackupFile?
    @State private var confirmingDeleteAll = false
    @State private var message: String?

    var body: some View {
        Form {
            Section {
                Picker(selection: $residenceState) {
                    Text("Not set").tag("")
                    Divider()
                    ForEach(USState.all) { state in
                        Text("\(state.name) (\(state.code))").tag(state.code)
                    }
                } label: {
                    Label("State of residence", systemImage: "house")
                }
            } header: {
                FormSectionHeader(page: "Settings", subtitle: "Your state, reminders, AI filling, backups and data", section: "Where you live")
            } footer: {
                Text(residenceFooter)
            }

            let limited = stateLimitedOffers
            if !limited.isEmpty {
                Section("Offers with a state limit") {
                    ForEach(limited, id: \.offer.persistentModelID) { item in
                        NavigationLink(value: item.offer) {
                            StateLimitRow(offer: item.offer, states: item.states, residenceState: residenceState)
                        }
                    }
                }
            }

            ReminderSettingsSection()

            AISettingsSection()

            Section {
                Button("Export Backup…", systemImage: "square.and.arrow.up") { export() }
                Button("Import Backup…", systemImage: "square.and.arrow.down") { showingImporter = true }
            } header: {
                Text("Backup")
            } footer: {
                Text("Your data is stored only on this device. Export a backup now and then; importing one replaces everything in the app.")
            }

            Section("Data") {
                Button("Load Sample Data", systemImage: "wand.and.stars") {
                    SampleData.load(into: context)
                    message = "Sample banks, offers and accounts were added."
                }
                Button("Delete All Data…", systemImage: "trash", role: .destructive) {
                    confirmingDeleteAll = true
                }
            }
        }
        .formStyle(.grouped)
        .groundBackground()
        .navigationTitle("Settings")
        .hidesToolbarTitle()
        .fileExporter(
            isPresented: $showingExporter,
            document: exportDocument,
            contentType: .json,
            defaultFilename: "Bank Tracker Backup \(Date.now.formatted(.iso8601.year().month().day()))"
        ) { result in
            if case .failure(let error) = result {
                message = "Export failed: \(error.localizedDescription)"
            }
        }
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.json]) { result in
            switch result {
            case .success(let url):
                do {
                    let accessing = url.startAccessingSecurityScopedResource()
                    defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                    pendingImport = try BackupService.decode(Data(contentsOf: url))
                } catch {
                    message = "That file isn't a Bank Tracker backup: \(error.localizedDescription)"
                }
            case .failure(let error):
                message = "Import failed: \(error.localizedDescription)"
            }
        }
        .confirmationDialog(
            "Replace all data with this backup?",
            isPresented: Binding(get: { pendingImport != nil }, set: { if !$0 { pendingImport = nil } }),
            presenting: pendingImport
        ) { backup in
            Button("Replace All Data", role: .destructive) { restore(backup) }
        } message: { backup in
            Text("The backup from \(DateText.format(backup.exportedAt)) has \(backup.accounts.count) accounts and \(backup.offers.count) offers. Everything currently in the app will be replaced.")
        }
        .confirmationDialog("Delete all data?", isPresented: $confirmingDeleteAll) {
            Button("Delete Everything", role: .destructive) {
                do {
                    try BackupService.deleteAll(in: context)
                    message = "All data was deleted."
                } catch {
                    message = "Couldn't delete: \(error.localizedDescription)"
                }
            }
        } message: {
            Text("This removes every bank, offer, account and tax checklist item. Export a backup first if you might want it back.")
        }
        .alert("Bank Tracker", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("OK") { message = nil }
        } message: {
            Text(message ?? "")
        }
    }

    private func export() {
        do {
            exportDocument = BackupDocument(data: try BackupService.makeBackup(context: context, residenceState: residenceState))
            showingExporter = true
        } catch {
            message = "Export failed: \(error.localizedDescription)"
        }
    }

    private func restore(_ backup: BackupFile) {
        do {
            try BackupService.restore(backup, into: context)
            if let state = backup.residenceState { residenceState = state }
            message = "Backup restored."
        } catch {
            message = "Restore failed: \(error.localizedDescription)"
        }
    }

    private var residenceFooter: String {
        guard let name = USState.name(for: residenceState) else {
            return "Some offers are only open to residents of certain states. Until you set your state, those offers are marked for you to check yourself."
        }
        return "Offers limited to certain states are checked against \(name)."
    }

    /// Offers you're considering that are limited to certain states, with the allowed states.
    private var stateLimitedOffers: [(offer: Offer, states: [String])] {
        offers.compactMap { offer in
            guard offer.status == .considering, !offer.isExpired else { return nil }
            let states = offer.eligibilityRules
                .filter { $0.kind == .stateRestriction }
                .flatMap(\.states)
            return states.isEmpty ? nil : (offer, states)
        }
    }
}

private struct StateLimitRow: View {
    let offer: Offer
    let states: [String]
    let residenceState: String

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(offer.title)
                Text("Only for residents of \(states.joined(separator: ", "))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            badge
        }
    }

    @ViewBuilder
    private var badge: some View {
        if residenceState.isEmpty {
            StatusBadge(text: "Set your state", systemImage: "questionmark.circle", tint: .secondary)
        } else if states.contains(residenceState) {
            StatusBadge(text: "Available in \(residenceState)", systemImage: "checkmark.circle.fill", tint: Palette.good)
        } else {
            StatusBadge(text: "Not in \(residenceState)", systemImage: "xmark.circle.fill", tint: Palette.critical)
        }
    }
}
