import Foundation

/// models/Attendee.kt
struct Attendee: Codable, Hashable {
    var contactId: Int = 0
    var name: String
    var email: String
    var status: Int
    var photoUri: String = ""
    var isMe: Bool = false
    var relationship: Int = 0

    var publicName: String { name.isEmpty ? email : name }
    var showStatusImage: Bool {
        status == ATTENDEE_STATUS_ACCEPTED || status == ATTENDEE_STATUS_DECLINED || status == ATTENDEE_STATUS_TENTATIVE
    }
}

/// models/Reminder.kt
struct Reminder: Hashable {
    var minutes: Int
    var type: Int
}

/// models/CalendarEntity.kt (the "event types" table). Synced calendars point at an
/// EventKit calendar through `caldavCalendarId` (its calendarIdentifier).
struct CalendarEntity: Codable, Hashable, Identifiable {
    var id: Int64
    var title: String
    var color: UInt32
    var caldavCalendarId: String = ""
    var caldavDisplayName: String = ""
    var caldavEmail: String = ""
    var type: Int = OTHER_EVENT

    var displayTitle: String { caldavCalendarId.isEmpty ? title : "\(caldavDisplayName) (\(caldavEmail))" }
    var isSyncedCalendar: Bool { !caldavCalendarId.isEmpty }
}

/// models/Task.kt: completion state of one occurrence of a task.
struct CompletedTask: Codable, Hashable {
    var taskId: Int64
    var startTS: Int64
    var flags: Int
}

/// models/Event.kt. Local events and tasks live in the app's own store; events of
/// synced calendars come from EventKit and carry `ekID`.
struct Event: Codable, Hashable {
    var id: Int64?
    var startTS: Int64 = 0
    var endTS: Int64 = 0
    var title = ""
    var location = ""
    var description = ""
    var reminder1Minutes = REMINDER_OFF
    var reminder2Minutes = REMINDER_OFF
    var reminder3Minutes = REMINDER_OFF
    var reminder1Type = REMINDER_NOTIFICATION
    var reminder2Type = REMINDER_NOTIFICATION
    var reminder3Type = REMINDER_NOTIFICATION
    var repeatInterval = 0
    var repeatRule = 0
    var repeatLimit: Int64 = 0
    var repetitionExceptions: [String] = []
    var attendees: [Attendee] = []
    var importId = ""
    var timeZone = ""
    var flags = 0
    var calendarId: Int64 = LOCAL_CALENDAR_ID
    var parentId: Int64 = 0
    var lastUpdated: Int64 = 0
    var source = SOURCE_SIMPLE_CALENDAR
    var availability = AVAILABILITY_BUSY
    var accessLevel = ACCESS_DEFAULT
    var color: UInt32 = 0
    var type = TYPE_EVENT
    var status = STATUS_CONFIRMED
    /// EventKit eventIdentifier for events of synced calendars.
    var ekID: String?

    init(id: Int64? = nil) { self.id = id }

    /// Stable identity of this occurrence in lists.
    var occurrenceKey: String { "\(ekID ?? String(id ?? 0))@\(startTS)" }
    var ref: EventRef { EventRef(id: id, ekID: ekID, occurrenceTS: startTS, isTask: isTask) }

    var isAllDay: Bool { flags & FLAG_ALL_DAY != 0 }
    var hasMissingYear: Bool { flags & FLAG_MISSING_YEAR != 0 }
    var isTask: Bool { type == TYPE_TASK }
    var isTaskCompleted: Bool { isTask && flags & FLAG_TASK_COMPLETED != 0 }
    var isSynced: Bool { ekID != nil }
    var isAttendeeInviteDeclined: Bool { attendees.contains { $0.isMe && $0.status == ATTENDEE_STATUS_DECLINED } }
    var isEventCanceled: Bool { status == STATUS_CANCELED }
    var shouldStrikeThrough: Bool { isTaskCompleted || isAttendeeInviteDeclined || isEventCanceled }

    var isPastEvent: Bool {
        get { flags & FLAG_IS_IN_PAST != 0 }
        set { flags = flags.addBitIf(newValue, FLAG_IS_IN_PAST) }
    }

    var reminders: [Reminder] {
        [Reminder(minutes: reminder1Minutes, type: reminder1Type),
         Reminder(minutes: reminder2Minutes, type: reminder2Type),
         Reminder(minutes: reminder3Minutes, type: reminder3Type)].filter { $0.minutes != REMINDER_OFF }
    }

    /// Properly return the start time of all-day events as midnight.
    var eventStartTS: Int64 { isAllDay ? JDate(ts: startTS).withTimeAtStartOfDay.seconds : startTS }

    var timeZoneString: String {
        if !timeZone.isEmpty && TimeZone(identifier: timeZone) != nil { return timeZone }
        return TimeZone.current.identifier
    }

    mutating func updateIsPastEvent() {
        let now = getNowSeconds()
        let endToCheck = startTS < now && isAllDay ? Formatter.getDayEndTS(Formatter.getDayCodeFromTS(endTS)) : endTS
        isPastEvent = endToCheck < now
    }

    mutating func addRepetitionException(_ dayCode: String) {
        if !repetitionExceptions.contains(dayCode) { repetitionExceptions.append(dayCode) }
    }

    // MARK: Repetition (Event.addIntervalTime)

    mutating func addIntervalTime(_ original: Event) {
        let oldStart = JDate(ts: startTS)
        let newStart: JDate
        if repeatInterval == DAY {
            newStart = oldStart.plusDays(1)
        } else if repeatInterval % YEAR == 0 {
            switch repeatRule {
            case REPEAT_ORDER_WEEKDAY: newStart = addXthDayInterval(oldStart, original, false)
            case REPEAT_ORDER_WEEKDAY_USE_LAST: newStart = addXthDayInterval(oldStart, original, true)
            default: newStart = addYearsWithSameDay(oldStart)
            }
        } else if repeatInterval % MONTH == 0 {
            switch repeatRule {
            case REPEAT_SAME_DAY: newStart = addMonthsWithSameDay(oldStart, original)
            case REPEAT_ORDER_WEEKDAY: newStart = addXthDayInterval(oldStart, original, false)
            case REPEAT_ORDER_WEEKDAY_USE_LAST: newStart = addXthDayInterval(oldStart, original, true)
            default:
                let m = oldStart.plusMonths(repeatInterval / MONTH)
                newStart = m.withDayOfMonth(m.maxDayOfMonth)
            }
        } else if repeatInterval % WEEK == 0 {
            // step through weekly repetition by days too, as events can trigger multiple times a week
            newStart = oldStart.plusDays(1)
        } else {
            newStart = oldStart.plusSeconds(repeatInterval)
        }
        let newStartTS = newStart.seconds
        endTS = newStartTS + (endTS - startTS)
        startTS = newStartTS
    }

    /// If an event should happen on 29th Feb. with Same Day yearly repetition, show it only on leap years.
    private func addYearsWithSameDay(_ cur: JDate) -> JDate {
        let years = repeatInterval / YEAR
        var n = cur.plusYears(years)
        if n.dayOfMonth != cur.dayOfMonth {
            var step = years
            while n.withDayOfMonth(1).maxDayOfMonth < cur.dayOfMonth && step < years * 40 {
                step += years
                n = cur.plusYears(step)
            }
            n = n.withDayOfMonth(cur.dayOfMonth)
        }
        return n
    }

    /// If an event should happen on 31st with Same Day monthly repetition, don't show it at months with 30 or less days.
    private func addMonthsWithSameDay(_ cur: JDate, _ original: Event) -> JDate {
        let months = repeatInterval / MONTH
        var n = cur.plusMonths(months)
        if n.dayOfMonth == cur.dayOfMonth { return n }
        let originalMax = JDate(ts: original.startTS).maxDayOfMonth
        var guardCount = 0
        while n.maxDayOfMonth < originalMax && guardCount < 48 {
            n = n.plusMonths(months)
            n = n.withDayOfMonth(cur.dayOfMonth)
            guardCount += 1
        }
        return n.withDayOfMonth(cur.dayOfMonth)
    }

    /// Handle monthly repetitions like Third Monday.
    private func addXthDayInterval(_ cur: JDate, _ original: Event, _ forceLastWeekday: Bool) -> JDate {
        let day = cur.dayOfWeek
        let months = max(1, repeatInterval % YEAR == 0 ? (repeatInterval / YEAR) * 12 : repeatInterval / MONTH)
        var order = (cur.dayOfMonth - 1) / 7
        var properMonth = cur.withDayOfMonth(7).plusMonths(months).withDayOfWeek(day)
        if forceLastWeekday && (order == 3 || order == 4) {
            let o = JDate(ts: original.startTS)
            if o.monthOfYear != o.plusDays(7).monthOfYear { order = -1 }
        }
        var wantedDay: Int
        if order == -1 {
            wantedDay = properMonth.dayOfMonth + ((properMonth.maxDayOfMonth - properMonth.dayOfMonth) / 7) * 7
        } else {
            wantedDay = properMonth.dayOfMonth + (order - (properMonth.dayOfMonth - 1) / 7) * 7
            var guardCount = 0
            while properMonth.maxDayOfMonth < wantedDay && guardCount < 48 {
                properMonth = properMonth.withDayOfMonth(7).plusMonths(months).withDayOfWeek(day)
                wantedDay = properMonth.dayOfMonth + (order - (properMonth.dayOfMonth - 1) / 7) * 7
                guardCount += 1
            }
        }
        return properMonth.withDayOfMonth(wantedDay)
    }

    /// Long.isTsOnProperDay()
    func isTsOnProperDay(_ ts: Int64) -> Bool {
        repeatRule & (1 << (JDate(ts: ts).dayOfWeek - 1)) != 0
    }

    /// Check if it's the proper week, for events repeating every x weeks (weeks start on Monday).
    func isOnProperWeek(originalStart: Int64) -> Bool {
        if repeatInterval == WEEK { return true }
        let initial = JDate(ts: originalStart).withTimeAtStartOfDay
        let initialWeekStart = initial.minusDays((initial.dayOfWeek - 1 + 7) % 7)
        let weeks = JDate.daysBetween(initialWeekStart, JDate(ts: startTS)) / 7
        return weeks % max(1, repeatInterval / WEEK) == 0
    }

    /// Event.maybeAdjustRepeatLimitCount(): keep the repetition ending on the original date.
    mutating func maybeAdjustRepeatLimitCount(_ original: Event, occurrenceTS: Int64) {
        if original.repeatLimit < 0 && repeatLimit < 0 && original.repeatLimit == repeatLimit && original.repeatInterval > 0 {
            let since = (occurrenceTS - original.startTS) / Int64(original.repeatInterval)
            repeatLimit += since
        }
    }
}

/// What a screen needs to open an event or task: the stored event plus the tapped occurrence.
struct EventRef: Hashable {
    var id: Int64?
    var ekID: String?
    var occurrenceTS: Int64
    var isTask: Bool
    var ident: String { "\(ekID ?? String(id ?? 0))@\(occurrenceTS)" }
}
