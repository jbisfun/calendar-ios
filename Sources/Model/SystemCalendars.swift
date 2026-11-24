import EventKit
import FossifyCommons
import SwiftUI
import UIKit

/// CalDAVHelper: on iOS the system calendar store (EventKit) plays the role of Android's
/// CalendarContract. Synced calendars get a CalendarEntity like on Android, but their events
/// are read from and written to EventKit directly instead of being mirrored.
extension CalendarStore {
    var hasCalendarAccess: Bool {
        if #available(iOS 17.0, *) { return calendarAccess == .fullAccess }
        return calendarAccess == .authorized
    }

    func requestCalendarAccess(_ done: @escaping (Bool) -> Void) {
        ekStore.requestFullAccessToEvents { granted, _ in
            DispatchQueue.main.async {
                self.calendarAccess = EKEventStore.authorizationStatus(for: .event)
                done(granted)
            }
        }
    }

    /// All event calendars on the device, grouped by account (getCalDAVCalendars).
    var systemCalendarsBySource: [(String, [EKCalendar])] {
        guard hasCalendarAccess else { return [] }
        let cals = ekStore.calendars(for: .event)
        let grouped = Dictionary(grouping: cals) { $0.source?.title ?? "" }
        return grouped.keys.sorted().map { key in (key, grouped[key]!.sorted { $0.title < $1.title }) }
    }

    func ekCalendar(_ id: String) -> EKCalendar? { hasCalendarAccess ? ekStore.calendar(withIdentifier: id) : nil }

    func canWrite(_ calendar: CalendarEntity) -> Bool {
        !calendar.isSyncedCalendar || (ekCalendar(calendar.caldavCalendarId)?.allowsContentModifications ?? false)
    }

    /// Settings › Manage synced calendars: store the selection and create/remove calendar entities.
    func setSyncedCalendars(_ ids: [String]) {
        let old = Set(config.syncedCalendarIds)
        config.caldavSyncedCalendarIds = ids.joined(separator: ",")
        config.caldavSync = !ids.isEmpty
        var existingTitles = Set(db.calendars.map { $0.displayTitle.lowercased() })
        for id in ids {
            guard let ek = ekCalendar(id) else { continue }
            if let entity = calendarWithCalDAVId(id) {
                config.addDisplayCalendar(entity.id)
                continue
            }
            let entity = CalendarEntity(id: 0, title: ek.title, color: ek.argb, caldavCalendarId: id,
                                        caldavDisplayName: ek.title, caldavEmail: ek.source?.title ?? "")
            if existingTitles.insert(entity.displayTitle.lowercased()).inserted {
                insertOrUpdateCalendar(entity, isNew: true)
            }
        }
        let removed = old.subtracting(ids)
        let removedEntities = db.calendars.filter { removed.contains($0.caldavCalendarId) }
        if !removedEntities.isEmpty {
            config.displayCalendars.subtract(removedEntities.map { String($0.id) })
            removeCalendarEntities(Set(removedEntities.map(\.id)))
        }
        if config.lastUsedCaldavCalendarId.isEmpty == false && !ids.contains(config.lastUsedCaldavCalendarId) {
            config.lastUsedCaldavCalendarId = ""
        }
        refresh()
    }

    /// The system store changed (another app or an account sync): refresh titles and colors.
    func systemCalendarsChanged() {
        calendarAccess = EKEventStore.authorizationStatus(for: .event)
        guard hasCalendarAccess else { refresh(); return }
        var changed = false
        for c in db.calendars where c.isSyncedCalendar {
            guard let ek = ekStore.calendar(withIdentifier: c.caldavCalendarId) else { continue }
            if ek.title != c.caldavDisplayName || ek.argb != c.color {
                var u = c
                u.title = ek.title
                u.caldavDisplayName = ek.title
                u.color = ek.argb
                replaceCalendarEntity(u)
                changed = true
            }
        }
        if changed { save() } else { refresh() }
    }

    /// Refresh CalDAV calendars: ask the accounts to sync, then refetch.
    func refreshSystemCalendars(showToast: Bool) {
        if showToast { toast = "Refreshing…" }
        ekStore.refreshSourcesIfNecessary()
        systemCalendarsChanged()
        if showToast {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.toast = "Refreshing complete" }
        }
    }

    func updateSystemCalendar(_ calendar: CalendarEntity) {
        guard let ek = ekCalendar(calendar.caldavCalendarId), ek.allowsContentModifications else { return }
        ek.cgColor = UIColor(Color(argb: calendar.color)).cgColor
        do { try ekStore.saveCalendar(ek, commit: true) } catch { toast = "Editing calendar failed" }
    }

    // MARK: Reading events

    func systemEvents(from: Int64, to: Int64, applyTypeFilter: Bool, display: Set<Int64>) -> [Event] {
        guard config.caldavSync, hasCalendarAccess else { return [] }
        var map: [String: CalendarEntity] = [:]
        for c in db.calendars where c.isSyncedCalendar && config.syncedCalendarIds.contains(c.caldavCalendarId) {
            if applyTypeFilter && !display.contains(c.id) { continue }
            map[c.caldavCalendarId] = c
        }
        let cals = map.keys.compactMap { ekStore.calendar(withIdentifier: $0) }
        guard !cals.isEmpty, to >= from else { return [] }
        var result: [Event] = []
        var start = from
        // EventKit limits a predicate to four years.
        let span: Int64 = 4 * 365 * 86400 - 86400
        while start <= to {
            let end = min(to, start + span)
            let predicate = ekStore.predicateForEvents(withStart: Date(timeIntervalSince1970: TimeInterval(start)),
                                                       end: Date(timeIntervalSince1970: TimeInterval(end) + 1), calendars: cals)
            for ek in ekStore.events(matching: predicate) {
                guard let entity = map[ek.calendar.calendarIdentifier] else { continue }
                var e = makeEvent(ek, calendar: entity)
                if e.endTS < from || e.startTS > to { continue }
                e.updateIsPastEvent()
                result.append(e)
            }
            start = end + 1
        }
        var seen = Set<String>()
        return result.filter { seen.insert($0.occurrenceKey).inserted }
    }

    /// The EventKit occurrence of `identifier` that starts at (or nearest to) `occurrenceTS`.
    func ekOccurrence(identifier: String, occurrenceTS: Int64) -> EKEvent? {
        guard hasCalendarAccess, let master = ekStore.event(withIdentifier: identifier) else { return nil }
        guard master.hasRecurrenceRules || master.isDetached else { return master }
        let at = Date(timeIntervalSince1970: TimeInterval(occurrenceTS))
        let predicate = ekStore.predicateForEvents(withStart: at.addingTimeInterval(-2 * 86400), end: at.addingTimeInterval(2 * 86400),
                                                   calendars: [master.calendar])
        let matches = ekStore.events(matching: predicate).filter { $0.eventIdentifier == identifier }
        return matches.min { abs($0.startDate.timeIntervalSince(at)) < abs($1.startDate.timeIntervalSince(at)) } ?? master
    }

    func systemEvent(identifier: String, occurrenceTS: Int64) -> Event? {
        guard let ek = ekOccurrence(identifier: identifier, occurrenceTS: occurrenceTS),
              let entity = calendarWithCalDAVId(ek.calendar.calendarIdentifier) else { return nil }
        return makeEvent(ek, calendar: entity)
    }

    func makeEvent(_ ek: EKEvent, calendar: CalendarEntity) -> Event {
        var e = Event()
        e.ekID = ek.eventIdentifier
        e.calendarId = calendar.id
        e.title = ek.title ?? ""
        e.location = ek.location ?? ""
        e.description = ek.notes ?? ""
        e.importId = ek.calendarItemExternalIdentifier ?? ek.eventIdentifier ?? ""
        e.source = "\(CALDAV)-\(calendar.caldavCalendarId)"
        e.timeZone = ek.timeZone?.identifier ?? TimeZone.current.identifier
        e.lastUpdated = Int64((ek.lastModifiedDate ?? Date()).timeIntervalSince1970 * 1000)
        let start = Int64(ek.startDate.timeIntervalSince1970)
        let end = Int64(ek.endDate.timeIntervalSince1970)
        if ek.isAllDay {
            e.flags |= FLAG_ALL_DAY
            e.startTS = JDate(ts: start).withTimeAtStartOfDay.seconds
            e.endTS = JDate(ts: max(start, end - 1)).withTimeAtStartOfDay.seconds + TWELVE_HOURS
        } else {
            e.startTS = start
            e.endTS = max(start, end)
        }
        let alarms = (ek.alarms ?? []).compactMap { a -> Int? in
            guard a.absoluteDate == nil else { return nil }
            return a.relativeOffset > 0 ? -Int(a.relativeOffset / 60) : Int(-a.relativeOffset / 60)
        }.sorted()
        e.reminder1Minutes = alarms.count > 0 ? alarms[0] : REMINDER_OFF
        e.reminder2Minutes = alarms.count > 1 ? alarms[1] : REMINDER_OFF
        e.reminder3Minutes = alarms.count > 2 ? alarms[2] : REMINDER_OFF
        if let rule = ek.recurrenceRules?.first {
            let r = Self.repetition(from: rule, startTS: e.startTS, allDay: ek.isAllDay)
            e.repeatInterval = r.interval
            e.repeatRule = r.rule
            e.repeatLimit = r.limit
        }
        e.availability = ek.availability == .free ? AVAILABILITY_FREE : AVAILABILITY_BUSY
        switch ek.status {
        case .tentative: e.status = STATUS_TENTATIVE
        case .canceled: e.status = STATUS_CANCELED
        default: e.status = STATUS_CONFIRMED
        }
        e.attendees = (ek.attendees ?? []).map { p in
            let email = p.url.absoluteString.replacingOccurrences(of: "mailto:", with: "")
            let status: Int
            switch p.participantStatus {
            case .accepted: status = ATTENDEE_STATUS_ACCEPTED
            case .declined: status = ATTENDEE_STATUS_DECLINED
            case .tentative: status = ATTENDEE_STATUS_TENTATIVE
            case .pending: status = ATTENDEE_STATUS_INVITED
            default: status = ATTENDEE_STATUS_NONE
            }
            return Attendee(name: p.name ?? "", email: email, status: status, isMe: p.isCurrentUser,
                            relationship: p.participantRole == .chair ? 2 : 1)
        }
        e.color = calendar.color
        return e
    }

    // MARK: Writing events

    /// insertCalDAVEvent / updateCalDAVEvent. Returns the event identifier.
    func saveSystemEvent(_ event: Event, span: EKSpan, isNew: Bool, allOccurrences: Bool = false, occurrenceTS: Int64? = nil) -> String? {
        guard hasCalendarAccess, let entity = calendar(event.calendarId), let cal = ekCalendar(entity.caldavCalendarId) else {
            toast = "You are not allowed to write in the selected calendar"
            return nil
        }
        guard cal.allowsContentModifications else {
            toast = "You are not allowed to write in the selected calendar"
            return nil
        }
        let ek: EKEvent
        var startTS = event.startTS
        var endTS = event.endTS
        if isNew || event.ekID == nil {
            ek = EKEvent(eventStore: ekStore)
        } else if allOccurrences, let id = event.ekID, let first = ekStore.event(withIdentifier: id) {
            // Shift the whole series by how much the edited occurrence moved.
            ek = first
            if let occ = occurrenceTS {
                let delta = event.startTS - occ
                let duration = event.endTS - event.startTS
                startTS = Int64(first.startDate.timeIntervalSince1970) + delta
                if event.isAllDay { startTS = JDate(ts: startTS).withTimeAtStartOfDay.seconds }
                endTS = startTS + duration
            }
        } else if let id = event.ekID, let occ = ekOccurrence(identifier: id, occurrenceTS: occurrenceTS ?? event.startTS) {
            ek = occ
        } else {
            return nil
        }
        ek.calendar = cal
        ek.title = event.title
        ek.location = event.location.isEmpty ? nil : event.location
        ek.notes = event.description.isEmpty ? nil : event.description
        ek.isAllDay = event.isAllDay
        if event.isAllDay {
            ek.startDate = JDate(ts: startTS).withTimeAtStartOfDay.date
            ek.endDate = JDate(ts: endTS).withTimeAtStartOfDay.date
            ek.timeZone = nil
        } else {
            ek.timeZone = TimeZone(identifier: event.timeZoneString)
            ek.startDate = Date(timeIntervalSince1970: TimeInterval(startTS))
            ek.endDate = Date(timeIntervalSince1970: TimeInterval(endTS))
        }
        ek.alarms = event.reminders.map { r in
            EKAlarm(relativeOffset: r.minutes < -1 ? TimeInterval(-r.minutes * 60) : TimeInterval(-r.minutes * 60))
        }
        if span == .futureEvents || isNew {
            ek.recurrenceRules = event.repeatInterval > 0 ? [Self.recurrenceRule(for: event)] : nil
        }
        if cal.supportedEventAvailabilities.contains(event.availability == AVAILABILITY_FREE ? .free : .busy) {
            ek.availability = event.availability == AVAILABILITY_FREE ? .free : .busy
        }
        do {
            try ekStore.save(ek, span: span, commit: true)
            config.lastUsedCaldavCalendarId = entity.caldavCalendarId
            return ek.eventIdentifier
        } catch {
            toast = error.localizedDescription
            return nil
        }
    }

    func deleteSystemEvent(_ event: Event, scope: EditScope) {
        guard let id = event.ekID else { return }
        do {
            switch scope {
            case .selectedOccurrence:
                if let occ = ekOccurrence(identifier: id, occurrenceTS: event.startTS) { try ekStore.remove(occ, span: .thisEvent, commit: true) }
            case .futureOccurrences:
                if let occ = ekOccurrence(identifier: id, occurrenceTS: event.startTS) { try ekStore.remove(occ, span: .futureEvents, commit: true) }
            case .allOccurrences:
                if let first = ekStore.event(withIdentifier: id) { try ekStore.remove(first, span: .futureEvents, commit: true) }
            }
        } catch {
            toast = error.localizedDescription
        }
    }

    // MARK: Recurrence mapping (Parser.parseRepeatInterval / getRepeatCode)

    static func isoDay(_ w: EKWeekday) -> Int { (w.rawValue + 5) % 7 + 1 }
    static func ekWeekday(iso: Int) -> EKWeekday { EKWeekday(rawValue: iso % 7 + 1) ?? .monday }

    static func repetition(from rule: EKRecurrenceRule, startTS: Int64, allDay: Bool) -> (interval: Int, rule: Int, limit: Int64) {
        let start = JDate(ts: startTS)
        let n = max(1, rule.interval)
        var interval = 0
        var repeatRule = 0
        switch rule.frequency {
        case .daily:
            interval = DAY * n
            if n % 7 == 0 {
                repeatRule = 1 << (start.dayOfWeek - 1)
            } else if let days = rule.daysOfTheWeek, !days.isEmpty {
                interval = WEEK
                repeatRule = days.reduce(0) { $0 | 1 << (isoDay($1.dayOfTheWeek) - 1) }
            }
        case .weekly:
            interval = WEEK * n
            if let days = rule.daysOfTheWeek, !days.isEmpty {
                repeatRule = days.reduce(0) { $0 | 1 << (isoDay($1.dayOfTheWeek) - 1) }
            } else {
                repeatRule = 1 << (start.dayOfWeek - 1)
            }
        case .monthly, .yearly:
            interval = (rule.frequency == .monthly ? MONTH : YEAR) * n
            repeatRule = REPEAT_SAME_DAY
            if let days = rule.daysOfTheWeek, let first = days.first {
                repeatRule = first.weekNumber < 0 ? REPEAT_ORDER_WEEKDAY_USE_LAST : REPEAT_ORDER_WEEKDAY
            } else if rule.daysOfTheMonth?.contains(-1) == true {
                repeatRule = REPEAT_LAST_DAY
            }
        @unknown default: break
        }
        var limit: Int64 = 0
        if let end = rule.recurrenceEnd {
            if end.occurrenceCount > 0 {
                limit = -Int64(end.occurrenceCount)
            } else if let date = end.endDate {
                limit = Int64(date.timeIntervalSince1970)
            }
        }
        return (interval, repeatRule, limit)
    }

    static func recurrenceRule(for event: Event) -> EKRecurrenceRule {
        let r = event.repeatInterval
        let start = JDate(ts: event.startTS)
        let freq: EKRecurrenceFrequency
        let n: Int
        if r % YEAR == 0 { freq = .yearly; n = r / YEAR }
        else if r % MONTH == 0 { freq = .monthly; n = r / MONTH }
        else if r % WEEK == 0 { freq = .weekly; n = r / WEEK }
        else { freq = .daily; n = max(1, r / DAY) }
        var daysOfWeek: [EKRecurrenceDayOfWeek]?
        var daysOfMonth: [NSNumber]?
        var months: [NSNumber]?
        if freq == .weekly {
            daysOfWeek = (1...7).filter { event.repeatRule & (1 << ($0 - 1)) != 0 }.map { EKRecurrenceDayOfWeek(ekWeekday(iso: $0)) }
        } else if freq == .monthly || freq == .yearly {
            if freq == .yearly { months = [NSNumber(value: start.monthOfYear)] }
            switch event.repeatRule {
            case REPEAT_LAST_DAY: daysOfMonth = [-1]
            case REPEAT_ORDER_WEEKDAY, REPEAT_ORDER_WEEKDAY_USE_LAST:
                let isLast = start.monthOfYear != start.plusDays(7).monthOfYear
                let order = isLast && event.repeatRule == REPEAT_ORDER_WEEKDAY_USE_LAST ? -1 : (start.dayOfMonth - 1) / 7 + 1
                daysOfWeek = [EKRecurrenceDayOfWeek(ekWeekday(iso: start.dayOfWeek), weekNumber: order)]
            default: break
            }
        }
        var end: EKRecurrenceEnd?
        if event.repeatLimit < 0 {
            end = EKRecurrenceEnd(occurrenceCount: Int(-event.repeatLimit))
        } else if event.repeatLimit > 0 {
            end = EKRecurrenceEnd(end: Date(timeIntervalSince1970: TimeInterval(event.repeatLimit)))
        }
        return EKRecurrenceRule(recurrenceWith: freq, interval: n, daysOfTheWeek: daysOfWeek, daysOfTheMonth: daysOfMonth,
                                monthsOfTheYear: months, weeksOfTheYear: nil, daysOfTheYear: nil, setPositions: nil, end: end)
    }
}

extension EKCalendar {
    var argb: UInt32 { Color(cgColor: cgColor).argb | 0xFF000000 }
}
