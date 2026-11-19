import I5Core
import SwiftUI

struct PopoverView: View {
    @ObservedObject var store: Store
    @Environment(\.snapshotting) private var snapshotting

    private var snap: Snapshot { store.snapshot }
    private var check: Assessment { snap.check }
    private var info: ExpressLanesInfo { store.result.info }
    private var today: DayKey { Seattle.day(of: snap.now) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(16)
            Divider()
            // ImageRenderer can't draw scroll views
            if snapshotting {
                content
            } else {
                ScrollView { content }
                    .frame(maxHeight: 540)
            }
            Divider()
            footer
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
        }
        .frame(width: 370)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 18) {
            if check.verdict == .uncertain { concerns }
            notices
            timelines
            comingUp
            planned
            regularSchedule
            sources
        }
        .padding(16)
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            Image(nsImage: Icon.current(check, height: 46, soon: snap.changingSoon))
            VStack(alignment: .leading, spacing: 2) {
                Text(caption)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .tracking(0.6)
                switch check.verdict {
                case .confident:
                    Text(check.scheduled.title)
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(check.scheduled.color)
                    Text(subtitle).font(.callout).foregroundStyle(.secondary)
                case .checking:
                    HStack(spacing: 8) {
                        Text("Checking…").font(.system(size: 26, weight: .bold, design: .rounded))
                        if !snapshotting { ProgressView().controlSize(.small) }
                    }
                    Text("Reading WSDOT's latest schedule").font(.callout).foregroundStyle(.secondary)
                case .uncertain:
                    Text("Can't confirm")
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(.orange)
                    Text("Posted schedule says \(check.scheduled.title.lowercased()), but don't rely on it")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
    }

    /// Mentions Seattle time when the Mac is set to another time zone
    private var caption: String {
        let differs = TimeZone.current.secondsFromGMT(for: snap.now) != Seattle.timeZone.secondsFromGMT(for: snap.now)
        return differs ? "I-5 EXPRESS LANES · SEATTLE TIME" : "I-5 EXPRESS LANES"
    }

    private var subtitle: String {
        guard let next = snap.next else { return "No changes in the next week" }
        let verb = next.to == .closed ? "Closes" : (check.scheduled == .closed ? "Opens \(next.to.title.lowercased())" : "Switches \(next.to.title.lowercased())")
        return "\(verb) at \(Format.when(next.date, now: snap.now)) · \(Format.countdown(to: next.date, from: snap.now))"
    }

    // MARK: Concerns

    private var concerns: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(check.concerns, id: \.self) { c in
                Callout(icon: "exclamationmark.triangle.fill", tint: .orange, title: c.title, text: c.detail, link: c.link)
            }
            Text("Check a live source before you drive:")
                .font(.callout.weight(.medium))
                .padding(.top, 2)
            HStack(spacing: 14) {
                WebLink("Traffic cameras", Sources.travelMap)
                WebLink("@wsdot_traffic", Sources.wsdotTrafficX)
                WebLink("WSDOT page", Sources.expressLanes)
            }
            .font(.callout)
        }
    }

    // MARK: Notices

    @ViewBuilder private var notices: some View {
        let showEarly = snap.earlyCloseTonight.map { Seattle.time(of: snap.now) < $0 } ?? false
        let oldNotices = info.advisories.filter { $0.isOver(before: today) }
        if snap.activeClosure != nil || showEarly || !oldNotices.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                if let c = snap.activeClosure {
                    Callout(icon: "xmark.octagon.fill", tint: .red, title: c.title,
                            text: "Closed until \(Format.when(c.end, now: snap.now)).")
                }
                if showEarly, let t = snap.earlyCloseTonight {
                    Callout(icon: "moon.fill", tint: .orange, title: "Closing early tonight",
                            text: "The lanes close at \(t.label) for construction.")
                }
                ForEach(oldNotices, id: \.self) { a in
                    Callout(icon: "clock.arrow.circlepath", tint: .gray,
                            title: "Old notice still on WSDOT's page",
                            text: a.text, link: a.link)
                }
            }
        }
    }

    // MARK: Timelines

    private var timelines: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(check.verdict == .confident ? "Schedule" : "Posted schedule · not confirmed")
            TimelineRow(label: "Today", warning: nil, segments: snap.today, nowMarker: Seattle.time(of: snap.now))
            TimelineRow(label: "Tomorrow", warning: snap.tomorrowConcerns.first?.title, segments: snap.tomorrow, nowMarker: nil)
            HStack(spacing: 14) {
                Legend(color: LaneStatus.southbound.color, text: "Southbound")
                Legend(color: LaneStatus.northbound.color, text: "Northbound")
                Legend(color: LaneStatus.closed.timelineColor, text: "Closed")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .opacity(check.verdict == .confident ? 1 : 0.6)
    }

    // MARK: Coming up

    private var comingUp: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionTitle("Coming up")
            ForEach(snap.changes, id: \.self) { change in
                let doubtful = snap.doubtfulDays.contains(Seattle.day(of: change.date))
                HStack(spacing: 8) {
                    Circle().fill(change.to.color).frame(width: 8, height: 8)
                    Text(change.to.title).fontWeight(.medium)
                    if doubtful {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .help("This day may not follow the regular schedule")
                    }
                    Spacer()
                    Text(Format.when(change.date, now: snap.now))
                        .monospacedDigit()
                    Text(Format.countdown(to: change.date, from: snap.now))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 58, alignment: .trailing)
                }
                .font(.callout)
            }
            if snap.changes.contains(where: { snap.doubtfulDays.contains(Seattle.day(of: $0.date)) }) {
                Text("⚠ marks days that may not follow the regular schedule.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Planned changes

    @ViewBuilder private var planned: some View {
        let closures = store.engine.upcomingClosures(from: snap.now)
        let early = store.engine.upcomingEarlyCloses(from: snap.now)
        let unclear = info.events.filter { $0.closure == nil && !($0.days?.isOver(before: today) ?? false) }
        let futureNotices = info.advisories.filter { a in a.days.map { today < $0.first } ?? false }
        let holidays = upcomingHolidays
        if !closures.isEmpty || !early.isEmpty || !unclear.isEmpty || !futureNotices.isEmpty || !holidays.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                SectionTitle("Planned changes")
                ForEach(closures, id: \.self) { c in
                    VStack(alignment: .leading, spacing: 2) {
                        Label(c.title, systemImage: "calendar.badge.exclamationmark").fontWeight(.medium)
                        Text("Closed \(Format.shortDate(c.start)) \(Format.clock(c.start)) → \(Format.shortDate(c.end)) \(Format.clock(c.end))")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .font(.callout)
                }
                ForEach(unclear, id: \.self) { e in
                    VStack(alignment: .leading, spacing: 2) {
                        Label(e.title, systemImage: "questionmark.circle").fontWeight(.medium)
                        Text("Exact times unclear. The app won't confirm a direction on these days.")
                            .foregroundStyle(.orange)
                        if !e.detail.isEmpty {
                            Text(e.detail).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .font(.callout)
                }
                ForEach(futureNotices, id: \.self) { a in
                    Label(a.text, systemImage: "info.circle")
                        .font(.callout)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !early.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Closing early", systemImage: "moon").fontWeight(.medium)
                        Text(early.map(earlyLabel).joined(separator: "  ·  "))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .font(.callout)
                }
                if !holidays.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Label("Holidays", systemImage: "star").fontWeight(.medium)
                        Text(holidays.map { "\($0.1) (\(Format.shortDate($0.0)))" }.joined(separator: "  ·  "))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("WSDOT doesn't post holiday hours, so the app won't confirm a direction on these days.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .font(.callout)
                }
            }
        }
    }

    private func earlyLabel(_ e: EarlyClose) -> String {
        "\(Format.shortDate(e.day)) at \(e.time?.label ?? "unknown time")"
    }

    /// Holidays in the next 14 days
    private var upcomingHolidays: [(DayKey, String)] {
        (0...14).compactMap { offset in
            guard let d = Seattle.calendar.date(byAdding: .day, value: offset, to: snap.now) else { return nil }
            let day = Seattle.day(of: d)
            return Holidays.name(for: day).map { (day, $0) }
        }
    }

    // MARK: Regular schedule

    private var regularSchedule: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionTitle("Regular schedule")
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                ScheduleRow(label: "Mon–Fri", windows: info.schedule.weekday)
                ScheduleRow(label: "Sat–Sun", windows: info.schedule.weekend)
            }
            .font(.callout)
        }
    }

    // MARK: Sources

    private var sources: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionTitle("Sources")
            SourceLink(title: "WSDOT express lanes schedule", subtitle: "Where this data comes from", url: Sources.expressLanes)
            ForEach(eventLinks, id: \.self) { url in
                let bulletin = url.host()?.contains("govdelivery") == true
                SourceLink(title: bulletin ? "WSDOT bulletin" : "Construction project page", subtitle: url.host() ?? "", url: url)
            }
            SourceLink(title: "Revive I-5", subtitle: "Ship Canal Bridge work", url: Sources.reviveI5)
            SourceLink(title: "WSDOT real-time travel map", subtitle: "Live traffic, alerts and cameras", url: Sources.travelMap)
            SourceLink(title: "@wsdot_traffic", subtitle: "Unplanned closures get posted here first", url: Sources.wsdotTrafficX)
            Text("""
            The app only shows N or S when it read WSDOT's page in the last 2 hours, the page made sense, \
            and nothing on it hints that today is different. Otherwise it shows ⚠. \
            It can't know about closures WSDOT hasn't posted yet.
            """)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 4)
        }
    }

    private var eventLinks: [URL] {
        var seen = Set<URL>()
        return (info.events.compactMap(\.link) + info.advisories.compactMap(\.link))
            .filter { $0 != Sources.reviveI5 && $0 != Sources.expressLanes && seen.insert($0).inserted }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 10) {
            sourceStatus
            Spacer()
            if snapshotting {
                Image(systemName: "arrow.clockwise")
                Image(systemName: "gearshape")
            } else {
                controls
            }
        }
    }

    @ViewBuilder private var controls: some View {
        Button {
            Task { await store.refresh() }
        } label: {
            if store.isRefreshing {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: "arrow.clockwise")
            }
        }
        .buttonStyle(.borderless)
        .help("Refresh from WSDOT")
        .keyboardShortcut("r")

        Menu {
            Toggle("Show countdown in menu bar", isOn: $store.showCountdown)
            Toggle("Notify when lanes change", isOn: Binding(get: { store.notifyOnChange }, set: { store.setNotify($0) }))
            Toggle("Launch at login", isOn: Binding(get: { store.launchAtLogin }, set: { store.setLaunchAtLogin($0) }))
            if store.canUpdate {
                Toggle("Install updates automatically", isOn: Binding(get: { store.autoUpdate }, set: { store.setAutoUpdate($0) }))
                Button("Check for Updates…") { store.checkForUpdates() }
            }
            Divider()
            Button("Quit I-5 Express") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        } label: {
            Image(systemName: "gearshape")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }

    private var sourceStatus: some View {
        VStack(alignment: .leading, spacing: 1) {
            switch store.result.source {
            case .live(let d):
                Label("Checked WSDOT at \(Format.clock(d))", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.secondary)
            case .cached(let d):
                Label("Using copy saved \(Format.when(d, now: snap.now))", systemImage: "wifi.slash")
                    .foregroundStyle(.orange)
            case .builtIn:
                Label("Built-in schedule only", systemImage: "wifi.slash")
                    .foregroundStyle(.orange)
            }
            if let e = store.settingsMessage ?? store.result.error {
                Text(e).foregroundStyle(.red).lineLimit(2)
            }
        }
        .font(.caption)
    }
}

// MARK: Pieces

private struct SectionTitle: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .tracking(0.6)
    }
}

private struct Callout: View {
    let icon: String
    let tint: Color
    let title: String
    let text: String
    var link: URL? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(tint)
                .font(.body)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.callout.weight(.semibold))
                Text(text)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let link {
                    WebLink("More info", link).font(.callout)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct TimelineRow: View {
    let label: String
    let warning: String?
    let segments: [Segment]
    let nowMarker: TimeOfDay?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(label).font(.caption.weight(.medium))
                if let warning {
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .lineLimit(1)
                }
            }
            GeometryReader { geo in
                let w = geo.size.width
                ZStack(alignment: .leading) {
                    ZStack(alignment: .leading) {
                        Rectangle().fill(LaneStatus.closed.timelineColor)
                        ForEach(segments, id: \.self) { s in
                            Rectangle()
                                .fill(s.status.timelineColor)
                                .frame(width: max(1, w * fraction(s.end) - w * fraction(s.start)))
                                .offset(x: w * fraction(s.start))
                                .help("\(s.status.title) \(s.start.label)–\(s.end.label)")
                        }
                    }
                    .frame(width: w, height: 14, alignment: .leading)
                    .clipShape(RoundedRectangle(cornerRadius: 4))

                    if let nowMarker {
                        Capsule()
                            .fill(Color.primary)
                            .frame(width: 3, height: 20)
                            .shadow(color: .black.opacity(0.3), radius: 1)
                            .offset(x: w * fraction(nowMarker) - 1.5)
                    }
                }
                .frame(width: w, height: 20, alignment: .leading)
            }
            .frame(height: 20)
            HStack {
                ForEach(Array(["12a", "6a", "12p", "6p", "12a"].enumerated()), id: \.offset) { i, mark in
                    if i > 0 { Spacer() }
                    Text(mark)
                }
            }
            .font(.system(size: 9))
            .foregroundStyle(.tertiary)
        }
    }

    private func fraction(_ t: TimeOfDay) -> CGFloat {
        CGFloat(t.minutes) / CGFloat(24 * 60)
    }
}

private struct Legend: View {
    let color: Color
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 2).fill(color).frame(width: 10, height: 10)
            Text(text)
        }
    }
}

private struct ScheduleRow: View {
    let label: String
    let windows: [LaneWindow]

    var body: some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                ForEach(windows, id: \.self) { w in
                    HStack(spacing: 6) {
                        Circle().fill(w.status.color).frame(width: 7, height: 7)
                        Text("\(w.status.title)  \(w.start.label) – \(w.end.label)")
                            .monospacedDigit()
                    }
                }
            }
        }
    }
}

private struct SourceLink: View {
    let title: String
    let subtitle: String
    let url: URL

    @Environment(\.snapshotting) private var snapshotting

    var body: some View {
        Group {
            if snapshotting {
                label.foregroundStyle(Color.accentColor)
            } else {
                Link(destination: url) { label }
            }
        }
        .font(.callout)
        .help(url.absoluteString)
    }

    private var label: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.up.right.square")
            VStack(alignment: .leading, spacing: 0) {
                Text(title).foregroundStyle(Color.accentColor)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

/// A text link. Snapshots draw it as plain text, since ImageRenderer can't draw links.
private struct WebLink: View {
    let title: String
    let url: URL
    @Environment(\.snapshotting) private var snapshotting

    init(_ title: String, _ url: URL) {
        self.title = title
        self.url = url
    }

    var body: some View {
        if snapshotting {
            Text(title).foregroundStyle(Color.accentColor)
        } else {
            Link(title, destination: url)
        }
    }
}

// Written out by hand, since the Command Line Tools don't ship the @Entry macro
private struct SnapshottingKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// True while rendering PNG snapshots
    var snapshotting: Bool {
        get { self[SnapshottingKey.self] }
        set { self[SnapshottingKey.self] = newValue }
    }
}
