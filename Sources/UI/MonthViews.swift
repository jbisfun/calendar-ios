import FossifyCommons
import SwiftUI

/// models/DayMonthly.kt
struct DayMonthly {
    var value: Int
    var isThisMonth: Bool
    var isToday: Bool
    var code: String
    var weekOfYear: Int
    var dayEvents: [Event]
    var indexOnMonthView: Int
    var isWeekend: Bool
}

/// MonthlyCalendarImpl.getDays() + markDaysWithEvents()
@MainActor
func monthDays(_ store: CalendarStore, month target: JDate) -> [DayMonthly] {
    let first = target.withDayOfMonth(1)
    let firstIndex = getProperDayIndexInWeek(first)
    let start = first.minusDays(firstIndex).withTimeAtStartOfDay
    let today = Formatter.getTodayCode()
    var days: [DayMonthly] = []
    for i in 0..<42 {
        let d = start.plusDays(i)
        let code = Formatter.getDayCodeFromDateTime(d)
        days.append(DayMonthly(value: d.dayOfMonth, isThisMonth: d.monthOfYear == target.monthOfYear, isToday: code == today,
                               code: code, weekOfYear: d.weekOfWeekyear, dayEvents: [], indexOnMonthView: i, isWeekend: isWeekendIndex(i % 7)))
    }
    let events = store.getEvents(from: target.minusDays(7).seconds, to: target.plusDays(43).seconds)
    var byDay: [String: [Event]] = [:]
    for e in events {
        var cur = JDate(ts: e.startTS)
        let endCode = Formatter.getDayCodeFromTS(e.endTS)
        var code = Formatter.getDayCodeFromDateTime(cur)
        byDay[code, default: []].append(e)
        var guardCount = 0
        while code != endCode && code < endCode && guardCount < 400 {
            cur = cur.plusDays(1)
            code = Formatter.getDayCodeFromDateTime(cur)
            byDay[code, default: []].append(e)
            guardCount += 1
        }
    }
    for i in days.indices { days[i].dayEvents = byDay[days[i].code] ?? [] }
    return days
}

/// models/MonthViewEvent.kt
private struct MonthViewEvent {
    var identity: String
    var title: String
    var startTS: Int64
    var endTS: Int64
    var color: UInt32
    var startDayIndex: Int
    var daysCnt: Int
    var isAllDay: Bool
    var isPastEvent: Bool
    var isTask: Bool
    var isTaskCompleted: Bool
    var strike: Bool
}

/// views/MonthView.kt drawn with a Canvas.
struct MonthGrid: View {
    @Environment(\.palette) private var palette
    @Environment(Config.self) private var config
    let days: [DayMonthly]
    var isMonthDayView = false
    var selectedIndex: Int?
    var isPrintVersion = false
    var onTap: (DayMonthly) -> Void = { _ in }

    private let normalText: CGFloat = 15
    private let smallerText: CGFloat = 11
    private let pad: CGFloat = 1

    var body: some View {
        GeometryReader { geo in
            Canvas { ctx, size in draw(&ctx, size) }
                .contentShape(Rectangle())
                .onTapGesture(coordinateSpace: .local) { loc in
                    let h = horizontalOffset
                    let letterH = normalText * 2
                    let dayW = (geo.size.width - h) / 7
                    let dayH = (geo.size.height - letterH) / 6
                    guard loc.y > letterH, loc.x > h else { return }
                    let x = min(6, Int((loc.x - h) / dayW))
                    let y = min(5, Int((loc.y - letterH) / dayH))
                    if let day = days[safe: y * 7 + x] { onTap(day) }
                }
        }
    }

    private var horizontalOffset: CGFloat { config.showWeekNumbers ? 28 : 0 }

    private func text(_ s: String, size: CGFloat, color: Color, weight: Font.Weight = .regular) -> Text {
        Text(s).font(.system(size: size, weight: weight)).foregroundColor(color)
    }

    private func draw(_ ctx: inout GraphicsContext, _ size: CGSize) {
        guard days.count == 42 else { return }
        let textColor = isPrintVersion ? Color(argb: 0xFF2D2D2D) : palette.textColor
        let primary = palette.primaryColor
        let weekendColor = Color(argb: config.highlightWeekendsColor)
        let h = horizontalOffset
        let letterH = normalText * 2
        let dayW = (size.width - h) / 7
        let dayH = (size.height - letterH) / 6
        var offsets = [Int: CGFloat]()

        if config.showGrid && !isMonthDayView {
            var path = Path()
            for i in 0..<7 {
                let x = CGFloat(i) * dayW + h
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
            }
            path.move(to: .zero)
            path.addLine(to: CGPoint(x: size.width, y: 0))
            for i in 0..<6 {
                let y = CGFloat(i) * dayH + letterH
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            }
            path.move(to: CGPoint(x: 0, y: size.height))
            path.addLine(to: CGPoint(x: size.width, y: size.height))
            ctx.stroke(path, with: .color(textColor.opacity(LOWER_ALPHA)), lineWidth: 0.5)
        }

        // week day letters
        let letters = weekDayLettersShort()
        let currentDow = days.contains { $0.isToday && $0.isThisMonth } ? getProperDayIndexInWeek(JDate.now()) : -1
        for i in 0..<7 {
            var c = textColor
            if i == currentDow && !isPrintVersion { c = primary } else if config.highlightWeekends && isWeekendIndex(i) { c = weekendColor }
            ctx.draw(text(letters[i], size: normalText, color: c), at: CGPoint(x: h + CGFloat(i) * dayW + dayW / 2, y: letterH * 0.45))
        }

        if config.showWeekNumbers {
            for row in 0..<6 {
                let week = days[row * 7 ..< row * 7 + 7]
                let c = week.contains { $0.isToday && !isPrintVersion } ? primary : textColor
                let number = days[row * 7 + 3].weekOfYear
                ctx.draw(text("\(number):", size: normalText - 2, color: c),
                         at: CGPoint(x: h * 0.5, y: CGFloat(row) * dayH + letterH + normalText * 0.6))
            }
        }

        for row in 0..<6 {
            for col in 0..<7 {
                let idx = row * 7 + col
                let day = days[idx]
                offsets[idx, default: 0] += letterH
                let vOff = offsets[idx]!
                let xPos = CGFloat(col) * dayW + h
                let yPos = CGFloat(row) * dayH + vOff
                let center = CGPoint(x: xPos + dayW / 2, y: yPos + normalText * 0.6)
                let radius = normalText * 0.8
                let circle = Path(ellipseIn: CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2))
                let selected = selectedIndex == idx
                var numberColor: Color
                if !isPrintVersion && day.isToday && !selected {
                    numberColor = palette.onPrimary
                } else if config.highlightWeekends && day.isWeekend {
                    numberColor = weekendColor
                } else {
                    numberColor = textColor
                }
                if selected {
                    ctx.stroke(circle, with: .color(primary), lineWidth: 2)
                } else if day.isToday && !isPrintVersion {
                    ctx.fill(circle, with: .color(day.isThisMonth ? primary : primary.opacity(MEDIUM_ALPHA)))
                }
                if !day.isThisMonth { numberColor = numberColor.opacity(MEDIUM_ALPHA) }

                if isMonthDayView && !selected && !day.isToday && !day.dayEvents.isEmpty {
                    var seen = Set<UInt32>()
                    let colors = day.dayEvents.sorted { ($0.startTS, $0.endTS, $0.title) < ($1.startTS, $1.endTS, $1.title) }
                        .map(\.color).filter { seen.insert($0).inserted }
                    let dotR = normalText * 0.2
                    let step = dotR * 2.5
                    let shown = min(colors.count, 3)
                    var x = center.x - step * CGFloat(shown - 1) / 2
                    let y = center.y + normalText * 1.1
                    for (i, c) in colors.enumerated() {
                        if day.dayEvents.count - 1 != i && i >= 2 && colors.count > 3 {
                            ctx.draw(text("+", size: step * 1.5, color: textColor.opacity(0.7)), at: CGPoint(x: x, y: y))
                            break
                        }
                        if i >= 3 { break }
                        ctx.fill(Path(ellipseIn: CGRect(x: x - dotR, y: y - dotR, width: dotR * 2, height: dotR * 2)), with: .color(Color(argb: c)))
                        x += step
                    }
                }

                ctx.draw(text("\(day.value)", size: normalText, color: numberColor), at: center)
                offsets[idx] = vOff + normalText * 2
            }
        }

        guard !isMonthDayView else { return }
        for e in groupAllEvents() {
            drawEvent(e, &ctx, size: size, offsets: &offsets, dayW: dayW, dayH: dayH, textColor: textColor)
        }
    }

    private func identity(_ e: Event) -> String { e.ekID ?? "\(e.id ?? 0)" }

    private func groupAllEvents() -> [MonthViewEvent] {
        var all: [MonthViewEvent] = []
        for day in days {
            for e in day.dayEvents {
                // an event ending exactly at this day's midnight doesn't belong to it
                let dayStart = Formatter.getDayStartTS(day.code)
                let validDayEvent = e.startTS != e.endTS && e.endTS == dayStart
                let last = all.last { $0.identity == identity(e) }
                let notYetAdded = last == nil || last!.endTS <= e.startTS
                let canOverlap = e.endTS - e.startTS > Int64(e.repeatInterval)
                let shouldAdd = notYetAdded || (canOverlap && last!.startTS < e.startTS)
                if shouldAdd && !validDayEvent {
                    all.append(MonthViewEvent(identity: identity(e), title: e.title, startTS: e.startTS, endTS: e.endTS, color: e.color,
                                              startDayIndex: day.indexOnMonthView, daysCnt: lastingDays(e), isAllDay: e.isAllDay,
                                              isPastEvent: e.isPastEvent, isTask: e.isTask, isTaskCompleted: e.isTaskCompleted,
                                              strike: e.shouldStrikeThrough))
                }
            }
        }
        return all.sorted { a, b in
            if a.daysCnt != b.daysCnt { return a.daysCnt > b.daysCnt }
            if a.isAllDay != b.isAllDay { return a.isAllDay }
            if a.startTS != b.startTS { return a.startTS < b.startTS }
            if a.endTS != b.endTS { return a.endTS < b.endTS }
            if a.startDayIndex != b.startDayIndex { return a.startDayIndex < b.startDayIndex }
            return a.title < b.title
        }
    }

    /// Take into account cases when an event starts on the previous screen, subtract those days.
    private func lastingDays(_ e: Event) -> Int {
        let screenStart = Formatter.getLocalDateTimeFromCode(days[0].code)
        var start = JDate(ts: e.startTS).withTimeAtStartOfDay
        let endDT = JDate(ts: e.endTS)
        if start < screenStart { start = screenStart }
        let isMidnight = endDT.seconds == endDT.withTimeAtStartOfDay.seconds
        let numDays = JDate.daysBetween(start, endDT)
        return (numDays == 1 && isMidnight ? 0 : numDays) + 1
    }

    private func drawEvent(_ event: MonthViewEvent, _ ctx: inout GraphicsContext, size: CGSize, offsets: inout [Int: CGFloat],
                           dayW: CGFloat, dayH: CGFloat, textColor: Color) {
        let h = horizontalOffset
        let titleH = smallerText + 2
        let covered = min(event.daysCnt, 7 - event.startDayIndex % 7)
        var vOff: CGFloat = 0
        for i in 0..<covered { vOff = max(vOff, offsets[event.startDayIndex + i] ?? 0) }
        let xPos = CGFloat(event.startDayIndex % 7) * dayW + h
        let yPos = CGFloat(event.startDayIndex / 7) * dayH
        if vOff - titleH * 2 > dayH - titleH {
            ctx.draw(Text("...").font(.system(size: normalText)).foregroundColor(textColor),
                     at: CGPoint(x: xPos + dayW / 2, y: yPos + vOff - titleH))
            return
        }
        let left = xPos + pad
        let top = yPos + vOff + pad - titleH
        var right = xPos - pad + dayW * CGFloat(event.daysCnt)
        let bottom = yPos + vOff + pad * 2
        if right > size.width {
            right = size.width - pad
            let next = (event.startDayIndex / 7 + 1) * 7
            if next < 42 {
                var cont = event
                cont.startDayIndex = next
                cont.daysCnt = event.daysCnt - (next - event.startDayIndex)
                drawEvent(cont, &ctx, size: size, offsets: &offsets, dayW: dayW, dayH: dayH, textColor: textColor)
            }
        }
        let dim = event.isTask ? config.dimCompletedTasks && event.isTaskCompleted : config.dimPastEvents && event.isPastEvent && !isPrintVersion
        var bg = Color(argb: event.color)
        var fg = event.color.contrastColor
        if dim {
            bg = bg.opacity(MEDIUM_ALPHA)
            fg = fg.opacity(HIGHER_ALPHA)
        }
        let rect = CGRect(x: left, y: top, width: max(0, right - left), height: max(0, bottom - top))
        ctx.fill(Path(roundedRect: rect, cornerRadius: 3), with: .color(bg))
        var iconW: CGFloat = 0
        if event.isTask {
            ctx.draw(Text(Image(systemName: "checkmark.circle")).font(.system(size: smallerText - 1)).foregroundColor(fg),
                     at: CGPoint(x: left + 2, y: rect.midY), anchor: .leading)
            iconW = smallerText + 1
        }
        var layer = ctx
        layer.clip(to: Path(rect.insetBy(dx: 1, dy: 0)))
        layer.draw(Text(event.title).font(.system(size: smallerText)).foregroundColor(fg).strikethrough(event.strike),
                   at: CGPoint(x: left + 2 + iconW, y: rect.midY), anchor: .leading)
        for i in 0..<covered { offsets[event.startDayIndex + i] = vOff + titleH + pad * 2 }
    }
}

extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

/// MonthFragmentsHolder + MonthFragment.
struct MonthHolder: View {
    @Environment(CalendarStore.self) private var store
    let anchor: String
    @Binding var current: String
    let onOpenDay: (String) -> Void
    let onTitle: () -> Void
    @State private var index = 0

    var body: some View {
        let base = Formatter.getLocalDateTimeFromCode(anchor).withDayOfMonth(1)
        Pager(index: $index) { i in
            MonthPage(month: base.plusMonths(i), onPrevious: { index -= 1 }, onNext: { index += 1 },
                      onTitle: onTitle, onOpenDay: onOpenDay)
        }
        .onChange(of: index) { _, i in current = Formatter.getDayCodeFromDateTime(base.plusMonths(i)) }
        .onAppear { current = Formatter.getDayCodeFromDateTime(Formatter.getLocalDateTimeFromCode(anchor)) }
    }
}

struct MonthPage: View {
    @Environment(CalendarStore.self) private var store
    @Environment(Config.self) private var config
    @Environment(\.palette) private var palette
    let month: JDate
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onTitle: () -> Void
    let onOpenDay: (String) -> Void
    @State private var days: [DayMonthly] = []

    var body: some View {
        VStack(spacing: 0) {
            TopNavigation(title: Formatter.getLongMonthYear(Formatter.getDayCodeFromDateTime(month)),
                          onPrevious: onPrevious, onTitle: onTitle, onNext: onNext)
            MonthGrid(days: days) { onOpenDay($0.code) }
                .padding(.horizontal, 4)
                .padding(.bottom, 4)
        }
        .task(id: reloadKey) { days = monthDays(store, month: month) }
    }

    private var reloadKey: String {
        "\(store.revision)-\(config.displayCalendars.count)-\(WeekDays.shared.firstDayOfWeek)-\(Formatter.getTodayCode())"
    }
}

/// Printable month (MonthFragment.printView()).
struct PrintableMonth: View {
    @Environment(CalendarStore.self) private var store
    let code: String

    var body: some View {
        let month = Formatter.getLocalDateTimeFromCode(code).withDayOfMonth(1)
        VStack(spacing: 8) {
            Text(Formatter.getLongMonthYear(code)).font(.system(size: 24, weight: .medium)).foregroundColor(.black)
            MonthGrid(days: monthDays(store, month: month), isPrintVersion: true)
        }
        .padding(24)
    }
}

/// MonthDayFragmentsHolder + MonthDayFragment: a compact month on top, the selected day's events below.
struct MonthDayHolder: View {
    @Environment(CalendarStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(Config.self) private var config
    @Environment(\.palette) private var palette
    let anchor: String
    @Binding var current: String
    let onTitle: () -> Void
    @State private var index = 0
    @State private var selectedCode = ""
    @State private var events: [Event] = []
    @State private var selection = Set<String>()

    var body: some View {
        let base = Formatter.getLocalDateTimeFromCode(anchor).withDayOfMonth(1)
        VStack(spacing: 0) {
            if !selection.isEmpty {
                SelectionBar(selection: $selection, events: events)
            }
            Pager(index: $index) { i in
                MonthDayPage(month: base.plusMonths(i), selectedCode: selectedCode, onPrevious: { index -= 1 }, onNext: { index += 1 },
                             onTitle: onTitle) { selectedCode = $0 }
            }
            .frame(height: 340)
            Divider().overlay(palette.divider)
            Text(Formatter.getDateFromCode(selectedCode.isEmpty ? anchor : selectedCode))
                .font(.system(size: palette.fontSize, weight: .medium))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            if events.isEmpty {
                Placeholder(text: "No items found.")
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        EventListItems(items: getEventListItems(events, addSectionDays: false, addSectionMonths: false),
                                       selection: $selection) { router.open($0.ref) }
                    }
                    .padding(.bottom, 90)
                }
                .refreshable(enabled: config.caldavSync && config.pullToRefresh) { store.refreshSystemCalendars(showToast: true) }
            }
        }
        .onAppear {
            selectedCode = anchor
            current = anchor
        }
        .onChange(of: index) { _, i in
            let m = base.plusMonths(i)
            let today = JDate.now()
            selectedCode = Formatter.getDayCodeFromDateTime(m.monthOfYear == today.monthOfYear && m.year == today.year ? today : m)
        }
        .onChange(of: selectedCode) { _, c in current = c }
        .task(id: "\(selectedCode)-\(store.revision)-\(config.displayCalendars.count)") {
            let code = selectedCode.isEmpty ? anchor : selectedCode
            events = store.getEvents(from: Formatter.getDayStartTS(code), to: Formatter.getDayEndTS(code))
        }
    }
}

struct MonthDayPage: View {
    @Environment(CalendarStore.self) private var store
    @Environment(Config.self) private var config
    let month: JDate
    let selectedCode: String
    let onPrevious: () -> Void
    let onNext: () -> Void
    let onTitle: () -> Void
    let onSelect: (String) -> Void
    @State private var days: [DayMonthly] = []

    var body: some View {
        VStack(spacing: 0) {
            TopNavigation(title: Formatter.getLongMonthYear(Formatter.getDayCodeFromDateTime(month)),
                          onPrevious: onPrevious, onTitle: onTitle, onNext: onNext)
            MonthGrid(days: days, isMonthDayView: true, selectedIndex: days.firstIndex { $0.code == selectedCode && $0.isThisMonth }) {
                onSelect($0.code)
            }
            .padding(.horizontal, 4)
        }
        .task(id: "\(store.revision)-\(config.displayCalendars.count)-\(WeekDays.shared.firstDayOfWeek)") {
            days = monthDays(store, month: month)
        }
    }
}

extension View {
    /// SwipeRefreshLayout, only when CalDAV pull-to-refresh is on.
    @ViewBuilder
    func refreshable(enabled: Bool, _ action: @escaping @Sendable () async -> Void) -> some View {
        if enabled { refreshable(action: action) } else { self }
    }
}
