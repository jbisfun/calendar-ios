import EventKit
import FossifyCommons
import Foundation
import Observation

/// What the Room database held: local events/tasks, calendars ("event types") and task completions.
struct LocalDatabase: Codable {
    var events: [Event] = []
    var calendars: [CalendarEntity] = []
    var completedTasks: [CompletedTask] = []
    var nextEventId: Int64 = 1
    var nextCalendarId: Int64 = 2
}

/// EventsDatabase + EventsHelper + the CalDAV helper: one observable store the screens read from.
@MainActor
@Observable
final class CalendarStore {
    /// One store per process: the app's screens and its home-screen widgets (in launcher-ios) share it.
    static let shared = CalendarStore()

    private(set) var db = LocalDatabase()
    /// Bumped on every change so pages refetch.
    private(set) var revision = 0
    var toast: String?

    @ObservationIgnored let ekStore = EKEventStore()
    var calendarAccess: EKAuthorizationStatus = EKEventStore.authorizationStatus(for: .event)
    @ObservationIgnored var config: Config { Config.shared }

    static var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("FossifyCalendar", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("events.json")
    }

    init() {
        load()
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: ekStore, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.systemCalendarsChanged() }
        }
    }

    // MARK: Persistence

    private func load() {
        if let data = try? Data(contentsOf: Self.fileURL), let decoded = try? JSONDecoder().decode(LocalDatabase.self, from: data) {
            db = decoded
        }
        if !db.calendars.contains(where: { $0.id == LOCAL_CALENDAR_ID }) {
            // EventsDatabase.insertLocalCalendar()
            db.calendars.insert(CalendarEntity(id: LOCAL_CALENDAR_ID, title: "Local calendar", color: BaseConfig.shared.customPrimaryColor), at: 0)
            config.addDisplayCalendar(LOCAL_CALENDAR_ID)
            save()
        }
    }

    func save() {
        revision += 1
        let snapshot = db
        DispatchQueue.global(qos: .utility).async {
            if let data = try? JSONEncoder().encode(snapshot) {
                try? data.write(to: Self.fileURL, options: .atomic)
            }
        }
        ReminderScheduler.shared.reschedule(self)
    }

    func refresh() { revision += 1 }

    // MARK: Calendars

    var calendars: [CalendarEntity] {
        db.calendars.filter { !$0.isSyncedCalendar || (config.caldavSync && config.syncedCalendarIds.contains($0.caldavCalendarId)) }
    }

    func calendar(_ id: Int64) -> CalendarEntity? { db.calendars.first { $0.id == id } }
    func calendarWithCalDAVId(_ ekId: String) -> CalendarEntity? { db.calendars.first { $0.caldavCalendarId == ekId } }
    func calendarIdWithTitle(_ title: String) -> Int64 { db.calendars.first { $0.title.caseInsensitiveCompare(title) == .orderedSame }?.id ?? -1 }
    func localCalendarIdWithType(_ type: Int) -> Int64 { db.calendars.first { $0.type == type && !$0.isSyncedCalendar }?.id ?? -1 }
    func calendarColor(_ id: Int64) -> UInt32? { calendar(id)?.color }

    /// insertOrUpdateCalendarSync()
    @discardableResult
    func insertOrUpdateCalendar(_ calendar: CalendarEntity, isNew: Bool) -> Int64 {
        var calendar = calendar
        if isNew {
            calendar.id = db.nextCalendarId
            db.nextCalendarId += 1
            db.calendars.append(calendar)
            config.addDisplayCalendar(calendar.id)
            if !config.quickFilterCalendars.isEmpty {
                config.addQuickFilterCalendar(calendar.id)
            } else if db.calendars.count == 2 {
                db.calendars.forEach { config.addQuickFilterCalendar($0.id) }
            }
        } else if let i = db.calendars.firstIndex(where: { $0.id == calendar.id }) {
            if calendar.isSyncedCalendar { updateSystemCalendar(calendar) }
            db.calendars[i] = calendar
        }
        save()
        return calendar.id
    }

    /// createPredefinedCalendar()
    func createPredefinedCalendar(_ title: String, color: UInt32, type: Int) -> Int64 {
        if let existing = db.calendars.firstIndex(where: { !$0.isSyncedCalendar && $0.title.caseInsensitiveCompare(title) == .orderedSame }) {
            db.calendars[existing].type = type
            save()
            return db.calendars[existing].id
        }
        return insertOrUpdateCalendar(CalendarEntity(id: 0, title: title, color: color, type: type), isNew: true)
    }

    func birthdaysCalendarId(create: Bool = true) -> Int64 {
        let id = localCalendarIdWithType(BIRTHDAY_EVENT)
        if id == -1 && create { return createPredefinedCalendar("Birthdays", color: DEFAULT_BIRTHDAYS_COLOR, type: BIRTHDAY_EVENT) }
        return id
    }

    func anniversariesCalendarId(create: Bool = true) -> Int64 {
        let id = localCalendarIdWithType(ANNIVERSARY_EVENT)
        if id == -1 && create { return createPredefinedCalendar("Anniversaries", color: DEFAULT_ANNIVERSARIES_COLOR, type: ANNIVERSARY_EVENT) }
        return id
    }

    func doCalendarsContainEvents(_ ids: [Int64]) -> Bool { db.events.contains { ids.contains($0.calendarId) } }

    func removeCalendarEntities(_ ids: Set<Int64>) {
        db.calendars.removeAll { ids.contains($0.id) }
        save()
    }

    func replaceCalendarEntity(_ c: CalendarEntity) {
        if let i = db.calendars.firstIndex(where: { $0.id == c.id }) { db.calendars[i] = c }
    }

    /// deleteCalendars()
    func deleteCalendars(_ calendars: [CalendarEntity], deleteEvents: Bool) {
        let toDelete = calendars.filter { !$0.isSyncedCalendar && $0.id != LOCAL_CALENDAR_ID }
        let ids = Set(toDelete.map(\.id))
        config.displayCalendars.subtract(ids.map(String.init))
        guard !ids.isEmpty else { return }
        if deleteEvents {
            self.deleteEvents(ids: db.events.filter { ids.contains($0.calendarId) }.compactMap(\.id))
        } else {
            for i in db.events.indices where ids.contains(db.events[i].calendarId) { db.events[i].calendarId = LOCAL_CALENDAR_ID }
        }
        db.calendars.removeAll { ids.contains($0.id) }
        if toDelete.contains(where: { $0.type == HOLIDAY_EVENT }) {
            config.holidayPaths = []
            config.holidayDataVersion = ""
        }
        if db.calendars.count == 1 { config.quickFilterCalendars = [] }
        save()
    }

    // MARK: Lookup

    func localEvent(_ id: Int64) -> Event? { db.events.first { $0.id == id } }

    /// The stored event (or EventKit occurrence) an EventRef points to.
    func event(for ref: EventRef) -> Event? {
        if let ek = ref.ekID { return systemEvent(identifier: ek, occurrenceTS: ref.occurrenceTS) }
        guard let id = ref.id, var e = localEvent(id) else { return nil }
        if e.isTask { e.flags = e.flags.addBitIf(isTaskCompleted(id: id, startTS: ref.occurrenceTS), FLAG_TASK_COMPLETED) }
        return e
    }

    var allLocations: [String] {
        Array(Set(db.events.map(\.location).filter { !$0.isEmpty })).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    // MARK: Fetching (EventsHelper.getEventsSync)

    func getEvents(from fromTS: Int64, to toTS: Int64, eventId: Int64 = -1, applyTypeFilter: Bool = true, searchQuery: String = "") -> [Event] {
        let birthdayId = birthdaysCalendarId(create: false)
        let anniversaryId = anniversariesCalendarId(create: false)
        let display = Set(config.displayCalendars.compactMap { Int64($0) })
        if applyTypeFilter && display.isEmpty { return [] }
        let q = searchQuery.lowercased()
        func matches(_ e: Event) -> Bool {
            q.isEmpty || e.title.lowercased().contains(q) || e.location.lowercased().contains(q) || e.description.lowercased().contains(q)
        }

        var events: [Event] = []
        for e in db.events where e.repeatInterval == 0 && e.startTS <= toTS && e.endTS >= fromTS {
            if eventId != -1 && e.id != eventId { continue }
            if applyTypeFilter && (e.startTS == 0 || !display.contains(e.calendarId) || !matches(e)) { continue }
            events.append(e)
        }
        events += repeatableEvents(from: fromTS, to: toTS, eventId: eventId, applyTypeFilter: applyTypeFilter, display: display, matches: matches)

        var seen = Set<String>()
        events = events.filter { e in
            !e.repetitionExceptions.contains(Formatter.getDayCodeFromTS(e.startTS)) && seen.insert(e.occurrenceKey).inserted
        }

        let colors = Dictionary(db.calendars.map { ($0.id, $0.color) }, uniquingKeysWith: { a, _ in a })
        let originals = Dictionary(db.events.compactMap { e in e.id.map { ($0, e) } }, uniquingKeysWith: { a, _ in a })
        for i in events.indices {
            if events[i].isTask, let id = events[i].id {
                events[i].flags = events[i].flags.addBitIf(isTaskCompleted(id: id, startTS: events[i].startTS), FLAG_TASK_COMPLETED)
            }
            events[i].updateIsPastEvent()
            let e = events[i]
            if (birthdayId != -1 && e.calendarId == birthdayId) || (anniversaryId != -1 && e.calendarId == anniversaryId),
               let id = e.id, let original = originals[id], !e.hasMissingYear {
                let years = max(0, JDate(ts: e.startTS).year - JDate(ts: original.startTS).year)
                if years > 0 { events[i].title = "\(e.title) (\(years))" }
            }
            if events[i].color == 0 { events[i].color = colors[e.calendarId] ?? BaseConfig.shared.customPrimaryColor }
        }

        if eventId == -1 {
            events += systemEvents(from: fromTS, to: toTS, applyTypeFilter: applyTypeFilter, display: display).filter(matches)
        }
        return events
    }

    private func repeatableEvents(from fromTS: Int64, to toTS: Int64, eventId: Int64, applyTypeFilter: Bool,
                                  display: Set<Int64>, matches: (Event) -> Bool) -> [Event] {
        var result: [Event] = []
        for e in db.events where e.repeatInterval != 0 && e.startTS <= toTS {
            if eventId != -1 && e.id != eventId { continue }
            if applyTypeFilter && (e.startTS == 0 || !display.contains(e.calendarId) || !matches(e)) { continue }
            if e.repeatLimit >= 0 {
                result += eventsRepeatingTillDateOrForever(fromTS, toTS, e)
            } else {
                result += eventsRepeatingXTimes(fromTS, toTS, e)
            }
        }
        return result
    }

    private func occurrence(_ e: Event) -> Event {
        var c = e
        c.updateIsPastEvent()
        return c
    }

    private func eventsRepeatingXTimes(_ fromTS: Int64, _ toTS: Int64, _ original: Event) -> [Event] {
        var event = original
        var events: [Event] = []
        var guardCount = 0
        while event.repeatLimit < 0 && event.startTS <= toTS && guardCount < 200_000 {
            guardCount += 1
            if isXWeeklyRepetition(event.repeatInterval) {
                if event.isTsOnProperDay(event.startTS) && event.isOnProperWeek(originalStart: original.startTS) {
                    if event.endTS >= fromTS { events.append(occurrence(event)) }
                    event.repeatLimit += 1
                }
            } else {
                if event.endTS >= fromTS {
                    events.append(occurrence(event))
                } else if event.isAllDay && Formatter.getDayCodeFromTS(fromTS) == Formatter.getDayCodeFromTS(event.endTS) {
                    events.append(occurrence(event))
                }
                event.repeatLimit += 1
            }
            event.addIntervalTime(original)
        }
        return events
    }

    private func eventsRepeatingTillDateOrForever(_ fromTS: Int64, _ toTS: Int64, _ original: Event) -> [Event] {
        var event = original
        var events: [Event] = []
        var guardCount = 0
        while event.startTS <= toTS && (event.repeatLimit == 0 || event.repeatLimit >= event.startTS) && guardCount < 200_000 {
            guardCount += 1
            if event.endTS >= fromTS {
                if isXWeeklyRepetition(event.repeatInterval) {
                    if event.isTsOnProperDay(event.startTS) && event.isOnProperWeek(originalStart: original.startTS) {
                        events.append(occurrence(event))
                    }
                } else {
                    events.append(occurrence(event))
                }
            }
            if event.isAllDay {
                if isXWeeklyRepetition(event.repeatInterval) {
                    if event.endTS >= toTS && event.isTsOnProperDay(event.startTS) && event.isOnProperWeek(originalStart: original.startTS) {
                        events.append(occurrence(event))
                    }
                } else if Formatter.getDayCodeFromTS(fromTS) == Formatter.getDayCodeFromTS(event.endTS) {
                    events.append(occurrence(event))
                }
            }
            event.addIntervalTime(original)
        }
        return events
    }

    // MARK: Tasks

    func isTaskCompleted(id: Int64, startTS: Int64) -> Bool {
        if let task = db.events.first(where: { $0.id == id }), task.flags & FLAG_TASK_COMPLETED != 0 { return true }
        return db.completedTasks.contains { $0.taskId == id && $0.startTS == startTS && $0.flags & FLAG_TASK_COMPLETED != 0 }
    }

    /// Context.updateTaskCompletion()
    func updateTaskCompletion(_ task: Event, completed: Bool) {
        guard let id = task.id else { return }
        db.completedTasks.removeAll { $0.taskId == id && $0.startTS == task.startTS }
        if completed { db.completedTasks.append(CompletedTask(taskId: id, startTS: task.startTS, flags: task.flags | FLAG_TASK_COMPLETED)) }
        if let i = db.events.firstIndex(where: { $0.id == id }) {
            db.events[i].flags = db.events[i].flags & ~FLAG_TASK_COMPLETED
        }
        save()
    }

    // MARK: Writing (EventsHelper)

    private func ensureCalendarVisibility(_ event: Event) {
        config.addDisplayCalendar(event.calendarId)
    }

    /// insertEvent() / insertTask(); returns the new id, or nil when the event ends before it starts.
    @discardableResult
    func insertEvent(_ event: Event, enableCalendar: Bool = true, persist: Bool = true) -> Int64? {
        var event = event
        if event.startTS > event.endTS { return nil }
        if let cal = calendar(event.calendarId), cal.isSyncedCalendar {
            if let ek = saveSystemEvent(event, span: .thisEvent, isNew: true) { event.ekID = ek }
            if enableCalendar { ensureCalendarVisibility(event) }
            refresh()
            return 0
        }
        if let id = event.id, let i = db.events.firstIndex(where: { $0.id == id }) {
            db.events[i] = event
        } else {
            event.id = db.nextEventId
            db.nextEventId += 1
            db.events.append(event)
        }
        if enableCalendar { ensureCalendarVisibility(event) }
        if persist { save() }
        return event.id
    }

    func insertEvents(_ events: [Event]) {
        for e in events {
            if e.startTS > e.endTS {
                toast = "The event cannot end earlier than it starts"
                continue
            }
            insertEvent(e, persist: false)
        }
        save()
    }

    func updateEvent(_ event: Event) {
        if event.isSynced || (calendar(event.calendarId)?.isSyncedCalendar ?? false) {
            _ = saveSystemEvent(event, span: .futureEvents, isNew: event.ekID == nil)
            ensureCalendarVisibility(event)
            refresh()
            return
        }
        guard let id = event.id, let i = db.events.firstIndex(where: { $0.id == id }) else {
            insertEvent(event)
            return
        }
        db.events[i] = event
        ensureCalendarVisibility(event)
        save()
    }

    /// applyOriginalStartEndTimes()
    func applyOriginalStartEndTimes(_ event: inout Event, oldStartTS: Int64, oldEndTS: Int64) {
        guard let id = event.id, let original = localEvent(id) else { return }
        let startDelta = oldStartTS - event.startTS
        let endDelta = oldEndTS - event.endTS
        event.startTS = original.startTS - startDelta
        event.endTS = event.isTask ? event.startTS : original.endTS - endDelta
    }

    func editSelectedOccurrence(_ event: Event, occurrenceTS: Int64) {
        if event.isSynced { _ = saveSystemEvent(event, span: .thisEvent, isNew: false, occurrenceTS: occurrenceTS); refresh(); return }
        guard let id = event.id, let i = db.events.firstIndex(where: { $0.id == id }) else { return }
        db.events[i].addRepetitionException(Formatter.getDayCodeFromTS(occurrenceTS))
        var child = event
        child.parentId = id
        child.id = nil
        child.repeatRule = 0
        child.repeatInterval = 0
        child.repeatLimit = 0
        child.repetitionExceptions = []
        insertEvent(child)
    }

    func editFutureOccurrences(_ event: Event, occurrenceTS: Int64) {
        if event.isSynced { _ = saveSystemEvent(event, span: .futureEvents, isNew: false, occurrenceTS: occurrenceTS); refresh(); return }
        guard let id = event.id, let original = localEvent(id) else { return }
        var newEvent = event
        newEvent.maybeAdjustRepeatLimitCount(original, occurrenceTS: occurrenceTS)
        newEvent.id = nil
        addEventRepeatLimit(id, occurrenceTS: occurrenceTS, persist: false)
        if occurrenceTS == original.startTS { deleteEvents(ids: [id], persist: false) }
        insertEvent(newEvent)
    }

    func editAllOccurrences(_ event: Event, originalStartTS: Int64, originalEndTS: Int64) {
        if event.isSynced { _ = saveSystemEvent(event, span: .futureEvents, isNew: false, allOccurrences: true, occurrenceTS: originalStartTS); refresh(); return }
        var event = event
        applyOriginalStartEndTimes(&event, oldStartTS: originalStartTS, oldEndTS: originalEndTS)
        updateEvent(event)
    }

    /// addEventRepeatLimit(): ends the repetition before the given occurrence.
    func addEventRepeatLimit(_ eventId: Int64, occurrenceTS: Int64, persist: Bool = true) {
        guard let i = db.events.firstIndex(where: { $0.id == eventId }) else { return }
        let event = db.events[i]
        let previous = occurrenceTS - Int64(event.repeatInterval)
        let day = JDate(ts: previous).withTimeAtStartOfDay
        db.events[i].repeatLimit = event.isAllDay ? day.seconds : day.withTime(23, 59, 59).seconds
        if event.isTask { db.completedTasks.removeAll { $0.taskId == eventId && $0.startTS >= occurrenceTS } }
        if persist { save() }
    }

    func deleteRepeatingEventOccurrence(_ parentId: Int64, occurrenceTS: Int64) {
        guard let i = db.events.firstIndex(where: { $0.id == parentId }) else { return }
        db.events[i].addRepetitionException(Formatter.getDayCodeFromTS(occurrenceTS))
        if db.events[i].isTask { db.completedTasks.removeAll { $0.taskId == parentId && $0.startTS == occurrenceTS } }
        save()
    }

    func deleteEvents(ids: [Int64], persist: Bool = true) {
        guard !ids.isEmpty else { return }
        let set = Set(ids)
        db.events.removeAll { $0.id.map(set.contains) ?? false }
        db.completedTasks.removeAll { set.contains($0.taskId) }
        let children = db.events.filter { set.contains($0.parentId) }.compactMap(\.id)
        if !children.isEmpty { deleteEvents(ids: children, persist: false) }
        if persist { save() }
    }

    func deleteAllEvents() {
        db.events.removeAll()
        db.completedTasks.removeAll()
        save()
    }

    /// DeleteEventDialog result for a set of occurrences (handleEventDeleting).
    func delete(_ events: [Event], scope: EditScope) {
        for e in events where e.isSynced {
            deleteSystemEvent(e, scope: e.repeatInterval > 0 ? scope : .allOccurrences)
        }
        let local = events.filter { !$0.isSynced }
        let nonRepeating = local.filter { $0.repeatInterval == 0 }.compactMap(\.id)
        deleteEvents(ids: nonRepeating, persist: false)
        for e in local where e.repeatInterval > 0 {
            guard let id = e.id else { continue }
            switch scope {
            case .selectedOccurrence:
                if let i = db.events.firstIndex(where: { $0.id == id }) {
                    db.events[i].addRepetitionException(Formatter.getDayCodeFromTS(e.startTS))
                    if e.isTask { db.completedTasks.removeAll { $0.taskId == id && $0.startTS == e.startTS } }
                }
            case .futureOccurrences: addEventRepeatLimit(id, occurrenceTS: e.startTS, persist: false)
            case .allOccurrences: deleteEvents(ids: [id], persist: false)
            }
        }
        save()
        refresh()
    }

    /// getEventsToExport()
    func eventsToExport(calendars: Set<Int64>, events: Bool, tasks: Bool, pastEntries: Bool) -> [Event] {
        let now = getNowSeconds()
        var result: [Event] = []
        for e in db.events where calendars.contains(e.calendarId) {
            if e.isTask ? !tasks : !events { continue }
            if !pastEntries && e.endTS <= now && e.repeatInterval == 0 { continue }
            var copy = e
            if copy.isTask, let id = copy.id {
                copy.flags = copy.flags.addBitIf(isTaskCompleted(id: id, startTS: copy.startTS), FLAG_TASK_COMPLETED)
            }
            result.append(copy)
        }
        return result
    }

    /// Replace the holiday calendar's managed events (HolidayHelper.replaceHolidays).
    func replaceHolidays(calendarId: Int64, holidays: [Event]) {
        let incoming = Set(holidays.map(\.importId))
        let owned = db.events.filter {
            $0.calendarId == calendarId && ($0.importId.hasPrefix(MANAGED_HOLIDAY_PREFIX) || ($0.source == SOURCE_IMPORTED_ICS && incoming.contains($0.importId)))
        }.compactMap(\.id)
        let ownedSet = Set(owned)
        for i in db.events.indices where ownedSet.contains(db.events[i].parentId) { db.events[i].parentId = 0 }
        db.events.removeAll { $0.id.map(ownedSet.contains) ?? false }
        for var h in holidays {
            h.calendarId = calendarId
            h.importId = MANAGED_HOLIDAY_PREFIX + holidayKey(h)
            h.id = db.nextEventId
            db.nextEventId += 1
            db.events.append(h)
        }
        save()
    }

    func holidayKey(_ e: Event) -> String { "\(e.importId):\(e.startTS):\(e.endTS):\(e.repeatInterval):\(e.repeatRule):\(e.repeatLimit)" }

    /// Birthdays/anniversaries stored per contact.
    func contactEvents(source: String) -> [Event] { db.events.filter { $0.source == source && !$0.isTask } }

    func deleteContactEvent(source: String, importId: String) {
        db.events.removeAll { $0.source == source && $0.importId == importId }
    }

    /// Import/merge helper for IcsImporter: events with import ids.
    var eventsWithImportIds: [Event] { db.events.filter { !$0.importId.isEmpty } }
    func eventWithImportId(_ importId: String) -> Event? { db.events.first { $0.importId == importId && !$0.isTask } }

    func setRepetitionException(_ id: Int64, dayCode: String) {
        if let i = db.events.firstIndex(where: { $0.id == id }) { db.events[i].addRepetitionException(dayCode) }
    }

    // MARK: Search ranges

    func searchEvents(_ query: String, from: Int64, to: Int64) -> [Event] {
        getEvents(from: from, to: to, searchQuery: query)
    }
}
