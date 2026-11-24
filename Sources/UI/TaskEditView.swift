import FossifyCommons
import SwiftUI

/// TaskActivity.
struct TaskEditView: View {
    @Environment(CalendarStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(Config.self) private var config
    @Environment(\.palette) private var palette
    @Environment(\.dismiss) private var dismiss

    let ref: EventRef?
    let newStartTS: Int64
    let duplicate: Bool

    @State private var loaded = false
    @State private var task = Event()
    @State private var isNew = true
    @State private var originalStartTS: Int64 = 0
    @State private var title = ""
    @State private var description = ""
    @State private var isAllDay = false
    @State private var date = Date()
    @State private var r1 = REMINDER_OFF
    @State private var r2 = REMINDER_OFF
    @State private var r3 = REMINDER_OFF
    @State private var repeatInterval = 0
    @State private var repeatRule = 0
    @State private var repeatLimit: Int64 = 0
    @State private var calendarId = LOCAL_CALENDAR_ID
    @State private var color: UInt32 = 0
    @State private var completed = false

    @State private var pickDate = false
    @State private var pickTime = false
    @State private var pickCalendar = false
    @State private var pickColor = false
    @State private var confirmDelete = false
    @State private var askScope = false
    @State private var askSave = false
    @State private var share: ShareItem?
    @State private var pendingSave: Event?

    private var calendar: CalendarEntity? { store.calendar(calendarId) }

    var body: some View {
        VStack(spacing: 0) {
            TopBar(title: isNew ? "New Task" : "Edit Task", onBack: back) {
                IconButton(icon: "checkmark") { save() }
                if !isNew {
                    Menu {
                        Button(role: .destructive) { confirmDelete = true } label: { Label("Delete", systemImage: "trash") }
                        Button { duplicateTask() } label: { Label("Duplicate task", systemImage: "doc.on.doc") }
                        Button { shareTask() } label: { Label("Share", systemImage: "square.and.arrow.up") }
                    } label: {
                        Image(systemName: "ellipsis").rotationEffect(.degrees(90)).font(.system(size: 18)).frame(width: 44, height: 48)
                    }
                }
            }
            ScrollView { form }
        }
        .background(palette.backgroundColor.ignoresSafeArea())
        .onAppear(perform: load)
        .sheet(isPresented: $pickDate) {
            DatePickerDialog(date: date) { d in date = JDate(d).withTime(JDate(date).hourOfDay, JDate(date).minuteOfHour).date }
        }
        .sheet(isPresented: $pickTime) {
            TimePickerDialog(date: date) { d in date = JDate(date).withTime(JDate(d).hourOfDay, JDate(d).minuteOfHour).date }
        }
        .sheet(isPresented: $pickCalendar) {
            SelectCalendarDialog(current: calendarId, showCalDAVCalendars: false) { calendarId = $0.id }
        }
        .sheet(isPresented: $pickColor) {
            ColorPickerDialog(color: color == 0 ? (calendar?.color ?? palette.primary) : color) { c in
                color = c == calendar?.color ? 0 : c
            }
        }
        .sheet(isPresented: $confirmDelete) {
            DeleteEventDialog(hasRepeatable: task.repeatInterval > 0, isTask: true) { scope in
                var e = task
                e.startTS = originalStartTS
                store.delete([e], scope: scope)
                dismiss()
            }
        }
        .sheet(isPresented: $askScope) {
            EditRepeatingEventDialog(isTask: true) { scope in storeRepeating(scope) }
        }
        .sheet(item: $share) { ShareSheet(items: [$0.url]) }
        .alert("Save changes before closing?", isPresented: $askSave) {
            Button("Discard", role: .destructive) { dismiss() }
            Button("Save") { save() }
        }
    }

    private var form: some View {
        VStack(spacing: 0) {
            VStack(spacing: 4) {
                FieldText(hint: "Title", text: $title)
                FieldText(hint: "Description", text: $description, multiline: true)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)
            Divider().overlay(palette.divider)

            IconSection(icon: "clock") {
                Toggle("All-day", isOn: $isAllDay).tint(palette.primaryColor).padding(.vertical, 6)
                HStack {
                    Button { pickDate = true } label: { Text(Formatter.getDate(JDate(date))) }
                    Spacer()
                    if !isAllDay {
                        Button { pickTime = true } label: { Text(Formatter.getTime(JDate(date))) }
                    }
                }
                .foregroundStyle(palette.textColor)
                .buttonStyle(.plain)
                .padding(.vertical, 10)
            }

            IconSection(icon: "bell") { ReminderRows(r1: $r1, r2: $r2, r3: $r3, allDay: isAllDay) }

            IconSection(icon: "repeat") {
                RepetitionRows(interval: $repeatInterval, rule: $repeatRule, limit: $repeatLimit, start: JDate(date))
            }

            IconSection(icon: "calendar") {
                Button { pickCalendar = true } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(calendar?.title ?? "").foregroundStyle(palette.textColor)
                            Text("Offline (never synced)").font(.system(size: 13)).foregroundStyle(palette.secondaryText)
                        }
                        Spacer()
                        ColorDot(color: calendar?.color ?? 0, size: 20)
                    }
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            IconSection(icon: "paintpalette") {
                Button { pickColor = true } label: {
                    HStack {
                        Text("Task color").foregroundStyle(palette.textColor)
                        Spacer()
                        ColorDot(color: color == 0 ? (calendar?.color ?? 0) : color)
                    }
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            if !isNew {
                Button { toggleCompletion() } label: {
                    Text(completed ? "Mark incomplete" : "Mark completed")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(completed ? palette.textColor : palette.onPrimary)
                        .padding(.horizontal, 24)
                        .padding(.vertical, 12)
                        .background {
                            if completed {
                                Capsule().stroke(palette.primaryColor, lineWidth: 2)
                            } else {
                                Capsule().fill(palette.primaryColor)
                            }
                        }
                }
                .buttonStyle(.plain)
                .padding(.top, 24)
            }
        }
        .padding(.bottom, 40)
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        if store.calendar(config.lastUsedLocalCalendarId) == nil { config.lastUsedLocalCalendarId = LOCAL_CALENDAR_ID }
        calendarId = config.lastUsedLocalCalendarId
        if let ref, let t = store.event(for: ref) {
            task = t
            isNew = duplicate
            originalStartTS = ref.occurrenceTS == 0 ? t.startTS : ref.occurrenceTS
            title = t.title
            description = t.description
            isAllDay = t.isAllDay
            date = Date(timeIntervalSince1970: TimeInterval(originalStartTS))
            r1 = t.reminder1Minutes
            r2 = t.reminder2Minutes
            r3 = t.reminder3Minutes
            repeatInterval = t.repeatInterval
            repeatRule = t.repeatRule
            repeatLimit = t.repeatLimit
            calendarId = t.calendarId
            color = t.color
            completed = t.id.map { store.isTaskCompleted(id: $0, startTS: originalStartTS) } ?? false
            if duplicate { task.id = nil }
        } else {
            isNew = true
            r1 = config.usePreviousEventReminders && config.lastEventReminderMinutes1 >= -1 ? config.lastEventReminderMinutes1 : config.defaultReminder1
            r2 = config.usePreviousEventReminders && config.lastEventReminderMinutes2 >= -1 ? config.lastEventReminderMinutes2 : config.defaultReminder2
            r3 = config.usePreviousEventReminders && config.lastEventReminderMinutes3 >= -1 ? config.lastEventReminderMinutes3 : config.defaultReminder3
            date = JDate(ts: newStartTS == 0 ? getNewEventTimestampFromCode(Formatter.getTodayCode()) : newStartTS).date
            task = Event()
            task.type = TYPE_TASK
            task.startTS = JDate(date).seconds
            task.endTS = task.startTS
            task.reminder1Minutes = r1
            task.reminder2Minutes = r2
            task.reminder3Minutes = r3
            task.calendarId = calendarId
        }
    }

    private var newStartTS_: Int64 {
        let j = JDate(date)
        return isAllDay ? j.withTimeAtStartOfDay.seconds : j.withTime(j.hourOfDay, j.minuteOfHour, 0).seconds
    }

    private var isChanged: Bool {
        let reminders = [r1, r2, r3].filter { $0 != REMINDER_OFF }.sorted()
        return title != task.title || description != task.description || reminders != task.reminders.map(\.minutes).sorted() ||
            repeatInterval != task.repeatInterval || repeatRule != task.repeatRule || repeatLimit != task.repeatLimit ||
            calendarId != task.calendarId || isAllDay != task.isAllDay || color != task.color ||
            newStartTS_ != (originalStartTS == 0 ? task.startTS : originalStartTS)
    }

    private func back() {
        if isChanged { askSave = true } else { dismiss() }
    }

    private func toggleCompletion() {
        var t = task
        t.startTS = originalStartTS
        store.updateTaskCompletion(t, completed: !completed)
        dismiss()
    }

    private func shareTask() {
        var t = task
        if let id = t.id, let stored = store.localEvent(id) { t = stored }
        t.flags = t.flags.addBitIf(completed, FLAG_TASK_COMPLETED)
        if let url = IcsExporter.temporaryFile([t], store: store, name: t.title.isEmpty ? "task" : t.title) { share = ShareItem(url: url) }
    }

    private func duplicateTask() {
        guard let ref else { return }
        dismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            router.push(.task(ref: ref, newStart: 0, duplicate: true))
        }
    }

    /// saveTask()
    private func save() {
        let newTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if newTitle.isEmpty {
            store.toast = "Title cannot be empty"
            return
        }
        let wasRepeatable = task.repeatInterval > 0
        var reminders = [r1, r2, r3].filter { $0 != REMINDER_OFF }.sorted()
        if !isAllDay { reminders.removeAll { $0 < -1 } }
        func m(_ i: Int) -> Int { i < reminders.count ? reminders[i] : REMINDER_OFF }
        if config.usePreviousEventReminders {
            config.lastEventReminderMinutes1 = m(0)
            config.lastEventReminderMinutes2 = m(1)
            config.lastEventReminderMinutes3 = m(2)
        }
        config.lastUsedLocalCalendarId = calendarId

        var t = isNew ? Event() : (task.id.flatMap { store.localEvent($0) } ?? task)
        t.startTS = newStartTS_
        t.endTS = t.startTS
        t.title = newTitle
        t.description = description
        if !wasRepeatable && t.flags & FLAG_TASK_COMPLETED != 0 {
            // migrate a completed task to the completed tasks table
            t.flags &= ~FLAG_TASK_COMPLETED
            var c = t
            c.startTS = originalStartTS
            store.updateTaskCompletion(c, completed: true)
        }
        t.importId = isNew ? generateImportId() : t.importId
        t.flags = t.flags.addBitIf(isAllDay, FLAG_ALL_DAY)
        t.lastUpdated = Int64(Date().timeIntervalSince1970 * 1000)
        t.calendarId = calendarId
        t.type = TYPE_TASK
        t.reminder1Minutes = m(0)
        t.reminder2Minutes = m(1)
        t.reminder3Minutes = m(2)
        t.repeatInterval = repeatInterval
        t.repeatLimit = repeatInterval == 0 ? 0 : repeatLimit
        t.repeatRule = repeatRule
        t.color = color
        if isNew { t.id = nil }
        if !t.reminders.isEmpty { ReminderScheduler.shared.requestPermission() }

        if isNew {
            store.insertEvent(t)
            dismiss()
        } else if repeatInterval > 0 && wasRepeatable {
            pendingSave = t
            askScope = true
        } else {
            store.updateEvent(t)
            dismiss()
        }
    }

    private func storeRepeating(_ scope: EditScope) {
        guard let t = pendingSave else { return }
        switch scope {
        case .selectedOccurrence: store.editSelectedOccurrence(t, occurrenceTS: originalStartTS)
        case .futureOccurrences: store.editFutureOccurrences(t, occurrenceTS: originalStartTS)
        case .allOccurrences: store.editAllOccurrences(t, originalStartTS: originalStartTS, originalEndTS: originalStartTS)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { dismiss() }
    }
}
