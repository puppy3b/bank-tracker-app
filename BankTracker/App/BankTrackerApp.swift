import SwiftUI
import SwiftData

@main
struct BankTrackerApp: App {
    @State private var router = Router()
    private let container: ModelContainer

    init() {
        // `--demo` runs on a throwaway in-memory store filled with sample data.
        let isDemo = ProcessInfo.processInfo.arguments.contains("--demo")
        do {
            container = try AppDataStore.makeContainer(inMemory: isDemo)
        } catch {
            fatalError("Couldn't open the Bank Tracker data store: \(error)")
        }
        if isDemo {
            SampleData.load(into: container.mainContext)
        }
        ReminderNotifications.shared.install()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(router)
        }
        .modelContainer(container)
        #if os(macOS)
        .defaultSize(width: 1180, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Offer…") { router.isPresentingNewOffer = true }
                    .keyboardShortcut("n")
                Button("New Account…") { router.isPresentingNewAccount = true }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
            }
            // ⌘, opens the Settings page in the main window rather than a separate window.
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { router.show(.settings) }
                    .keyboardShortcut(",")
            }
            CommandMenu("Go") {
                ForEach(Array(SidebarItem.mainItems.enumerated()), id: \.element) { index, item in
                    Button(item.title) { router.show(item) }
                        .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                }
            }
        }
        #endif
    }
}
