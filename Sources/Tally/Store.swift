import Foundation

/// Append-only, one newline-delimited JSON file per day, sitting in plain sight
/// in Application Support. No database, no network, no sync — you can read your
/// own history with `cat` and delete a day by deleting a file.
enum Store {
    static let directory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask)[0]
        return base.appendingPathComponent("Tally", isDirectory: true)
    }()

    static func ensureDirectory() {
        try? FileManager.default.createDirectory(at: directory,
                                                 withIntermediateDirectories: true)
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func file(for day: Date) -> URL {
        directory.appendingPathComponent("\(dayFormatter.string(from: day)).ndjson")
    }

    /// Splits sessions that cross midnight so each day's file stays self-contained.
    static func append(_ session: Session) {
        let cal = Calendar.current
        if !cal.isDate(session.start, inSameDayAs: session.end),
           let midnight = cal.nextDate(after: session.start,
                                       matching: DateComponents(hour: 0, minute: 0, second: 0),
                                       matchingPolicy: .nextTime),
           midnight < session.end {
            var first = session
            first.end = midnight
            var second = session
            second.start = midnight
            write(first)
            write(second)
            return
        }
        write(session)
    }

    private static func write(_ session: Session) {
        guard session.duration > 0 else { return }
        ensureDirectory()
        guard var data = try? encoder.encode(session) else { return }
        data.append(0x0A)

        let url = file(for: session.start)

        // A day's file is created once and only ever appended to afterwards.
        //
        // This used to fall back to writing the session as the whole file when
        // opening it for append failed — which silently replaced an entire day
        // with a single line. Never overwrite an existing day: dropping one
        // session is a rounding error, dropping the day is not.
        guard FileManager.default.fileExists(atPath: url.path) else {
            try? data.write(to: url, options: .atomic)
            return
        }

        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
    }

    static func load(day: Date) -> [Session] {
        guard let text = try? String(contentsOf: file(for: day), encoding: .utf8) else {
            return []
        }
        return text
            .split(separator: "\n")
            .compactMap { try? decoder.decode(Session.self, from: Data($0.utf8)) }
    }
}
