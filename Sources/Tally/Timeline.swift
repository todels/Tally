import SwiftUI

/// One app or site inside a block, with how long it ran there.
struct TimelinePart: Identifiable {
    let name: String
    let duration: TimeInterval
    let category: Category
    var id: String { name }
}

/// A run of neighbouring sessions drawn as one solid bar.
struct TimelineBlock: Identifiable {
    let start: Date
    let end: Date
    let category: Category
    /// Everything that ran inside this block, longest first.
    let parts: [TimelinePart]

    var id: Date { start }
    var duration: TimeInterval { end.timeIntervalSince(start) }
    var label: String { parts.first?.name ?? category.label }
}

enum TimelineBuilder {

    /// Builds the bars for the day.
    ///
    /// Two passes. First, adjacent same-category sessions merge into runs.
    /// Then any run shorter than `minimumVisible` that merely *interrupts* a
    /// longer run of one category is absorbed into it — a ten-second glance at
    /// Discord shouldn't slice a three-hour Figma block into pinstripes.
    ///
    /// Absorbed time is never lost: it stays in the block's `parts`, so hovering
    /// still shows it. Totals and the breakdown list are untouched by any of
    /// this — they always count every second where it was actually spent.
    static func blocks(from sessions: [Session],
                       rules: RulesStore,
                       joining: TimeInterval = 120,
                       minimumVisible: TimeInterval = 90) -> [TimelineBlock] {
        var blocks = runs(from: sessions, rules: rules, joining: joining)

        var merging = true
        while merging {
            merging = false
            guard blocks.count > 2 else { break }

            for i in 1..<(blocks.count - 1) {
                let sliver = blocks[i]
                let before = blocks[i - 1]
                let after = blocks[i + 1]

                // The sliver must actually touch both neighbours. Without this
                // a two-second glance on waking would weld yesterday's last
                // block to this morning's first one straight across the night.
                guard sliver.duration < minimumVisible,
                      before.category == after.category,
                      before.category != sliver.category,
                      sliver.start.timeIntervalSince(before.end) <= joining,
                      after.start.timeIntervalSince(sliver.end) <= joining else { continue }

                blocks.replaceSubrange((i - 1)...(i + 1), with: [
                    TimelineBlock(start: before.start,
                                  end: after.end,
                                  category: before.category,
                                  parts: merged(before.parts, sliver.parts, after.parts))
                ])
                merging = true
                break
            }
        }
        return blocks
    }

    /// Pass one: contiguous same-category sessions become a single run. Gaps
    /// longer than `joining` stay gaps — that's how "the machine was off"
    /// remains visible on the bar.
    private static func runs(from sessions: [Session],
                             rules: RulesStore,
                             joining: TimeInterval) -> [TimelineBlock] {
        var out: [TimelineBlock] = []
        var start: Date?
        var end = Date.distantPast
        var category: Category = .neutral
        var tally: [String: (TimeInterval, Category)] = [:]

        func close() {
            guard let start else { return }
            out.append(TimelineBlock(start: start, end: end,
                                     category: category,
                                     parts: parts(from: tally)))
            tally = [:]
        }

        for session in sessions.sorted(by: { $0.start < $1.start }) {
            let sessionCategory = rules.category(for: session.ruleKey)
            let continues = start != nil
                && sessionCategory == category
                && session.start.timeIntervalSince(end) <= joining

            if continues {
                end = max(end, session.end)
            } else {
                close()
                start = session.start
                end = session.end
                category = sessionCategory
            }

            let existing = tally[session.displayName]?.0 ?? 0
            tally[session.displayName] = (existing + session.duration, sessionCategory)
        }
        close()
        return out
    }

    private static func parts(from tally: [String: (TimeInterval, Category)]) -> [TimelinePart] {
        tally.map { TimelinePart(name: $0.key, duration: $0.value.0, category: $0.value.1) }
            .sorted { $0.duration > $1.duration }
    }

    private static func merged(_ lists: [TimelinePart]...) -> [TimelinePart] {
        var tally: [String: (TimeInterval, Category)] = [:]
        for list in lists {
            for part in list {
                let existing = tally[part.name]?.0 ?? 0
                tally[part.name] = (existing + part.duration, part.category)
            }
        }
        return parts(from: tally)
    }
}

/// The whole day, midnight to midnight, with an hour grid behind it.
///
/// Empty track means the machine genuinely wasn't in use — asleep, shut, or
/// away — so you can read "9 till 12 in Figma, then nothing until 3" straight
/// off the bar. Hovering any block breaks it down.
struct DayTimeline: View {
    let day: Date
    let sessions: [Session]
    let rules: RulesStore
    var compact: Bool = false

    @State private var hoveredID: Date?

    private var dayStart: Date { Calendar.current.startOfDay(for: day) }
    private let span: TimeInterval = 86_400

    private var majorStride: Int { compact ? 6 : 3 }
    private var trackHeight: CGFloat { compact ? 30 : 64 }
    private var inset: CGFloat { compact ? 2 : 4 }

    var body: some View {
        let blocks = TimelineBuilder.blocks(from: sessions, rules: rules)
        let hovered = blocks.first { $0.id == hoveredID }

        VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.secondary.opacity(0.10))

                    hourGrid(width: geo.size.width)
                    bars(blocks, width: geo.size.width)

                    if Calendar.current.isDateInToday(dayStart) {
                        nowMarker(width: geo.size.width)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .onContinuousHover(coordinateSpace: .local) { phase in
                    switch phase {
                    case .active(let point):
                        let hit = block(at: point.x, in: blocks, width: geo.size.width)
                        if hit?.id != hoveredID { hoveredID = hit?.id }
                    case .ended:
                        if hoveredID != nil { hoveredID = nil }
                    }
                }
            }
            .frame(height: trackHeight)

            hourLabels
            readout(hovered)
        }
    }

    // MARK: - Grid

    private func hourGrid(width: CGFloat) -> some View {
        ForEach(1..<24) { hour in
            Rectangle()
                .fill(Color.secondary.opacity(hour % majorStride == 0 ? 0.30 : 0.13))
                .frame(width: 1)
                .offset(x: width * CGFloat(hour) / 24)
        }
    }

    private var hourLabels: some View {
        GeometryReader { geo in
            ForEach(Array(stride(from: 0, to: 24, by: majorStride)), id: \.self) { hour in
                Text(String(format: "%02d", hour))
                    .font(.system(size: 8))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
                    .offset(x: max(0, geo.size.width * CGFloat(hour) / 24 - 7))
            }
        }
        .frame(height: 11)
    }

    // MARK: - Activity

    private func geometry(for block: TimelineBlock, width: CGFloat) -> (x: CGFloat, w: CGFloat) {
        let x = CGFloat(block.start.timeIntervalSince(dayStart) / span) * width
        let w = max(1.5, CGFloat(block.duration / span) * width)
        return (x, w)
    }

    private func bars(_ blocks: [TimelineBlock], width: CGFloat) -> some View {
        ForEach(blocks) { block in
            let frame = geometry(for: block, width: width)
            let isHovered = block.id == hoveredID
            let full = trackHeight - inset * 2

            // Idle draws as a thin centred band rather than a full-height bar,
            // so a long stretch of nothing never looks like a long stretch of
            // work. An empty track still means the machine was off entirely.
            let isIdle = block.category == .idle
            let height = isIdle ? max(3, full * 0.3) : full
            let y = isIdle ? (trackHeight - height) / 2 : inset

            RoundedRectangle(cornerRadius: 2)
                .fill(block.category.color)
                .opacity(isIdle ? 0.55 : 1)
                .overlay(
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(Color.primary.opacity(isHovered ? 0.75 : 0), lineWidth: 1.5)
                )
                .brightness(isHovered ? 0.06 : 0)
                .frame(width: frame.w, height: height)
                .offset(x: frame.x, y: y)
        }
    }

    /// Finds the block under the cursor, with a few pixels of slack so thin
    /// bars are still catchable.
    private func block(at x: CGFloat, in blocks: [TimelineBlock], width: CGFloat) -> TimelineBlock? {
        var nearest: (block: TimelineBlock, distance: CGFloat)?
        for block in blocks {
            let frame = geometry(for: block, width: width)
            if x >= frame.x && x <= frame.x + frame.w { return block }

            let distance = x < frame.x ? frame.x - x : x - (frame.x + frame.w)
            if distance < 4, nearest == nil || distance < nearest!.distance {
                nearest = (block, distance)
            }
        }
        return nearest?.block
    }

    private func nowMarker(width: CGFloat) -> some View {
        let offset = Date().timeIntervalSince(dayStart) / span
        return Rectangle()
            .fill(Color.primary.opacity(0.45))
            .frame(width: 1.5)
            .offset(x: width * offset)
    }

    // MARK: - Hover readout

    /// Fixed height so the layout never jumps as you move across the bar.
    @ViewBuilder
    private func readout(_ block: TimelineBlock?) -> some View {
        HStack(spacing: 10) {
            if let block {
                Text("\(clock(block.start))–\(clock(block.end))")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .monospacedDigit()

                Text(formatDuration(block.duration))
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(block.category.color)

                Divider().frame(height: 10)

                ForEach(block.parts.prefix(compact ? 2 : 4)) { part in
                    HStack(spacing: 4) {
                        Circle()
                            .fill(part.category.color)
                            .frame(width: 5, height: 5)
                        Text(part.name)
                            .font(.system(size: 10))
                            .lineLimit(1)
                        Text(formatDuration(part.duration))
                            .font(.system(size: 10))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }

                if block.parts.count > (compact ? 2 : 4) {
                    Text("+\(block.parts.count - (compact ? 2 : 4))")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                }
            } else {
                Text(sessions.isEmpty
                     ? "No activity recorded for this day."
                     : "Hover the bar to see what you were doing.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 0)
        }
        .frame(height: 16)
        .padding(.top, 2)
    }

    private func clock(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        return f.string(from: date)
    }
}
