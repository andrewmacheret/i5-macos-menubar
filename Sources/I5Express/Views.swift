import AppKit
import I5Core
import SwiftUI

/// What's open in the popover. A class, since the Command Line Tools can't expand SwiftUI's @State macro.
final class PopoverState: ObservableObject {
    /// Closed until asked, so no pictures load until then
    @Published var camerasOpen: Bool
    @Published var allCameras: Bool
    @Published var scrollToCameras = false
    /// The camera showing full width, by id
    @Published var expandedCamera: Int?
    /// Planned notices showing all their times, by position
    @Published var allTimes: Set<Int> = []
    /// Planned notices showing WSDOT's own words, by position
    @Published var openWords: Set<Int> = []
    /// Each camera's picture and retries, kept here so expanding a camera doesn't load it again
    private var pictures: [Int: PictureLoader] = [:]

    init(camerasOpen: Bool, allCameras: Bool, expandedCamera: Int? = nil) {
        self.camerasOpen = camerasOpen
        self.allCameras = allCameras
        self.expandedCamera = expandedCamera
    }

    @MainActor func picture(_ id: Int) -> PictureLoader {
        if let p = pictures[id] { return p }
        let p = PictureLoader()
        pictures[id] = p
        return p
    }

    /// Forgets the pictures, so the next open starts fresh
    func closeCameras() {
        camerasOpen = false
        expandedCamera = nil
        pictures = [:]
    }
}

struct PopoverView: View {
    @ObservedObject var store: Store
    var openMenu: () -> Void = {}
    /// Gets the gear's frame, measured from the top left of the popover
    var gearMoved: (CGRect) -> Void = { _ in }
    @Environment(\.snapshotting) private var snapshotting

    @StateObject private var ui: PopoverState

    private static let camerasID = "cameras"

    init(store: Store, openMenu: @escaping () -> Void = {}, gearMoved: @escaping (CGRect) -> Void = { _ in },
         camerasOpen: Bool = false, allCameras: Bool = false, expandedCamera: Int? = nil) {
        self.store = store
        self.openMenu = openMenu
        self.gearMoved = gearMoved
        _ui = StateObject(wrappedValue: PopoverState(camerasOpen: camerasOpen, allCameras: allCameras, expandedCamera: expandedCamera))
    }

    static func cameraID(_ id: Int) -> String { "camera-\(id)" }

    private static let width: CGFloat = 400
    private static let padding: CGFloat = 16
    /// How wide the sections are, inside the padding
    static let contentWidth = width - 2 * padding

    private var snap: Snapshot { store.snapshot }
    private var check: Assessment { snap.check }
    private var loaded: Bool { store.status != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(16)
            Divider()
            // ImageRenderer can't draw scroll views
            if snapshotting {
                content
            } else {
                ScrollViewReader { proxy in
                    ScrollView { content }
                        .frame(maxHeight: maxHeight)
                        .onChange(of: ui.scrollToCameras) { _, go in
                            guard go else { return }
                            ui.scrollToCameras = false
                            DispatchQueue.main.async {
                                withAnimation { proxy.scrollTo(Self.camerasID, anchor: .top) }
                            }
                        }
                        // Keeps the bigger picture in view, scrolling as little as it can
                        .onChange(of: ui.expandedCamera) { _, id in
                            guard let id else { return }
                            DispatchQueue.main.async {
                                withAnimation { proxy.scrollTo(Self.cameraID(id)) }
                            }
                        }
                }
            }
            Divider()
            footer
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
        }
        .frame(width: Self.width)
        .coordinateSpace(.named("popover"))
        .onChange(of: store.popoverShown) { _, shown in
            if !shown { ui.closeCameras() }
        }
    }

    /// Leaves room for the menu bar, header and footer on small screens
    private var maxHeight: CGFloat {
        min(620, (NSScreen.main?.visibleFrame.height ?? 900) - 220)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 18) {
            if loaded, check.verdict == .uncertain { concerns }
            notices
            timelines
            travelTimes
            cameras
            comingUp
            planned
            regularSchedule
            sources
        }
        .padding(Self.padding)
    }

    // MARK: Header

    private var header: some View {
        let h = Page.header(snap, loading: !loaded, loadError: store.isRefreshing ? nil : store.loadError)
        return HStack(alignment: .center, spacing: 14) {
            Image(nsImage: Icon.current(check, height: 46, soon: snap.changingSoon))
            VStack(alignment: .leading, spacing: 2) {
                Text(caption)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .tracking(0.6)
                HStack(spacing: 8) {
                    Text(h.title)
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .foregroundStyle(h.tone.color)
                    if h.tone == .unknown, !snapshotting { ProgressView().controlSize(.small) }
                }
                Text(h.subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
    }

    /// Mentions Seattle time when the Mac is set to another time zone
    private var caption: String {
        Seattle.differsFromLocal(snap.now) ? "I-5 EXPRESS LANES · SEATTLE TIME" : "I-5 EXPRESS LANES"
    }

    // MARK: Concerns

    private var concerns: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(check.concerns, id: \.self) { c in
                Callout(icon: "exclamationmark.triangle.fill", tint: .orange, title: c.title, text: c.detail, link: c.link)
            }
            Text(Page.liveSourcesLead)
                .font(.callout.weight(.semibold))
                .padding(.top, 2)
            HStack(spacing: 6) {
                WebLink("WSDOT Traffic on Bluesky", Sources.wsdotTraffic)
                Text("·").foregroundStyle(.secondary)
                switch Page.trafficCameras(snap.status) {
                case .section:
                    TextButton("Traffic cameras") {
                        ui.camerasOpen = true
                        ui.scrollToCameras = true
                    }
                case .url(let url):
                    WebLink("Traffic cameras", url)
                }
                Text("·").foregroundStyle(.secondary)
                WebLink("WSDOT page", Sources.expressLanes)
            }
            .font(.callout)
        }
    }

    // MARK: Notices

    @ViewBuilder private var notices: some View {
        let items = Page.noticesToday(snap)
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(items, id: \.self) { item in
                    let tone = Page.tone(item.notice.kind)
                    Callout(icon: tone.icon, tint: tone.color, title: item.notice.title, text: item.text, link: item.notice.link)
                }
            }
        }
    }

    // MARK: Timelines

    private var timelines: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionTitle(Page.timelineTitle(snap))
            TimelineRow(label: "Today", warning: Page.todayDoubt(snap)?.title, segments: snap.todaySegments,
                        nowMarker: Seattle.time(snap.now))
            TimelineRow(label: "Tomorrow", warning: snap.tomorrowDoubts.first?.title, segments: snap.tomorrowSegments, nowMarker: nil)
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

    // MARK: Travel times

    @ViewBuilder private var travelTimes: some View {
        if let t = Page.travelTimes(snap) {
            VStack(alignment: .leading, spacing: 8) {
                SectionTitle("Travel times")
                Grid(alignment: .topLeading, horizontalSpacing: 14, verticalSpacing: 8) {
                    GridRow {
                        Color.clear.gridCellUnsizedAxes([.horizontal, .vertical])
                        Text("Express lanes").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                        Text("Regular lanes").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    }
                    ForEach(t.rows, id: \.self) { row in
                        GridRow {
                            Text(row.label).fontWeight(.medium)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(row.express).monospacedDigit()
                                if let saves = row.saves {
                                    Text("saves \(saves) min").font(.caption).foregroundStyle(LaneStatus.northbound.color)
                                }
                            }
                            VStack(alignment: .leading, spacing: 1) {
                                Text(row.regular).monospacedDigit()
                                if let usual = row.times.usual {
                                    Text("usually \(usual)").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                .font(.callout)
                Hint(t.hint)
            }
        }
    }

    // MARK: Cameras

    @ViewBuilder private var cameras: some View {
        let all = snap.status.cameras
        if !all.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SectionTitle("Cameras")
                TextButton(Cameras.summary(all, open: ui.camerasOpen), chevron: ui.camerasOpen ? "chevron.down" : "chevron.right") {
                    ui.camerasOpen.toggle()
                }
                .font(.callout)
                if ui.camerasOpen {
                    CameraGrid(cameras: Cameras.shown(all, all: ui.allCameras), now: snap.now, ui: ui)
                    if let toggle = Cameras.toggleText(all, all: ui.allCameras) {
                        TextButton(toggle) { ui.allCameras.toggle() }
                            .font(.callout)
                    }
                    Hint(Cameras.hint)
                    WebLink(Cameras.travelMapLink, Sources.travelMap).font(.caption)
                }
            }
            .id(Self.camerasID)
        }
    }

    // MARK: Coming up

    private var comingUp: some View {
        let changes = Page.comingUp(snap)
        return VStack(alignment: .leading, spacing: 6) {
            SectionTitle("Coming up")
            if changes.isEmpty {
                Hint("No changes coming up.")
            }
            ForEach(changes, id: \.self) { change in
                HStack(spacing: 8) {
                    Circle().fill(change.to.color).frame(width: 8, height: 8)
                    Text(change.to.title).fontWeight(.medium)
                    if Page.doubtful(snap, change.at) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                            .help("This day may not go as planned")
                    }
                    Spacer()
                    Text(Format.when(change.at, now: snap.now))
                        .monospacedDigit()
                    Text(Format.countdown(to: change.at, from: snap.now))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 58, alignment: .trailing)
                }
                .font(.callout)
            }
            if changes.contains(where: { Page.doubtful(snap, $0.at) }) {
                Hint("⚠ marks days that may not go as planned.")
            }
        }
    }

    // MARK: Planned changes

    @ViewBuilder private var planned: some View {
        if let p = Page.planned(snap) {
            VStack(alignment: .leading, spacing: 12) {
                SectionTitle("Planned changes")
                ForEach(Array(p.notices.enumerated()), id: \.offset) { i, item in
                    plannedNotice(i, item)
                }
                ForEach(p.holidays, id: \.self) { h in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(h.title).fontWeight(.semibold)
                        Text(h.detail).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                    }
                    .font(.callout)
                }
            }
        }
    }

    private func plannedNotice(_ i: Int, _ item: Page.PlannedNotice) -> some View {
        let showAll = ui.allTimes.contains(i)
        let times = showAll ? item.times : item.shownTimes
        return VStack(alignment: .leading, spacing: 4) {
            Text(item.notice.title).font(.callout.weight(.semibold))
            VStack(alignment: .leading, spacing: 1) {
                ForEach(Array(times.enumerated()), id: \.offset) { _, t in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("•")
                        Text(t).monospacedDigit()
                    }
                }
                if !showAll, let more = item.moreLabel {
                    TextButton("…") { ui.allTimes.insert(i) }
                        .padding(.leading, 12)
                        .help(more)
                        .accessibilityLabel(more)
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            if let note = item.note {
                Text(note).font(.callout).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }
            let open = ui.openWords.contains(i)
            TextButton(item.wordsTitle, chevron: open ? "chevron.down" : "chevron.right") {
                if open { ui.openWords.remove(i) } else { ui.openWords.insert(i) }
            }
            .font(.callout)
            if open {
                Text(item.notice.detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
            if let link = item.moreInfo {
                WebLink("More info", link).font(.callout)
            }
        }
    }

    // MARK: Regular schedule

    private var regularSchedule: some View {
        let r = Page.regularSchedule(snap)
        return VStack(alignment: .leading, spacing: 6) {
            SectionTitle("Regular schedule")
            if let hint = r.hint { Hint(hint) }
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                ScheduleRow(label: "Mon–Fri", windows: r.schedule.weekday)
                ScheduleRow(label: "Sat–Sun", windows: r.schedule.weekend)
            }
            .font(.callout)
        }
    }

    // MARK: Sources

    private var sources: some View {
        VStack(alignment: .leading, spacing: 6) {
            SectionTitle("Sources")
            ForEach(Page.sources(snap), id: \.self) { s in
                SourceLink(title: s.title, subtitle: s.subtitle, url: s.url)
            }
            Hint(Page.sourcesHint).padding(.top, 4)
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(alignment: .top, spacing: 10) {
            dataStatus
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
        .help("Refresh")
        .keyboardShortcut("r")

        // Opens the same menu as right-clicking the icon
        Button(action: openMenu) {
            Image(systemName: "gearshape")
        }
        .buttonStyle(.borderless)
        .help("Settings")
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("popover")) } action: { gearMoved($0) }
    }

    private var dataStatus: some View {
        let status = !loaded && store.loadError != nil
            ? (text: "Nothing saved yet", warn: true)
            : Page.dataStatus(snap, loaded: loaded)
        return VStack(alignment: .leading, spacing: 2) {
            Label(status.text, systemImage: status.warn ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                .foregroundStyle(status.warn ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary))
                .fixedSize(horizontal: false, vertical: true)
            if let reading = Page.readingText(snap) {
                Text(reading).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if let live = Page.liveText(snap) {
                Text(live).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if let e = store.settingsMessage ?? store.loadError {
                Text(e).foregroundStyle(.red).lineLimit(3)
            }
        }
        .font(.caption)
    }
}

// MARK: Pieces

extension Page.Tone {
    var color: Color {
        switch self {
        case .northbound: LaneStatus.northbound.color
        case .southbound: LaneStatus.southbound.color
        case .closed: LaneStatus.closed.color
        case .unknown: .secondary
        case .warning: .orange
        }
    }
}

extension Page.NoticeTone {
    var color: Color {
        switch self {
        case .bad: .red
        case .warn: .orange
        case .muted: .gray
        }
    }

    var icon: String {
        switch self {
        case .bad: "xmark.octagon.fill"
        case .warn: "exclamationmark.triangle.fill"
        case .muted: "clock.arrow.circlepath"
        }
    }
}

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

private struct Hint: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct Callout: View {
    let icon: String
    let tint: Color
    let title: String
    let text: String
    var link: String? = nil

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
    let segments: [DaySegment]
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
                            Group {
                                if s.status == .unknown {
                                    Stripes().stroke(Color.secondary.opacity(0.45), lineWidth: 1.5)
                                } else {
                                    Rectangle().fill(s.status.timelineColor)
                                }
                            }
                            .frame(width: max(1, w * fraction(s.end) - w * fraction(s.start)))
                            .clipped()
                            .offset(x: w * fraction(s.start))
                            .help("\(s.status.title) \(timeLabel(s.start))–\(timeLabel(s.end))")
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
            .accessibilityElement()
            .accessibilityLabel("\(label): \(Page.timelineSummary(segments))")
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
        CGFloat(t) / CGFloat(24 * 60)
    }
}

/// Diagonal lines for times the timeline doesn't cover
private struct Stripes: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        var x = rect.minX - rect.height
        while x < rect.maxX {
            p.move(to: CGPoint(x: x, y: rect.maxY))
            p.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
            x += 6
        }
        return p
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
                        Text("\(w.status.title)  \(timeLabel(w.start)) – \(timeLabel(w.end))")
                            .monospacedDigit()
                    }
                }
            }
        }
    }
}

/// Two pictures per row, express lane cameras first. The expanded one gets a row to itself.
private struct CameraGrid: View {
    let cameras: [Camera]
    let now: Moment
    @ObservedObject var ui: PopoverState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(Cameras.rows(cameras, expanded: ui.expandedCamera), id: \.first?.id) { row in
                HStack(alignment: .top, spacing: 10) {
                    ForEach(row) { c in cell(c) }
                    if row.count == 1, row[0].id != ui.expandedCamera {
                        Color.clear.frame(maxWidth: .infinity, maxHeight: 1)
                    }
                }
            }
        }
    }

    private func cell(_ c: Camera) -> some View {
        CameraCell(camera: c, now: now, loader: ui.picture(c.id), expanded: c.id == ui.expandedCamera) {
            ui.expandedCamera = ui.expandedCamera == c.id ? nil : c.id
        }
        .id(PopoverView.cameraID(c.id))
    }
}

private struct CameraCell: View {
    let camera: Camera
    let now: Moment
    @ObservedObject var loader: PictureLoader
    let expanded: Bool
    let toggle: () -> Void
    @Environment(\.snapshotting) private var snapshotting

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Group {
                if snapshotting {
                    picture
                } else {
                    // Shows it bigger, or smaller again
                    Button(action: toggle) { picture }
                        .buttonStyle(.plain)
                        .linkCursor()
                        .help(expanded ? "Show a smaller picture" : "Show a bigger picture")
                }
            }
            Text(camera.name).font(.caption.weight(.semibold)).lineLimit(2)
            HStack(spacing: 4) {
                Text(Cameras.milepost(camera))
                Text("·")
                WebLink("map", Cameras.mapLink(camera))
                if expanded {
                    Text("·")
                    WebLink(Cameras.openInBrowser, Cameras.imageURL(camera, now: now))
                }
                Spacer(minLength: 4)
                reloadButton
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var picture: some View {
        CameraPicture(camera: camera, now: now, expanded: expanded, loader: loader)
    }

    @ViewBuilder private var reloadButton: some View {
        if snapshotting {
            Image(systemName: "arrow.clockwise").foregroundStyle(Color.accentColor)
        } else {
            Button { loader.reload(now: now) } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(.borderless)
                .help(Cameras.reloadHelp)
                .accessibilityLabel(Cameras.reloadLabel(camera))
        }
    }
}

/// WSDOT's picture. Keeps showing the old one while a new one loads.
private struct CameraPicture: View {
    let camera: Camera
    let now: Moment
    let expanded: Bool
    @ObservedObject var loader: PictureLoader
    @Environment(\.snapshotting) private var snapshotting
    @Environment(\.cameraImages) private var preloaded

    var body: some View {
        let shown = loader.image ?? preloaded[camera.image]
        // A fixed height, since the scrolling popover gives no height to fit into.
        // The expanded one takes the picture's shape, so none of it gets cut off.
        let shape = shown.map { $0.size.width / max(1, $0.size.height) } ?? 4 / 3
        Rectangle().fill(Color.secondary.opacity(0.15))
            .frame(maxWidth: .infinity)
            .frame(height: expanded ? PopoverView.contentWidth / shape : 132)
            .overlay {
                if loader.gaveUp {
                    VStack(spacing: 4) {
                        Image(systemName: "photo").font(.title2).foregroundStyle(.tertiary)
                        Text(Cameras.failed).font(.caption).foregroundStyle(.secondary)
                    }
                } else if let shown {
                    Image(nsImage: shown).resizable().scaledToFill()
                } else if snapshotting {
                    Image(systemName: "photo").font(.title2).foregroundStyle(.tertiary)
                } else {
                    ProgressView().controlSize(.small)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
        .accessibilityLabel(loader.gaveUp ? "\(Cameras.failed) from \(camera.name)" : "WSDOT camera at \(camera.name)")
        .task(id: loader.url(camera, now: now)) {
            if !snapshotting { await loader.load(camera, now: now) }
        }
    }
}

/// One camera's picture. When it fails, it tries again after 5, 15 and 45 seconds, then gives up.
@MainActor final class PictureLoader: ObservableObject {
    @Published private(set) var image: NSImage?
    /// Every try failed, so the picture's spot says so
    @Published private(set) var gaveUp = false
    /// Retries and reload clicks since the 5-minute version changed. Each one changes the address.
    @Published private(set) var reloads = 0
    private var failures = 0
    private var version: Int?

    /// Changing it restarts the view's task, which loads the picture again
    func url(_ camera: Camera, now: Moment) -> String {
        Cameras.imageURL(camera, now: now, reload: Cameras.version(now) == version ? reloads : 0)
    }

    func load(_ camera: Camera, now: Moment) async {
        newVersion(now)
        // Opening the section again after giving up starts the retries over
        if gaveUp {
            failures = 0
            gaveUp = false
        }
        guard let u = URL(string: url(camera, now: now)) else { return }
        var req = URLRequest(url: u, timeoutInterval: 20)
        req.setValue(Store.userAgent, forHTTPHeaderField: "User-Agent")
        if let (data, _) = try? await URLSession.shared.data(for: req), let loaded = NSImage(data: data) {
            image = loaded
            failures = 0
            return
        }
        if Task.isCancelled { return }
        failures += 1
        guard let delay = Cameras.retryDelay(afterFailures: failures) else {
            gaveUp = true
            return
        }
        try? await Task.sleep(for: .milliseconds(delay))
        if Task.isCancelled { return }
        reloads += 1
    }

    /// The reload button. Tries now with a new address and starts the retries over.
    func reload(now: Moment) {
        newVersion(now)
        failures = 0
        gaveUp = false
        reloads += 1
    }

    private func newVersion(_ now: Moment) {
        let v = Cameras.version(now)
        guard v != version else { return }
        version = v
        reloads = 0
        failures = 0
        gaveUp = false
    }
}

private struct SourceLink: View {
    let title: String
    let subtitle: String
    let url: String

    @Environment(\.snapshotting) private var snapshotting

    var body: some View {
        Group {
            if snapshotting {
                label
            } else if let u = URL(string: url) {
                Link(destination: u) { label }.linkCursor()
            }
        }
        .font(.callout)
        .help(url)
    }

    private var label: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.up.right.square").foregroundStyle(Color.accentColor)
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
    let url: String
    @Environment(\.snapshotting) private var snapshotting

    init(_ title: String, _ url: String) {
        self.title = title
        self.url = url
    }

    var body: some View {
        if snapshotting {
            Text(title).foregroundStyle(Color.accentColor)
        } else if let u = URL(string: url) {
            Link(title, destination: u).linkCursor().help(url)
        }
    }
}

/// A button that looks like a link, for things that open in the popover
private struct TextButton: View {
    let title: String
    var chevron: String?
    let action: () -> Void
    @Environment(\.snapshotting) private var snapshotting

    init(_ title: String, chevron: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.chevron = chevron
        self.action = action
    }

    var body: some View {
        if snapshotting {
            label
        } else {
            Button(action: action) { label }
                .buttonStyle(.plain)
                .linkCursor()
        }
    }

    private var label: some View {
        HStack(spacing: 4) {
            if let chevron {
                Image(systemName: chevron).font(.caption2.weight(.semibold)).frame(width: 10)
            }
            Text(title)
        }
        .foregroundStyle(Color.accentColor)
        .contentShape(Rectangle())
    }
}

extension View {
    /// The pointing hand, like links on a web page
    @ViewBuilder func linkCursor() -> some View {
        if #available(macOS 15, *) {
            pointerStyle(.link)
        } else {
            onHover { inside in
                if inside { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
        }
    }
}

// Written out by hand, since the Command Line Tools don't ship the @Entry macro
private struct SnapshottingKey: EnvironmentKey {
    static let defaultValue = false
}

private struct CameraImagesKey: EnvironmentKey {
    static let defaultValue: [String: NSImage] = [:]
}

extension EnvironmentValues {
    /// True while rendering PNG snapshots
    var snapshotting: Bool {
        get { self[SnapshottingKey.self] }
        set { self[SnapshottingKey.self] = newValue }
    }

    /// Camera pictures downloaded ahead of time for snapshots, by their address
    var cameraImages: [String: NSImage] {
        get { self[CameraImagesKey.self] }
        set { self[CameraImagesKey.self] = newValue }
    }
}
