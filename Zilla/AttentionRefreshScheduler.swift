import Foundation
import os

/// Periodically polls `AttentionMonitor` and bumps
/// `Workspace.revisionListRefreshToken` so the visible revision list
/// refetches from Phabricator.
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
final class AttentionRefreshScheduler {
    private static let log = Logger(subsystem: "com.zilla", category: "RefreshScheduler")
    private static let identifier = "mozilla.Zilla.attentionRefresh"

    private weak var workspace: Workspace?
    private weak var monitor: AttentionMonitor?
    private let interval: TimeInterval

    #if os(macOS)
    private var scheduler: NSBackgroundActivityScheduler?
    #else
    private var loopTask: Task<Void, Never>?
    #endif

    init(workspace: Workspace, monitor: AttentionMonitor, interval: TimeInterval = 10 * 60) {
        self.workspace = workspace
        self.monitor = monitor
        self.interval = interval
    }

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
                await self?.tick()
                completion(.finished)
            }
        }
        scheduler = s
        Self.log.notice("Started attention refresh (NSBackgroundActivity), interval=\(self.interval, privacy: .public)s")
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
                await self?.tick()
            }
        }
        Self.log.notice("Started attention refresh (Task loop), interval=\(self.interval, privacy: .public)s")
        #endif
    }

    func stop() {
        #if os(macOS)
        scheduler?.invalidate()
        scheduler = nil
        #else
        loopTask?.cancel()
        loopTask = nil
        #endif
        Self.log.notice("Stopped attention refresh")
    }

    private func tick() async {
        guard let workspace, let monitor, monitor.isSignedIn else {
            Self.log.notice("Skipping refresh: not signed in")
            return
        }
        Self.log.notice("Bumping revision refresh token and polling attention")
        workspace.revisionListRefreshToken = UUID()
        await monitor.poll(force: true)
    }
}
