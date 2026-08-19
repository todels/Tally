import AppKit
import SwiftUI

/// Watches what you're actually doing and turns it into sessions.
///
/// Everything here is local: the frontmost app comes from AppKit, the front tab
/// comes from an Apple event to Dia, and idle time comes from the HID system.
/// Nothing leaves the machine.
@MainActor
final class Tracker: ObservableObject {

    /// Only Dia is ever scripted. Other browsers are tracked as plain apps.
    static let browserBundleID = "company.thebrowser.dia"

    /// Count as idle after this long without a keystroke or mouse move.
    private let idleThreshold: TimeInterval = 300

    /// While the microphone is live you're on a call, and sitting still is not
    /// the same as being away. The ceiling still exists so an app that holds the
    /// mic open — Discord in a voice channel, say — can't log a whole night.
    private let micIdleThreshold: TimeInterval = 7200

    /// Ignore blips shorter than this, so alt-tabbing doesn't shred the timeline.
    private let minimumSession: TimeInterval = 3

    @Published private(set) var sessions: [Session] = []
    @Published private(set) var isIdle = false
    @Published private(set) var micActive = false
    @Published private(set) var automationBlocked = false
    @Published private(set) var currentKey: RuleKey?
    @Published private(set) var currentName: String = "—"

    /// If this long passes between ticks, the machine wasn't running — asleep,
    /// locked, or suspended. Comfortably above normal timer jitter, far below
    /// any real sleep.
    private let maxTickGap: TimeInterval = 15

    private var open: Session?
    private var timer: Timer?
    private var day = Calendar.current.startOfDay(for: Date())
    private var lastTick = Date()

    private var lastURLFetch = Date.distantPast
    private var cachedHost: String?
    private let urlRefresh: TimeInterval = 3

    /// Keeps App Nap from throttling the poll loop when the window is closed,
    /// while still letting the Mac sleep normally when you walk away.
    private var activity: NSObjectProtocol?

    init() {
        sessions = Store.load(day: Date())
        activity = ProcessInfo.processInfo.beginActivity(
            options: .userInitiatedAllowingIdleSystemSleep,
            reason: "Tracking active application time")
        observePowerEvents()
        start()
    }

    func start() {
        timer?.invalidate()
        let t = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
        tick()
    }

    // MARK: - The loop

    private func tick() {
        // If ticks stopped for a while, the Mac was asleep or suspended. Close
        // the open session at the last moment we know it was awake rather than
        // stretching it silently across the gap. This is the safety net that
        // catches sleep even if the notifications below never arrive.
        let previousTick = lastTick
        lastTick = Date()
        if lastTick.timeIntervalSince(previousTick) > maxTickGap {
            flush(at: previousTick)
            isIdle = false
        }

        rolloverIfNeeded()

        let now = Date()
        let idle = Self.secondsSinceLastInput()

        // The single number this app reads about your input: how many seconds
        // since the last event. Not which key, not what text, not where.
        let lastInput = now.addingTimeInterval(-idle)

        micActive = Microphone.isInUse()
        let threshold = micActive ? micIdleThreshold : idleThreshold

        if idle > threshold {
            if !isIdle {
                // Close the app session where input actually stopped, then open
                // an idle session covering the same moment onwards.
                flush(at: lastInput)
                isIdle = true
                open = Session(start: lastInput, end: now,
                               app: Idle.name, bundleID: Idle.bundleID, host: nil)
            } else {
                open?.end = now
            }
            currentKey = nil
            currentName = Idle.name
            objectWillChange.send()
            return
        }

        if isIdle {
            // Input came back — close the idle stretch at that exact second.
            flush(at: lastInput)
            isIdle = false
        }

        guard let front = NSWorkspace.shared.frontmostApplication,
              let bundleID = front.bundleIdentifier else { return }
        let appName = front.localizedName ?? bundleID

        var host: String?

        if bundleID == Self.browserBundleID {
            refreshBrowserTabIfStale()
            host = cachedHost
        } else {
            cachedHost = nil
            lastURLFetch = .distantPast
        }

        let sameAsOpen = open.map { $0.bundleID == bundleID && $0.host == host } ?? false

        if sameAsOpen {
            open?.end = now
        } else {
            flush(at: now)
            open = Session(start: now, end: now, app: appName,
                           bundleID: bundleID, host: host)
        }

        currentKey = host.map { RuleKey.host($0) } ?? .app(bundleID)
        currentName = host ?? appName
        objectWillChange.send()
    }

    /// Ends the open session and commits it to disk.
    private func flush(at end: Date) {
        guard var session = open else { return }
        open = nil
        session.end = max(session.start, end)
        guard session.duration >= minimumSession else { return }
        Store.append(session)
        sessions.append(session)
    }

    private func rolloverIfNeeded() {
        let today = Calendar.current.startOfDay(for: Date())
        guard today != day else { return }
        flush(at: Date())
        day = today
        sessions = Store.load(day: Date())
    }

    // MARK: - Sleep, wake and locking

    /// macOS tells us before it sleeps, which lets the clock stop at the right
    /// second instead of relying on the gap guard to clean up afterwards.
    private func observePowerEvents() {
        let workspace = NSWorkspace.shared.notificationCenter
        for name: NSNotification.Name in [
            NSWorkspace.willSleepNotification,          // lid shut, Sleep menu
            NSWorkspace.screensDidSleepNotification,    // display off
            NSWorkspace.sessionDidResignActiveNotification, // fast user switch
        ] {
            workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.suspend() }
            }
        }

        workspace.addObserver(forName: NSWorkspace.didWakeNotification,
                              object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.resume() }
        }

        // Screen lock isn't a workspace notification, it's a distributed one.
        let distributed = DistributedNotificationCenter.default()
        distributed.addObserver(forName: .init("com.apple.screenIsLocked"),
                                object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.suspend() }
        }
        distributed.addObserver(forName: .init("com.apple.screenIsUnlocked"),
                                object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.resume() }
        }
    }

    /// Stop the clock now and bank whatever was open.
    private func suspend() {
        flush(at: Date())
        isIdle = true
        currentKey = nil
        currentName = "Away"
    }

    /// Start fresh. `lastTick` is reset first so the gap guard doesn't fire on
    /// a session that was already closed cleanly on the way down.
    private func resume() {
        lastTick = Date()
        tick()
    }

    // MARK: - Dia

    private func refreshBrowserTabIfStale() {
        guard Date().timeIntervalSince(lastURLFetch) >= urlRefresh else { return }
        lastURLFetch = Date()

        Task.detached(priority: .utility) {
            let result = DiaBridge.frontTab()
            await MainActor.run {
                switch result {
                case .success(let host):
                    self.automationBlocked = false
                    self.cachedHost = host
                case .blocked:
                    self.automationBlocked = true
                    self.cachedHost = nil
                case .unavailable:
                    self.cachedHost = nil
                }
            }
        }
    }

    // MARK: - Idle

    private static func secondsSinceLastInput() -> TimeInterval {
        guard let any = CGEventType(rawValue: ~0) else { return 0 }
        return CGEventSource.secondsSinceLastEventType(.hidSystemState, eventType: any)
    }

    // MARK: - Reading the day

    /// Sessions plus the still-running one, so the UI counts live.
    func sessionsIncludingOpen() -> [Session] {
        var all = sessions
        if var live = open {
            live.end = Date()
            if live.duration > 0 { all.append(live) }
        }
        return all
    }

    func totals(rules: RulesStore) -> [Category: TimeInterval] {
        var out: [Category: TimeInterval] = [.work: 0, .distraction: 0, .neutral: 0]
        for s in sessionsIncludingOpen() {
            out[rules.category(for: s.ruleKey), default: 0] += s.duration
        }
        return out
    }

    /// Live total for the pinned app — Figma unless you've changed it.
    func pinnedTotal(rules: RulesStore) -> TimeInterval {
        let key = rules.pinnedKey
        return sessionsIncludingOpen()
            .filter { $0.ruleKey == key }
            .reduce(0) { $0 + $1.duration }
    }

    /// Everything you touched today, biggest first, merged by app or site.
    /// Idle is left out — it isn't a place you spent time.
    func breakdown(rules: RulesStore) -> [BreakdownRow] {
        var totals: [RuleKey: BreakdownRow] = [:]
        for s in sessionsIncludingOpen() where s.bundleID != Idle.bundleID {
            let key = s.ruleKey
            if var existing = totals[key] {
                existing.duration += s.duration
                totals[key] = existing
            } else {
                totals[key] = BreakdownRow(key: key,
                                           name: s.displayName,
                                           duration: s.duration)
            }
        }
        return totals.values
            .sorted { $0.duration > $1.duration }
            .filter { $0.duration >= 10 }
    }
}

struct BreakdownRow: Identifiable {
    let key: RuleKey
    let name: String
    var duration: TimeInterval
    var id: RuleKey { key }
}
