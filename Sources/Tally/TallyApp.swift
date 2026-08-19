import SwiftUI
import AppKit

@main
struct TallyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var rules = RulesStore()
    @StateObject private var tracker = Tracker()

    var body: some Scene {
        // The real window. Closing it does not quit — tracking continues.
        Window("Tally", id: "dashboard") {
            DashboardView()
                .environmentObject(tracker)
                .environmentObject(rules)
        }
        .defaultSize(width: 780, height: 640)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }

        // The glance. Same data, always one click away.
        MenuBarExtra {
            ContentView()
                .environmentObject(tracker)
                .environmentObject(rules)
        } label: {
            MenuBarLabel()
                .environmentObject(tracker)
                .environmentObject(rules)
        }
        .menuBarExtraStyle(.window)
    }
}

/// Focus time, always visible. The icon follows whatever you're doing right now,
/// so a glance tells you whether you're on task.
struct MenuBarLabel: View {
    @EnvironmentObject var tracker: Tracker
    @EnvironmentObject var rules: RulesStore
    @State private var now = Date()

    private let tick = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    var body: some View {
        let focus = tracker.totals(rules: rules)[.work] ?? 0
        HStack(spacing: 4) {
            Image(systemName: symbol)
            Text(formatDuration(focus, style: .compact))
                .monospacedDigit()
        }
        .onReceive(tick) { now = $0 }
    }

    private var symbol: String {
        if tracker.isIdle { return "moon.zzz" }
        guard let key = tracker.currentKey else { return "circle.dashed" }
        switch rules.category(for: key) {
        case .work: return "circle.fill"
        case .distraction: return "exclamationmark.triangle.fill"
        case .neutral: return "circle"
        case .idle: return "moon.zzz"
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Closing the window must not stop the clock.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Clicking the Dock icon brings the dashboard back.
    func applicationShouldHandleReopen(_ sender: NSApplication,
                                       hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            for window in sender.windows where window.canBecomeMain {
                window.makeKeyAndOrderFront(nil)
                return true
            }
        }
        return true
    }
}
