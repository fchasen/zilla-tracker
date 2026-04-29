import Foundation
import os

/// Periodically bumps `Workspace.revisionListRefreshToken` so the visible
/// revision list refetches from Phabricator. The visible list refreshes
/// immediately; lists not currently mounted refresh on their next
/// `.task(id:)` evaluation.
///
/// On macOS this wraps `NSBackgroundActivityScheduler`, which lets the OS
/// coalesce ticks with other background work, adapt to power state, and run
/// while the app is in the background (subject to AppNap).
///
/// On iOS, where `NSBackgroundActivityScheduler` isn't available, it runs a
/// `Task.sleep` loop. Foreground only — the system suspends the
/// task when the app is backgrounded and resumes it when the user returns,
/// which is exactly the behavior we want for "refresh while the user is
/// looking at the app". Exact timing isn't load-bearing.
@MainActor
final class RevisionRefreshScheduler {
    private static let log = Logger(subsystem: "com.zilla", category: "RefreshScheduler")
    private static let identifier = "mozilla.Zilla.revisionRefresh"

    private weak var workspace: Workspace?
    private weak var phab: PhabricatorAuthStore?
    private let interval: TimeInterval

    #if os(macOS)
    private var scheduler: NSBackgroundActivityScheduler?
    #else
    private var loopTask: Task<Void, Never>?
    #endif

    init(workspace: Workspace, phab: PhabricatorAuthStore, interval: TimeInterval = 10 * 60) {
        self.workspace = workspace
        self.phab = phab
        self.interval = interval
    }

    /// Starts the periodic refresh. Idempotent.
    func start() {
        #if os(macOS)
        guard scheduler == nil else { return }
        let s = NSBackgroundActivityScheduler(identifier: Self.identifier)
        s.repeats = true
        s.interval = interval
        // Allow ±20% slop (min 60s) so the OS can coalesce with other activity.
        s.tolerance = max(60, interval * 0.2)
        s.qualityOfService = .utility
        s.schedule { [weak self] completion in
            Task { @MainActor [weak self] in
                self?.tick()
                completion(.finished)
            }
        }
        scheduler = s
        Self.log.notice("Started revision refresh (NSBackgroundActivity), interval=\(self.interval, privacy: .public)s")
        #else
        guard loopTask == nil else { return }
        let interval = self.interval
        loopTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(interval))
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }
                self?.tick()
            }
        }
        Self.log.notice("Started revision refresh (Task loop), interval=\(self.interval, privacy: .public)s")
        #endif
    }

    /// Stops the scheduler. Safe to call when not running.
    func stop() {
        #if os(macOS)
        scheduler?.invalidate()
        scheduler = nil
        #else
        loopTask?.cancel()
        loopTask = nil
        #endif
        Self.log.notice("Stopped revision refresh")
    }

    private func tick() {
        guard let workspace, let phab, phab.isSignedIn else {
            Self.log.notice("Skipping refresh: not signed in")
            return
        }
        Self.log.notice("Bumping refresh tokens")
        workspace.revisionListRefreshToken = UUID()
        workspace.bugListRefreshToken = UUID()
    }
}
