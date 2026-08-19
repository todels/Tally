import SwiftUI
import Charts

/// The main window — the thing you open when you want to actually read your week.
struct DashboardView: View {
    @EnvironmentObject var tracker: Tracker
    @EnvironmentObject var rules: RulesStore
    @StateObject private var history = History()

    @State private var period: Period = .week
    @State private var anchor = Date()
    @State private var now = Date()

    private let tick = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    private var data: PeriodData {
        history.aggregate(period: period, anchor: anchor, rules: rules, tracker: tracker)
    }

    var body: some View {
        let data = self.data

        VStack(alignment: .leading, spacing: 0) {
            toolbar
            Divider().opacity(0.4)

            ScrollView {
                VStack(alignment: .leading, spacing: 26) {
                    navigator
                    hero(data)

                    // The day view always draws its timeline, even for an empty
                    // day — an empty track is the answer to "was I at the
                    // machine?", not a missing view.
                    if data.tracked < 60 && period != .day {
                        emptyState
                    } else {
                        chart(data)
                        if data.rows.isEmpty {
                            emptyState
                        } else {
                            breakdown(data)
                        }
                    }
                }
                .padding(28)
            }
        }
        .frame(minWidth: 700, minHeight: 560)
        .background(Color(nsColor: .windowBackgroundColor))
        .onReceive(tick) { now = $0 }
        .onChange(of: rules.rules.apps) { _, _ in }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack {
            HStack(spacing: 7) {
                Circle()
                    .fill(Category.work.color)
                    .frame(width: 9, height: 9)
                Text("Tally")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
            }

            Spacer()

            Picker("", selection: $period) {
                ForEach(Period.allCases) { Text($0.label).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 210)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
    }

    // MARK: - Date navigation

    private var canGoForward: Bool {
        !Calendar.current.isDate(anchor, equalTo: Date(),
                                 toGranularity: period.calendarComponent)
    }

    private var navigator: some View {
        HStack(spacing: 12) {
            Button { anchor = period.shift(anchor, by: -1) } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Text(period.title(for: anchor))
                .font(.system(size: 13, weight: .medium))
                .frame(minWidth: 130, alignment: .leading)

            Button { anchor = period.shift(anchor, by: 1) } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.plain)
            .foregroundStyle(canGoForward ? .secondary : .quaternary)
            .disabled(!canGoForward)

            if !Calendar.current.isDate(anchor, equalTo: Date(),
                                        toGranularity: period.calendarComponent) {
                Button("Today") { anchor = Date() }
                    .buttonStyle(.plain)
                    .font(.system(size: 11))
                    .foregroundStyle(Category.work.color)
            }

            Spacer()
        }
    }

    // MARK: - Hero

    private func hero(_ data: PeriodData) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 40) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(formatDuration(data.focus))
                            .font(.system(size: 46, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .contentTransition(.numericText())

                        if data.tracked > 60 {
                            Text("\(Int(data.focusShare * 100))%")
                                .font(.system(size: 15, weight: .medium, design: .rounded))
                                .foregroundStyle(Category.work.color)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Category.work.color.opacity(0.14), in: Capsule())
                        }
                    }
                    Text(data.tracked > 60
                         ? "focused, of \(formatDuration(data.tracked)) at the computer"
                         : "focused")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                if data.tracked > 60 {
                    stat("Drain", formatDuration(data.totals[.distraction] ?? 0),
                         Category.distraction.color)
                    stat("Other", formatDuration(data.totals[.neutral] ?? 0),
                         Category.neutral.color)
                    stat("Idle", formatDuration(data.away), Category.idle.color)
                    if period != .day {
                        stat("Avg / active day", formatDuration(data.dailyAverage), .secondary)
                    }
                }

                Spacer()
            }

            pinnedCard(data)
        }
    }

    /// The "how long was I actually in Figma" number, called out on its own
    /// because it answers a different question than focus time does.
    private func pinnedCard(_ data: PeriodData) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "pin.fill")
                .font(.system(size: 11))
                .foregroundStyle(Category.work.color)

            VStack(alignment: .leading, spacing: 2) {
                Text("In \(rules.pinnedLabel)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(formatDuration(data.pinned))
                    .font(.system(size: 26, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }

            if data.focus > 60 {
                VStack(alignment: .leading, spacing: 5) {
                    Text("\(Int(data.pinnedShareOfFocus * 100))% of focused time")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)

                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Category.work.color.opacity(0.15))
                            Capsule()
                                .fill(Category.work.color)
                                .frame(width: max(3, geo.size.width * data.pinnedShareOfFocus))
                        }
                    }
                    .frame(height: 6)
                }
                .frame(maxWidth: 220)
                .padding(.leading, 6)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 13)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Category.work.color.opacity(0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(Category.work.color.opacity(0.18), lineWidth: 1)
                )
        )
    }

    private func stat(_ label: String, _ value: String, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 5) {
                Circle().fill(color).frame(width: 6, height: 6)
                Text(label)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.system(size: 20, weight: .medium, design: .rounded))
                .monospacedDigit()
        }
        .padding(.top, 6)
    }

    // MARK: - Chart

    @ViewBuilder
    private func chart(_ data: PeriodData) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel(period == .day ? "MIDNIGHT TO MIDNIGHT" : "BY DAY")

            if period == .day {
                DayTimeline(day: anchor, sessions: data.sessions, rules: rules)
            } else {
                Chart {
                    ForEach(data.days) { day in
                        ForEach(Category.allCases) { category in
                            BarMark(
                                x: .value("Day", day.date, unit: .day),
                                y: .value("Hours", (day.totals[category] ?? 0) / 3600)
                            )
                            .foregroundStyle(category.color)
                            .cornerRadius(2)
                        }
                    }
                }
                .chartLegend(.hidden)
                .chartXAxis {
                    AxisMarks(values: .stride(by: .day,
                                              count: period == .month ? 5 : 1)) { _ in
                        AxisValueLabel(
                            format: period == .month
                                ? Date.FormatStyle.dateTime.day()
                                : Date.FormatStyle.dateTime.weekday(.narrow)
                        )
                        .font(.system(size: 9))
                    }
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { value in
                        AxisGridLine().foregroundStyle(Color.secondary.opacity(0.12))
                        AxisValueLabel {
                            if let hours = value.as(Double.self) {
                                Text("\(Int(hours))h").font(.system(size: 9))
                            }
                        }
                    }
                }
                .frame(height: 180)
            }
        }
    }

    // MARK: - Breakdown

    private func breakdown(_ data: PeriodData) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionLabel("WHERE IT WENT")
                Spacer()
                Text("click a dot to reclassify — it updates every day on record")
                    .font(.system(size: 9))
                    .foregroundStyle(.quaternary)
            }

            VStack(spacing: 2) {
                ForEach(data.rows.prefix(25)) { row in
                    DashboardRow(row: row,
                                 maximum: data.rows.first?.duration ?? 1,
                                 share: data.tracked > 0 ? row.duration / data.tracked : 0)
                }
            }
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold))
            .foregroundStyle(.tertiary)
            .tracking(0.8)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Nothing recorded here yet.")
                .font(.system(size: 13, weight: .medium))
            Text(period == .day
                 ? "Tally only sees time from when you first ran it."
                 : "Keep it running and this fills in day by day.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 40)
    }
}

// MARK: - Row

struct DashboardRow: View {
    let row: BreakdownRow
    let maximum: TimeInterval
    let share: Double

    @EnvironmentObject var rules: RulesStore
    @State private var hovering = false

    private var category: Category { rules.category(for: row.key) }

    var body: some View {
        HStack(spacing: 11) {
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
                    .frame(width: 8, height: 8)
                    .overlay(
                        Circle()
                            .stroke(category.color.opacity(0.35), lineWidth: 4)
                            .opacity(hovering ? 1 : 0)
                    )
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .frame(width: 10)

            HStack(spacing: 5) {
                Text(row.name)
                    .font(.system(size: 12))
                    .lineLimit(1)
                    .truncationMode(.middle)
                if rules.isPinned(row.key) {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(Category.work.color)
                }
            }
            .frame(width: 190, alignment: .leading)

            GeometryReader { geo in
                RoundedRectangle(cornerRadius: 3)
                    .fill(category.color.opacity(0.75))
                    .frame(width: max(2, geo.size.width * (row.duration / max(maximum, 1))),
                           height: 10)
                    .frame(maxHeight: .infinity, alignment: .center)
            }
            .frame(height: 18)

            Text(formatDuration(row.duration))
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .monospacedDigit()
                .frame(width: 62, alignment: .trailing)

            Text("\(Int(share * 100))%")
                .font(.system(size: 10))
                .monospacedDigit()
                .foregroundStyle(.tertiary)
                .frame(width: 34, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(hovering ? Color.secondary.opacity(0.08) : .clear)
        )
        .onHover { hovering = $0 }
    }
}
