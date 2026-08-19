import Foundation

/// Asks Dia — and only Dia — what's in the front tab.
///
/// Runs `osascript` as a separate short-lived process rather than using
/// NSAppleScript in-process, so a wedged Apple event can never beachball the
/// menu bar. The call is hard-capped by `timeout`.
enum DiaBridge {

    enum Result {
        case success(String?)   // the host Dia answered with; nil means no window open
        case blocked            // macOS hasn't granted Automation access yet
        case unavailable        // Dia not running, or something else went wrong
    }

    // Only the URL is ever requested — the page title is deliberately never asked
    // for, so it can't be recorded even by accident.
    //
    // Dia chokes on `set t to active tab of front window` (-1700), so the tab is
    // dereferenced inline instead of held in a variable.
    private static let script = """
    tell application id "company.thebrowser.dia"
        if (count of windows) is 0 then return ""
        return URL of active tab of front window
    end tell
    """

    private static let timeout: TimeInterval = 3

    static func frontTab() -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]

        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err

        do {
            try process.run()
        } catch {
            return .unavailable
        }

        // Hard deadline — kill rather than hang.
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning && Date() < deadline {
            usleep(20_000)
        }
        if process.isRunning {
            process.terminate()
            return .unavailable
        }

        let stdout = String(decoding: out.fileHandleForReading.readDataToEndOfFile(),
                            as: UTF8.self)
        let stderr = String(decoding: err.fileHandleForReading.readDataToEndOfFile(),
                            as: UTF8.self)

        if process.terminationStatus != 0 {
            // -1743 / -1728 are the "user hasn't allowed Automation" family.
            if stderr.contains("-1743") || stderr.lowercased().contains("not allowed") {
                return .blocked
            }
            return .unavailable
        }

        guard !stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let host = normalizedHost(stdout) else {
            return .success(nil)
        }

        return .success(host)
    }

    /// `https://www.youtube.com/watch?v=…` → `youtube.com`
    /// Only ever keeps the host. Full URLs, paths and query strings are dropped
    /// on the floor and never written to disk.
    static func normalizedHost(_ raw: String) -> String? {
        guard let components = URLComponents(string: raw.trimmingCharacters(in: .whitespacesAndNewlines)),
              var host = components.host?.lowercased(),
              !host.isEmpty else { return nil }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        return host
    }
}
