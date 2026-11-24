import FossifyCommons
import SwiftUI
import UIKit

/// EventActivity.
struct EventEditView: View {
    @Environment(CalendarStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(Config.self) private var config
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    let ref: EventRef?
    let newStartTS: Int64
    let setHourDuration: Bool
    let duplicate: Bool

    @State private var loaded = false
    @State private var event = Event()
    @State private var isNew = true
    @State private var occurrenceTS: Int64 = 0
    @State private var originalStartTS: Int64 = 0
    @State private var originalEndTS: Int64 = 0
    @State private var originalTimeZone = TimeZone.current.identifier

    @State private var title = ""
    @State private var location = ""
    @State private var description = ""
    @State private var isAllDay = false
    @State private var start = Date()
    @State private var end = Date()
    @State private var timeZone = TimeZone.current.identifier
    @State private var r1 = REMINDER_OFF
    @State private var r2 = REMINDER_OFF
    @State private var r3 = REMINDER_OFF
    @State private var repeatInterval = 0
    @State private var repeatRule = 0
    @State private var repeatLimit: Int64 = 0
    @State private var availability = AVAILABILITY_BUSY
    @State private var status = STATUS_CONFIRMED
    @State private var calendarId = LOCAL_CALENDAR_ID
    @State private var color: UInt32 = 0
    @State private var convertedFromOriginalAllDay = false

    @State private var picker: PickerKind?
    @State private var pickCalendar = false
    @State private var pickTimeZone = false
    @State private var pickColor = false
    @State private var pickStatus = false
    @State private var pickAvailability = false
    @State private var confirmDelete = false
    @State private var askScope = false
    @State private var askSave = false
    @State private var share: ShareItem?
    @State private var pendingSave: Event?

    enum PickerKind: Int, Identifiable {
        case startDate, startTime, endDate, endTime
        var id: Int { rawValue }
    }

    private var calendar: CalendarEntity? { store.calendar(calendarId) }
    private var isSynced: Bool { calendar?.isSyncedCalendar ?? false }
    private var editTZ: TimeZone { config.allowChangingTimeZones && !isAllDay ? TimeZone(identifier: timeZone) ?? .current : .current }

    var body: some View {
        VStack(spacing: 0) {
            TopBar(title: isNew ? "New Event" : "Edit Event", onBack: back) {
                IconButton(icon: "checkmark") { save() }
                if !isNew {
                    Menu {
                        Button(role: .destructive) { confirmDelete = true } label: { Label("Delete", systemImage: "trash") }
                        Button { duplicateEvent() } label: { Label("Duplicate event", systemImage: "doc.on.doc") }
                        Button { shareEvent() } label: { Label("Share", systemImage: "square.and.arrow.up") }
                    } label: {
                        Image(systemName: "ellipsis").rotationEffect(.degrees(90)).font(.system(size: 18)).frame(width: 44, height: 48)
                    }
                }
            }
            ScrollView { form }
        }
        .background(palette.backgroundColor.ignoresSafeArea())
        .onAppear(perform: load)
        .sheet(item: $picker) { kind in
            switch kind {
            case .startDate:
                DatePickerDialog(date: start) { setStart(date: $0) }.environment(\.timeZone, editTZ)
            case .endDate:
                DatePickerDialog(date: end) { end = combine(date: $0, time: end) }.environment(\.timeZone, editTZ)
            case .startTime:
                TimePickerDialog(date: start) { setStart(time: $0) }.environment(\.timeZone, editTZ)
            case .endTime:
                TimePickerDialog(date: end) { end = combine(date: end, time: $0) }.environment(\.timeZone, editTZ)
            }
        }
        .sheet(isPresented: $pickCalendar) {
            SelectCalendarDialog(current: calendarId, showCalDAVCalendars: config.caldavSync) { c in
                calendarId = c.id
                if c.isSyncedCalendar {
                    config.lastUsedCaldavCalendarId = c.caldavCalendarId
                } else {
                    config.lastUsedLocalCalendarId = c.id
                    config.lastUsedCaldavCalendarId = ""
                }
            }
        }
        .sheet(isPresented: $pickTimeZone) {
            SelectTimeZoneDialog(current: timeZone) { setTimeZone($0) }
        }
        .sheet(isPresented: $pickColor) {
            ColorPickerDialog(color: color == 0 ? (calendar?.color ?? palette.primary) : color) { c in
                color = c == calendar?.color ? 0 : c
            }
        }
        .sheet(isPresented: $pickStatus) {
            RadioDialog(title: nil, items: [(STATUS_TENTATIVE, "Tentative"), (STATUS_CONFIRMED, "Confirmed"), (STATUS_CANCELED, "Canceled")],
                        selected: status) { status = $0 }
        }
        .sheet(isPresented: $pickAvailability) {
            RadioDialog(title: nil, items: [(AVAILABILITY_BUSY, "Busy"), (AVAILABILITY_FREE, "Free")], selected: availability) { availability = $0 }
        }
        .sheet(isPresented: $confirmDelete) {
            DeleteEventDialog(hasRepeatable: event.repeatInterval > 0) { scope in
                var e = event
                e.startTS = occurrenceTS
                store.delete([e], scope: scope)
                dismiss()
            }
        }
        .sheet(isPresented: $askScope) {
            EditRepeatingEventDialog { scope in storeRepeating(scope) }
        }
        .sheet(item: $share) { ShareSheet(items: [$0.url]) }
        .alert("Save changes before closing?", isPresented: $askSave) {
            Button("Discard", role: .destructive) { dismiss() }
            Button("Save") { save() }
        }
    }

    // MARK: Form

    @ViewBuilder
    private var form: some View {
        VStack(spacing: 0) {
            VStack(spacing: 4) {
                FieldText(hint: "Title", text: $title)
                HStack {
                    FieldText(hint: "Location", text: $location)
                    IconButton(icon: "map") { showOnMap() }
                }
                FieldText(hint: "Description", text: $description, multiline: true)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            Divider().overlay(palette.divider)

            IconSection(icon: "clock") {
                Toggle("All-day", isOn: Binding(get: { isAllDay }, set: toggleAllDay)).tint(palette.primaryColor).padding(.vertical, 6)
                dateTimeRow(date: start, isEnd: false)
                dateTimeRow(date: end, isEnd: true)
            }

            if config.allowChangingTimeZones && !isAllDay {
                IconSection(icon: "globe") {
                    Button { pickTimeZone = true } label: { plainRow(timeZone) }.buttonStyle(.plain)
                }
            }

            IconSection(icon: "bell") {
                ReminderRows(r1: $r1, r2: $r2, r3: $r3, allDay: isAllDay)
            }

            IconSection(icon: "repeat") {
                RepetitionRows(interval: $repeatInterval, rule: $repeatRule, limit: $repeatLimit, start: JDate(start))
            }

            if isSynced && !event.attendees.isEmpty {
                IconSection(icon: "person.2") {
                    ForEach(event.attendees, id: \.email) { a in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(a.publicName)
                                if a.relationship == 2 { Text("Organizer").font(.system(size: 13)).foregroundStyle(palette.secondaryText) }
                            }
                            Spacer()
                            if a.showStatusImage {
                                Image(systemName: a.status == ATTENDEE_STATUS_ACCEPTED ? "checkmark.circle.fill"
                                      : a.status == ATTENDEE_STATUS_DECLINED ? "xmark.circle.fill" : "questionmark.circle.fill")
                                    .foregroundStyle(palette.primaryColor)
                            }
                        }
                        .padding(.vertical, 8)
                    }
                }
            }

            IconSection(icon: "checkmark.seal") {
                Button { if !isSynced { pickStatus = true } } label: { plainRow(statusText) }.buttonStyle(.plain)
            }

            if isSynced {
                IconSection(icon: "briefcase") {
                    Button { pickAvailability = true } label: { plainRow(availability == AVAILABILITY_FREE ? "Free" : "Busy") }.buttonStyle(.plain)
                }
            }

            IconSection(icon: "calendar") {
                Button { pickCalendar = true } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(isSynced ? (calendar?.caldavDisplayName.isEmpty == false ? calendar!.caldavDisplayName : calendar?.title ?? "") : calendar?.title ?? "")
                                .foregroundStyle(palette.textColor)
                            Text(isSynced ? calendar?.caldavEmail ?? "" : "Offline (never synced)")
                                .font(.system(size: 13)).foregroundStyle(palette.secondaryText)
                        }
                        Spacer()
                        ColorDot(color: calendar?.color ?? 0, size: 20)
                    }
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            if !isSynced {
                IconSection(icon: "paintpalette") {
                    Button { pickColor = true } label: {
                        HStack {
                            Text("Event color").foregroundStyle(palette.textColor)
                            Spacer()
                            ColorDot(color: color == 0 ? (calendar?.color ?? 0) : color)
                        }
                        .padding(.vertical, 10)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(.bottom, 40)
    }

    private func plainRow(_ text: String) -> some View {
        Text(text).foregroundStyle(palette.textColor).frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 12).contentShape(Rectangle())
    }

    private func dateTimeRow(date: Date, isEnd: Bool) -> some View {
        let invalid = isEnd && start > end
        let color = invalid ? Color(argb: RED_TEXT_COLOR) : palette.textColor
        let j = JDate(wall: date, tz: editTZ)
        return HStack {
            Button { picker = isEnd ? .endDate : .startDate } label: { Text(Formatter.getDate(j)).foregroundStyle(color) }
            Spacer()
            if !isAllDay {
                Button { picker = isEnd ? .endTime : .startTime } label: { Text(Formatter.getTime(j)).foregroundStyle(color) }
            }
        }
        .buttonStyle(.plain)
        .padding(.vertical, 10)
    }

    private var statusText: String {
        status == STATUS_TENTATIVE ? "Tentative" : status == STATUS_CANCELED ? "Canceled" : "Confirmed"
    }

    // MARK: Loading

    private func load() {
        guard !loaded else { return }
        loaded = true
        if store.calendar(config.lastUsedLocalCalendarId) == nil { config.lastUsedLocalCalendarId = LOCAL_CALENDAR_ID }
        calendarId = defaultCalendarId()

        if let ref, let e = store.event(for: ref) {
            event = e
            isNew = duplicate
            occurrenceTS = ref.occurrenceTS
            let duration = e.endTS - e.startTS
            let realStart = ref.occurrenceTS == 0 ? e.startTS : ref.occurrenceTS
            originalStartTS = realStart
            originalEndTS = realStart + duration
            originalTimeZone = e.timeZone
            title = e.title
            location = e.location
            description = e.description
            isAllDay = e.isAllDay
            start = Date(timeIntervalSince1970: TimeInterval(realStart))
            end = Date(timeIntervalSince1970: TimeInterval(realStart + duration))
            timeZone = e.timeZoneString
            r1 = e.reminder1Minutes
            r2 = e.reminder2Minutes
            r3 = e.reminder3Minutes
            repeatInterval = e.repeatInterval
            repeatRule = e.repeatRule
            repeatLimit = e.repeatLimit
            availability = e.availability
            status = e.status
            calendarId = e.calendarId
            color = e.isSynced ? 0 : (store.localEvent(e.id ?? -1)?.color ?? 0)
            if duplicate {
                event.id = nil
                event.ekID = nil
            }
        } else {
            isNew = true
            r1 = config.usePreviousEventReminders && config.lastEventReminderMinutes1 >= -1 ? config.lastEventReminderMinutes1 : config.defaultReminder1
            r2 = config.usePreviousEventReminders && config.lastEventReminderMinutes2 >= -1 ? config.lastEventReminderMinutes2 : config.defaultReminder2
            r3 = config.usePreviousEventReminders && config.lastEventReminderMinutes3 >= -1 ? config.lastEventReminderMinutes3 : config.defaultReminder3
            let s = JDate(ts: newStartTS == 0 ? getNewEventTimestampFromCode(Formatter.getTodayCode()) : newStartTS)
            start = s.date
            let addMinutes = setHourDuration ? (s.hourOfDay == 23 ? 59 : 60) : config.defaultDuration
            end = s.plusMinutes(addMinutes).date
            event = Event()
            event.startTS = s.seconds
            event.endTS = JDate(end).seconds
            event.reminder1Minutes = r1
            event.reminder2Minutes = r2
            event.reminder3Minutes = r3
            event.calendarId = calendarId
        }
    }

    /// The calendar new events go to (default calendar, last used CalDAV one, or last used local one).
    private func defaultCalendarId() -> Int64 {
        if config.defaultCalendarId != -1, let c = store.calendar(config.defaultCalendarId), store.calendars.contains(c) { return c.id }
        let lastCaldav = config.lastUsedCaldavCalendarId
        if config.caldavSync && !lastCaldav.isEmpty && config.syncedCalendarIds.contains(lastCaldav),
           let c = store.calendarWithCalDAVId(lastCaldav) {
            return c.id
        }
        return config.lastUsedLocalCalendarId
    }

    // MARK: Editing helpers

    private func combine(date: Date, time: Date) -> Date {
        var cal = Calendar.current
        cal.timeZone = editTZ
        let d = cal.dateComponents([.year, .month, .day], from: date)
        let t = cal.dateComponents([.hour, .minute], from: time)
        var c = DateComponents()
        c.year = d.year
        c.month = d.month
        c.day = d.day
        c.hour = t.hour
        c.minute = t.minute
        return cal.date(from: c) ?? date
    }

    /// Moving the start keeps the duration (startDateSet / startTimeSet).
    private func setStart(date: Date) {
        let duration = end.timeIntervalSince(start)
        start = combine(date: date, time: start)
        end = start.addingTimeInterval(duration)
    }

    private func setStart(time: Date) {
        let duration = end.timeIntervalSince(start)
        start = combine(date: start, time: time)
        end = start.addingTimeInterval(duration)
    }

    private func setTimeZone(_ id: String) {
        // keep the wall-clock times, like Android shifting by the zone offset on save
        guard let new = TimeZone(identifier: id) else { return }
        let old = editTZ
        func shift(_ d: Date) -> Date { d.addingTimeInterval(TimeInterval(old.secondsFromGMT(for: d) - new.secondsFromGMT(for: d))) }
        start = shift(start)
        end = shift(end)
        timeZone = id
    }

    private func toggleAllDay(_ on: Bool) {
        // when converting from all-day to timed for the first time, use the default start time and duration
        if !on && event.isAllDay && !convertedFromOriginalAllDay {
            let s = JDate(ts: getNewEventTimestampFromCode(Formatter.getDayCodeFromTS(Int64(start.timeIntervalSince1970))))
            let e = s.plusMinutes(config.defaultDuration)
            start = JDate(start).withTime(s.hourOfDay, s.minuteOfHour).date
            end = JDate(end).withTime(e.hourOfDay, e.minuteOfHour).date
            convertedFromOriginalAllDay = true
        }
        isAllDay = on
        if end < start && JDate(end).dayOfMonth == JDate(start).dayOfMonth {
            end = JDate(end).withTime(JDate(start).hourOfDay, JDate(start).minuteOfHour).date
        }
    }

    private func startEndTimes() -> (Int64, Int64) {
        if isAllDay {
            return (JDate(start).withTimeAtStartOfDay.seconds, JDate(end).withTimeAtStartOfDay.seconds + TWELVE_HOURS)
        }
        return (Int64(start.timeIntervalSince1970), Int64(end.timeIntervalSince1970))
    }

    private var sortedReminders: [Reminder] {
        [Reminder(minutes: r1, type: REMINDER_NOTIFICATION), Reminder(minutes: r2, type: REMINDER_NOTIFICATION),
         Reminder(minutes: r3, type: REMINDER_NOTIFICATION)].filter { $0.minutes != REMINDER_OFF }.sorted { $0.minutes < $1.minutes }
    }

    private var isChanged: Bool {
        let (s, e) = startEndTimes()
        let timeChanged = originalStartTS == 0 ? (event.startTS != s || event.endTS != e) : (originalStartTS != s || originalEndTS != e)
        return title != event.title || location != event.location || description != event.description ||
            sortedReminders != event.reminders.sorted { $0.minutes < $1.minutes } ||
            repeatInterval != event.repeatInterval || repeatRule != event.repeatRule || repeatLimit != event.repeatLimit ||
            availability != event.availability || status != event.status || calendarId != event.calendarId ||
            isAllDay != event.isAllDay || (!event.isSynced && color != (store.localEvent(event.id ?? -1)?.color ?? 0)) || timeChanged
    }

    private func back() {
        if isChanged { askSave = true } else { dismiss() }
    }

    // MARK: Actions

    private func showOnMap() {
        let value = location.trimmingCharacters(in: .whitespaces)
        if value.isEmpty {
            store.toast = "Please fill in a location to be shown on a map"
            return
        }
        let pattern = #"^[-+]?([1-8]?\d(\.\d+)?|90(\.0+)?)([,;])\s*[-+]?(180(\.0+)?|((1[0-7]\d)|([1-9]?\d))(\.\d+)?)$"#
        if value.range(of: pattern, options: .regularExpression) != nil {
            let parts = value.split(whereSeparator: { $0 == "," || $0 == ";" }).map { $0.trimmingCharacters(in: .whitespaces) }
            Launcher.open(URL(string: "http://maps.apple.com/?ll=\(parts.first ?? ""),\(parts.last ?? "")"))
        } else {
            Launcher.open(URL(string: "http://maps.apple.com/?q=\(value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"))
        }
    }

    private func shareEvent() {
        var e = event
        if !e.isSynced, let id = e.id, let stored = store.localEvent(id) { e = stored }
        if let url = IcsExporter.temporaryFile([e], store: store, name: e.title.isEmpty ? "event" : e.title) { share = ShareItem(url: url) }
    }

    private func duplicateEvent() {
        guard let ref else { return }
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            router.push(.event(ref: ref, newStart: 0, hourDuration: false, duplicate: true))
        }
    }

    /// saveEvent()
    private func save() {
        let newTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if newTitle.isEmpty {
            store.toast = "Title cannot be empty"
            return
        }
        let (newStart, newEnd) = startEndTimes()
        if newStart > newEnd {
            store.toast = "The event cannot end earlier than it starts"
            return
        }
        guard let cal = calendar else {
            store.toast = "An unknown error occurred"
            return
        }
        if cal.isSyncedCalendar {
            guard store.canWrite(cal) else {
                store.toast = "You are not allowed to write in the selected calendar"
                return
            }
            config.lastUsedCaldavCalendarId = cal.caldavCalendarId
        } else {
            config.lastUsedLocalCalendarId = calendarId
            config.lastUsedCaldavCalendarId = ""
        }

        var reminders = sortedReminders
        if !isAllDay { reminders.removeAll { $0.minutes < -1 } }
        func m(_ i: Int) -> Int { i < reminders.count ? reminders[i].minutes : REMINDER_OFF }
        if config.usePreviousEventReminders {
            config.lastEventReminderMinutes1 = m(0)
            config.lastEventReminderMinutes2 = m(1)
            config.lastEventReminderMinutes3 = m(2)
        }

        let wasRepeatable = event.repeatInterval > 0
        let oldSynced = event.isSynced
        var e = isNew ? Event() : event
        if !isNew && !e.isSynced, let id = e.id, let stored = store.localEvent(id) {
            e = stored
        }
        e.startTS = newStart
        e.endTS = newEnd
        e.title = newTitle
        e.description = description
        e.location = location
        e.reminder1Minutes = m(0)
        e.reminder2Minutes = m(1)
        e.reminder3Minutes = m(2)
        e.reminder1Type = REMINDER_NOTIFICATION
        e.reminder2Type = REMINDER_NOTIFICATION
        e.reminder3Type = REMINDER_NOTIFICATION
        e.repeatInterval = repeatInterval
        e.importId = isNew ? generateImportId() : e.importId
        e.timeZone = isAllDay || timeZone.isEmpty ? TimeZone.current.identifier : timeZone
        e.flags = e.flags.addBitIf(isAllDay, FLAG_ALL_DAY)
        e.repeatLimit = repeatInterval == 0 ? 0 : repeatLimit
        e.repeatRule = repeatRule
        e.calendarId = calendarId
        e.lastUpdated = Int64(Date().timeIntervalSince1970 * 1000)
        e.source = cal.isSyncedCalendar ? "\(CALDAV)-\(cal.caldavCalendarId)" : SOURCE_SIMPLE_CALENDAR
        e.availability = availability
        e.status = status
        e.color = cal.isSyncedCalendar ? 0 : color
        if isNew {
            e.id = nil
            e.ekID = nil
        }

        if !e.reminders.isEmpty { ReminderScheduler.shared.requestPermission() }

        // recreate the event if it moved between the app's storage and a system calendar
        if !isNew && oldSynced != cal.isSyncedCalendar {
            var old = event
            old.startTS = occurrenceTS
            store.delete([old], scope: .allOccurrences)
            if wasRepeatable && repeatInterval > 0 && !oldSynced {
                store.applyOriginalStartEndTimes(&e, oldStartTS: originalStartTS, oldEndTS: originalEndTS)
            }
            e.id = nil
            e.ekID = nil
            store.insertEvent(e)
            dismiss()
            return
        }

        if isNew {
            store.insertEvent(e)
            dismiss()
        } else if repeatInterval > 0 && wasRepeatable {
            pendingSave = e
            askScope = true
        } else {
            if e.isSynced {
                _ = store.saveSystemEvent(e, span: .futureEvents, isNew: false, occurrenceTS: occurrenceTS)
                store.refresh()
            } else {
                store.updateEvent(e)
            }
            dismiss()
        }
    }

    private func storeRepeating(_ scope: EditScope) {
        guard let e = pendingSave else { return }
        switch scope {
        case .selectedOccurrence: store.editSelectedOccurrence(e, occurrenceTS: occurrenceTS)
        case .futureOccurrences: store.editFutureOccurrences(e, occurrenceTS: occurrenceTS)
        case .allOccurrences: store.editAllOccurrences(e, originalStartTS: originalStartTS, originalEndTS: originalEndTS)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { dismiss() }
    }
}

extension JDate {
    /// The wall-clock time of `wall` in `tz`, expressed in the device zone for formatting.
    init(wall: Date, tz: TimeZone) {
        let shift = TimeInterval(tz.secondsFromGMT(for: wall) - TimeZone.current.secondsFromGMT(for: wall))
        self.init(wall.addingTimeInterval(shift))
    }
}
