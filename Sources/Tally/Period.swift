import Foundation

/// The span the dashboard is showing.
enum Period: String, CaseIterable, Identifiable {
    case day, week, month

    var id: String { rawValue }

    var label: String {
        switch self {
        case .day: return "Day"
        case .week: return "Week"
        case .month: return "Month"
        }
    }

    var calendarComponent: Calendar.Component {
        switch self {
        case .day: return .day
        case .week: return .weekOfYear
        case .month: return .month
        }
    }

    /// The days covered by this period, anchored on `date`.
    func days(around date: Date) -> [Date] {
        let cal = Calendar.current
        guard let interval = cal.dateInterval(of: calendarComponent, for: date) else {
            return [cal.startOfDay(for: date)]
        }
        var out: [Date] = []
        var cursor = interval.start
        while cursor < interval.end {
            out.append(cal.startOfDay(for: cursor))
            guard let next = cal.date(byAdding: .day, value: 1, to: cursor) else { break }
            cursor = next
        }
        return out
    }

    func shift(_ date: Date, by amount: Int) -> Date {
        Calendar.current.date(byAdding: calendarComponent, value: amount, to: date) ?? date
    }

    /// "Today", "This week", "August" — or an explicit date when it's in the past.
    func title(for date: Date) -> String {
        let cal = Calendar.current
        let f = DateFormatter()

        switch self {
        case .day:
            if cal.isDateInToday(date) { return "Today" }
            if cal.isDateInYesterday(date) { return "Yesterday" }
            f.dateFormat = "EEEE d MMMM"
            return f.string(from: date)

        case .week:
            if cal.isDate(date, equalTo: Date(), toGranularity: .weekOfYear) {
                return "This week"
            }
            guard let interval = cal.dateInterval(of: .weekOfYear, for: date) else { return "Week" }
            let last = interval.end.addingTimeInterval(-1)
            f.dateFormat = "d"
            let from = f.string(from: interval.start)
            f.dateFormat = "d MMMM"
            return "\(from)–\(f.string(from: last))"

        case .month:
            if cal.isDate(date, equalTo: Date(), toGranularity: .month) {
                return "This month"
            }
            f.dateFormat = cal.isDate(date, equalTo: Date(), toGranularity: .year)
                ? "MMMM" : "MMMM yyyy"
            return f.string(from: date)
        }
    }
}

/// One day's worth of totals, for the bar chart.
struct DayTotal: Identifiable {
    let date: Date
    var totals: [Category: TimeInterval]
    var id: Date { date }

    var tracked: TimeInterval { totals.values.reduce(0, +) }
    var away: TimeInterval { totals[.idle] ?? 0 }
    var focus: TimeInterval { totals[.work] ?? 0 }
}

struct PeriodData {
    var days: [DayTotal] = []
    var totals: [Category: TimeInterval] = [:]
    var rows: [BreakdownRow] = []
    var sessions: [Session] = []

    /// Time in the pinned app — Figma by default. Tracked separately because
    /// "how much did I actually design today" is a different question from
    /// "how much was I not distracted".
    var pinned: TimeInterval = 0

    /// Everything recorded: hands-on time plus idle. This is "how long was I at
    /// the computer", and every category on screen adds up to it — so the split
    /// bar, the legend and the percentage all describe the same whole.
    var tracked: TimeInterval { totals.values.reduce(0, +) }

    /// Hands actually on the machine.
    var active: TimeInterval {
        Category.assignable.reduce(0) { $0 + (totals[$1] ?? 0) }
    }

    var away: TimeInterval { totals[.idle] ?? 0 }
    var focus: TimeInterval { totals[.work] ?? 0 }

    /// Share of focused time that was the pinned app, 0–1.
    var pinnedShareOfFocus: Double {
        focus > 0 ? min(1, pinned / focus) : 0
    }

    /// Share of tracked time that was focused, 0–1.
    var focusShare: Double {
        tracked > 0 ? focus / tracked : 0
    }

    /// Average focus per day that actually had activity — a fairer number than
    /// dividing by 7 when you didn't work the weekend.
    var dailyAverage: TimeInterval {
        let active = days.filter { $0.tracked > 60 }
        guard !active.isEmpty else { return 0 }
        return active.reduce(0) { $0 + $1.focus } / Double(active.count)
    }
}

/// Reads days back off disk and caches them. Today always comes live from the
/// tracker instead, so the dashboard counts up while you watch it.
@MainActor
final class History: ObservableObject {
    private var cache: [Date: [Session]] = [:]

    func sessions(for day: Date, tracker: Tracker) -> [Session] {
        let start = Calendar.current.startOfDay(for: day)
        if Calendar.current.isDateInToday(start) {
            return tracker.sessionsIncludingOpen()
        }
        if let cached = cache[start] { return cached }
        let loaded = Store.load(day: start)
        cache[start] = loaded
        return loaded
    }

    func aggregate(period: Period,
                   anchor: Date,
                   rules: RulesStore,
                   tracker: Tracker) -> PeriodData {
        var data = PeriodData()
        var totals: [Category: TimeInterval] = [.work: 0, .distraction: 0, .neutral: 0]
        var byKey: [RuleKey: BreakdownRow] = [:]
        let pinnedKey = rules.pinnedKey
        var pinnedTotal: TimeInterval = 0

        for day in period.days(around: anchor) {
            // Don't total up days that haven't happened yet.
            if day > Date() { continue }

            let sessions = sessions(for: day, tracker: tracker)
            var dayTotals: [Category: TimeInterval] = [.work: 0, .distraction: 0, .neutral: 0]

            for session in sessions {
                let category = rules.category(for: session.ruleKey)
                dayTotals[category, default: 0] += session.duration
                totals[category, default: 0] += session.duration

                let key = session.ruleKey
                if key == pinnedKey { pinnedTotal += session.duration }

                // Idle counts in the totals but isn't a "place" — keep it out
                // of the breakdown list.
                if session.bundleID == Idle.bundleID { continue }

                if var row = byKey[key] {
                    row.duration += session.duration
                    byKey[key] = row
                } else {
                    byKey[key] = BreakdownRow(key: key,
                                              name: session.displayName,
                                              duration: session.duration)
                }
            }

            data.days.append(DayTotal(date: day, totals: dayTotals))
            data.sessions.append(contentsOf: sessions)
        }

        data.totals = totals
        data.pinned = pinnedTotal
        data.rows = byKey.values
            .sorted { $0.duration > $1.duration }
            .filter { $0.duration >= 30 }
        return data
    }

    /// Called when rules change or a new day is written.
    func invalidate() { cache.removeAll() }
}
