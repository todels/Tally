import SwiftUI
import ServiceManagement

struct ContentView: View {
    @EnvironmentObject var tracker: Tracker
    @EnvironmentObject var rules: RulesStore
    @Environment(\.openWindow) private var openWindow
    @StateObject private var updater = Updater()
    @State private var now = Date()

    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().opacity(0.5)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    hero
                    splitBar
                    legend
                    VStack(alignment: .leading, spacing: 5) {
                        Text("TODAY, HOUR BY HOUR")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.tertiary)
                            .tracking(0.8)
                        DayTimeline(day: Date(),
                                    sessions: tracker.sessionsIncludingOpen(),
                                    rules: rules,
                                    compact: true)
                    }
                    breakdown
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 18)
            }
            .frame(maxHeight: 420)

            Divider().opacity(0.5)
            footer
        }
        .frame(width: 340)
        .onReceive(tick) { now = $0 }
        .onAppear { updater.check() }
    }

    private var totals: [Category: TimeInterval] { tracker.totals(rules: rules) }

    /// Everything recorded, idle included — the four categories on screen add
    /// up to exactly this.
    private var tracked: TimeInterval { totals.values.reduce(0, +) }
    private var away: TimeInterval { totals[.idle] ?? 0 }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(tracker.isIdle ? Color.secondary.opacity(0.4) : currentColor)
                .frame(width: 7, height: 7)

            Text(tracker.currentName)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)

            // Explains why you're not being marked idle while sitting still.
            if tracker.micActive {
                Image(systemName: "mic.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(Category.work.color)
                    .help("Microphone in use — idle detection paused")
            }

            Spacer(minLength: 4)

            Text(Date(), format: .dateTime.weekday(.abbreviated).day().month(.abbreviated))
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }

    private var currentColor: Color {
        guard let key = tracker.currentKey else { return .secondary }
        return rules.category(for: key).color
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(formatDuration(totals[.work] ?? 0))
                    .font(.system(size: 38, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())

                if tracked > 60 {
                    Text("\(Int(((totals[.work] ?? 0) / tracked) * 100))%")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(Category.work.color)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Category.work.color.opacity(0.14),
                                    in: Capsule())
                }
            }

            Text(tracked > 0
                 ? "focused, of \(formatDuration(tracked)) at the computer"
                 : "nothing tracked yet today")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                Image(systemName: "pin.fill")
                    .font(.system(size: 8))
                Text("In \(rules.pinnedLabel)")
                    .font(.system(size: 10, weight: .medium))
                Text(formatDuration(tracker.pinnedTotal(rules: rules)))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }
            .foregroundStyle(Category.work.color)
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(Category.work.color.opacity(0.10),
                        in: RoundedRectangle(cornerRadius: 6))
            .padding(.top, 7)
        }
    }

    // MARK: - Split bar

    private var splitBar: some View {
        GeometryReader { geo in
            HStack(spacing: 2) {
                ForEach(Category.allCases) { category in
                    let value = totals[category] ?? 0
                    if value > 0 {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(category.color)
                            .frame(width: max(3, geo.size.width * (value / max(tracked, 1))))
                    }
                }
                if tracked == 0 {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(Color.secondary.opacity(0.15))
                }
            }
        }
        .frame(height: 8)
        .animation(.easeOut(duration: 0.4), value: tracked)
    }

    private var legend: some View {
        HStack(spacing: 0) {
            ForEach(Category.allCases) { category in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Circle().fill(category.color).frame(width: 6, height: 6)
                        Text(category.label)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    Text(formatDuration(totals[category] ?? 0))
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .monospacedDigit()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    // MARK: - Breakdown

    private var breakdown: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("WHERE IT WENT")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .tracking(0.8)
                Spacer()
                Text("tap a dot to reclassify")
                    .font(.system(size: 9))
                    .foregroundStyle(.quaternary)
            }

            let rows = tracker.breakdown(rules: rules)
            if rows.isEmpty {
                Text("Start working and this fills in.")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 1) {
                    ForEach(rows.prefix(12)) { row in
                        BreakdownRowView(row: row, maximum: rows[0].duration)
                    }
                }
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 12) {
            if tracker.automationBlocked {
                Button {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
                } label: {
                    Label("Allow Dia access", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.orange)
                }
                .buttonStyle(.plain)
            } else {
                LaunchAtLoginToggle()
            }

            Spacer()

            if updater.isAvailable {
                UpdateButton(updater: updater)
            }

            Button {
                openWindow(id: "dashboard")
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Label("Open Tally", systemImage: "chart.bar.fill")
                    .font(.system(size: 10, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Category.work.color)

            Button("Quit") { NSApp.terminate(nil) }
                .buttonStyle(.plain)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
    }
}

// MARK: - Row

struct BreakdownRowView: View {
    let row: BreakdownRow
    let maximum: TimeInterval
    @EnvironmentObject var rules: RulesStore
    @State private var hovering = false

    private var category: Category { rules.category(for: row.key) }

    var body: some View {
        HStack(spacing: 9) {
            Menu {
                ForEach(Category.assignable) { option in
                    Button {
                        rules.set(option, for: row.key)
                    } label: {
                        Label(option.label, systemImage: option.symbol)
                    }
                }
                Divider()
                Button {
                    rules.pin(row.key, named: row.name)
                } label: {
                    Label("Show as headline", systemImage: "pin")
                }
                .disabled(rules.isPinned(row.key))
            } label: {
                Circle()
                    .fill(category.color)
                    .frame(width: 7, height: 7)
                    .overlay(
                        Circle()
                            .stroke(category.color.opacity(0.35), lineWidth: 4)
                            .opacity(hovering ? 1 : 0)
                    )
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 9)

            Text(row.name)
                .font(.system(size: 11.5))
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 6)

            Text(formatDuration(row.duration))
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 5)
                    .fill(category.color.opacity(hovering ? 0.14 : 0.07))
                    .frame(width: max(20, geo.size.width * (row.duration / max(maximum, 1))))
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .onHover { hovering = $0 }
    }
}

// MARK: - Login item

struct LaunchAtLoginToggle: View {
    @State private var enabled = SMAppService.mainApp.status == .enabled

    var body: some View {
        Toggle(isOn: $enabled) {
            Text("Open at login").font(.system(size: 10))
        }
        .toggleStyle(.checkbox)
        .foregroundStyle(.secondary)
        .onChange(of: enabled) { _, newValue in
            do {
                if newValue { try SMAppService.mainApp.register() }
                else { try SMAppService.mainApp.unregister() }
            } catch {
                enabled = SMAppService.mainApp.status == .enabled
            }
        }
    }
}

/// One button that changes meaning with the updater's state. Pulling and
/// rebuilding only ever happens on an explicit click — nothing is fetched or
/// installed on its own.
struct UpdateButton: View {
    @ObservedObject var updater: Updater

    var body: some View {
        Button(action: act) {
            Label(title, systemImage: symbol)
                .font(.system(size: 10, weight: weight))
        }
        .buttonStyle(.plain)
        .foregroundStyle(tint)
        .disabled(busy)
        .help(hint)
    }

    private func act() {
        switch updater.state {
        case .behind: updater.update()
        default: updater.check()
        }
    }

    private var busy: Bool {
        updater.state == .checking || updater.state == .building
    }

    private var title: String {
        switch updater.state {
        case .idle:      return "Check for updates"
        case .checking:  return "Checking…"
        case .behind:    return "Update"
        case .upToDate:  return "Up to date"
        case .building:  return "Updating…"
        case .failed:    return "Update failed"
        }
    }

    private var symbol: String {
        switch updater.state {
        case .behind:            return "arrow.down.circle.fill"
        case .checking, .building: return "arrow.triangle.2.circlepath"
        case .upToDate:          return "checkmark.circle"
        case .failed:            return "exclamationmark.triangle.fill"
        case .idle:              return "arrow.triangle.2.circlepath"
        }
    }

    private var weight: Font.Weight {
        if case .behind = updater.state { return .semibold }
        return .medium
    }

    private var tint: Color {
        switch updater.state {
        case .behind:   return Category.work.color
        case .failed:   return .orange
        case .upToDate: return .secondary
        default:        return .secondary
        }
    }

    private var hint: String {
        switch updater.state {
        case .behind(let whatsNew):
            return "\(whatsNew) — click to update and relaunch"
        case .failed(let message):
            return message
        default:
            return "Fetches with git or curl and swaps itself out. Tally never opens a network connection itself."
        }
    }
}
