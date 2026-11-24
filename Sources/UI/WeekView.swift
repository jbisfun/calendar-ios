import FossifyCommons
import SwiftUI
import UIKit

/// WeekFragmentsHolder: pages of `weeklyViewDays` days plus the day count slider.
struct WeekHolder: View {
    @Environment(Config.self) private var config
    @Environment(\.palette) private var palette
    let anchor: String
    @Binding var current: String
    let onOpenDay: (String) -> Void
    @State private var index = 0
    @State private var daysOverride: Int?

    var body: some View {
        @Bindable var config = config
        let base = Formatter.getLocalDateTimeFromCode(anchor)
        let days = config.weeklyViewDays
        VStack(spacing: 0) {
            Pager(index: $index) { i in
                WeekPage(start: base.plusDays(i * days), days: days, onOpenDay: onOpenDay)
            }
            .id(days)
            if config.allowCustomizeDayCount {
                Divider().overlay(palette.divider)
                HStack(spacing: 12) {
                    Slider(value: Binding(get: { Double(config.weeklyViewDays) }, set: { v in
                        let n = max(1, Int(v.rounded()))
                        if n != config.weeklyViewDays {
                            config.weeklyViewDays = n
                            index = 0
                            current = Formatter.getDayCodeFromDateTime(getFirstDayOfWeekDt(Formatter.getLocalDateTimeFromCode(current)))
                        }
                    }), in: 1...14, step: 1)
                    Text("\(days) day\(days == 1 ? "" : "s")").font(.system(size: 15)).frame(width: 70, alignment: .trailing)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }
        }
        .onAppear { current = anchor }
        .onChange(of: index) { _, i in current = Formatter.getDayCodeFromDateTime(base.plusDays(i * days)) }
    }
}

/// models/EventWeeklyView.kt
private final class EventWeeklyView {
    var range: ClosedRange<Int>
    var slot = 0
    var slotMax = 0
    var collisions: [String] = []
    init(_ r: ClosedRange<Int>) { range = r }
}

private func intersects(_ a: ClosedRange<Int>, _ b: ClosedRange<Int>) -> Bool {
    (a.upperBound >= b.lowerBound && a.lowerBound <= b.upperBound) || (b.upperBound >= a.lowerBound && b.lowerBound <= a.upperBound)
}

private struct PlacedEvent: Identifiable {
    var event: Event
    var dayIndex: Int
    var range: ClosedRange<Int>
    var slot: Int
    var slotMax: Int
    var id: String { "\(event.occurrenceKey)-\(dayIndex)" }
}

private struct AllDayPlacement: Identifiable {
    var event: Event
    var firstCol: Int
    var lastCol: Int
    var row: Int
    var id: String { event.occurrenceKey }
}

/// WeekFragment.
struct WeekPage: View {
    @Environment(CalendarStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(Config.self) private var config
    @Environment(\.palette) private var palette
    let start: JDate
    let days: Int
    var isPrintVersion = false
    let onOpenDay: (String) -> Void

    @State private var events: [Event] = []
    @State private var selectedCell: (col: Int, hour: Int)?
    @State private var askType: (col: Int, hour: Int)?
    @State private var pendingDrop: (event: Event, newEvent: Event)?
    @State private var pinchBase: Double?
    @State private var now = Date()

    private let hoursWidth: CGFloat = 46

    var body: some View {
        let rowHeight = 60 * config.weeklyViewItemHeightMultiplier
        let placed = layoutEvents()
        let allDay = layoutAllDay()
        VStack(spacing: 0) {
            header
            if !allDay.isEmpty { allDayArea(allDay) }
            Divider().overlay(palette.divider)
            if isPrintVersion {
                grid(rowHeight: 40, placed: placed)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        grid(rowHeight: rowHeight, placed: placed)
                    }
                    .onAppear { proxy.scrollTo("hour-\(config.startWeeklyAt)", anchor: .top) }
                }
                .simultaneousGesture(MagnifyGesture().onChanged { v in
                    if pinchBase == nil { pinchBase = config.weeklyViewItemHeightMultiplier }
                    config.weeklyViewItemHeightMultiplier = min(5, max(0.3, (pinchBase ?? 1) * v.magnification))
                }.onEnded { _ in pinchBase = nil })
            }
        }
        .task(id: "\(start.seconds)-\(days)-\(store.revision)-\(config.displayCalendars.count)") {
            events = store.getEvents(from: start.seconds, to: start.plusDays(days).seconds - 1)
        }
        .onReceive(Timer.publish(every: 60, on: .main, in: .common).autoconnect()) { now = $0 }
        .sheet(isPresented: Binding(get: { askType != nil }, set: { if !$0 { askType = nil } })) {
            RadioDialog(title: nil, items: [(TYPE_EVENT, "Event"), (TYPE_TASK, "Task")], selected: -1) { type in
                if let cell = askType { create(cell, task: type == TYPE_TASK) }
            }
        }
        .sheet(isPresented: Binding(get: { pendingDrop != nil }, set: { if !$0 { pendingDrop = nil } })) {
            EditRepeatingEventDialog(isTask: pendingDrop?.event.isTask ?? false) { scope in
                guard let drop = pendingDrop else { return }
                switch scope {
                case .selectedOccurrence: store.editSelectedOccurrence(drop.newEvent, occurrenceTS: drop.event.startTS)
                case .futureOccurrences: store.editFutureOccurrences(drop.newEvent, occurrenceTS: drop.event.startTS)
                case .allOccurrences: store.editAllOccurrences(drop.newEvent, originalStartTS: drop.event.startTS, originalEndTS: drop.event.endTS)
                }
            }
        }
    }

    private var columnCodes: [String] { (0..<days).map { Formatter.getDayCodeFromDateTime(start.plusDays($0)) } }

    // MARK: Header (week_view_month_label, day letters)

    private var header: some View {
        let todayCode = Formatter.getTodayCode()
        let textColor = isPrintVersion ? Color(argb: 0xFF2D2D2D) : palette.textColor
        return HStack(spacing: 0) {
            VStack(spacing: 0) {
                Text(Formatter.getShortMonthName(start.monthOfYear)).font(.system(size: 13, weight: .medium))
                Text("Wk. \(start.plusDays(3).weekOfWeekyear)").font(.system(size: 11))
            }
            .foregroundStyle(textColor)
            .frame(width: hoursWidth)
            ForEach(0..<days, id: \.self) { i in
                let d = start.plusDays(i)
                let code = columnCodes[i]
                let isToday = code == todayCode && !isPrintVersion
                let weekend = config.highlightWeekends && (d.dayOfWeek == 6 || d.dayOfWeek == 7)
                let color = isToday ? palette.primaryColor : weekend ? Color(argb: config.highlightWeekendsColor) : textColor
                VStack(spacing: 0) {
                    Text(String(WeekDays.letters[d.dayOfWeek - 1])).font(.system(size: 13))
                    Text("\(d.dayOfMonth)").font(.system(size: 15, weight: isToday ? .bold : .regular))
                }
                .foregroundStyle(color)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
                .onTapGesture { if !isPrintVersion { onOpenDay(code) } }
            }
        }
    }

    // MARK: All-day events (week_all_day_holder)

    private func layoutAllDay() -> [AllDayPlacement] {
        let codes = columnCodes
        var rows: [Set<Int>] = []
        var result: [AllDayPlacement] = []
        let candidates = events.filter { onTopBar($0) }.sorted { a, b in
            let la = a.endTS - a.startTS, lb = b.endTS - b.startTS
            return a.startTS != b.startTS ? a.startTS < b.startTS : la > lb
        }
        for e in candidates {
            let startCode = Formatter.getDayCodeFromTS(e.startTS)
            let endDT = JDate(ts: e.endTS)
            var endCode = Formatter.getDayCodeFromDateTime(endDT)
            // an event ending at midnight doesn't occupy that day
            if !e.isAllDay && endDT.seconds == endDT.withTimeAtStartOfDay.seconds && endCode > startCode {
                endCode = Formatter.getDayCodeFromDateTime(endDT.minusDays(1))
            }
            let first = codes.firstIndex { $0 >= startCode } ?? 0
            let last = codes.lastIndex { $0 <= endCode } ?? (days - 1)
            guard first <= last, startCode <= codes.last!, endCode >= codes.first! else { continue }
            let span = Set(first...last)
            var row = rows.firstIndex { $0.isDisjoint(with: span) }
            if row == nil {
                rows.append([])
                row = rows.count - 1
            }
            rows[row!].formUnion(span)
            result.append(AllDayPlacement(event: e, firstCol: first, lastCol: last, row: row!))
        }
        return result
    }

    private func allDayArea(_ items: [AllDayPlacement]) -> some View {
        let rowsCount = (items.map(\.row).max() ?? 0) + 1
        let rowH: CGFloat = 22
        return GeometryReader { geo in
            let colW = (geo.size.width - hoursWidth) / CGFloat(days)
            ZStack(alignment: .topLeading) {
                ForEach(items) { p in
                    eventBlock(p.event, lines: 1)
                        .frame(width: colW * CGFloat(p.lastCol - p.firstCol + 1) - 2, height: rowH - 2)
                        .offset(x: hoursWidth + colW * CGFloat(p.firstCol) + 1, y: CGFloat(p.row) * rowH + 1)
                }
            }
        }
        .frame(height: CGFloat(rowsCount) * rowH + 2)
    }

    private func onTopBar(_ e: Event) -> Bool {
        let s = Formatter.getDayCodeFromTS(e.startTS), en = Formatter.getDayCodeFromTS(e.endTS)
        return e.isAllDay || (s != en && config.showMidnightSpanningEventsAtTop)
    }

    // MARK: Timed events

    private func layoutEvents() -> [PlacedEvent] {
        let codes = columnCodes
        let rowHeight = 60 * config.weeklyViewItemHeightMultiplier
        let minuteHeight = rowHeight / 60
        let minimalMinutes = Int((10 / minuteHeight).rounded(.up))
        var ranges: [String: [(String, EventWeeklyView)]] = [:]
        var byKey: [String: Event] = [:]
        for e in events where !onTopBar(e) {
            byKey[e.occurrenceKey] = e
            let s = JDate(ts: e.startTS), en = JDate(ts: e.endTS)
            let startCode = Formatter.getDayCodeFromDateTime(s), endCode = Formatter.getDayCodeFromDateTime(en)
            var cur = s
            var code = startCode
            var guardCount = 0
            repeat {
                let startMin = code == startCode ? s.minuteOfDay : 0
                let duration = code == endCode ? en.minuteOfDay - startMin : 1440
                var endMin = startMin + duration
                if endMin - startMin < minimalMinutes { endMin = startMin + minimalMinutes }
                ranges[code, default: []].append((e.occurrenceKey, EventWeeklyView(startMin...max(startMin, endMin))))
                cur = cur.plusDays(1)
                code = Formatter.getDayCodeFromDateTime(cur)
                guardCount += 1
            } while code <= endCode && guardCount < 60
        }

        // slot assignment (WeekFragment.addEvents)
        for (_, dayList) in ranges {
            var checked = Set<String>()
            for (id, v) in dayList {
                if v.slot == 0 {
                    v.slot = 1
                    v.slotMax = 1
                }
                checked.insert(id)
                for (otherId, o) in dayList where !checked.contains(otherId) {
                    let touching = intersects(v.range, o.range)
                    let common = touching && (v.range.upperBound > o.range.lowerBound ||
                        (v.range.lowerBound == v.range.upperBound && v.range.upperBound == o.range.lowerBound))
                    guard touching && common else { continue }
                    if o.slot == 0 {
                        let collisionViews = dayList.filter { v.collisions.contains($0.0) }.map(\.1)
                        var curMax = max(max(v.slotMax, 1), max(v.slot, 1))
                        curMax = max(curMax, collisionViews.map { max($0.slot, 1) }.max() ?? 1)
                        let next = curMax + 1
                        var slots = Array(1...curMax)
                        for c in collisionViews where intersects(c.range, o.range) && (1...curMax).contains(c.slot) {
                            slots[c.slot - 1] = next
                        }
                        if (1...curMax).contains(v.slot) { slots[v.slot - 1] = next }
                        let slot = slots.min() ?? next
                        o.slot = slot
                        if slot == next {
                            o.slotMax = next
                            v.slotMax = next
                            for c in collisionViews { c.slotMax = max(c.slotMax, next) }
                        } else {
                            o.slotMax = curMax
                        }
                    }
                    v.collisions.append(otherId)
                    o.collisions.append(id)
                }
            }
        }

        var result: [PlacedEvent] = []
        for (code, list) in ranges {
            guard let col = codes.firstIndex(of: code) else { continue }
            for (id, v) in list {
                guard let e = byKey[id] else { continue }
                result.append(PlacedEvent(event: e, dayIndex: col, range: v.range, slot: max(1, v.slot), slotMax: max(1, v.slotMax)))
            }
        }
        return result
    }

    private func grid(rowHeight: CGFloat, placed: [PlacedEvent]) -> some View {
        let textColor = isPrintVersion ? Color(argb: 0xFF2D2D2D) : palette.textColor
        let codes = columnCodes
        let todayCode = Formatter.getTodayCode()
        return HStack(alignment: .top, spacing: 0) {
            VStack(spacing: 0) {
                ForEach(0..<24, id: \.self) { h in
                    Text(h == 0 ? "" : Formatter.getHours(JDate.now().withTime(h, 0)))
                        .font(.system(size: 11))
                        .foregroundStyle(textColor)
                        .frame(width: hoursWidth, height: rowHeight, alignment: .top)
                        .offset(y: -7)
                        .id("hour-\(h)")
                }
            }
            GeometryReader { geo in
                let colW = geo.size.width / CGFloat(days)
                ZStack(alignment: .topLeading) {
                    // grid
                    Path { p in
                        for h in 0...24 {
                            p.move(to: CGPoint(x: 0, y: CGFloat(h) * rowHeight))
                            p.addLine(to: CGPoint(x: geo.size.width, y: CGFloat(h) * rowHeight))
                        }
                        for d in 0...days {
                            p.move(to: CGPoint(x: CGFloat(d) * colW, y: 0))
                            p.addLine(to: CGPoint(x: CGFloat(d) * colW, y: rowHeight * 24))
                        }
                    }
                    .stroke(textColor.opacity(0.15), lineWidth: 0.5)

                    // tap targets / drop targets per column
                    HStack(spacing: 0) {
                        ForEach(0..<days, id: \.self) { col in
                            Color.clear
                                .contentShape(Rectangle())
                                .onTapGesture(coordinateSpace: .local) { loc in
                                    guard !isPrintVersion else { return }
                                    selectedCell = (col, min(23, Int(loc.y / rowHeight)))
                                    let cell = selectedCell
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                                        if selectedCell?.col == cell?.col && selectedCell?.hour == cell?.hour { selectedCell = nil }
                                    }
                                }
                                .dropDestination(for: String.self) { items, loc in
                                    guard let key = items.first else { return false }
                                    return drop(key, col: col, hour: min(23, Int(loc.y / rowHeight)))
                                }
                        }
                    }

                    if let cell = selectedCell {
                        Image(systemName: "plus")
                            .foregroundStyle(palette.onPrimary)
                            .frame(width: colW, height: rowHeight)
                            .background(palette.primaryColor)
                            .offset(x: CGFloat(cell.col) * colW, y: CGFloat(cell.hour) * rowHeight)
                            .onTapGesture {
                                selectedCell = nil
                                if config.allowCreatingTasks { askType = cell } else { create(cell, task: false) }
                            }
                    }

                    ForEach(placed) { p in
                        let minuteH = rowHeight / 60
                        let width = (colW - 1) / CGFloat(p.slotMax)
                        let isPoint = p.event.startTS == p.event.endTS
                        eventBlock(p.event, lines: p.event.isTask || isPoint ? 1 : 3)
                            .frame(width: max(1, width - (p.slot > 1 ? 1 : 0)),
                                   height: max(10, CGFloat(p.range.upperBound - p.range.lowerBound) * minuteH - 1))
                            .offset(x: CGFloat(p.dayIndex) * colW + width * CGFloat(p.slot - 1) + (p.slot > 1 ? 1 : 0),
                                    y: CGFloat(p.range.lowerBound) * minuteH)
                            .draggable(p.event.occurrenceKey)
                    }

                    // CurrentTimeIndicatorView
                    if !isPrintVersion, let col = codes.firstIndex(of: todayCode) {
                        let minutes = JDate(now).minuteOfDay
                        let y = CGFloat(minutes) * rowHeight / 60
                        ZStack(alignment: .leading) {
                            Rectangle().fill(palette.primaryColor).frame(width: colW, height: 2)
                            Circle().fill(palette.primaryColor).frame(width: 8, height: 8).offset(x: -4)
                        }
                        .offset(x: CGFloat(col) * colW, y: y - 1)
                        .allowsHitTesting(false)
                    }
                }
            }
            .frame(height: rowHeight * 24)
        }
        .padding(.bottom, rowHeight)
    }

    private func eventBlock(_ e: Event, lines: Int) -> some View {
        let dim = e.isTask ? config.dimCompletedTasks && e.isTaskCompleted : config.dimPastEvents && e.isPastEvent && !isPrintVersion
        let bg = Color(argb: e.color).opacity(dim ? MEDIUM_ALPHA : 1)
        let fg = e.color.contrastColor.opacity(dim ? HIGHER_ALPHA : 1)
        return HStack(alignment: .top, spacing: 2) {
            if e.isTask { Image(systemName: "checkmark.circle").font(.system(size: 10)) }
            Text(e.title).font(.system(size: 11)).strikethrough(e.shouldStrikeThrough).lineLimit(lines)
            Spacer(minLength: 0)
        }
        .foregroundStyle(fg)
        .padding(.horizontal, 2)
        .padding(.top, 1)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 2).fill(bg))
        .clipped()
        .contentShape(Rectangle())
        .onTapGesture { if !isPrintVersion { router.open(e.ref) } }
    }

    private func create(_ cell: (col: Int, hour: Int), task: Bool) {
        let ts = start.plusDays(cell.col).withTime(cell.hour, 0).seconds
        if task {
            router.push(.task(ref: nil, newStart: ts, duplicate: false))
        } else {
            router.push(.event(ref: nil, newStart: ts, hourDuration: true, duplicate: false))
        }
    }

    /// Drag and drop an event to another hour or day.
    private func drop(_ key: String, col: Int, hour: Int) -> Bool {
        guard let e = events.first(where: { $0.occurrenceKey == key }) else { return false }
        let original = (e.isSynced ? e : (e.id.flatMap { store.localEvent($0) } ?? e))
        let cur = JDate(ts: e.startTS)
        let newStart = start.plusDays(col).withTime(hour, cur.minuteOfHour, cur.secondOfMinute).seconds
        var newEvent = original
        newEvent.startTS = newStart
        newEvent.endTS = newStart + (e.endTS - e.startTS)
        newEvent.flags &= ~FLAG_ALL_DAY
        newEvent.color = original.color
        if e.repeatInterval > 0 {
            pendingDrop = (e, newEvent)
        } else if newEvent.startTS != e.startTS || newEvent.endTS != e.endTS {
            store.updateEvent(newEvent)
        }
        return true
    }
}

struct PrintableWeek: View {
    let startCode: String

    var body: some View {
        WeekPage(start: Formatter.getLocalDateTimeFromCode(startCode), days: Config.shared.weeklyViewDays, isPrintVersion: true) { _ in }
            .padding(16)
    }
}
