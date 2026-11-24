import Foundation

/// helpers/Parser.kt
enum Parser {
    /// From RRULE:FREQ=DAILY;COUNT=5 to Daily, 5x...
    static func parseRepeatInterval(_ fullString: String, startTS: Int64) -> (interval: Int, rule: Int, limit: Int64) {
        var repeatInterval = 0
        var repeatRule = 0
        var repeatLimit: Int64 = 0
        for part in fullString.split(separator: ";").map(String.init) where !part.isEmpty {
            let kv = part.split(separator: "=", maxSplits: 1).map(String.init)
            guard kv.count > 1 else { continue }
            let key = kv[0], value = kv[1]
            switch key {
            case "FREQ":
                repeatInterval = frequencySeconds(value)
                if value == "WEEKLY" {
                    repeatRule = 1 << (JDate(ts: startTS).dayOfWeek - 1)
                } else if value == "MONTHLY" || value == "YEARLY" {
                    repeatRule = REPEAT_SAME_DAY
                } else if value == "DAILY" && fullString.contains("INTERVAL") {
                    let interval = fullString.components(separatedBy: "INTERVAL=").last?.components(separatedBy: ";").first ?? ""
                    if let n = Int(interval), n % 7 == 0 {
                        repeatRule = 1 << (JDate(ts: startTS).dayOfWeek - 1)
                    } else if fullString.contains("BYDAY") {
                        repeatInterval = WEEK
                    }
                }
            case "COUNT": repeatLimit = -(Int64(value) ?? 0)
            case "UNTIL": repeatLimit = parseDateTimeValue(value)
            case "INTERVAL": repeatInterval *= Int(value) ?? 1
            case "BYDAY":
                if isXWeeklyRepetition(repeatInterval) {
                    repeatRule = handleRepeatRule(value)
                } else if isXMonthlyRepetition(repeatInterval) || isXYearlyRepetition(repeatInterval) {
                    repeatRule = value.hasPrefix("-1") ? REPEAT_ORDER_WEEKDAY_USE_LAST : REPEAT_ORDER_WEEKDAY
                }
            case "BYMONTHDAY":
                if value.split(separator: ",").contains(where: { Int($0) == -1 }) { repeatRule = REPEAT_LAST_DAY }
            default: break
            }
        }
        return (repeatInterval, repeatRule, repeatLimit)
    }

    static func frequencySeconds(_ v: String) -> Int {
        switch v {
        case "DAILY": return DAY
        case "WEEKLY": return WEEK
        case "MONTHLY": return MONTH
        case "YEARLY": return YEAR
        default: return 0
        }
    }

    static func handleRepeatRule(_ value: String) -> Int {
        var r = 0
        if value.contains("MO") { r |= MONDAY_BIT }
        if value.contains("TU") { r |= TUESDAY_BIT }
        if value.contains("WE") { r |= WEDNESDAY_BIT }
        if value.contains("TH") { r |= THURSDAY_BIT }
        if value.contains("FR") { r |= FRIDAY_BIT }
        if value.contains("SA") { r |= SATURDAY_BIT }
        if value.contains("SU") { r |= SUNDAY_BIT }
        return r
    }

    static func parseDateTimeValue(_ value: String, timeZone: TimeZone = TimeZone(identifier: "UTC")!) -> Int64 {
        let edited = value.replacingOccurrences(of: "T", with: "").replacingOccurrences(of: "Z", with: "").replacingOccurrences(of: "-", with: "")
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        if edited.count == 14 {
            f.timeZone = value.hasSuffix("Z") ? TimeZone(identifier: "UTC") : timeZone
            f.dateFormat = "yyyyMMddHHmmss"
            return Int64(f.date(from: edited)?.timeIntervalSince1970 ?? 0)
        }
        f.timeZone = timeZone
        f.dateFormat = "yyyyMMdd"
        guard let d = f.date(from: String(edited.prefix(8))) else { return 0 }
        return Formatter.shiftedMidnight(Int64(d.timeIntervalSince1970), from: timeZone, to: TimeZone.current)
    }

    /// From Daily, 5x... to RRULE:FREQ=DAILY;COUNT=5
    static func getRepeatCode(_ e: Event) -> String {
        let r = e.repeatInterval
        guard r != 0 else { return "" }
        let freq = r % YEAR == 0 ? "YEARLY" : r % MONTH == 0 ? "MONTHLY" : r % WEEK == 0 ? "WEEKLY" : "DAILY"
        let interval = r % YEAR == 0 ? r / YEAR : r % MONTH == 0 ? r / MONTH : r % WEEK == 0 ? r / WEEK : r / DAY
        var limit = ""
        if e.repeatLimit < 0 {
            limit = ";COUNT=\(-e.repeatLimit)"
        } else if e.repeatLimit > 0 {
            if e.isAllDay {
                limit = ";UNTIL=\(Formatter.getDayCodeFromTS(e.repeatLimit))"
            } else {
                limit = ";UNTIL=\(Formatter.getExportedTime(e.repeatLimit * 1000))"
            }
        }
        let start = JDate(ts: e.startTS)
        let byMonth = isXYearlyRepetition(r) ? ";BYMONTH=\(start.monthOfYear)" : ""
        var byDay = ""
        if isXWeeklyRepetition(r) {
            byDay = ";BYDAY=" + ["MO", "TU", "WE", "TH", "FR", "SA", "SU"].enumerated()
                .filter { e.repeatRule & (1 << $0.offset) != 0 }.map(\.element).joined(separator: ",")
        } else if isXMonthlyRepetition(r) || isXYearlyRepetition(r) {
            switch e.repeatRule {
            case REPEAT_LAST_DAY: byDay = ";BYMONTHDAY=-1"
            case REPEAT_ORDER_WEEKDAY_USE_LAST, REPEAT_ORDER_WEEKDAY:
                let isLast = start.monthOfYear != start.plusDays(7).monthOfYear
                let order = isLast ? "-1" : String((start.dayOfMonth - 1) / 7 + 1)
                byDay = ";BYDAY=\(order)\(["MO", "TU", "WE", "TH", "FR", "SA", "SU"][start.dayOfWeek - 1])"
            default: break
            }
        }
        return "FREQ=\(freq);INTERVAL=\(interval)\(limit)\(byMonth)\(byDay)"
    }

    /// From P0DT1H5M0S to 3900 (seconds)
    static func parseDurationSeconds(_ duration: String) -> Int {
        func value(_ c: String) -> Int {
            guard let r = duration.range(of: "[0-9]+(?=\(c))", options: .regularExpression) else { return 0 }
            return Int(duration[r]) ?? 0
        }
        return value("S") + value("M") * 60 + value("H") * 3600 + value("D") * 86400 + value("W") * 604_800
    }

    /// From 65 to P0DT1H5M0S
    static func getDurationCode(_ minutes: Int) -> String {
        var remainder = minutes
        let days = remainder / 1440
        remainder -= days * 1440
        let hours = remainder / 60
        remainder -= hours * 60
        return "P\(days)DT\(hours)H\(remainder)M0S"
    }
}

enum ImportResult {
    case fail, nothingNew, ok, partial
}

/// helpers/IcsImporter.kt
@MainActor
final class IcsImporter {
    private let store: CalendarStore
    private var curStart: Int64 = -1
    private var curEnd: Int64 = -1
    private var curDuration = 0
    private var curTitle = ""
    private var curLocation = ""
    private var curDescription = ""
    private var curImportId = ""
    private var curRecurrenceDayCode = ""
    private var curRrule = ""
    private var curFlags = 0
    private var curReminderMinutes: [Int] = []
    private var curReminderActions: [Int] = []
    private var curRepeatExceptions: [String] = []
    private var curRepeatInterval = 0
    private var curRepeatLimit: Int64 = 0
    private var curRepeatRule = 0
    private var curCalendarId = LOCAL_CALENDAR_ID
    private var curLastModified: Int64 = 0
    private var curCategoryColor: UInt32?
    private var curAvailability = AVAILABILITY_BUSY
    private var curAccessLevel = ACCESS_DEFAULT
    private var curStatus = STATUS_CONFIRMED
    private var isNotificationDescription = false
    private var isProperReminderAction = false
    private var isSequence = false
    private var curType = TYPE_EVENT
    private var isParsingEvent = false
    private var isParsingTask = false
    private var curReminderTriggerMinutes = REMINDER_OFF
    private var curReminderTriggerAction = REMINDER_NOTIFICATION
    private var curColor: UInt32 = 0

    private(set) var eventsImported = 0
    private(set) var eventsFailed = 0
    private(set) var eventsAlreadyExist = 0
    private var parsedHolidays: [Event]?

    init(store: CalendarStore) { self.store = store }

    func parseHolidays(_ text: String, calendarId: Int64, reminders: [Int]) -> [Event]? {
        parsedHolidays = []
        let result = importEvents(text: text, defaultCalendarId: calendarId, overrideFileCalendars: true, eventReminders: reminders)
        let events = parsedHolidays
        parsedHolidays = nil
        return result == .ok && eventsFailed == 0 ? events : nil
    }

    func importEvents(text: String, defaultCalendarId: Int64, overrideFileCalendars: Bool, eventReminders: [Int]? = nil) -> ImportResult {
        let existing = parsedHolidays == nil ? store.eventsWithImportIds : []
        var toInsert: [Event] = []
        var line = ""
        var holidayEventCount = 0
        let lines = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n") + ["END:VCALENDAR-SENTINEL"]

        for curLine in lines {
            if curLine.trimmingCharacters(in: .whitespaces).isEmpty { continue }
            if curLine.hasPrefix("\t") || curLine.hasPrefix(" ") {
                line += String(curLine.dropFirst())
                continue
            }
            if parsedHolidays != nil && curLine.trimmingCharacters(in: .whitespaces) == "BEGIN:VEVENT" { holidayEventCount += 1 }
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed == "BEGIN:VEVENT" {
                resetValues()
                curCalendarId = defaultCalendarId
                isParsingEvent = true
            } else if trimmed == "BEGIN:VTODO" {
                resetValues()
                curCalendarId = defaultCalendarId
                isParsingTask = true
                curType = TYPE_TASK
            } else if line.hasPrefix("DUE") {
                if isParsingTask {
                    curStart = getTimestamp(String(line.dropFirst(3)))
                    if !curRrule.isEmpty { parseRepeatRule() }
                }
            } else if line.hasPrefix("DTSTART") {
                if isParsingEvent || isParsingTask {
                    curStart = getTimestamp(String(line.dropFirst(7)))
                    if !curRrule.isEmpty { parseRepeatRule() }
                }
                if curDuration != 0 { curEnd = curStart + Int64(curDuration) }
            } else if line.hasPrefix("DTEND") {
                curEnd = getTimestamp(String(line.dropFirst(5)))
            } else if line.hasPrefix("DURATION:") {
                curDuration = Parser.parseDurationSeconds(String(line.dropFirst(9)))
                curEnd = curStart + Int64(curDuration)
            } else if line.hasPrefix("SUMMARY") && !isNotificationDescription {
                curTitle = cleanup(getTitle(String(line.dropFirst(7))))
            } else if line.hasPrefix("DESCRIPTION") && !isNotificationDescription {
                if let idx = descriptionValueStart(line) {
                    curDescription = cleanup(String(line[idx...]))
                }
                if curDescription.trimmingCharacters(in: .whitespaces).isEmpty { curDescription = "" }
            } else if line.hasPrefix("UID:") {
                curImportId = String(line.dropFirst(4)).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("RRULE:") {
                curRrule = String(line.dropFirst(6))
                if curStart != -1 { parseRepeatRule() }
            } else if line.hasPrefix("ACTION:") {
                let action = String(line.dropFirst(7)).trimmingCharacters(in: .whitespaces)
                isProperReminderAction = action == "DISPLAY" || action == "EMAIL"
                if isProperReminderAction { curReminderTriggerAction = action == "DISPLAY" ? REMINDER_NOTIFICATION : REMINDER_EMAIL }
            } else if line.hasPrefix("TRIGGER") {
                let value = line.components(separatedBy: ":").last ?? ""
                curReminderTriggerMinutes = Parser.parseDurationSeconds(value) / 60
                if !value.hasPrefix("-") { curReminderTriggerMinutes *= -1 }
            } else if line.hasPrefix("CATEGORY_COLOR:") {
                if let c = Int(line.dropFirst(15)) { curCategoryColor = UInt32(signed: c) }
            } else if line.hasPrefix("X-FOSSIFY-CATEGORY-COLOR:") {
                if let c = Int(line.dropFirst(25)) { curCategoryColor = UInt32(signed: c) }
            } else if line.hasPrefix("X-SMT-CATEGORY-COLOR:") {
                if let c = Int(line.dropFirst(21)) { curCategoryColor = UInt32(signed: c) }
            } else if line.hasPrefix("COLOR:") {
                if let c = CssColors.colorByName(String(line.dropFirst(6))) { curColor = c }
            } else if line.hasPrefix("X-FOSSIFY-EVENT-COLOR:") {
                if let c = Int(line.dropFirst(22)) { curColor = UInt32(signed: c) }
            } else if line.hasPrefix("X-FOSSIFY-MISSING-YEAR:") {
                if line.dropFirst(23) == "1" { curFlags |= FLAG_MISSING_YEAR }
            } else if line.hasPrefix("X-SMT-MISSING-YEAR:") {
                if line.dropFirst(19) == "1" { curFlags |= FLAG_MISSING_YEAR }
            } else if line.hasPrefix("CLASS") {
                switch line.components(separatedBy: ":").last ?? "" {
                case "PRIVATE": curAccessLevel = ACCESS_PRIVATE
                case "CONFIDENTIAL": curAccessLevel = ACCESS_CONFIDENTIAL
                default: curAccessLevel = ACCESS_PUBLIC
                }
            } else if line.hasPrefix("STATUS:") {
                let v = String(line.dropFirst(7))
                if isParsingTask && v == "COMPLETED" {
                    curFlags |= FLAG_TASK_COMPLETED
                } else {
                    curStatus = v == "CONFIRMED" ? STATUS_CONFIRMED : v == "CANCELLED" ? STATUS_CANCELED : STATUS_TENTATIVE
                }
            } else if line.hasPrefix("COMPLETED") {
                if isParsingTask && !line.dropFirst(9).trimmingCharacters(in: .whitespaces).isEmpty { curFlags |= FLAG_TASK_COMPLETED }
            } else if line.hasPrefix("CATEGORIES:") && !overrideFileCalendars {
                tryAddCategories(String(line.dropFirst(11)))
            } else if line.hasPrefix("LAST-MODIFIED") {
                curLastModified = getTimestamp(String(line.dropFirst(13))) * 1000
            } else if line.hasPrefix("EXDATE") {
                var value = String(line.dropFirst(6))
                if value.hasSuffix("}") { value.removeLast() }
                let prefix = value.contains(":") ? String(value[..<value.lastIndex(of: ":")!]) + ":" : ""
                let dates = value.contains(":") ? String(value[value.index(after: value.lastIndex(of: ":")!)...]) : value
                for d in dates.split(separator: ",") {
                    curRepeatExceptions.append(Formatter.getDayCodeFromTS(getTimestamp(prefix.isEmpty ? String(d) : prefix + d)))
                }
            } else if line.hasPrefix("LOCATION") {
                curLocation = getLocation(String(line.dropFirst(8)).replacingOccurrences(of: "\\,", with: ","))
                if curLocation.trimmingCharacters(in: .whitespaces).isEmpty { curLocation = "" }
            } else if line.hasPrefix("RECURRENCE-ID") {
                curRecurrenceDayCode = Formatter.getDayCodeFromTS(getTimestamp(String(line.dropFirst(13))))
            } else if line.hasPrefix("SEQUENCE") {
                isSequence = true
            } else if line.hasPrefix("TRANSP:") {
                curAvailability = line.dropFirst(7) == "TRANSPARENT" ? AVAILABILITY_FREE : AVAILABILITY_BUSY
            } else if trimmed == "BEGIN:VALARM" {
                isNotificationDescription = true
            } else if trimmed == "END:VALARM" {
                if isProperReminderAction && curReminderTriggerMinutes != REMINDER_OFF {
                    curReminderMinutes.append(curReminderTriggerMinutes)
                    curReminderActions.append(curReminderTriggerAction)
                }
                isNotificationDescription = false
            } else if trimmed == "END:VEVENT" || trimmed == "END:VTODO" {
                finishEvent(existing: existing, toInsert: &toInsert, eventReminders: eventReminders)
            }
            line = curLine
        }

        if parsedHolidays != nil {
            return eventsFailed == 0 && holidayEventCount > 0 && parsedHolidays?.count == holidayEventCount ? .ok : .fail
        }

        let tasks = toInsert.filter(\.isTask)
        store.insertEvents(toInsert)
        for t in tasks where t.isTaskCompleted {
            if let stored = store.db.events.last(where: { $0.importId == t.importId && $0.isTask }) {
                store.updateTaskCompletion(stored, completed: true)
            }
        }

        if eventsImported == 0 { return eventsAlreadyExist > 0 ? .nothingNew : .fail }
        return eventsFailed > 0 ? .partial : .ok
    }

    private func finishEvent(existing: [Event], toInsert: inout [Event], eventReminders: [Int]?) {
        if curStart != -1 && (curEnd == -1 || isParsingTask) { curEnd = curStart }
        isParsingEvent = false
        isParsingTask = false
        if curTitle.isEmpty || curStart == -1 { return }

        // repeating event exceptions can have the same import id as their parents, so pick the latest event to update
        let eventToUpdate = existing.filter { !curImportId.isEmpty && curImportId == $0.importId }.max { $0.lastUpdated < $1.lastUpdated }
        if let u = eventToUpdate, u.lastUpdated >= curLastModified {
            eventsAlreadyExist += 1
            return
        }

        var reminders: [Reminder]
        if let eventReminders {
            reminders = eventReminders.map { Reminder(minutes: $0, type: REMINDER_NOTIFICATION) }
        } else {
            reminders = (0..<3).map { i in
                Reminder(minutes: i < curReminderMinutes.count ? curReminderMinutes[i] : REMINDER_OFF,
                         type: i < curReminderActions.count ? curReminderActions[i] : REMINDER_NOTIFICATION)
            }
        }
        while reminders.count < 3 { reminders.append(Reminder(minutes: REMINDER_OFF, type: REMINDER_NOTIFICATION)) }
        reminders = reminders.sorted { $0.minutes < $1.minutes }.sorted { ($0.minutes == REMINDER_OFF ? 1 : 0) < ($1.minutes == REMINDER_OFF ? 1 : 0) }

        var event = Event()
        event.startTS = curStart
        event.endTS = curEnd
        event.title = curTitle
        event.location = curLocation
        event.description = curDescription
        event.reminder1Minutes = reminders[0].minutes
        event.reminder2Minutes = reminders[1].minutes
        event.reminder3Minutes = reminders[2].minutes
        event.reminder1Type = reminders[0].type
        event.reminder2Type = reminders[1].type
        event.reminder3Type = reminders[2].type
        event.repeatInterval = curRepeatInterval
        event.repeatRule = curRepeatRule
        event.repeatLimit = curRepeatLimit
        event.repetitionExceptions = curRepeatExceptions
        event.importId = curImportId
        event.timeZone = TimeZone.current.identifier
        event.flags = curFlags
        event.calendarId = curCalendarId
        event.lastUpdated = curLastModified
        event.source = SOURCE_IMPORTED_ICS
        event.availability = curAvailability
        event.type = curType
        event.status = curStatus
        event.accessLevel = curAccessLevel
        event.color = curColor

        if event.isAllDay && curEnd > curStart && !event.isTask {
            event.endTS -= TWELVE_HOURS
            // fix some glitches related to daylight saving shifts
            if event.startTS - event.endTS == 3600 {
                event.endTS += 3600
            } else if event.startTS - event.endTS == -3600 {
                event.endTS -= 3600
            }
        }

        if parsedHolidays != nil {
            if event.importId.isEmpty || event.isTask || !curRecurrenceDayCode.isEmpty || event.startTS > event.endTS {
                eventsFailed += 1
            } else {
                parsedHolidays?.append(event)
                eventsImported += 1
            }
            resetValues()
            return
        }

        if event.importId.isEmpty {
            event.importId = String(abs("\(event.title)\(event.startTS)\(event.endTS)\(event.description)".hashValue))
            if existing.contains(where: { $0.importId == event.importId }) {
                eventsAlreadyExist += 1
                return
            }
        }

        if eventToUpdate == nil {
            if isSequence && !curRecurrenceDayCode.isEmpty {
                // an exception to a recurring event, so update its parent too
                if let parent = store.eventWithImportId(event.importId), let pid = parent.id,
                   !parent.repetitionExceptions.contains(curRecurrenceDayCode) {
                    store.setRepetitionException(pid, dayCode: curRecurrenceDayCode)
                    event.parentId = pid
                    toInsert.append(event)
                }
            } else {
                toInsert.append(event)
            }
        } else {
            event.id = eventToUpdate?.id
            store.updateEvent(event)
        }
        eventsImported += 1
        resetValues()
    }

    private func descriptionValueStart(_ line: String) -> String.Index? {
        // DESCRIPTION(;PARAM="..."|;PARAM=...)*:value — skip quoted parameter values.
        var inQuotes = false
        var i = line.startIndex
        while i < line.endIndex {
            let c = line[i]
            if c == "\"" { inQuotes.toggle() } else if c == ":" && !inQuotes { return line.index(after: i) }
            i = line.index(after: i)
        }
        return nil
    }

    private func cleanup(_ v: String) -> String {
        v.replacingOccurrences(of: "\\n", with: "\n").replacingOccurrences(of: "\\N", with: "\n")
            .replacingOccurrences(of: "\\,", with: ",").replacingOccurrences(of: "\\;", with: ";")
    }

    private func getTimestamp(_ fullString: String) -> Int64 {
        var tz = TimeZone.current
        if fullString.hasPrefix(";") {
            if fullString.contains(":"), let r = fullString.range(of: "TZID=") {
                let id = String(fullString[r.upperBound...].prefix { $0 != ":" && $0 != ";" })
                if let z = TimeZone(identifier: id) { tz = z }
            }
            let value = String(fullString[fullString.index(after: fullString.lastIndex(of: ":") ?? fullString.startIndex)...])
                .replacingOccurrences(of: " ", with: "")
            if value.isEmpty { return 0 }
            if !value.contains("T") { curFlags |= FLAG_ALL_DAY }
            return checked(Parser.parseDateTimeValue(value, timeZone: tz))
        } else if fullString.hasPrefix(":") {
            return checked(Parser.parseDateTimeValue(String(fullString.dropFirst()).trimmingCharacters(in: .whitespaces), timeZone: tz))
        }
        return checked(Parser.parseDateTimeValue(fullString))
    }

    private func checked(_ ts: Int64) -> Int64 {
        if ts == 0 { eventsFailed += 1; return -1 }
        return ts
    }

    private func getLocation(_ s: String) -> String {
        s.hasPrefix(":") ? String(s.drop { $0 == ":" }) : (s.components(separatedBy: ":").dropFirst().joined(separator: ":")).trimmingCharacters(in: .whitespaces)
    }

    private func tryAddCategories(_ categories: String) {
        let title = categories.split(separator: ",").first.map(String.init) ?? categories
        let id = store.calendarIdWithTitle(title)
        if id == -1 {
            let color = curCategoryColor ?? DEFAULT_PRIMARY_COLOR
            curCalendarId = store.insertOrUpdateCalendar(CalendarEntity(id: 0, title: title, color: color), isNew: true)
        } else {
            curCalendarId = id
        }
    }

    private func getTitle(_ title: String) -> String {
        if title.hasPrefix(";") && title.contains(":") {
            return String(title[title.index(after: title.lastIndex(of: ":")!)...])
        }
        return String(title.dropFirst().prefix(179))
    }

    private func parseRepeatRule() {
        let r = Parser.parseRepeatInterval(curRrule, startTS: curStart)
        curRepeatRule = r.rule
        curRepeatInterval = r.interval
        curRepeatLimit = r.limit
    }

    private func resetValues() {
        curStart = -1
        curEnd = -1
        curDuration = 0
        curTitle = ""
        curLocation = ""
        curDescription = ""
        curImportId = ""
        curRecurrenceDayCode = ""
        curRrule = ""
        curFlags = 0
        curReminderMinutes = []
        curReminderActions = []
        curRepeatExceptions = []
        curRepeatInterval = 0
        curRepeatLimit = 0
        curRepeatRule = 0
        curCalendarId = LOCAL_CALENDAR_ID
        curLastModified = 0
        curCategoryColor = nil
        curAvailability = AVAILABILITY_BUSY
        curAccessLevel = ACCESS_DEFAULT
        curStatus = STATUS_CONFIRMED
        isNotificationDescription = false
        isProperReminderAction = false
        isSequence = false
        isParsingEvent = false
        isParsingTask = false
        curReminderTriggerMinutes = REMINDER_OFF
        curReminderTriggerAction = REMINDER_NOTIFICATION
        curType = TYPE_EVENT
        curColor = 0
    }
}

/// helpers/IcsExporter.kt
@MainActor
enum IcsExporter {
    static func export(_ events: [Event], store: CalendarStore) -> String {
        var out: [String] = ["BEGIN:VCALENDAR", "PRODID:-//Fossify//NONSGML Event Calendar//EN", "VERSION:2.0"]
        let exportTime = Formatter.getExportedTime(Int64(Date().timeIntervalSince1970 * 1000))
        for e in events {
            let cal = store.calendar(e.calendarId)
            out.append(e.isTask ? "BEGIN:VTODO" : "BEGIN:VEVENT")
            let title = e.title.replacingOccurrences(of: "\n", with: "\\n")
            if !title.isEmpty { out.append("SUMMARY:\(title)") }
            if !e.importId.isEmpty { out.append("UID:\(e.importId)") }
            out.append("X-FOSSIFY-CATEGORY-COLOR:\(cal.map { String($0.color.asSignedInt) } ?? "null")")
            if e.color != 0 && e.color != cal?.color {
                if let css = CssColors.findClosestCssColor(e.color) { out.append("COLOR:\(css)") }
                out.append("X-FOSSIFY-EVENT-COLOR:\(e.color.asSignedInt)")
            }
            out.append("CATEGORIES:\(cal?.title ?? "null")")
            out.append("LAST-MODIFIED:\(Formatter.getExportedTime(e.lastUpdated))")
            if !e.isTask { out.append("TRANSP:\(e.availability == AVAILABILITY_FREE ? "TRANSPARENT" : "OPAQUE")") }
            if !e.location.isEmpty { out.append("LOCATION:\(e.location)") }
            if e.isAllDay {
                let tz = TimeZone(identifier: e.timeZone) ?? TimeZone.current
                out.append("DTSTART;VALUE=DATE:\(Formatter.getDayCodeFromTS(e.startTS, tz: tz))")
                if !e.isTask { out.append("DTEND;VALUE=DATE:\(Formatter.getDayCodeFromTS(e.endTS + TWELVE_HOURS, tz: tz))") }
            } else {
                out.append("DTSTART:\(Formatter.getExportedTime(e.startTS * 1000))")
                if !e.isTask { out.append("DTEND:\(Formatter.getExportedTime(e.endTS * 1000))") }
            }
            if !e.isTask { out.append("X-FOSSIFY-MISSING-YEAR:\(e.hasMissingYear ? 1 : 0)") }
            out.append("DTSTAMP:\(exportTime)")
            if e.isTask {
                if e.isTaskCompleted { out.append("STATUS:COMPLETED") }
            } else {
                let cls = e.accessLevel == ACCESS_PRIVATE ? "PRIVATE" : e.accessLevel == ACCESS_CONFIDENTIAL ? "CONFIDENTIAL" : "PUBLIC"
                out.append("CLASS:\(cls)")
                let st = e.status == STATUS_CONFIRMED ? "CONFIRMED" : e.status == STATUS_CANCELED ? "CANCELLED" : "TENTATIVE"
                out.append("STATUS:\(st)")
            }
            let rrule = Parser.getRepeatCode(e)
            if !rrule.isEmpty { out.append("RRULE:\(rrule)") }
            out += descriptionLines(e.description.replacingOccurrences(of: "\n", with: "\\n"))
            for r in e.reminders {
                out.append("BEGIN:VALARM")
                out.append("DESCRIPTION:Reminder")
                out.append(r.type == REMINDER_NOTIFICATION ? "ACTION:DISPLAY" : "ACTION:EMAIL")
                let sign = r.minutes < -1 ? "" : "-"
                out.append("TRIGGER:\(sign)\(Parser.getDurationCode(abs(r.minutes)))")
                out.append("END:VALARM")
            }
            for ex in e.repetitionExceptions { out.append("EXDATE:\(ex)") }
            out.append(e.isTask ? "END:VTODO" : "END:VEVENT")
        }
        out.append("END:VCALENDAR")
        return out.joined(separator: "\r\n") + "\r\n"
    }

    private static func descriptionLines(_ d: String) -> [String] {
        guard !d.isEmpty else { return [] }
        var lines: [String] = []
        var rest = Substring(d)
        var first = true
        while !rest.isEmpty {
            let chunk = rest.prefix(75)
            lines.append(first ? "DESCRIPTION:\(chunk)" : " \(chunk)")
            rest = rest.dropFirst(chunk.count)
            first = false
        }
        return lines
    }

    /// shareEvents(): writes the events to a temporary .ics file.
    static func temporaryFile(_ events: [Event], store: CalendarStore, name: String = "events") -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name.replacingOccurrences(of: "/", with: "_") + ".ics")
        do {
            try export(events, store: store).data(using: .utf8)?.write(to: url, options: .atomic)
            return url
        } catch {
            return nil
        }
    }
}
