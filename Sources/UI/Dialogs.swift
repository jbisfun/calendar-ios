import EventKit
import FossifyCommons
import SwiftUI
import UniformTypeIdentifiers

// MARK: Calendars

/// SelectCalendarsDialog: checkboxes for every calendar.
struct SelectCalendarsDialog: View {
    @Environment(CalendarStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State var selected: Set<String>
    let onPick: (Set<String>) -> Void

    var body: some View {
        DialogFrame(title: nil) {
            ForEach(store.calendars) { c in
                HStack {
                    CheckRow(title: c.displayTitle, on: Binding(get: { selected.contains(String(c.id)) }, set: { on in
                        if on { selected.insert(String(c.id)) } else { selected.remove(String(c.id)) }
                    }))
                    ColorDot(color: c.color, size: 20)
                }
            }
            DialogButtons {
                onPick(selected)
                dismiss()
            }
        }
    }
}

/// SelectCalendarDialog: a radio list of calendars, optionally with "Last used one" and "Manage calendars".
struct SelectCalendarDialog: View {
    @Environment(CalendarStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    let current: Int64
    var showCalDAVCalendars = true
    var addLastUsedOneAsFirstOption = false
    var showOnlyWritable = true
    var showManageCalendars = true
    let onPick: (CalendarEntity) -> Void

    var body: some View {
        DialogFrame(title: nil) {
            if addLastUsedOneAsFirstOption {
                Button {
                    onPick(CalendarEntity(id: -1, title: "Last used one", color: 0))
                    dismiss()
                } label: { RadioRow(title: "Last used one", on: current == -1) }
                    .buttonStyle(.plain)
            }
            ForEach(calendars) { c in
                Button {
                    onPick(c)
                    dismiss()
                } label: {
                    HStack {
                        RadioRow(title: c.displayTitle, on: c.id == current)
                        ColorDot(color: c.color, size: 20)
                    }
                }
                .buttonStyle(.plain)
            }
            if showManageCalendars {
                Divider().overlay(palette.divider).padding(.vertical, 8)
                Button {
                    dismiss()
                    router.push(.manageCalendars)
                } label: {
                    Text("Manage calendars").foregroundStyle(palette.textColor).padding(.vertical, 12)
                        .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var calendars: [CalendarEntity] {
        store.calendars.filter { c in
            (showCalDAVCalendars || !c.isSyncedCalendar) && (!showOnlyWritable || store.canWrite(c))
        }
    }
}

/// EditCalendarDialog: title and color of a local calendar (only the color of a synced one).
struct EditCalendarDialog: View {
    @Environment(CalendarStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    let calendar: CalendarEntity?
    var onSaved: (CalendarEntity) -> Void = { _ in }
    @State private var title = ""
    @State private var color: UInt32 = 0
    @State private var pickColor = false
    @FocusState private var focused: Bool

    var body: some View {
        DialogFrame(title: calendar == nil ? "Add a new calendar" : "Edit calendar", scroll: false) {
            TextField("Title", text: $title)
                .focused($focused)
                .disabled(calendar?.isSyncedCalendar == true)
                .padding(.vertical, 8)
                .overlay(alignment: .bottom) { Rectangle().fill(palette.primaryColor).frame(height: 1) }
            Button { pickColor = true } label: {
                HStack {
                    Text("Color").foregroundStyle(palette.textColor)
                    Spacer()
                    ColorDot(color: color)
                }
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            DialogButtons { save() }
        }
        .onAppear {
            title = calendar?.title ?? ""
            color = calendar?.color ?? palette.primary
            if calendar == nil { focused = true }
        }
        .sheet(isPresented: $pickColor) {
            if let cal = calendar, cal.isSyncedCalendar {
                SelectEventColorDialog(colors: [], current: color, allowCustom: true) { color = $0 }
            } else {
                ColorPickerDialog(color: color) { color = $0 }
            }
        }
    }

    private func save() {
        let t = title.trimmingCharacters(in: .whitespaces)
        if t.isEmpty {
            store.toast = "Title cannot be empty"
            return
        }
        let existing = store.calendarIdWithTitle(t)
        if existing != -1 && existing != calendar?.id && calendar?.isSyncedCalendar != true {
            store.toast = "Calendar with this title already exists"
            return
        }
        var c = calendar ?? CalendarEntity(id: 0, title: t, color: color)
        if !c.isSyncedCalendar { c.title = t }
        c.color = color
        let id = store.insertOrUpdateCalendar(c, isNew: calendar == nil)
        c.id = id
        onSaved(c)
        dismiss()
    }
}

/// SelectEventColorDialog: preset colors (CalDAV colors on Android) plus the default.
struct SelectEventColorDialog: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    let colors: [UInt32]
    let current: UInt32
    var allowCustom = false
    let onPick: (UInt32) -> Void
    @State private var custom = false

    var body: some View {
        DialogFrame(title: nil) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 16) {
                ForEach(colors, id: \.self) { c in
                    ColorDot(color: c, size: 40)
                        .overlay { if c == current { Image(systemName: "checkmark").foregroundStyle(c.contrastColor) } }
                        .onTapGesture {
                            onPick(c)
                            dismiss()
                        }
                }
            }
            if allowCustom {
                Button("Custom") { custom = true }.padding(.top, 16)
            }
        }
        .sheet(isPresented: $custom) {
            ColorPickerDialog(color: current) {
                onPick($0)
                dismiss()
            }
        }
    }
}

/// ManageSyncedCalendarsDialog: choose which system calendars to show (CalDAV sync).
struct ManageSyncedCalendarsDialog: View {
    @Environment(CalendarStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    let onDone: () -> Void
    @State private var selected = Set<String>()

    var body: some View {
        DialogFrame(title: "Select calendars to sync") {
            let groups = store.systemCalendarsBySource
            if groups.isEmpty {
                Text("No synchronizable calendars have been found").foregroundStyle(palette.secondaryText)
            }
            ForEach(groups, id: \.0) { source, cals in
                Text(source).font(.system(size: 14, weight: .bold)).foregroundStyle(palette.primaryColor).padding(.top, 12)
                ForEach(cals, id: \.calendarIdentifier) { c in
                    HStack {
                        CheckRow(title: c.title, on: Binding(get: { selected.contains(c.calendarIdentifier) }, set: { on in
                            if on { selected.insert(c.calendarIdentifier) } else { selected.remove(c.calendarIdentifier) }
                        }))
                        ColorDot(color: c.argb, size: 20)
                    }
                }
            }
            DialogButtons {
                store.setSyncedCalendars(Array(selected))
                onDone()
                dismiss()
            }
        }
        .onAppear { selected = Set(Config.shared.syncedCalendarIds) }
    }
}

// MARK: Deleting / editing repeating events

/// DeleteEventDialog
struct DeleteEventDialog: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    let hasRepeatable: Bool
    var isTask = false
    var multiple = false
    let onConfirm: (EditScope) -> Void
    @State private var scope = EditScope.selectedOccurrence

    var body: some View {
        DialogFrame(title: nil, scroll: false) {
            Text("Are you sure you want to proceed with the deletion?").foregroundStyle(palette.textColor).padding(.bottom, 8)
            if hasRepeatable {
                Text(multiple ? "The selection contains repeating events" : isTask ? "The task is repeatable" : "The event is repeatable")
                    .foregroundStyle(palette.textColor).padding(.vertical, 8)
                ForEach([(EditScope.selectedOccurrence, "Delete the selected occurrence only"),
                         (.futureOccurrences, "Delete this and all future occurrences"),
                         (.allOccurrences, "Delete all occurrences")], id: \.0) { item in
                    Button { scope = item.0 } label: { RadioRow(title: item.1, on: scope == item.0) }.buttonStyle(.plain)
                }
            }
            HStack(spacing: 24) {
                Spacer()
                Button("No") { dismiss() }
                Button("Yes") {
                    onConfirm(hasRepeatable ? scope : .allOccurrences)
                    dismiss()
                }
            }
            .font(.system(size: 16, weight: .medium))
            .foregroundStyle(palette.primaryColor)
            .padding(.top, 16)
        }
        .presentationDetents([.medium])
    }
}

/// EditRepeatingEventDialog
struct EditRepeatingEventDialog: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    var isTask = false
    let onPick: (EditScope) -> Void

    var body: some View {
        DialogFrame(title: isTask ? "The task is repeatable" : "The event is repeatable", scroll: false) {
            ForEach([(EditScope.selectedOccurrence, "Update the selected occurrence only"),
                     (.futureOccurrences, "Update this and all future occurrences"),
                     (.allOccurrences, "Update all occurrences")], id: \.0) { item in
                Button {
                    onPick(item.0)
                    dismiss()
                } label: { RadioRow(title: item.1, on: false) }
                    .buttonStyle(.plain)
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: Repetition

/// showEventRepeatIntervalDialog()
struct RepeatIntervalDialog: View {
    @Environment(\.dismiss) private var dismiss
    let current: Int
    let onPick: (Int) -> Void
    @State private var custom = false

    var body: some View {
        Group {
            if custom {
                CustomEventRepeatIntervalDialog { onPick($0) }
            } else {
                DialogFrame(title: nil) {
                    ForEach(Array(Set([0, DAY, WEEK, MONTH, YEAR, current])).sorted(), id: \.self) { v in
                        Button {
                            onPick(v)
                            dismiss()
                        } label: { RadioRow(title: getRepetitionText(v), on: v == current) }
                            .buttonStyle(.plain)
                    }
                    Button { custom = true } label: { RadioRow(title: "Custom", on: false) }.buttonStyle(.plain)
                }
            }
        }
    }
}

/// CustomEventRepeatIntervalDialog: a value in days / weeks / months / years.
struct CustomEventRepeatIntervalDialog: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    let onPick: (Int) -> Void
    @State private var value = ""
    @State private var unit = DAY
    @FocusState private var focused: Bool

    var body: some View {
        DialogFrame(title: nil, scroll: false) {
            TextField("Value", text: $value)
                .keyboardType(.numberPad)
                .focused($focused)
                .padding(.vertical, 8)
                .overlay(alignment: .bottom) { Rectangle().fill(palette.primaryColor).frame(height: 1) }
            ForEach([(DAY, "days"), (WEEK, "weeks"), (MONTH, "months"), (YEAR, "years")], id: \.0) { u in
                Button { unit = u.0 } label: { RadioRow(title: u.1, on: unit == u.0) }.buttonStyle(.plain)
            }
            DialogButtons {
                onPick((Int(value) ?? 0) * unit)
                dismiss()
            }
        }
        .onAppear { focused = true }
    }
}

/// RepeatRuleWeeklyDialog: checkboxes for the week days.
struct RepeatRuleWeeklyDialog: View {
    @Environment(\.dismiss) private var dismiss
    @State var rule: Int
    let onPick: (Int) -> Void

    var body: some View {
        DialogFrame(title: nil) {
            ForEach(WeekDays.shared.rotated(), id: \.self) { i in
                CheckRow(title: WeekDays.names[i], on: Binding(get: { rule & (1 << i) != 0 }, set: { on in
                    rule = on ? rule | (1 << i) : rule & ~(1 << i)
                }))
            }
            DialogButtons {
                onPick(rule)
                dismiss()
            }
        }
    }
}

/// RepeatLimitTypePickerDialog: till a date, x times, or forever.
struct RepeatLimitTypePickerDialog: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    let limit: Int64
    let startTS: Int64
    let onPick: (Int64) -> Void
    @State private var type = 0
    @State private var date = Date()
    @State private var count = ""

    var body: some View {
        DialogFrame(title: nil) {
            Button { type = 0 } label: { RadioRow(title: "Repeat till a date", on: type == 0) }.buttonStyle(.plain)
            if type == 0 {
                DatePicker("", selection: $date, in: Date(timeIntervalSince1970: TimeInterval(startTS))..., displayedComponents: .date)
                    .labelsHidden()
                    .environment(\.calendar, weekCalendar)
            }
            Button { type = 1 } label: { RadioRow(title: "Stop repeating after x occurrences", on: type == 1) }.buttonStyle(.plain)
            if type == 1 {
                TextField("Value", text: $count)
                    .keyboardType(.numberPad)
                    .padding(.vertical, 8)
                    .overlay(alignment: .bottom) { Rectangle().fill(palette.primaryColor).frame(height: 1) }
            }
            Button { type = 2 } label: { RadioRow(title: "Repeat forever", on: type == 2) }.buttonStyle(.plain)
            DialogButtons {
                switch type {
                case 0:
                    var ts = JDate(date).withTime(23, 59, 59).seconds
                    if ts < startTS { ts = startTS }
                    onPick(ts)
                case 1: onPick(-max(1, Int64(count) ?? 1))
                default: onPick(0)
                }
                dismiss()
            }
        }
        .onAppear {
            if limit > 0 {
                type = 0
                date = Date(timeIntervalSince1970: TimeInterval(limit))
            } else if limit < 0 {
                type = 1
                count = String(-limit)
                date = Date(timeIntervalSince1970: TimeInterval(startTS))
            } else {
                type = 2
                date = Date(timeIntervalSince1970: TimeInterval(startTS))
            }
        }
    }
}

// MARK: Reminders

/// showPickSecondsDialogHelper(showDuringDayOption:) with the "During the day at hh:mm" option of all-day events.
struct ReminderPickerDialog: View {
    @Environment(\.dismiss) private var dismiss
    let minutes: Int
    var showDuringDayOption = false
    let onPick: (Int) -> Void
    @State private var mode = 0  // 0 list, 1 custom, 2 time

    var body: some View {
        let seconds = minutes == -1 ? -1 : minutes * 60
        Group {
            switch mode {
            case 1:
                CustomIntervalPickerDialog(selectedSeconds: max(0, seconds)) { pick($0) }
            case 2:
                TimePickerDialog(date: JDate.now().withTime(max(0, -seconds) / 3600, max(0, -seconds) % 3600 / 60).date) { d in
                    let j = JDate(d)
                    pick(j.hourOfDay * -3600 + j.minuteOfHour * -60)
                }
            default:
                DialogFrame(title: nil) {
                    ForEach(Array(Set([-1, 0, 60, 300, 600, 1800, 3600, seconds])).sorted(), id: \.self) { v in
                        Button { pick(v) } label: { RadioRow(title: DurationStrings.formatted(seconds: v), on: v == seconds) }
                            .buttonStyle(.plain)
                    }
                    Button { mode = 1 } label: { RadioRow(title: "Custom", on: false) }.buttonStyle(.plain)
                    if showDuringDayOption {
                        Button { mode = 2 } label: { RadioRow(title: "During the day at hh:mm", on: false) }.buttonStyle(.plain)
                    }
                }
            }
        }
    }

    /// Converts back to minutes like `if (it == -1 || it == 0) it else it / 60`.
    private func pick(_ s: Int) {
        onPick(s == -1 || s == 0 ? s : s / 60)
        dismiss()
    }
}

/// Three reminder rows (event_reminder_1..3 / set_reminders_1..3), each opening the picker.
struct ReminderRows: View {
    @Environment(\.palette) private var palette
    @Binding var r1: Int
    @Binding var r2: Int
    @Binding var r3: Int
    var allDay = false
    @State private var editing: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            row(1, r1, show: true)
            row(2, r2, show: r1 != REMINDER_OFF || r2 != REMINDER_OFF)
            row(3, r3, show: (r1 != REMINDER_OFF && r2 != REMINDER_OFF) || r3 != REMINDER_OFF)
        }
        .sheet(item: Binding(get: { editing.map(IntItem.init) }, set: { editing = $0?.value })) { item in
            let cur = item.value == 1 ? r1 : item.value == 2 ? r2 : r3
            ReminderPickerDialog(minutes: cur, showDuringDayOption: allDay) { m in
                ReminderScheduler.shared.requestPermission()
                switch item.value {
                case 1: r1 = m
                case 2: r2 = m
                default: r3 = m
                }
            }
        }
    }

    @ViewBuilder
    private func row(_ n: Int, _ value: Int, show: Bool) -> some View {
        if show {
            Button { editing = n } label: {
                Text(n > 1 && value == REMINDER_OFF ? "Add another reminder" : DurationStrings.formatted(minutes: value))
                    .foregroundStyle(palette.textColor.opacity(n > 1 && value == REMINDER_OFF ? 0.4 : 1))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

/// SetRemindersDialog: reminders of added birthdays / anniversaries / holidays.
struct SetRemindersDialog: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(Config.self) private var config
    let eventType: Int
    let initial: [Int]
    let onPick: ([Int]) -> Void
    @State private var r1 = REMINDER_OFF
    @State private var r2 = REMINDER_OFF
    @State private var r3 = REMINDER_OFF
    @State private var automatic = false

    var body: some View {
        DialogFrame(title: "Event reminders") {
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: "bell").padding(.top, 10)
                ReminderRows(r1: $r1, r2: $r2, r3: $r3, allDay: true)
            }
            if eventType != OTHER_EVENT {
                CheckRow(title: eventType == BIRTHDAY_EVENT ? "Add new birthdays automatically" : "Add new anniversaries automatically",
                         on: $automatic)
            }
            DialogButtons {
                let sorted = [r1, r2, r3].filter { $0 != REMINDER_OFF }.sorted()
                let reminders = (0..<3).map { $0 < sorted.count ? sorted[$0] : REMINDER_OFF }
                if eventType == BIRTHDAY_EVENT {
                    config.addBirthdaysAutomatically = automatic
                    config.birthdayReminders = reminders
                } else if eventType == ANNIVERSARY_EVENT {
                    config.addAnniversariesAutomatically = automatic
                    config.anniversaryReminders = reminders
                }
                onPick(reminders)
                dismiss()
            }
        }
        .onAppear {
            r1 = initial.count > 0 ? initial[0] : REMINDER_OFF
            r2 = initial.count > 1 ? initial[1] : REMINDER_OFF
            r3 = initial.count > 2 ? initial[2] : REMINDER_OFF
            automatic = eventType == BIRTHDAY_EVENT ? config.addBirthdaysAutomatically
                : eventType == ANNIVERSARY_EVENT ? config.addAnniversariesAutomatically : false
        }
    }
}

// MARK: Holidays

/// ManageHolidaysDialog: countries and their public / regional / other holiday sets.
struct ManageHolidaysDialog: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    let onPick: (Set<String>) -> Void
    @State private var selected = Config.shared.holidayPaths
    @State private var countries: [HolidayInfo] = []
    @State private var filter = ""

    var body: some View {
        DialogFrame(title: "Manage holidays") {
            TextField("Search", text: $filter)
                .padding(.vertical, 8)
                .overlay(alignment: .bottom) { Rectangle().fill(palette.divider).frame(height: 1) }
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(countries.filter { filter.isEmpty || $0.country.localizedCaseInsensitiveContains(filter) }, id: \.code) { info in
                    let on = info.paths.contains { selected.contains($0) }
                    CheckRow(title: info.country, on: Binding(get: { on }, set: { v in
                        if v { if let f = info.paths.first { selected.insert(f) } } else { selected.subtract(info.paths) }
                    }))
                    if on && info.paths.count > 1 {
                        ForEach([("Public holidays", info.public), ("Regional holidays", info.regional),
                                 ("Other holidays and observances", info.other)], id: \.0) { t in
                            if let path = t.1, !path.isEmpty {
                                CheckRow(title: t.0, on: Binding(get: { selected.contains(path) }, set: { v in
                                    if v { selected.insert(path) } else { selected.remove(path) }
                                }))
                                .padding(.leading, 32)
                            }
                        }
                    }
                }
            }
            DialogButtons {
                onPick(selected)
                dismiss()
            }
        }
        .presentationDetents([.large])
        .onAppear {
            let all = HolidayHelper.load()?.countries ?? []
            countries = all.sorted { a, b in
                let sa = a.paths.contains { selected.contains($0) }, sb = b.paths.contains { selected.contains($0) }
                return sa != sb ? sa : a.country.localizedCompare(b.country) == .orderedAscending
            }
        }
    }
}

// MARK: Import / export

/// ImportEventsDialog
struct ImportEventsDialog: View {
    @Environment(CalendarStore.self) private var store
    @Environment(Config.self) private var config
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    let url: URL
    @State private var calendarId: Int64 = LOCAL_CALENDAR_ID
    @State private var ignore = false
    @State private var pick = false

    var body: some View {
        DialogFrame(title: "Import events", scroll: false) {
            let cal = store.calendar(calendarId)
            Text("Default calendar").font(.system(size: 13)).foregroundStyle(palette.secondaryText)
            Button { pick = true } label: {
                HStack {
                    Text(cal?.displayTitle ?? "").foregroundStyle(palette.textColor)
                    Spacer()
                    ColorDot(color: cal?.color ?? 0)
                }
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            CheckRow(title: "Ignore calendars in the file, always use the default one", on: $ignore)
            DialogButtons { run() }
        }
        .presentationDetents([.medium])
        .onAppear {
            let last = config.lastUsedLocalCalendarId
            calendarId = store.calendar(last) != nil ? last : LOCAL_CALENDAR_ID
            ignore = config.lastUsedIgnoreCalendarsState
        }
        .sheet(isPresented: $pick) {
            SelectCalendarDialog(current: calendarId, showManageCalendars: false) { calendarId = $0.id }
        }
    }

    private func run() {
        config.lastUsedIgnoreCalendarsState = ignore
        config.lastUsedLocalCalendarId = calendarId
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url), let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            store.toast = "No items found."
            dismiss()
            return
        }
        store.toast = "Importing…"
        let result = IcsImporter(store: store).importEvents(text: text, defaultCalendarId: calendarId, overrideFileCalendars: ignore)
        switch result {
        case .nothingNew: store.toast = "No new items have been found"
        case .ok: store.toast = "Importing successful"
        case .partial: store.toast = "Importing some entries failed"
        case .fail: store.toast = "No items found."
        }
        store.refresh()
        dismiss()
    }
}

/// ExportEventsDialog: filename, events / tasks / past entries and calendars; the file is then shared.
struct ExportEventsDialog: View {
    @Environment(CalendarStore.self) private var store
    @Environment(Config.self) private var config
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    let onExported: (URL) -> Void
    @State private var filename = ""
    @State private var events = true
    @State private var tasks = true
    @State private var past = true
    @State private var calendars = Set<Int64>()

    var body: some View {
        DialogFrame(title: "Export events") {
            Text("Filename (without .ics)").font(.system(size: 13)).foregroundStyle(palette.secondaryText)
            TextField("", text: $filename)
                .padding(.vertical, 8)
                .overlay(alignment: .bottom) { Rectangle().fill(palette.primaryColor).frame(height: 1) }
            CheckRow(title: "Export events", on: $events)
            CheckRow(title: "Export tasks", on: $tasks)
            CheckRow(title: "Export past entries too", on: $past)
            Divider().overlay(palette.divider).padding(.vertical, 8)
            Text("Include calendars").font(.system(size: 14, weight: .bold)).foregroundStyle(palette.primaryColor)
            ForEach(store.calendars.filter { !$0.isSyncedCalendar }) { c in
                HStack {
                    CheckRow(title: c.displayTitle, on: Binding(get: { calendars.contains(c.id) }, set: { on in
                        if on { calendars.insert(c.id) } else { calendars.remove(c.id) }
                    }))
                    ColorDot(color: c.color, size: 20)
                }
            }
            DialogButtons { export() }
        }
        .onAppear {
            filename = "Events_\(Formatter.formatter("yyyy_MM_dd_HH_mm_ss").string(from: Date()))"
            events = config.exportEvents
            tasks = config.exportTasks
            past = config.exportPastEntries
            calendars = Set(store.calendars.filter { !$0.isSyncedCalendar }.map(\.id))
        }
    }

    private func export() {
        let name = filename.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { store.toast = "Empty name"; return }
        guard !name.contains("/") else { store.toast = "Invalid name"; return }
        config.exportEvents = events
        config.exportTasks = tasks
        config.exportPastEntries = past
        config.lastExportFilename = name
        let list = store.eventsToExport(calendars: calendars, events: events, tasks: tasks, pastEntries: past)
        guard (events || tasks), !list.isEmpty else {
            store.toast = "No entries for exporting have been found"
            return
        }
        if let url = IcsExporter.temporaryFile(list, store: store, name: name) {
            dismiss()
            onExported(url)
        } else {
            store.toast = "Exporting failed"
        }
    }
}

/// ManageAutomaticBackupsDialog
struct ManageAutomaticBackupsDialog: View {
    @Environment(CalendarStore.self) private var store
    @Environment(Config.self) private var config
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    let onSuccess: () -> Void
    @State private var filename = ""
    @State private var events = true
    @State private var tasks = true
    @State private var past = true
    @State private var calendars = Set<String>()
    @State private var pickCalendars = false

    var body: some View {
        DialogFrame(title: "Manage automatic backups") {
            Text("Folder").font(.system(size: 13)).foregroundStyle(palette.secondaryText)
            Text("On My iPhone › Calendar › Backups").padding(.vertical, 6)
            Text("Filename (without .ics)").font(.system(size: 13)).foregroundStyle(palette.secondaryText).padding(.top, 8)
            TextField("", text: $filename)
                .padding(.vertical, 8)
                .overlay(alignment: .bottom) { Rectangle().fill(palette.primaryColor).frame(height: 1) }
            CheckRow(title: "Export events", on: $events)
            CheckRow(title: "Export tasks", on: $tasks)
            CheckRow(title: "Export past entries too", on: $past)
            Divider().overlay(palette.divider).padding(.vertical, 8)
            Button { pickCalendars = true } label: {
                Text("Manage calendars").foregroundStyle(palette.textColor).padding(.vertical, 10)
                    .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            DialogButtons { save() }
        }
        .onAppear {
            filename = config.autoBackupFilename.isEmpty ? "Events_%Y%M%D_%h%m%s" : config.autoBackupFilename
            events = config.autoBackupEvents
            tasks = config.autoBackupTasks
            past = config.autoBackupPastEntries
            calendars = config.autoBackupCalendars.isEmpty ? config.displayCalendars : config.autoBackupCalendars
        }
        .sheet(isPresented: $pickCalendars) {
            SelectCalendarsDialog(selected: calendars) { calendars = $0 }
        }
    }

    private func save() {
        let name = filename.trimmingCharacters(in: .whitespaces)
        if name.isEmpty { store.toast = "Empty name"; return }
        if name.contains("/") { store.toast = "Invalid name"; return }
        if (!events && !tasks) || calendars.isEmpty {
            store.toast = "No entries for exporting have been found"
            return
        }
        config.autoBackupFilename = name
        config.autoBackupEvents = events
        config.autoBackupTasks = tasks
        config.autoBackupPastEntries = past
        config.autoBackupCalendars = calendars
        onSuccess()
        dismiss()
    }
}

/// SelectTimeZoneActivity, as a searchable sheet.
struct SelectTimeZoneDialog: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    let current: String
    let onPick: (String) -> Void
    @State private var query = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                IconButton(icon: "arrow.left") { dismiss() }
                TextField("Enter a country or time zone", text: $query).autocorrectionDisabled()
            }
            .padding(.horizontal, 4)
            .frame(height: 56)
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(zones, id: \.self) { id in
                        Button {
                            onPick(id)
                            dismiss()
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(id.replacingOccurrences(of: "_", with: " ")).foregroundStyle(id == current ? palette.primaryColor : palette.textColor)
                                    Text(offset(id)).font(.system(size: 13)).foregroundStyle(palette.secondaryText)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .background(palette.backgroundColor.ignoresSafeArea())
    }

    private var zones: [String] {
        let all = TimeZone.knownTimeZoneIdentifiers
        guard !query.isEmpty else { return all }
        return all.filter { $0.replacingOccurrences(of: "_", with: " ").localizedCaseInsensitiveContains(query) }
    }

    private func offset(_ id: String) -> String {
        let s = TimeZone(identifier: id)?.secondsFromGMT() ?? 0
        return String(format: "GMT%@%02d:%02d", s >= 0 ? "+" : "-", abs(s) / 3600, abs(s) % 3600 / 60)
    }
}

extension UTType {
    static let ics = UTType(filenameExtension: "ics") ?? .calendarEvent
}
