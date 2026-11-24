import FossifyCommons
import SwiftUI

/// DayFragmentsHolder + DayFragment.
struct DayHolder: View {
    @Environment(CalendarStore.self) private var store
    let anchor: String
    @Binding var current: String
    let onTitle: () -> Void
    @State private var index = 0
    @State private var selection = Set<String>()
    @State private var visibleEvents: [Event] = []

    var body: some View {
        let base = Formatter.getLocalDateTimeFromCode(anchor)
        VStack(spacing: 0) {
            if !selection.isEmpty {
                SelectionBar(selection: $selection, events: visibleEvents)
            }
            Pager(index: $index) { i in
                DayPage(code: Formatter.getDayCodeFromDateTime(base.plusDays(i)), selection: $selection,
                        onPrevious: { index -= 1 }, onNext: { index += 1 }, onTitle: onTitle) { events in
                    if i == index { visibleEvents = events }
                }
            }
        }
        .onAppear { current = anchor }
        .onChange(of: index) { _, i in
            current = Formatter.getDayCodeFromDateTime(base.plusDays(i))
            selection.removeAll()
        }
    }
}

struct DayPage: View {
    @Environment(CalendarStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(Config.self) private var config
    @Environment(\.palette) private var palette
    let code: String
    @Binding var selection: Set<String>
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onTitle: () -> Void
    let onLoaded: ([Event]) -> Void
    @State private var events: [Event] = []

    var body: some View {
        VStack(spacing: 0) {
            TopNavigation(title: Formatter.getDayTitle(code),
                          onPrevious: onPrevious, onTitle: onTitle, onNext: onNext)
            ScrollView {
                LazyVStack(spacing: 0) {
                    EventListItems(items: getEventListItems(events, addSectionDays: false, addSectionMonths: false),
                                   selection: $selection) { router.open($0.ref) }
                }
                .padding(.bottom, 90)
            }
            .refreshable(enabled: config.caldavSync && config.pullToRefresh) {
                await MainActor.run { store.refreshSystemCalendars(showToast: true) }
            }
        }
        .task(id: "\(code)-\(store.revision)-\(config.displayCalendars.count)") {
            events = store.getEvents(from: Formatter.getDayStartTS(code), to: Formatter.getDayEndTS(code))
            onLoaded(events)
        }
    }
}

/// EventListFragment: upcoming events with endless scrolling in both directions.
struct EventListHolder: View {
    @Environment(CalendarStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(Config.self) private var config
    @Environment(\.palette) private var palette
    @State private var minFetched: Int64 = 0
    @State private var maxFetched: Int64 = 0
    @State private var events: [Event] = []
    @State private var selection = Set<String>()
    @State private var didScroll = false

    var body: some View {
        VStack(spacing: 0) {
            if !selection.isEmpty {
                SelectionBar(selection: $selection, events: events)
            }
            if events.isEmpty && maxFetched != 0 {
                Placeholder(text: config.displayCalendars.isEmpty ? "You have filtered out all calendars" : "No upcoming events.",
                            action: "Create a new event") { router.newEvent() }
            } else {
                let items = getEventListItems(events)
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            Color.clear.frame(height: 1).onAppear { if didScroll { fetchPrevious() } }
                            EventListItems(items: items, selection: $selection) { router.open($0.ref) }
                            Color.clear.frame(height: 1).onAppear { fetchNext() }
                        }
                        .padding(.bottom, 90)
                    }
                    .refreshable(enabled: config.caldavSync && config.pullToRefresh) {
                        await MainActor.run { store.refreshSystemCalendars(showToast: true) }
                    }
                    .onChange(of: events.count) { _, _ in
                        guard !didScroll else { return }
                        didScroll = true
                        let now = getNowSeconds()
                        if let first = items.first(where: { if case let .event(e) = $0 { return e.endTS >= now || e.isAllDay && Formatter.getDayCodeFromTS(e.startTS) >= Formatter.getTodayCode() } else { return false } }) {
                            proxy.scrollTo(first.id, anchor: .top)
                        }
                    }
                }
            }
        }
        .task(id: "\(store.revision)-\(config.displayCalendars.count)") { initialFetch() }
    }

    private func initialFetch() {
        let now = getNowSeconds()
        let from = minFetched == 0 ? now - Int64(config.displayPastEvents * 60) : minFetched
        let to = maxFetched == 0 ? now + Int64(YEAR) : maxFetched
        minFetched = from
        maxFetched = to
        events = store.getEvents(from: from, to: to)
    }

    private func fetchPrevious() {
        let old = minFetched - 1
        minFetched -= FETCH_INTERVAL
        merge(store.getEvents(from: minFetched, to: old))
    }

    private func fetchNext() {
        guard maxFetched != 0, maxFetched < MAX_SEARCH_YEAR else { return }
        let old = maxFetched + 1
        maxFetched += FETCH_INTERVAL
        merge(store.getEvents(from: old, to: maxFetched))
    }

    private func merge(_ new: [Event]) {
        let keys = Set(events.map(\.occurrenceKey))
        let add = new.filter { !keys.contains($0.occurrenceKey) }
        if !add.isEmpty { events += add }
    }
}

/// Printable day / event list (printView of DayFragment and EventListFragment).
struct PrintableList: View {
    @Environment(CalendarStore.self) private var store
    let title: String
    let from: Int64
    let to: Int64

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title).font(.system(size: 24, weight: .medium)).foregroundColor(.black).padding(.bottom, 12)
            EventListItems(items: Array(getEventListItems(store.getEvents(from: from, to: to)).prefix(40)),
                           selection: .constant([])) { _ in }
            Spacer(minLength: 0)
        }
        .padding(24)
    }
}

/// YearFragmentsHolder + YearFragment.
struct YearHolder: View {
    let anchor: String
    @Binding var current: String
    let onOpenMonth: (String) -> Void
    let onTitle: () -> Void
    @State private var index = 0

    var body: some View {
        let baseYear = Int(anchor.prefix(4)) ?? JDate.now().year
        Pager(index: $index) { i in
            YearPage(year: baseYear + i, onPrevious: { index -= 1 }, onNext: { index += 1 }, onTitle: onTitle, onOpenMonth: onOpenMonth)
        }
        .onAppear { current = "\(baseYear)0101" }
        .onChange(of: index) { _, i in current = "\(baseYear + i)0101" }
    }
}

struct YearPage: View {
    @Environment(CalendarStore.self) private var store
    @Environment(Config.self) private var config
    @Environment(\.palette) private var palette
    let year: Int
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onTitle: () -> Void
    let onOpenMonth: (String) -> Void
    @State private var colors: [String: UInt32] = [:]

    var body: some View {
        VStack(spacing: 0) {
            TopNavigation(title: String(year), titleColor: year == JDate.now().year ? palette.primaryColor : nil,
                          onPrevious: onPrevious, onTitle: onTitle, onNext: onNext)
            YearGrid(year: year, colors: colors, onOpenMonth: onOpenMonth)
                .padding(.horizontal, 8)
        }
        .task(id: "\(year)-\(store.revision)-\(config.displayCalendars.count)") { colors = yearColors(store, year: year) }
    }
}

/// YearlyCalendarImpl: the first event color of every day with events.
@MainActor
func yearColors(_ store: CalendarStore, year: Int) -> [String: UInt32] {
    let start = JDate.now().withDate(year, 1, 1).withTimeAtStartOfDay
    let events = store.getEvents(from: start.seconds, to: start.plusYears(1).seconds - 1)
        .sorted { ($0.startTS, $0.endTS) < ($1.startTS, $1.endTS) }
    var result: [String: UInt32] = [:]
    for e in events {
        var cur = JDate(ts: e.startTS)
        let end = Formatter.getDayCodeFromTS(e.endTS)
        var code = Formatter.getDayCodeFromDateTime(cur)
        var guardCount = 0
        repeat {
            if result[code] == nil { result[code] = e.color }
            cur = cur.plusDays(1)
            code = Formatter.getDayCodeFromDateTime(cur)
            guardCount += 1
        } while code <= end && guardCount < 400
    }
    return result
}

struct YearGrid: View {
    @Environment(\.palette) private var palette
    let year: Int
    let colors: [String: UInt32]
    var isPrintVersion = false
    let onOpenMonth: (String) -> Void

    var body: some View {
        Grid(horizontalSpacing: 12, verticalSpacing: 8) {
            ForEach(0..<4, id: \.self) { row in
                GridRow {
                    ForEach(0..<3, id: \.self) { col in
                        let month = row * 3 + col + 1
                        SmallMonth(year: year, month: month, colors: colors, isPrintVersion: isPrintVersion)
                            .contentShape(Rectangle())
                            .onTapGesture { onOpenMonth(String(format: "%04d%02d01", year, month)) }
                    }
                }
            }
        }
    }
}

/// views/SmallMonthView.kt
struct SmallMonth: View {
    @Environment(\.palette) private var palette
    @Environment(Config.self) private var config
    let year: Int
    let month: Int
    let colors: [String: UInt32]
    var isPrintVersion = false

    var body: some View {
        let now = JDate.now()
        let isCurrent = now.year == year && now.monthOfYear == month
        let textColor = isPrintVersion ? Color(argb: 0xFF2D2D2D) : palette.textColor
        VStack(alignment: .leading, spacing: 2) {
            Text(Formatter.getMonthName(month))
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(isCurrent && !isPrintVersion ? palette.primaryColor : textColor)
            Canvas { ctx, size in
                let first = JDate.now().withDate(year, month, 1).withTimeAtStartOfDay
                let firstDay = getProperDayIndexInWeek(first)
                let days = first.maxDayOfMonth
                let dayW = size.width / 7
                let todayCode = Formatter.getTodayCode()
                var cur = 1 - firstDay
                for y in 0..<6 {
                    for x in 0..<7 {
                        if (1...days).contains(cur) {
                            let code = String(format: "%04d%02d%02d", year, month, cur)
                            var c = textColor.opacity(MEDIUM_ALPHA)
                            if let ev = colors[code] {
                                c = Color(argb: ev)
                            } else if config.highlightWeekends && isWeekendIndex(x) {
                                c = Color(argb: config.highlightWeekendsColor).opacity(MEDIUM_ALPHA)
                            }
                            let center = CGPoint(x: CGFloat(x) * dayW + dayW / 2, y: CGFloat(y) * dayW + dayW / 2)
                            ctx.draw(Text("\(cur)").font(.system(size: 9)).foregroundColor(c), at: center)
                            if code == todayCode && !isPrintVersion {
                                let r = dayW * 0.41
                                ctx.fill(Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)),
                                         with: .color(palette.primaryColor.opacity(MEDIUM_ALPHA)))
                            }
                        }
                        cur += 1
                    }
                }
            }
            .aspectRatio(7.0 / 6.0, contentMode: .fit)
        }
    }
}

struct PrintableYear: View {
    @Environment(CalendarStore.self) private var store
    let year: Int

    var body: some View {
        VStack(spacing: 16) {
            Text(String(year)).font(.system(size: 28, weight: .medium)).foregroundColor(.black)
            YearGrid(year: year, colors: yearColors(store, year: year), isPrintVersion: true) { _ in }
            Spacer(minLength: 0)
        }
        .padding(24)
    }
}
