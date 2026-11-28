import AppKit

MainActor.assumeIsolated {
    // `--snapshot <dir>` renders the popover and badges to PNGs from the test fixtures, then quits.
    // `--fixtures <dir>` says where the fixtures are. It defaults to the repo's test fixtures.
    let args = CommandLine.arguments
    if let i = args.firstIndex(of: "--snapshot"), i + 1 < args.count {
        let fixtures = args.firstIndex(of: "--fixtures").flatMap { $0 + 1 < args.count ? args[$0 + 1] : nil }
            ?? "Tests/I5CoreTests/Fixtures"
        let ok = Snapshotter.run(into: URL(fileURLWithPath: args[i + 1], isDirectory: true),
                                 fixtures: URL(fileURLWithPath: fixtures, isDirectory: true))
        exit(ok ? 0 : 1)
    }

    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
