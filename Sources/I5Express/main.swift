import AppKit

MainActor.assumeIsolated {
    // `--snapshot <dir>` renders the popover and badges to PNGs, then quits
    if let i = CommandLine.arguments.firstIndex(of: "--snapshot"), i + 1 < CommandLine.arguments.count {
        Snapshotter.run(into: URL(fileURLWithPath: CommandLine.arguments[i + 1], isDirectory: true))
        exit(0)
    }

    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
