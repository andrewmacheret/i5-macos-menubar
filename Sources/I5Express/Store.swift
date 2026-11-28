import AppKit
import Combine
import I5Core
import Network
import ServiceManagement
import UserNotifications

@MainActor
final class Store: ObservableObject {
    /// The server's latest answer, or the saved copy. Nil before the first one.
    @Published private(set) var status: ServerStatus?
    @Published private(set) var loadError: String?
    @Published private(set) var snapshot: Snapshot
    @Published private(set) var isRefreshing = false
    @Published private(set) var settingsMessage: String?
    /// Set by the app delegate, so camera pictures only load while someone can see them
    @Published var popoverShown = false

    @Published var showCountdown: Bool {
        didSet { defaults.set(showCountdown, forKey: "showCountdown") }
    }
    /// Only changed through `setNotify` and `setLaunchAtLogin`, so they always match reality
    @Published private(set) var notifyOnChange: Bool
    @Published private(set) var launchAtLogin: Bool
    @Published private(set) var canUpdate = false
    @Published private(set) var autoUpdate = false
    private var updates: Updates?

    private let client = StatusClient(userAgent: Store.userAgent)
    private let defaults = UserDefaults.standard
    private var tickTimer: Timer?
    private var refreshTimer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private var network: NWPathMonitor?
    private var wasOnline: Bool?
    private var lastSeen: Notifications.Seen?
    /// Frozen time for snapshots
    private var previewNow: Moment?

    /// Notifications and login items need a real .app bundle
    private let isBundled = Bundle.main.bundleIdentifier != nil

    nonisolated static var userAgent: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        return "I5ExpressMac/\(version) (+https://github.com/andrewmacheret/i5-macos-menubar)"
    }

    init() {
        let saved = client.saved()
        status = saved
        // Counts as refreshing, since start() downloads right away
        snapshot = Snapshot(status: saved ?? .empty, now: Date().moment, refreshing: true)
        isRefreshing = true
        showCountdown = defaults.object(forKey: "showCountdown") as? Bool ?? false
        notifyOnChange = defaults.bool(forKey: "notifyOnChange")
        launchAtLogin = false
        syncLaunchAtLogin()
    }

    /// A frozen store for snapshots
    init(preview status: ServerStatus?, now: Moment, refreshing: Bool = false, loadError: String? = nil) {
        self.status = status
        self.loadError = loadError
        previewNow = now
        snapshot = Snapshot(status: status ?? .empty, now: now, refreshing: refreshing)
        isRefreshing = refreshing
        showCountdown = false
        notifyOnChange = false
        launchAtLogin = false
    }

    func start() {
        tickTimer = Timer.scheduledTimer(withTimeInterval: 15, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        // The server reads WSDOT every 15 minutes, so every 5 minutes catches each new read soon enough
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 5 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        watchNetwork()
        isRefreshing = false
        Task { await refresh() }
        if notifyOnChange { checkNotificationPermission() }
        updates = Updates.make()
        canUpdate = updates != nil
        autoUpdate = updates?.automatic ?? false
    }

    /// Refreshes when the Mac comes back online
    private func watchNetwork() {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            let online = path.status == .satisfied
            Task { @MainActor in self?.networkChanged(online: online) }
        }
        monitor.start(queue: DispatchQueue(label: "i5.network"))
        network = monitor
    }

    private func networkChanged(online: Bool) {
        defer { wasOnline = online }
        if online, wasOnline == false { Task { await refresh() } }
    }

    func setAutoUpdate(_ on: Bool) {
        updates?.automatic = on
        autoUpdate = updates?.automatic ?? false
    }

    func checkForUpdates() {
        updates?.checkNow()
    }

    func refresh() async {
        guard !isRefreshing, previewNow == nil else { return }
        isRefreshing = true
        tick()
        let result = await client.load()
        if let s = result.status { status = s }
        loadError = result.error
        isRefreshing = false
        tick()
    }

    func tick() {
        snapshot = Snapshot(status: status ?? .empty, now: previewNow ?? Date().moment, refreshing: isRefreshing)
        let check = snapshot.check
        if notifyOnChange, isBundled,
           let m = Notifications.decide(lastSeen, check: check, next: snapshot.next, now: snapshot.now) {
            send(m.title, m.body)
        }
        if !Notifications.waiting(check) { lastSeen = Notifications.seen(check, next: snapshot.next) }
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
