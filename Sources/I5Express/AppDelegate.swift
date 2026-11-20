import AppKit
import Combine
import I5Core
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = Store()
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var bag = Set<AnyCancellable>()
    /// NSApp.isActive says true as soon as the popover opens, even when macOS hasn't made the app active
    private var active = false
    private var pendingMenuAt: NSPoint?
    private var gearMenu: NSMenu?
    /// The gear button's frame, measured from the top left of the popover
    private var gear = CGRect.zero

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(clicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageLeading
        }

        let host = NSHostingController(rootView: PopoverView(store: store, openMenu: { [weak self] in self?.popUpMenu() },
                                                             gearMoved: { [weak self] in self?.gear = $0 }))
        host.sizingOptions = .preferredContentSize
        popover.contentViewController = host
        popover.behavior = .transient
        popover.animates = true

        store.$snapshot
            .combineLatest(store.$showCountdown)
            .receive(on: RunLoop.main)
            .sink { [weak self] snap, countdown in self?.updateButton(snap, countdown: countdown) }
            .store(in: &bag)

        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                guard let self else { return }
                active = true
                // Let this notification finish before the menu takes over the run loop
                DispatchQueue.main.async { self.showPendingMenu() }
            }
            .store(in: &bag)
        NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)
            .sink { [weak self] _ in
                guard let self else { return }
                active = false
                // The popover doesn't always close by itself once the app has been active
                if popover.isShown { popover.performClose(nil) }
            }
            .store(in: &bag)
        // Don't leave the gear menu floating on its own
        NotificationCenter.default.publisher(for: NSPopover.willCloseNotification, object: popover)
            .sink { [weak self] _ in self?.gearMenu?.cancelTracking() }
            .store(in: &bag)

        store.start()

        if CommandLine.arguments.contains("--debug") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                guard let self, let button = statusItem.button else { return }
                let frame = button.window?.frame ?? .zero
                print("status item visible=\(statusItem.isVisible) frame=\(frame) image=\(button.image?.size ?? .zero)")
                let check = store.snapshot.check
                print("verdict=\(check.verdict) scheduled=\(check.scheduled) source=\(store.result.source) error=\(store.result.error ?? "none")")
                for c in check.concerns { print("concern: \(c.title) | \(c.detail)") }
                fflush(stdout)
            }
        }
    }

    private func updateButton(_ snap: Snapshot, countdown: Bool) {
        guard let button = statusItem.button else { return }
        let check = snap.check
        button.image = Icon.current(check, height: 16, soon: snap.changingSoon)
        if countdown, check.verdict == .confident, let next = snap.next {
            button.title = " " + Format.countdown(to: next.date, from: snap.now)
            button.font = NSFont.monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        } else {
            button.title = ""
        }
        switch check.verdict {
        case .confident:
            var tip = "I-5 express lanes: \(check.scheduled.title)"
            if let next = snap.next { tip += "\n\(next.to.title) at \(Format.when(next.date, now: snap.now))" }
            button.toolTip = tip
        case .checking:
            button.toolTip = "Checking WSDOT…"
        case .uncertain:
            button.toolTip = "Can't confirm the I-5 express lanes\n" + check.concerns.map(\.title).joined(separator: "\n")
        }
    }

    @objc private func clicked(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu()
        } else {
            togglePopover(sender)
        }
    }

    private func togglePopover(_ sender: NSStatusBarButton) {
        if popover.isShown {
            popover.performClose(nil)
        } else {
            store.tick()
            popover.show(relativeTo: sender.bounds, of: sender, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
            NSApp.activate()
        }
    }

    private func showMenu() {
        statusItem.menu = makeMenu()
        statusItem.button?.performClick(nil)
        // Clear it so the next left click opens the popover again
        statusItem.menu = nil
    }

    /// For the gear button in the popover
    private func popUpMenu() {
        guard let view = popover.contentViewController?.view else { return }
        // Open it a bit below the gear, not under the mouse. A second click on the gear then
        // closes the menu, instead of landing on the menu's clear edge and closing the popover.
        // The menu window has about 6 points of clear padding above its first item.
        let gap: CGFloat = 12
        let at = NSPoint(x: gear.minX, y: view.isFlipped ? gear.maxY + gap : view.bounds.height - gear.maxY - gap)
        if active {
            showMenu(at: at)
            return
        }
        // macOS won't make the app active when the popover opens, but it will when the gear is clicked.
        // A menu that opens before that closes as soon as the app becomes active, so wait for it.
        pendingMenuAt = at
        NSApp.activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in self?.showPendingMenu() }
    }

    private func showPendingMenu() {
        guard let at = pendingMenuAt else { return }
        pendingMenuAt = nil
        if popover.isShown { showMenu(at: at) }
    }

    /// `at` is in the popover's view
    private func showMenu(at: NSPoint) {
        let menu = makeMenu()
        gearMenu = menu
        menu.popUp(positioning: nil, at: at, in: popover.contentViewController?.view)
        gearMenu = nil
    }

    /// The menu for right-clicking the icon and for the gear button
    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(withTitle: "Refresh", action: #selector(refresh), keyEquivalent: "r").target = self
        menu.addItem(withTitle: "Open WSDOT Express Lanes Page", action: #selector(openSource), keyEquivalent: "").target = self
        if store.canUpdate {
            menu.addItem(withTitle: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "").target = self
        }
        menu.addItem(.separator())
        addToggle(to: menu, "Show countdown in menu bar", store.showCountdown, #selector(toggleCountdown))
        addToggle(to: menu, "Notify when lanes change", store.notifyOnChange, #selector(toggleNotify))
        addToggle(to: menu, "Launch at login", store.launchAtLogin, #selector(toggleLaunchAtLogin))
        if store.canUpdate {
            addToggle(to: menu, "Install updates automatically", store.autoUpdate, #selector(toggleAutoUpdate))
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit I-5 Express", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        return menu
    }

    @objc private func refresh() {
        Task { await store.refresh() }
    }

    private func addToggle(to menu: NSMenu, _ title: String, _ on: Bool, _ action: Selector) {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
        item.target = self
        item.state = on ? .on : .off
    }

    @objc private func checkForUpdates() {
        store.checkForUpdates()
    }

    @objc private func toggleCountdown() {
        store.showCountdown.toggle()
    }

    @objc private func toggleNotify() {
        store.setNotify(!store.notifyOnChange)
    }

    @objc private func toggleLaunchAtLogin() {
        store.setLaunchAtLogin(!store.launchAtLogin)
    }

    @objc private func toggleAutoUpdate() {
        store.setAutoUpdate(!store.autoUpdate)
    }

    @objc private func openSource() {
        NSWorkspace.shared.open(Sources.expressLanes)
    }
}
