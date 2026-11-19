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

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(clicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.imagePosition = .imageLeading
        }

        let host = NSHostingController(rootView: PopoverView(store: store))
        host.sizingOptions = .preferredContentSize
        popover.contentViewController = host
        popover.behavior = .transient
        popover.animates = true

        store.$snapshot
            .combineLatest(store.$showCountdown)
            .receive(on: RunLoop.main)
            .sink { [weak self] snap, countdown in self?.updateButton(snap, countdown: countdown) }
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
        let menu = NSMenu()
        menu.addItem(withTitle: "Refresh", action: #selector(refresh), keyEquivalent: "r").target = self
        menu.addItem(withTitle: "Open WSDOT Express Lanes Page", action: #selector(openSource), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit I-5 Express", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        // Clear it so the next left click opens the popover again
        statusItem.menu = nil
    }

    @objc private func refresh() {
        Task { await store.refresh() }
    }

    @objc private func openSource() {
        NSWorkspace.shared.open(Sources.expressLanes)
    }
}
