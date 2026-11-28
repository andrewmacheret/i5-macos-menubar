import Foundation

// Questions about the timeline the server published. No schedule logic lives here.
// The server works out the segments, so the app only looks things up.

public struct Change: Hashable, Sendable {
    public var at: Moment
    public var to: LaneStatus

    public init(at: Moment, to: LaneStatus) {
        self.at = at
        self.to = to
    }
}

/// A run of one status across part of a Seattle day, in wall clock minutes
public struct DaySegment: Hashable, Sendable {
    public var start: TimeOfDay
    public var end: TimeOfDay
    public var status: LaneStatus
}

public extension Timeline {
    /// The index of the segment covering a moment, by binary search
    private func segmentIndex(_ t: Moment) -> Int? {
        var lo = 0, hi = segments.count - 1
        while lo <= hi {
            let mid = (lo + hi) / 2
            let s = segments[mid]
            if t < s.start { hi = mid - 1 } else if t >= s.end { lo = mid + 1 } else { return mid }
        }
        return nil
    }

    func segment(at t: Moment) -> Segment? { segmentIndex(t).map { segments[$0] } }

    /// Unknown outside the published range
    func status(at t: Moment) -> LaneStatus { segment(at: t)?.status ?? .unknown }

    func doubts(at t: Moment) -> [Doubt] { doubts.filter { $0.start <= t && t < $0.end } }

    func doubts(from start: Moment, to end: Moment) -> [Doubt] { doubts.filter { $0.start < end && $0.end > start } }

    /// The next few times the status flips, after `from`
    func upcomingChanges(from: Moment, limit: Int = 5) -> [Change] {
        var out: [Change] = []
        var current = status(at: from)
        for s in segments where s.start > from && s.status != current {
            out.append(Change(at: s.start, to: s.status))
            current = s.status
            if out.count == limit { break }
        }
        // Past the end of the published range nothing is known
        if out.count < limit, horizon.end > from, current != .unknown { out.append(Change(at: horizon.end, to: .unknown)) }
        return out
    }

    /// The last time the status flipped at or before `t`, or nil if it hasn't within the published range
    func lastChange(at t: Moment) -> Moment? {
        guard let i = segmentIndex(t) else { return nil }
        let status = segments[i].status
        var j = i
        while j > 0 {
            if segments[j - 1].status != status { return segments[j].start }
            j -= 1
        }
        return nil
    }

    /// Colored runs across one Seattle day, for the timeline bar. Placed by wall clock time,
    /// so daylight saving days still fit a 24 hour bar. Fall back's repeated hour is drawn once.
    func daySegments(_ day: DayKey) -> [DaySegment] {
        let start = Seattle.startOfDay(day)
        let end = Seattle.startOfDay(Seattle.addDays(day, 1))
        var out: [DaySegment] = []
        func push(_ from: TimeOfDay, _ to: TimeOfDay, _ status: LaneStatus) {
            var from = from
            if to <= from { return }
            if let last = out.last, last.end > from { from = last.end }
            if to <= from { return }
            if let last = out.last, last.status == status, last.end == from {
                out[out.count - 1].end = to
            } else {
                out.append(DaySegment(start: from, end: to, status: status))
            }
        }
        func wall(_ t: Moment) -> TimeOfDay { t >= end ? endOfDay : Seattle.time(t) }
        var t = start
        if start < horizon.start {
            push(0, wall(min(horizon.start, end)), .unknown)
            t = horizon.start
        }
        for s in segments where s.end > t && s.start < end {
            let a = max(s.start, t), b = min(s.end, end)
            // Wall time can jump at a clock change, so walk across it an hour at a time
            var x = a
            while x < b {
                let next = min(b, (floorDiv(x, Seattle.hour) + 1) * Seattle.hour)
                let w = wall(next)
                push(Seattle.time(x), w == 0 ? endOfDay : w, s.status)
                x = next
            }
            t = b
        }
        if t < end { push(wall(t), endOfDay, .unknown) }
        return out
    }
}
