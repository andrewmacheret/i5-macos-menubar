import Foundation
import I5Core

// Reads the I-5 server's /status and prints what the app would show.
// Exit codes: 0 when the status can be trusted, 2 when it can't be confirmed
let useColor = isatty(STDOUT_FILENO) != 0

func paint(_ text: String, _ code: String) -> String {
    useColor ? "\u{1B}[\(code)m\(text)\u{1B}[0m" : text
}

func paint(_ status: LaneStatus) -> String {
    let code = switch status {
    case .northbound: "1;32"
    case .southbound: "1;34"
    case .closed: "1;31"
    case .unknown: "1;90"
    }
    return paint(status.title.uppercased(), code)
}

let client = StatusClient(cacheDir: nil, userAgent: "I5ExpressTerminal/1.0 (+https://github.com/andrewmacheret/i5-macos-menubar)")
let result = await client.load()
let now = Date().moment
let snap = Snapshot(status: result.status ?? .empty, now: now)
let check = snap.check

if check.verdict == .confident {
    print("I-5 express lanes: \(paint(check.scheduled))")
} else {
    let expected = check.scheduled == .unknown ? "" : " (expected \(check.scheduled.title.lowercased()))"
    let word = check.verdict == .checking ? "CHECKING" : "CAN'T CONFIRM"
    print("I-5 express lanes: \(paint(word, "1;33"))\(expected)")
    for c in check.concerns {
        print(paint("  ⚠ \(c.title): \(c.detail)", "33"))
    }
}
if let next = snap.next, result.status != nil {
    print("  \(snap.nextText) (\(Format.countdown(to: next.at, from: now)))")
}
for n in Page.noticesToday(snap) {
    print(paint("  \(n.notice.title): \(n.text)", "33"))
}
if let t = Page.travelTimes(snap) {
    for row in t.rows {
        let saves = row.saves.map { ", saves \($0) min" } ?? ""
        print("  \(row.label): express lanes \(row.express)\(saves), regular lanes \(row.regular)")
    }
}

if let status = result.status {
    // The canary looks for "Checked WSDOT at", so it only shows when the server read WSDOT recently
    if let fetchedAt = status.fetchedAt, status.error == nil, status.published != nil, now - fetchedAt <= Trust.maxAge {
        print(paint("  Checked WSDOT at \(Format.when(fetchedAt, now: now))", "2"))
    } else if let fetchedAt = status.fetchedAt, status.error == nil {
        print(paint("  The server last read WSDOT at \(Format.when(fetchedAt, now: now))", "2"))
    } else {
        print(paint("  \(Page.dataStatus(snap, loaded: true).text)", "2"))
    }
    if let reading = Page.readingText(snap) { print(paint("  \(reading)", "2")) }
}
if let e = result.error { print(paint("  \(e)", "2")) }
print(paint("  Source: \(Sources.status)", "2"))
exit(check.verdict == .confident ? 0 : 2)
