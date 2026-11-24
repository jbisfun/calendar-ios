import FossifyCommons
import Foundation

/// Publishes events for the iOS home-screen calendar widgets (fossify-ios/widgets-ios): the
/// event list for the next year and the monthly grids (2 months back to 12 ahead) with their
/// event slots laid out like MyWidgetMonthlyProvider, so the extension only draws them.
public enum CalendarWidgetData {
    static let snapshotName = "calendar"

    /// Call once at launch (LauncherApp.init): publishes now, after every change and when the
    /// day changes.
    @MainActor
    public static func install() {
        WidgetBridge.track { publish() }
        NotificationCenter.default.addObserver(forName: Notification.Name("UIApplicationSignificantTimeChangeNotification"), object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { publish() }
        }
    }

    /// `fossify://open/calendar`: the app opens on its current view.
    @MainActor
    public static func handle(_ url: URL) {}

    @MainActor
    static func publish() {
        let store = CalendarStore.shared
        let config = Config.shared
        _ = store.revision
        _ = WeekDays.shared.firstDayOfWeek
        let now = JDate.now()

        // EventListWidgetAdapter: the widest period (a year) from the oldest past event shown.
        let fromTS = now.seconds - Int64(config.displayPastEvents * 60) - 86_400
        let events = store.getEvents(from: fromTS, to: now.plusYears(1).seconds, applyTypeFilter: true)
        let list = getEventListItems(events, addSectionDays: false, addSectionMonths: false).compactMap { item -> CalendarWidgetSnapshot.ListEvent? in
            guard case .event(let e) = item else { return nil }
            let code = Formatter.getDayCodeFromTS(e.startTS)
            return .init(key: e.occurrenceKey, title: e.title, time: timeText(e, config: config), startTS: e.startTS, endTS: e.endTS,
                         color: e.color, isAllDay: e.isAllDay, isTask: e.isTask, isTaskCompleted: e.isTaskCompleted,
                         strike: e.shouldStrikeThrough, dayCode: code, dayTitle: Formatter.getDateDayTitle(code),
                         monthLabel: Formatter.getLongMonthYear(code), eventID: e.id ?? 0)
        }

        let current = now.withTimeAtStartOfDay.withDayOfMonth(1)
        let months = (-2...12).map { month(store, current.plusMonths($0)) }
        let snapshot = CalendarWidgetSnapshot(
            listEvents: Array(list.prefix(400)), months: months, weekDayLetters: weekDayLettersShort(),
            fontSize: Double(widgetFontSize()), showWeekNumbers: config.showWeekNumbers, showGrid: config.showGrid,
            highlightWeekends: config.highlightWeekends, weekendColor: config.highlightWeekendsColor,
            dimPastEvents: config.dimPastEvents, dimCompletedTasks: config.dimCompletedTasks,
            displayPastMinutes: config.displayPastEvents, generated: Date())
        WidgetBridge.save(snapshot, snapshotName, reload: WidgetKinds.calendar)
        WidgetBridge.publishTheme()
    }

    /// EventListWidgetAdapter.setupListEvent(): the time line plus the optional description.
    private static func timeText(_ e: Event, config: Config) -> String {
        var time = e.isAllDay ? "All-day" : Formatter.getTimeFromTS(e.startTS)
        if e.startTS != e.endTS {
            if !e.isAllDay { time += " - \(Formatter.getTimeFromTS(e.endTS))" }
            let startCode = Formatter.getDayCodeFromTS(e.startTS)
            let endCode = Formatter.getDayCodeFromTS(e.endTS)
            if startCode != endCode { time += " (\(Formatter.getDateDayTitle(endCode)))" }
        }
        let desc = config.replaceDescription ? e.location : e.description.replacingOccurrences(of: "\n", with: " ")
        if config.displayDescription && !desc.isEmpty { time += "\n\(desc)" }
        return time
    }

    /// One monthly grid: monthDays() plus MyWidgetMonthlyProvider's buildDaySlotLists().
    @MainActor
    private static func month(_ store: CalendarStore, _ month: JDate) -> CalendarWidgetSnapshot.Month {
        let days = monthDays(store, month: month)
        var indices: [String: [Int]] = [:]
        var byKey: [String: Event] = [:]
        for (i, day) in days.enumerated() {
            for e in day.dayEvents where indices[e.occurrenceKey]?.last != i {
                indices[e.occurrenceKey, default: []].append(i)
                if byKey[e.occurrenceKey] == nil { byKey[e.occurrenceKey] = e }
            }
        }
        let keys = indices.keys.sorted { a, b in
            let ea = byKey[a]!, eb = byKey[b]!
            let ca = indices[a]!.count, cb = indices[b]!.count
            if ca != cb { return ca > cb }
            if ea.isAllDay != eb.isAllDay { return ea.isAllDay }
            if ea.startTS != eb.startTS { return ea.startTS < eb.startTS }
            if ea.endTS != eb.endTS { return ea.endTS < eb.endTS }
            let fa = indices[a]!.first ?? 0, fb = indices[b]!.first ?? 0
            if fa != fb { return fa < fb }
            return ea.title < eb.title
        }
        var events: [CalendarWidgetSnapshot.MonthEvent] = []
        var slots = Array(repeating: [Int](), count: days.count)
        for key in keys {
            let e = byKey[key]!
            let index = events.count
            events.append(.init(title: e.title, color: e.color, endTS: e.endTS, isTask: e.isTask,
                                isTaskCompleted: e.isTaskCompleted, strike: e.shouldStrikeThrough))
            let weeks = Dictionary(grouping: indices[key]!) { $0 / 7 }
            for weekDays in weeks.keys.sorted().map({ weeks[$0]! }) {
                var slot = 0
                while weekDays.contains(where: { slot < slots[$0].count && slots[$0][slot] != -1 }) { slot += 1 }
                for d in weekDays {
                    while slots[d].count <= slot { slots[d].append(-1) }
                    slots[d][slot] = index
                }
            }
        }
        let code = Formatter.getDayCodeFromDateTime(month)
        return .init(code: String(code.prefix(6)), title: Formatter.getLongMonthYear(code),
                     days: days.enumerated().map { i, d in
                         .init(value: d.value, code: d.code, isThisMonth: d.isThisMonth, isWeekend: d.isWeekend,
                               weekOfYear: d.weekOfYear, slots: slots[i])
                     },
                     events: events)
    }
}
