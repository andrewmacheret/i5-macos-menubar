import Foundation
import I5Core

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

let now = Date()
let result = await Fetcher().load(now: now)
let engine = Engine(info: result.info)
let check = Trust.assess(result, now: now)

if check.verdict == .confident {
    print("I-5 express lanes: \(paint(check.scheduled))")
} else {
    print("I-5 express lanes: \(paint("CAN'T CONFIRM", "1;33")) (schedule says \(check.scheduled.title.lowercased()))")
    for c in check.concerns {
        print(paint("  ⚠ \(c.title): \(c.detail)", "33"))
    }
}
if let next = engine.upcomingChanges(from: now, limit: 1).first {
    print("  \(next.to.title) at \(Format.when(next.date, now: now)) (\(Format.countdown(to: next.date, from: now)))")
}
if let c = engine.closure(at: now) {
    print(paint("  \(c.title)", "33"))
}
if let t = engine.earlyCloseTime(on: Seattle.day(of: now)), Seattle.time(of: now) < t {
    print(paint("  Closing early at \(t.label) tonight", "33"))
}
switch result.source {
case .live(let d): print(paint("  Checked WSDOT at \(Format.clock(d))", "2"))
case .cached(let d): print(paint("  Using WSDOT page saved \(Format.when(d, now: now))", "2"))
case .builtIn: print(paint("  Using the built-in schedule", "2"))
}
if let e = result.error { print(paint("  \(e)", "2")) }
print(paint("  Source: \(Sources.expressLanes.absoluteString)", "2"))
exit(check.verdict == .confident ? 0 : 2)
