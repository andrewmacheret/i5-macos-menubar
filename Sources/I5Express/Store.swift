import AppKit
import Combine
import I5Core
import ServiceManagement
import UserNotifications

/// Everything the menu bar icon and popover show, worked out once per tick.
struct Snapshot {
    var now: Date
    var check: Assessment
    var changes: [Change]
    var today: [Segment]
    var tomorrow: [Segment]
    var tomorrowConcerns: [Concern]
    /// Days in the next week that may not follow the schedule
    var doubtfulDays: Set<DayKey>
    var activeClosure: Closure?
    var earlyCloseTonight: TimeOfDay?

    var next: Change? { changes.first }

    /// True when the lanes flip within 15 minutes
    var changingSoon: Bool {
        guard let next else { return false }
        return next.date.timeIntervalSince(now) <= 15 * 60
    }
}

@MainActor
final class Store: ObservableObject {
    @Published private(set) var result: FetchResult
    @Published private(set) var snapshot: Snapshot
    @Published private(set) var isRefreshing = false
    @Published private(set) var settingsMessage: String?

    @Published var showCountdown: Bool {
        didSet { defaults.set(showCountdown, forKey: "showCountdown") }
    }
    /// Only changed through `setNotify` and `setLaunchAtLogin`, so they always match reality
    @Published private(set) var notifyOnChange: Bool
    @Published private(set) var launchAtLogin: Bool
    @Published private(set) var canUpdate = false
    @Published private(set) var autoUpdate = false
    private var updates: Updates?

    private let fetcher = Fetcher()
    private let defaults = UserDefaults.standard
    private var tickTimer: Timer?
    private var refreshTimer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private var lastSeen: Alerts.Seen?

    /// Notifications and login items need a real .app bundle
    private let isBundled = Bundle.main.bundleIdentifier != nil

    init() {
        let initial = Fetcher().cachedOrBuiltIn()
        result = initial
        // Counts as refreshing, since start() downloads right away
        snapshot = Store.makeSnapshot(initial, now: Date(), refreshing: true)
        showCountdown = defaults.object(forKey: "showCountdown") as? Bool ?? false
        notifyOnChange = defaults.bool(forKey: "notifyOnChange")
        launchAtLogin = false
        syncLaunchAtLogin()
    }

    /// A frozen store for snapshots
    init(preview result: FetchResult, now: Date, refreshing: Bool = false) {
        self.result = result
        snapshot = Store.makeSnapshot(result, now: now, refreshing: refreshing)
        isRefreshing = refreshing
        showCountdown = false
        notifyOnChange = false
        launchAtLogin = false
    }

    func start() {
        tickTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        // Every 15 minutes keeps data well inside the 2 hour freshness limit
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 15 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        Task { await refresh() }
        if notifyOnChange { checkNotificationPermission() }
        updates = Updates.make()
        canUpdate = updates != nil
        autoUpdate = updates?.automatic ?? false
    }

    func setAutoUpdate(_ on: Bool) {
        updates?.automatic = on
        autoUpdate = updates?.automatic ?? false
    }

    func checkForUpdates() {
        updates?.checkNow()
    }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        tick()
        result = await fetcher.load()
        isRefreshing = false
        tick()
    }

    func tick() {
        snapshot = Store.makeSnapshot(result, now: Date(), refreshing: isRefreshing)
        let check = snapshot.check
        if notifyOnChange, isBundled,
           let m = Alerts.decide(lastSeen, check: check, next: snapshot.next, now: snapshot.now) {
            send(m.title, m.body)
        }
        if !Alerts.waiting(check) { lastSeen = Alerts.seen(check, next: snapshot.next) }
    }

    var engine: Engine { Engine(info: result.info) }

    private static func makeSnapshot(_ result: FetchResult, now: Date, refreshing: Bool) -> Snapshot {
        let engine = Engine(info: result.info)
        let today = Seattle.day(of: now)
        let tomorrowDate = Seattle.calendar.date(byAdding: .day, value: 1, to: now) ?? now
        let tomorrow = Seattle.day(of: tomorrowDate)
        let changes = engine.upcomingChanges(from: now, limit: 4)

        var doubtful = Set<DayKey>()
        for offset in 0...7 {
            guard let d = Seattle.calendar.date(byAdding: .day, value: offset, to: now) else { continue }
            let day = Seattle.day(of: d)
            if !Trust.dayConcerns(result.info, day: day, today: today).isEmpty { doubtful.insert(day) }
        }

        return Snapshot(
            now: now,
            check: Trust.assess(result, now: now, refreshing: refreshing),
            changes: changes,
            today: engine.segments(for: today),
            tomorrow: engine.segments(for: tomorrow),
            tomorrowConcerns: Trust.dayConcerns(result.info, day: tomorrow, today: today),
            doubtfulDays: doubtful,
            activeClosure: engine.closure(at: now),
            earlyCloseTonight: engine.earlyCloseTime(on: today)
        )
    }

    // MARK: Notifications

    private func send(_ title: String, _ body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: "i5-status", content: content, trigger: nil))
    }

    func setNotify(_ on: Bool) {
        guard on else {
            notifyOnChange = false
            defaults.set(false, forKey: "notifyOnChange")
            return
        }
        guard isBundled else {
            settingsMessage = "Notifications only work from the installed app"
            return
        }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            Task { @MainActor in
                self.notifyOnChange = granted
                self.defaults.set(granted, forKey: "notifyOnChange")
                self.settingsMessage = granted ? nil : "Turn on notifications for I-5 Express in System Settings → Notifications"
            }
        }
    }

    /// Turns the setting off if permission was taken away in System Settings
    private func checkNotificationPermission() {
        guard isBundled else { return }
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            let allowed = settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional
            Task { @MainActor in
                if !allowed {
                    self.notifyOnChange = false
                    self.settingsMessage = "Notifications are off for I-5 Express in System Settings"
                }
            }
        }
    }

    // MARK: Launch at login

    func setLaunchAtLogin(_ on: Bool) {
        guard isBundled else {
            settingsMessage = "Launch at login only works from the installed app"
            return
        }
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            settingsMessage = nil
        } catch {
            settingsMessage = "Launch at login: \(error.localizedDescription)"
        }
        syncLaunchAtLogin()
    }

    /// Reads the real state back so the toggle never lies
    private func syncLaunchAtLogin() {
        guard isBundled else { return }
        switch SMAppService.mainApp.status {
        case .enabled:
            launchAtLogin = true
        case .requiresApproval:
            launchAtLogin = false
            settingsMessage = "Approve I-5 Express in System Settings → General → Login Items"
        default:
            launchAtLogin = false
        }
    }
}
