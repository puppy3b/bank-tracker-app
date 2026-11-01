#if DEBUG && os(macOS)
import AppKit
import BankTrackerCore
import SwiftData
import SwiftUI

/// Debug aid: launch with `--demo --snapshot` to walk through the main screens, save a PNG
/// of the window for each (light and dark), print the folder and quit. It draws the app's
/// own window, so it works from the command line without screen-recording permission.
enum DebugSnapshots {
    static func runIfRequested(router: Router, context: ModelContext) async {
        guard ProcessInfo.processInfo.arguments.contains("--snapshot") else { return }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("snapshots", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        var shots = screens(router: router, context: context).map { (name: $0.name, show: $0.show) }
        shots.append(("new-offer-sheet", {
            router.show(.offers)
            router.isPresentingNewOffer = true
        }))

        try? await Task.sleep(for: .seconds(1))
        mainWindow?.setFrame(NSRect(x: 80, y: 80, width: 1280, height: 1000), display: true)

        for (appearance, suffix) in [(NSAppearance.Name.aqua, "light"), (.darkAqua, "dark")] {
            NSApp.appearance = NSAppearance(named: appearance)
            for shot in shots {
                await shot.show()
                try? await Task.sleep(for: .milliseconds(1200))
                capture(named: "\(shot.name)-\(suffix)", in: directory)
                router.isPresentingNewOffer = false
            }
        }
        print("SNAPSHOTS: \(directory.path)")
        fflush(stdout)
        // terminate(_:) can be deferred while a sheet is closing; the demo store is
        // in-memory, so there is nothing to save and exiting directly is safe.
        exit(0)
    }

    /// Debug aid for the README screenshots: launch with `--demo --tour` to step through the same
    /// screens as `--snapshot` in the real window, sidebar included. When each screen is ready the
    /// app prints `TOUR <name> <window id>` and holds still for a moment, so
    /// scripts/make-screenshots.sh can capture it. A few screens are shown again in dark mode.
    ///
    /// The tour never pulls itself in front of another app. If its window isn't the active one,
    /// or isn't showing the expected screen because someone used it, the tour stops with
    /// `TOUR failed: …` rather than capture the wrong thing.
    static func runTourIfRequested(router: Router, context: ModelContext) async {
        guard ProcessInfo.processInfo.arguments.contains("--tour") else { return }
        let darkScreens: Set = ["dashboard", "account-inProgress"]
        let tour = screens(router: router, context: context)

        try? await Task.sleep(for: .seconds(1))
        guard let window = mainWindow else {
            print("TOUR failed: no window")
            exit(1)
        }
        window.setFrame(NSRect(x: 80, y: 80, width: 1280, height: 960), display: true)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)

        for (appearance, suffix) in [(NSAppearance.Name.aqua, ""), (.darkAqua, "-dark")] {
            NSApp.appearance = NSAppearance(named: appearance)
            for screen in tour where suffix.isEmpty || darkScreens.contains(screen.name) {
                await screen.show()
                try? await Task.sleep(for: .milliseconds(1500))
                // An inactive window draws gray controls, so its screenshots would look wrong.
                guard window.isKeyWindow else {
                    print("TOUR failed: the window wasn't active. Run it again without using the Mac.")
                    exit(1)
                }
                guard router.selection == screen.section else {
                    print("TOUR failed: the window was used during the tour. Run it again without using the Mac.")
                    exit(1)
                }
                print("TOUR \(screen.name)\(suffix) \(window.windowNumber)")
                fflush(stdout)
                try? await Task.sleep(for: .seconds(2))
            }
        }
        print("TOUR done")
        fflush(stdout)
        exit(0)
    }

    /// Each main sidebar section (Settings reads the Keychain, so it's left out), then a few
    /// detail pages from the demo data.
    private static func screens(router: Router, context: ModelContext) -> [(name: String, section: SidebarItem, show: () async -> Void)] {
        let accounts = (try? context.fetch(FetchDescriptor<BankAccount>())) ?? []
        let offers = (try? context.fetch(FetchDescriptor<Offer>())) ?? []

        var screens: [(name: String, section: SidebarItem, show: () async -> Void)] = SidebarItem.mainItems.map { item in
            (item.rawValue, item, { router.show(item) })
        }
        for status in [BonusStatus.inProgress, .awaitingPayout] {
            if let account = accounts.first(where: { $0.isOpen && $0.snapshot.bonusStatus() == status }) {
                screens.append(("account-\(status.rawValue)", .accounts, { await push(account, in: .accounts, router: router) }))
            }
        }
        if let offer = offers.first(where: { $0.status == .considering && $0.bank?.name.hasPrefix("Harbor") == true }) {
            screens.append(("offer-detail", .offers, { await push(offer, in: .offers, router: router) }))
        }
        if let bank = offers.compactMap(\.bank).first(where: { $0.accountList.count > 1 }) {
            screens.append(("bank-detail", .banks, { await push(bank, in: .banks, router: router) }))
        }
        return screens
    }

    /// Debug aid: launch with `--demo --click-test` to click each sidebar row with
    /// synthesized mouse events and print where navigation ended up, then quit.
    static func runClickTestIfRequested(router: Router) async {
        guard ProcessInfo.processInfo.arguments.contains("--click-test") else { return }
        try? await Task.sleep(for: .seconds(1.5))
        guard let window = mainWindow else {
            print("CLICK-TEST: no window")
            exit(1)
        }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        try? await Task.sleep(for: .milliseconds(500))

        guard let sidebar = tables(in: window.contentView?.superview ?? window.contentView!)
            .min(by: { $0.convert($0.bounds, to: nil).minX < $1.convert($1.bounds, to: nil).minX })
        else {
            print("CLICK-TEST: no sidebar table")
            exit(1)
        }
        print("CLICK-TEST: sidebar rows=\(sidebar.numberOfRows) start selection=\(router.selection?.rawValue ?? "nil")")
        // The last row is Settings, which reads the Keychain; leave it out of automated runs.
        for row in (0..<sidebar.numberOfRows - 1).reversed() {
            await clickRow(row, of: sidebar, in: window)
            print("CLICK-TEST: sidebar row \(row) -> selection=\(router.selection?.rawValue ?? "nil")")
        }

        // Rows inside each section should push a detail screen.
        let sections: [(item: SidebarItem, clicks: Int)] = [(.offers, 1), (.accounts, 2), (.banks, 1)]
        for (item, clicks) in sections {
            // Sidebar clicks are covered above; switch directly (section spacer rows shift indexes).
            router.show(item)
            try? await Task.sleep(for: .milliseconds(900))
            let content = tables(in: window.contentView?.superview ?? window.contentView!).filter { $0 !== sidebar }
            if let list = content.first, list.numberOfRows > 0 {
                await clickRow(0, of: list, in: window, clicks: clicks)
                print("CLICK-TEST: \(item.rawValue) row 0 (\(clicks) click) -> selection=\(router.selection?.rawValue ?? "nil") pathCount=\(router.path.count)")
            } else {
                // Not a table (e.g. a grid of cards): click down the content area until something opens.
                let left = sidebar.convert(sidebar.bounds, to: nil).maxX + 120
                var y = window.contentLayoutRect.maxY - 30
                while router.path.isEmpty, y > window.contentLayoutRect.maxY - 400 {
                    click(at: NSPoint(x: left, y: y), in: window)
                    try? await Task.sleep(for: .milliseconds(500))
                    y -= 25
                }
                print("CLICK-TEST: \(item.rawValue) first card -> selection=\(router.selection?.rawValue ?? "nil") pathCount=\(router.path.count)")
            }
        }
        fflush(stdout)
        exit(0)
    }

    /// Debug aid: `--demo --ai-fill-test --ai-fill-source <text or link>` opens a new offer,
    /// lets the editor fill it with AI, saves a picture of the sheet and quits.
    static func runAIFillTestIfRequested(router: Router) async {
        guard ProcessInfo.processInfo.arguments.contains("--ai-fill-test") else { return }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("snapshots", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? await Task.sleep(for: .seconds(1))
        router.show(.offers)
        router.isPresentingNewOffer = true
        try? await Task.sleep(for: .seconds(8))
        if let sheet = mainWindow?.attachedSheet {
            sheet.setContentSize(NSSize(width: 640, height: 1300))
            try? await Task.sleep(for: .milliseconds(800))
        }
        capture(named: "ai-fill-sheet", in: directory)
        print("AI-FILL-TEST: captured \(directory.path)")
        fflush(stdout)
        exit(0)
    }

    /// Debug aid: `--keychain-test` saves, reads, updates and deletes a throwaway Keychain item.
    static func runKeychainTestIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("--keychain-test") else { return }
        let account = "debug-keychain-test"
        let saved = Keychain.save("first-value", account: account)
        let read = Keychain.read(account: account) == "first-value"
        let updated = Keychain.save("second-value", account: account)
        let reread = Keychain.read(account: account) == "second-value"
        let deleted = Keychain.save("", account: account)
        let gone = Keychain.read(account: account) == nil
        print("KEYCHAIN-TEST: saved=\(saved) read=\(read) updated=\(updated) reread=\(reread) deleted=\(deleted) gone=\(gone)")
        fflush(stdout)
        exit(0)
    }

    /// Debug aid: `--ai-settings-test` checks that AI settings persist changes, and only
    /// changes, using a throwaway defaults domain.
    static func runAISettingsTestIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("--ai-settings-test") else { return }
        let suite = "com.zibin.BankTracker.debug-ai-settings-test"
        guard let defaults = UserDefaults(suiteName: suite) else { exit(1) }
        defaults.removePersistentDomain(forName: suite)

        let first = AISettings(defaults: defaults)
        let untouched = defaults.dictionaryRepresentation().keys.filter { $0.hasPrefix("ai.") }.isEmpty
        first.provider = .gemini
        first.model = "gemini-2.5-pro"
        first.provider = .openAICompatible
        first.baseURL = "http://localhost:11434/v1"
        first.model = "llama3.1"
        first.provider = .gemini

        let second = AISettings(defaults: defaults)
        print("AI-SETTINGS-TEST: initNoWrites=\(untouched) provider=\(second.provider?.rawValue ?? "nil") model=\(second.model) baseURL=\(second.baseURL) compatibleModel=\(defaults.string(forKey: "ai.model.openAICompatible") ?? "nil") problem=\(second.setupProblem ?? "none")")
        fflush(stdout)
        // exit(0) skips `defer`, so clean up explicitly.
        defaults.removePersistentDomain(forName: suite)
        let file = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences/\(suite).plist")
        try? FileManager.default.removeItem(at: file)
        exit(0)
    }

    private static func clickRow(_ row: Int, of table: NSTableView, in window: NSWindow, clicks: Int = 1) async {
        let rect = table.convert(table.rect(ofRow: row), to: nil)
        for count in 1...clicks {
            click(at: NSPoint(x: rect.midX, y: rect.midY), in: window, clickCount: count)
        }
        try? await Task.sleep(for: .milliseconds(900))
    }

    private static func tables(in view: NSView) -> [NSTableView] {
        var result: [NSTableView] = []
        if let table = view as? NSTableView { result.append(table) }
        for subview in view.subviews { result += tables(in: subview) }
        return result
    }

    private static func click(at point: NSPoint, in window: NSWindow, clickCount: Int = 1) {
        let time = ProcessInfo.processInfo.systemUptime
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            if let event = NSEvent.mouseEvent(
                with: type, location: point, modifierFlags: [], timestamp: time,
                windowNumber: window.windowNumber, context: nil, eventNumber: 0,
                clickCount: clickCount, pressure: type == .leftMouseDown ? 1 : 0
            ) {
                NSApp.postEvent(event, atStart: false)
            }
        }
    }

    private static func push(_ value: some Hashable, in section: SidebarItem, router: Router) async {
        router.show(section)
        // Let the section switch (which clears the path) settle before pushing.
        try? await Task.sleep(for: .milliseconds(500))
        router.push(value)
    }

    private static var mainWindow: NSWindow? {
        NSApp.windows.first { $0.isVisible && !$0.isSheet && $0.frame.width > 600 }
    }

    private static func capture(named name: String, in directory: URL) {
        guard let window = mainWindow else { return }
        let target = window.attachedSheet ?? window
        guard let view = target.contentView?.superview ?? target.contentView,
              let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)
        else { return }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        try? bitmap.representation(using: .png, properties: [:])?
            .write(to: directory.appendingPathComponent("\(name).png"))
    }
}
#endif
