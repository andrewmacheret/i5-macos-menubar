import AppKit
import I5Core
import SwiftUI

/// Renders the UI to PNG files so it can be checked without clicking around.
@MainActor
enum Snapshotter {
    static func run(into dir: URL) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        for status in LaneStatus.allCases {
            for soon in [false, true] {
                let name = "badge-\(status.rawValue)\(soon ? "-soon" : "").png"
                write(Icon.badge(status, height: 16, soon: soon), scale: 4, to: dir.appendingPathComponent(name))
            }
        }
        write(Icon.warning(height: 16), scale: 4, to: dir.appendingPathComponent("badge-warning.png"))

        var live: FetchResult?
        let done = DispatchSemaphore(value: 0)
        Task {
            live = await Fetcher().load()
            done.signal()
        }
        while done.wait(timeout: .now()) == .timedOut {
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
        }
        guard let live else { return }

        let now = Date()
        var thanksgiving = live
        let tgDate = Seattle.date(DayKey(year: 2026, month: 11, day: 26), TimeOfDay(10))!
        thanksgiving.source = .live(tgDate)

        let scenarios: [(String, Store)] = [
            ("now", Store(preview: live, now: now)),
            ("thanksgiving", Store(preview: thanksgiving, now: tgDate)),
            ("offline", Store(preview: FetchResult(info: .builtIn, source: .builtIn, error: "The Internet connection appears to be offline."), now: now)),
            ("checking", Store(preview: FetchResult(info: .builtIn, source: .builtIn), now: now, refreshing: true)),
        ]
        for (name, store) in scenarios {
            for scheme in [ColorScheme.light, .dark] {
                let view = PopoverView(store: store)
                    .environment(\.snapshotting, true)
                    .environment(\.colorScheme, scheme)
                    .background(scheme == .dark ? Color(white: 0.16) : Color(white: 0.97))
                let renderer = ImageRenderer(content: view)
                renderer.scale = 2
                if let image = renderer.nsImage {
                    write(image, scale: 1, to: dir.appendingPathComponent("popover-\(name)-\(scheme == .dark ? "dark" : "light").png"))
                }
            }
        }
        // Fixed example times so the README images don't depend on when they're made
        let tenAM = Seattle.date(DayKey(year: 2026, month: 11, day: 19), TimeOfDay(10, 8))!
        let quarterPast = Seattle.date(DayKey(year: 2026, month: 11, day: 19), TimeOfDay(11, 15))!
        let elevenPM = Seattle.date(DayKey(year: 2026, month: 11, day: 19), TimeOfDay(23))!
        let change = Alerts.change(.northbound, next: Change(date: elevenPM, to: .closed), now: quarterPast)
        let cantConfirm = Alerts.cantConfirm(scenarios[1].1.snapshot.check)

        let extras: [(String, AnyView)] = [
            ("icons", AnyView(IconStates())),
            ("menubar", AnyView(MenuBarPreview(status: .southbound, countdown: Format.countdown(to: tenAM.addingTimeInterval(52 * 60), from: tenAM)))),
            ("notifications", AnyView(NotificationPreview(messages: [change, cantConfirm]))),
            ("menus", AnyView(MenusPreview())),
        ]
        for (name, view) in extras {
            for scheme in [ColorScheme.light, .dark] {
                let renderer = ImageRenderer(content: view.environment(\.colorScheme, scheme))
                renderer.scale = 2
                if let image = renderer.nsImage {
                    write(image, scale: 1, to: dir.appendingPathComponent("\(name)-\(scheme == .dark ? "dark" : "light").png"))
                }
            }
        }
        print("Wrote snapshots to \(dir.path)")
    }

    /// Every menu bar icon with what it means, drawn on a fake menu bar
    private struct IconStates: View {
        @Environment(\.colorScheme) private var scheme

        private let rows: [(NSImage, String)] = [
            (Icon.badge(.northbound, height: 16), "Northbound"),
            (Icon.badge(.southbound, height: 16), "Southbound"),
            (Icon.badge(.closed, height: 16), "Closed"),
            (Icon.badge(.northbound, height: 16, soon: true), "Switching soon"),
            (Icon.warning(height: 16), "Can't confirm"),
            (Icon.badge(.unknown, height: 16), "Checking"),
        ]

        var body: some View {
            HStack(spacing: 22) {
                ForEach(rows.indices, id: \.self) { i in
                    HStack(spacing: 7) {
                        Image(nsImage: rows[i].0)
                        Text(rows[i].1).font(.system(size: 13))
                    }
                }
            }
            .padding(.horizontal, 16)
            .frame(height: 30)
            .background(scheme == .dark ? Color(white: 0.13) : Color(white: 0.93))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    /// The menu bar with and without the countdown, next to some system icons
    private struct MenuBarPreview: View {
        let status: LaneStatus
        let countdown: String
        @Environment(\.colorScheme) private var scheme

        var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                row(label: "Icon only", countdown: nil)
                row(label: "With countdown", countdown: countdown)
            }
            .padding(14)
            .background(scheme == .dark ? Color(white: 0.08) : Color(white: 0.85))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }

        private func row(label: String, countdown: String?) -> some View {
            HStack(spacing: 12) {
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 104, alignment: .leading)
                HStack(spacing: 16) {
                    HStack(spacing: 3) {
                        Image(nsImage: Icon.badge(status, height: 16))
                        if let countdown {
                            Text(countdown).font(.system(size: 13).monospacedDigit())
                        }
                    }
                    Image(systemName: "wifi")
                    Image(systemName: "battery.75percent")
                    Image(systemName: "magnifyingglass")
                    Image(systemName: "switch.2")
                    Text("Thu Nov 19  10:08 AM").font(.system(size: 13))
                }
                .font(.system(size: 13))
                .padding(.horizontal, 12)
                .frame(height: 26)
                .background(scheme == .dark ? Color(white: 0.18) : Color(white: 0.97))
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
        }
    }

    /// Banners laid out like macOS notifications, using the app's real messages
    private struct NotificationPreview: View {
        let messages: [Alerts.Message]
        @Environment(\.colorScheme) private var scheme

        var body: some View {
            VStack(spacing: 10) {
                ForEach(messages.indices, id: \.self) { i in
                    HStack(alignment: .top, spacing: 10) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: Bundle.main.bundlePath))
                            .resizable()
                            .frame(width: 38, height: 38)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(messages[i].title).font(.system(size: 13, weight: .semibold))
                                Spacer()
                                Text("now").font(.system(size: 11)).foregroundStyle(.secondary)
                            }
                            Text(messages[i].body).font(.system(size: 13)).foregroundStyle(.secondary)
                        }
                    }
                    .padding(12)
                    .frame(width: 360)
                    .background(scheme == .dark ? Color(white: 0.2) : Color.white, in: RoundedRectangle(cornerRadius: 16))
                    .shadow(color: .black.opacity(0.18), radius: 8, y: 2)
                }
            }
            .padding(18)
            .background(
                LinearGradient(colors: scheme == .dark ? [Color(white: 0.1), Color(white: 0.05)] : [Color(white: 0.88), Color(white: 0.8)],
                               startPoint: .top, endPoint: .bottom)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    /// The gear menu and the right-click menu
    private struct MenusPreview: View {
        @Environment(\.colorScheme) private var scheme

        var body: some View {
            HStack(alignment: .top, spacing: 22) {
                menu("Gear menu in the popover, or right-click the icon", [
                    (nil, "Refresh", "⌘R"),
                    (nil, "Open WSDOT Express Lanes Page", nil),
                    (nil, "Check for Updates…", nil),
                    (nil, "-", nil),
                    ("checkmark", "Show countdown in menu bar", nil),
                    ("checkmark", "Notify when lanes change", nil),
                    ("checkmark", "Launch at login", nil),
                    ("checkmark", "Install updates automatically", nil),
                    (nil, "-", nil),
                    (nil, "Quit I-5 Express", "⌘Q"),
                ])
            }
            .padding(18)
            .background(scheme == .dark ? Color(white: 0.08) : Color(white: 0.85))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }

        private func menu(_ caption: String, _ items: [(String?, String, String?)]) -> some View {
            VStack(alignment: .leading, spacing: 6) {
                Text(caption).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(items.indices, id: \.self) { i in
                        let (check, title, key) = items[i]
                        if title == "-" {
                            Divider().padding(.vertical, 4).padding(.horizontal, 10)
                        } else {
                            HStack(spacing: 6) {
                                Image(systemName: check ?? "checkmark")
                                    .font(.system(size: 11, weight: .semibold))
                                    .opacity(check == nil ? 0 : 1)
                                    .frame(width: 14)
                                Text(title).fixedSize()
                                Spacer(minLength: 24)
                                if let key { Text(key).foregroundStyle(.secondary) }
                            }
                            .font(.system(size: 13))
                            .padding(.horizontal, 10)
                            .frame(height: 24)
                        }
                    }
                }
                .padding(.vertical, 5)
                .frame(minWidth: 250)
                .background(scheme == .dark ? Color(white: 0.2) : Color.white, in: RoundedRectangle(cornerRadius: 8))
                .shadow(color: .black.opacity(0.2), radius: 6, y: 2)
            }
        }
    }

    private static func write(_ image: NSImage, scale: CGFloat, to url: URL) {
        let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height),
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return }
        rep.size = image.size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(origin: .zero, size: image.size))
        NSGraphicsContext.restoreGraphicsState()
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
