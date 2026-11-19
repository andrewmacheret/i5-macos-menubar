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
        for scheme in [ColorScheme.light, .dark] {
            let renderer = ImageRenderer(content: IconStates().environment(\.colorScheme, scheme))
            renderer.scale = 2
            if let image = renderer.nsImage {
                write(image, scale: 1, to: dir.appendingPathComponent("icons-\(scheme == .dark ? "dark" : "light").png"))
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
