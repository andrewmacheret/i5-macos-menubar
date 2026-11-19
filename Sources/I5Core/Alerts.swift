import Foundation

/// Decides when to send a notification.
public enum Alerts {
    public struct Message: Equatable, Sendable {
        public var title: String
        public var body: String

        public init(_ title: String, _ body: String) {
            self.title = title
            self.body = body
        }
    }

    /// What the app last saw, so it can spot a change
    public struct Seen: Equatable, Sendable {
        public var verdict: Assessment.Verdict
        public var scheduled: LaneStatus
        public var nextAt: Date?
    }

    /// A change older than this happened while the Mac was asleep. Don't report old news.
    public static let lateLimit: TimeInterval = 10 * 60

    /// Closed gaps shorter than this, like the 15 minute weekday switch, aren't worth a notification
    public static let shortGap: TimeInterval = 30 * 60

    public static func seen(_ check: Assessment, next: Change?) -> Seen {
        Seen(verdict: check.verdict, scheduled: check.scheduled, nextAt: next?.date)
    }

    /// True when it's too soon to judge, so nothing is sent and the last `Seen` is kept:
    /// - a refresh is running, or every problem is old data that a refresh should fix
    ///   (this keeps it quiet after waking up and while the Mac is offline)
    /// - the posted schedule says closed, so a "can't confirm" can wait until the lanes
    ///   would open instead of popping up at midnight
    public static func waiting(_ check: Assessment) -> Bool {
        switch check.verdict {
        case .confident: false
        case .checking: true
        case .uncertain: check.concerns.allSatisfy(\.fixedByRefresh) || check.scheduled == .closed
        }
    }

    public static func decide(_ old: Seen?, check new: Assessment, next: Change?, now: Date) -> Message? {
        guard let old, !waiting(new) else { return nil }
        if old.verdict == .confident, new.verdict == .uncertain {
            return cantConfirm(new)
        }
        guard old.verdict == .confident, new.verdict == .confident, old.scheduled != new.scheduled,
              let expected = old.nextAt, now.timeIntervalSince(expected) <= lateLimit
        else { return nil }
        if new.scheduled == .closed, let next, next.date.timeIntervalSince(now) < shortGap { return nil }
        return change(new.scheduled, next: next, now: now)
    }

    public static func change(_ status: LaneStatus, next: Change?, now: Date) -> Message {
        let title = status == .closed ? "I-5 express lanes closed" : "I-5 express lanes now \(status.title.lowercased())"
        guard let next else { return Message(title, "") }
        let when = Format.when(next.date, now: now)
        let body = switch (status, next.to) {
        case (_, .closed): "Closes at \(when)"
        case (.closed, let to): "Opens \(to.title.lowercased()) at \(when)"
        case (_, let to): "Switches \(to.title.lowercased()) at \(when)"
        }
        return Message(title, body)
    }

    public static func cantConfirm(_ check: Assessment) -> Message {
        let concern = check.concerns.first { !$0.fixedByRefresh } ?? check.concerns.first
        return Message("Can't confirm the I-5 express lanes", concern?.title ?? "Open the app for details")
    }
}
