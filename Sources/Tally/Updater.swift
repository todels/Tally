import AppKit
import Foundation
import SwiftUI

/// Pulls a new version from the source checkout and rebuilds it.
///
/// Tally itself still contains no networking. Every byte that crosses the wire
/// is fetched by `git`, which is already on the machine, already signed by
/// Apple, and already trusted to do exactly this. The app only ever runs two
/// local programs — `git` and its own `build.sh` — and never opens a socket.
///
/// The repo path is stamped into Info.plist at build time, so a copy installed
/// from a zip has no path, no button, and no update machinery at all.
@MainActor
final class Updater: ObservableObject {

    enum State: Equatable {
        case idle
        case checking
        case behind(Int)
        case upToDate
        case building
        case failed(String)
    }

    @Published private(set) var state: State = .idle

    private struct Failure: Error { let message: String }

    /// Where this build came from. `nil` when Tally wasn't built from a
    /// checkout — which is exactly when updating shouldn't be offered.
    nonisolated static var repo: URL? {
        guard let path = Bundle.main.object(forInfoDictionaryKey: "TallySourceRepo") as? String,
              !path.isEmpty else { return nil }
        let url = URL(fileURLWithPath: path)
        guard FileManager.default.fileExists(atPath: url.appendingPathComponent(".git").path)
        else { return nil }
        return url
    }

    var isAvailable: Bool { Self.repo != nil }

    // MARK: - Actions

    func check() {
        guard let repo = Self.repo, state != .checking, state != .building else { return }
        state = .checking

        Task.detached(priority: .utility) {
            do {
                try Self.git(["fetch", "--quiet"], in: repo)
                let ahead = try Self.gitOutput(["rev-list", "--count", "HEAD..@{u}"], in: repo)
                let count = Int(ahead.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
                await MainActor.run { self.state = count > 0 ? .behind(count) : .upToDate }
            } catch {
                await MainActor.run { self.state = .failed(Self.describe(error)) }
            }
        }
    }

    func update() {
        guard let repo = Self.repo, state != .building else { return }
        state = .building

        Task.detached(priority: .userInitiated) {
            do {
                // --ff-only: refuse anything that isn't a clean fast-forward
                // rather than trying to auto-merge local edits.
                try Self.git(["pull", "--ff-only"], in: repo)

                let script = repo.appendingPathComponent("build.sh")
                let result = try Self.run("/bin/bash", [script.path], in: repo)
                guard result.status == 0 else {
                    throw Failure(message: "build failed\n" + result.output.suffix(400))
                }

                await MainActor.run { Self.relaunch(at: repo.appendingPathComponent("Tally.app")) }
            } catch {
                await MainActor.run { self.state = .failed(Self.describe(error)) }
            }
        }
    }

    // MARK: - Subprocess plumbing

    nonisolated private static func git(_ args: [String], in repo: URL) throws {
        let result = try run("/usr/bin/git", ["-C", repo.path] + args, in: repo)
        guard result.status == 0 else {
            throw Failure(message: result.output.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    nonisolated private static func gitOutput(_ args: [String], in repo: URL) throws -> String {
        let result = try run("/usr/bin/git", ["-C", repo.path] + args, in: repo)
        guard result.status == 0 else {
            throw Failure(message: result.output.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return result.output
    }

    nonisolated private static func run(_ tool: String,
                                        _ args: [String],
                                        in directory: URL) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = args
        process.currentDirectoryURL = directory

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        try process.run()
        // Drain before waiting, or a chatty build fills the pipe and deadlocks.
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    nonisolated private static func describe(_ error: Error) -> String {
        if let failure = error as? Failure {
            return failure.message.isEmpty ? "update failed" : failure.message
        }
        return error.localizedDescription
    }

    /// build.sh has just replaced the bundle underneath us, so the running
    /// process is the old binary. Hand off to a tiny shell that waits for this
    /// PID to die and then opens the freshly built app.
    private static func relaunch(at app: URL) {
        let quoted = "'" + app.path.replacingOccurrences(of: "'", with: "'\\''") + "'"
        let watcher = Process()
        watcher.executableURL = URL(fileURLWithPath: "/bin/sh")
        watcher.arguments = ["-c",
            "while kill -0 \(getpid()) 2>/dev/null; do sleep 0.2; done; sleep 0.3; open \(quoted)"]
        try? watcher.run()

        NSApp.terminate(nil)
    }
}
