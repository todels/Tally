import AppKit
import Foundation
import SwiftUI

/// Gets a newer Tally onto this Mac. Two ways, picked from Info.plist at launch:
///
/// - **Checkout.** `build.sh` stamps the repo path in. Updating is `git pull`
///   followed by `build.sh` — the code path for anyone hacking on the source.
/// - **Release.** `release.sh` stamps the build id and GitHub repo in instead.
///   Updating downloads the latest zip from GitHub Releases and swaps the
///   bundle in place — the path for anyone who installed from the DMG.
///
/// In both cases Tally itself contains no networking. Every byte that crosses
/// the wire is moved by `git` or `curl`, which are already on the machine,
/// already signed by Apple, and already trusted to do exactly this. The app
/// only ever runs local programs and never opens a socket of its own. Nothing
/// is fetched or installed without a click.
@MainActor
final class Updater: ObservableObject {

    enum Channel {
        case checkout(URL)
        case release(repo: String, build: String)
    }

    enum State: Equatable {
        case idle
        case checking
        case behind(String)   // what's new, for the tooltip
        case upToDate
        case building
        case failed(String)
    }

    @Published private(set) var state: State = .idle

    let channel: Channel?
    var isAvailable: Bool { channel != nil }

    private struct Failure: Error { let message: String }

    init() {
        channel = Self.detectChannel()
    }

    /// A checkout wins when both are stamped, so a dev build of a release
    /// never tries to replace itself with a download.
    private nonisolated static func detectChannel() -> Channel? {
        let info = Bundle.main.infoDictionary ?? [:]

        if let path = info["TallySourceRepo"] as? String, !path.isEmpty {
            let url = URL(fileURLWithPath: path)
            if FileManager.default.fileExists(atPath: url.appendingPathComponent(".git").path) {
                return .checkout(url)
            }
        }

        if let repo = info["TallyUpdateRepo"] as? String, !repo.isEmpty,
           let build = info["TallyBuild"] as? String, !build.isEmpty, build != "dev" {
            return .release(repo: repo, build: build)
        }

        return nil
    }

    // MARK: - Actions

    func check() {
        guard let channel, state != .checking, state != .building else { return }
        state = .checking

        Task.detached(priority: .utility) {
            do {
                let result: State
                switch channel {
                case .checkout(let repo):
                    try Self.git(["fetch", "--quiet"], in: repo)
                    let count = try Self.gitOutput(["rev-list", "--count", "HEAD..@{u}"], in: repo)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    let n = Int(count) ?? 0
                    result = n > 0 ? .behind("\(n) new commit\(n == 1 ? "" : "s")") : .upToDate

                case .release(let repo, let build):
                    let tag = try Self.latestReleaseTag(repo: repo)
                    result = tag.hasSuffix(build) ? .upToDate : .behind("build \(tag)")
                }
                await MainActor.run { self.state = result }
            } catch {
                await MainActor.run { self.state = .failed(Self.describe(error)) }
            }
        }
    }

    func update() {
        guard let channel, state != .building else { return }
        state = .building

        Task.detached(priority: .userInitiated) {
            do {
                let relaunchAt: URL
                switch channel {
                case .checkout(let repo):
                    // --ff-only: refuse anything that isn't a clean fast-forward
                    // rather than trying to auto-merge local edits.
                    try Self.git(["pull", "--ff-only"], in: repo)
                    let script = repo.appendingPathComponent("build.sh")
                    let result = try Self.run("/bin/bash", [script.path], in: repo)
                    guard result.status == 0 else {
                        throw Failure(message: "build failed\n" + result.output.suffix(400))
                    }
                    relaunchAt = repo.appendingPathComponent("Tally.app")

                case .release(let repo, _):
                    relaunchAt = try Self.installLatestRelease(repo: repo)
                }
                await MainActor.run { Self.relaunch(at: relaunchAt) }
            } catch {
                await MainActor.run { self.state = .failed(Self.describe(error)) }
            }
        }
    }

    // MARK: - Release channel

    private nonisolated static func releasesURL(_ repo: String) -> String {
        "https://github.com/\(repo)/releases"
    }

    /// GitHub redirects `/releases/latest` to `/releases/tag/<tag>`. Following
    /// the redirect and reading where it landed gives the tag with no API call,
    /// no token, and no JSON.
    private nonisolated static func latestReleaseTag(repo: String) throws -> String {
        let result = try run("/usr/bin/curl", [
            "-fsSIL", "-o", "/dev/null", "-w", "%{url_effective}",
            releasesURL(repo) + "/latest",
        ], in: FileManager.default.temporaryDirectory)
        guard result.status == 0 else {
            throw Failure(message: result.status == 22
                          ? "no releases published yet"
                          : "couldn't reach GitHub")
        }
        let landed = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let range = landed.range(of: "/releases/tag/") else {
            throw Failure(message: "no releases published yet")
        }
        let tag = String(landed[range.upperBound...])
        guard !tag.isEmpty else { throw Failure(message: "no releases published yet") }
        return tag
    }

    /// Downloads the latest zip, checks it, and swaps it in over the running
    /// bundle. Returns where the new app lives.
    private nonisolated static func installLatestRelease(repo: String) throws -> URL {
        let fm = FileManager.default
        let current = Bundle.main.bundleURL

        // Running straight off the mounted DMG: it's read-only, nothing we
        // can do except say so.
        guard !current.path.hasPrefix("/Volumes/") else {
            throw Failure(message: "drag Tally to Applications first, then update")
        }

        let work = fm.temporaryDirectory.appendingPathComponent("tally-update-\(getpid())")
        try? fm.removeItem(at: work)
        try fm.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: work) }

        let zip = work.appendingPathComponent("Tally.zip")
        let download = try run("/usr/bin/curl", [
            "-fsSL", "-o", zip.path,
            releasesURL(repo) + "/latest/download/Tally.zip",
        ], in: work)
        guard download.status == 0 else { throw Failure(message: "download failed") }

        let unzip = try run("/usr/bin/ditto", ["-x", "-k", zip.path, work.path], in: work)
        guard unzip.status == 0 else { throw Failure(message: "couldn't unpack the download") }

        // release.sh zips a folder holding Tally.app + INSTALL.md; find the app
        // wherever it landed rather than hard-coding the layout.
        guard let fresh = try fm.contentsOfDirectory(at: work, includingPropertiesForKeys: nil)
                .flatMap({ dir -> [URL] in
                    (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [dir]
                })
                .first(where: { $0.lastPathComponent == "Tally.app" }) else {
            throw Failure(message: "download didn't contain Tally.app")
        }

        // A truncated or tampered download fails its own seal.
        let verify = try run("/usr/bin/codesign", ["--verify", "--strict", fresh.path], in: work)
        guard verify.status == 0 else { throw Failure(message: "downloaded app failed signature check") }

        // Swap: move the old one aside, the new one in. If the second step
        // fails, put the old one back so nothing is ever left half-done.
        let aside = work.appendingPathComponent("Tally-previous.app")
        do {
            try fm.moveItem(at: current, to: aside)
        } catch {
            NSWorkspace.shared.activateFileViewerSelecting([fresh])
            throw Failure(message: "couldn't replace \(current.path) — the new copy is shown in Finder, drag it in by hand")
        }
        do {
            try fm.moveItem(at: fresh, to: current)
        } catch {
            try? fm.moveItem(at: aside, to: current)
            throw Failure(message: "couldn't install the new copy; the old one was kept")
        }
        return current
    }

    // MARK: - Checkout channel

    private nonisolated static func git(_ args: [String], in repo: URL) throws {
        _ = try gitOutput(args, in: repo)
    }

    private nonisolated static func gitOutput(_ args: [String], in repo: URL) throws -> String {
        let result = try run("/usr/bin/git", ["-C", repo.path] + args, in: repo)
        guard result.status == 0 else {
            throw Failure(message: result.output.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return result.output
    }

    // MARK: - Subprocess plumbing

    private nonisolated static func run(_ tool: String,
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

    private nonisolated static func describe(_ error: Error) -> String {
        if let failure = error as? Failure {
            return failure.message.isEmpty ? "update failed" : failure.message
        }
        return error.localizedDescription
    }

    /// The bundle on disk has just been replaced underneath us, so the running
    /// process is the old binary. Hand off to a tiny shell that waits for this
    /// PID to die and then opens the fresh app.
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
