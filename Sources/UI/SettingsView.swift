import FossifyCommons
import SwiftUI
import UniformTypeIdentifiers

/// SettingsActivity.
struct SettingsView: View {
    @Environment(CalendarStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(Config.self) private var config
    @Environment(\.palette) private var palette

    @State private var dialog: SettingsDialog?
    @State private var pickWeekendColor = false
    @State private var exported: ShareItem?
    @State private var importer = false
    @State private var settingsImporter = false
    @State private var importURL: URL?
    @State private var confirmDeleteAll = false
    @State private var syncedPicker = false

    enum SettingsDialog: Int, Identifiable {
        case fontSize, quickFilter, startWeekOn, snoozeTime, defaultStartTime, otherStartTime, defaultDuration, defaultCalendar
        case reminder1, reminder2, reminder3, startWeeklyAt, displayPastEvents, manageBackups, export
        var id: Int { rawValue }
    }

    var body: some View {
        @Bindable var config = config
        @Bindable var timeFormat = DateTimeFormat.shared
        VStack(spacing: 0) {
            TopBar(title: "Settings")
            ScrollView {
                VStack(spacing: 0) {
                    Text("Color customization").sectionHeader(palette)
                    SettingsItem("Customize colors") { router.push(.customizeColors) }

                    Text("General").sectionHeader(palette)
                    SettingsItem("Font size", value: BaseConfig.shared.fontSize.title) { dialog = .fontSize }
                    SettingsItem("Manage calendars") { router.push(.manageCalendars) }
                    if store.calendars.count >= 2 {
                        SettingsItem("Manage quick filter calendars") { dialog = .quickFilter }
                    }
                    SettingsItem("Start week on", value: WeekDays.names[WeekDays.shared.firstDayOfWeek - 1]) { dialog = .startWeekOn }
                    SettingsToggle("Use 24-hour time format", isOn: $timeFormat.use24HourFormat)
                    SettingsToggle("Highlight weekends on some views", isOn: $config.highlightWeekends)
                    if config.highlightWeekends {
                        Button { pickWeekendColor = true } label: {
                            HStack {
                                Text("Color of highlighted weekends").font(.system(size: 16)).foregroundStyle(palette.textColor)
                                Spacer()
                                ColorDot(color: config.highlightWeekendsColor)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }

                    Text("Reminders").sectionHeader(palette)
                    SettingsItem("Customize notifications") { Launcher.open(URL(string: UIApplication.openNotificationSettingsURLString)) }
                    SettingsToggle("Use the same snooze", isOn: $config.useSameSnooze)
                    if config.useSameSnooze {
                        SettingsItem("Snooze time", value: DurationStrings.minutes(config.snoozeTime)) { dialog = .snoozeTime }
                    }

                    Text("CalDAV").sectionHeader(palette)
                    SettingsToggle("CalDAV sync", isOn: Binding(get: { config.caldavSync }, set: toggleCaldav))
                    if config.caldavSync {
                        SettingsToggle("Enable pull to refresh", isOn: $config.pullToRefresh)
                        SettingsItem("Manage synced calendars") { syncedPicker = true }
                    }

                    Text("New events").sectionHeader(palette)
                    SettingsItem("Default start time", value: defaultStartTimeText) { dialog = .defaultStartTime }
                    SettingsItem("Default duration", value: config.defaultDuration == 0 ? "0 minutes" : DurationStrings.formatted(minutes: config.defaultDuration, showBefore: false)) {
                        dialog = .defaultDuration
                    }
                    SettingsItem("Default calendar", value: defaultCalendarText) { dialog = .defaultCalendar }
                    SettingsToggle("Use the last event's reminders as the default for new events", isOn: $config.usePreviousEventReminders)
                    if !config.usePreviousEventReminders {
                        SettingsItem("Default reminder 1", value: DurationStrings.formatted(minutes: config.defaultReminder1)) { dialog = .reminder1 }
                        SettingsItem("Default reminder 2", value: DurationStrings.formatted(minutes: config.defaultReminder2)) { dialog = .reminder2 }
                        SettingsItem("Default reminder 3", value: DurationStrings.formatted(minutes: config.defaultReminder3)) { dialog = .reminder3 }
                    }

                    Text("Weekly view").sectionHeader(palette)
                    SettingsItem("Start day at", value: hoursString(config.startWeeklyAt)) { dialog = .startWeeklyAt }
                    SettingsToggle("Show events spanning across midnight at the top bar", isOn: $config.showMidnightSpanningEventsAtTop)
                    SettingsToggle("Allow customizing day count", isOn: $config.allowCustomizeDayCount)
                    SettingsToggle("Start week with the current day", isOn: $config.startWeekWithCurrentDay)

                    Text("Monthly view").sectionHeader(palette)
                    SettingsToggle("Show week numbers", isOn: $config.showWeekNumbers)
                    SettingsToggle("Show a grid", isOn: $config.showGrid)

                    Text("Event lists").sectionHeader(palette)
                    SettingsItem("Display events from the past",
                                 value: config.displayPastEvents == 0 ? "Never" : DurationStrings.formatted(minutes: config.displayPastEvents, showBefore: false)) {
                        dialog = .displayPastEvents
                    }
                    SettingsToggle("Display description or location", isOn: $config.displayDescription)
                    if config.displayDescription {
                        SettingsToggle("Replace event description with location", isOn: $config.replaceDescription)
                    }

                    Text("Events").sectionHeader(palette)
                    SettingsToggle("Dim past events", isOn: $config.dimPastEvents)
                    SettingsToggle("Allow changing event time zones", isOn: $config.allowChangingTimeZones)
                    SettingsItem("Delete all events and tasks") { confirmDeleteAll = true }

                    Text("Tasks").sectionHeader(palette)
                    SettingsToggle("Allow creating tasks", isOn: $config.allowCreatingTasks)
                    SettingsToggle("Dim completed tasks", isOn: $config.dimCompletedTasks)

                    Text("Backups").sectionHeader(palette)
                    SettingsToggle("Enable automatic backups", isOn: Binding(get: { config.autoBackup }, set: { on in
                        if on { dialog = .manageBackups } else { config.autoBackup = false }
                    }))
                    if config.autoBackup {
                        SettingsItem("Manage automatic backups") { dialog = .manageBackups }
                    }

                    Text("Migrating").sectionHeader(palette)
                    SettingsItem("Export events to an .ics file") { dialog = .export }
                    SettingsItem("Import events from an .ics file") { importer = true }
                    SettingsItem("Export settings") { exportSettings() }
                    SettingsItem("Import settings") { settingsImporter = true }
                }
                .padding(.bottom, 32)
            }
        }
        .background(palette.backgroundColor.ignoresSafeArea())
        .onDisappear(perform: sortDefaultReminders)
        .sheet(item: $dialog) { d in sheet(d) }
        .sheet(isPresented: $pickWeekendColor) {
            ColorPickerDialog(color: config.highlightWeekendsColor) { config.highlightWeekendsColor = $0 }
        }
        .sheet(isPresented: $syncedPicker) {
            ManageSyncedCalendarsDialog {
                if config.caldavSync { store.toast = "Syncing…" }
            }
        }
        .sheet(item: $exported) { ShareSheet(items: [$0.url]) }
        .fileImporter(isPresented: $importer, allowedContentTypes: [.ics, .calendarEvent, .data]) { result in
            if case .success(let url) = result {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { importURL = url }
            }
        }
        .fileImporter(isPresented: $settingsImporter, allowedContentTypes: [.plainText, .text, .data]) { result in
            if case .success(let url) = result { importSettings(url) }
        }
        .sheet(item: Binding(get: { importURL.map(IdentifiedURL.init) }, set: { importURL = $0?.url })) { ImportEventsDialog(url: $0.url) }
        .alert("Are you sure you want to delete all events and tasks? This will leave your calendars and other settings intact.",
               isPresented: $confirmDeleteAll) {
            Button("No", role: .cancel) {}
            Button("Yes", role: .destructive) { store.deleteAllEvents() }
        }
    }

    @ViewBuilder
    private func sheet(_ d: SettingsDialog) -> some View {
        switch d {
        case .fontSize:
            RadioDialog(title: nil, items: FontSize.allCases.map { ($0, $0.title) }, selected: BaseConfig.shared.fontSize) { BaseConfig.shared.fontSize = $0 }
        case .quickFilter:
            SelectCalendarsDialog(selected: config.quickFilterCalendars) { config.quickFilterCalendars = $0 }
        case .startWeekOn:
            RadioDialog(title: nil, items: [7, 1, 2, 3, 4, 5, 6].map { ($0, WeekDays.names[$0 - 1]) }, selected: WeekDays.shared.firstDayOfWeek) {
                WeekDays.shared.firstDayOfWeek = $0
                store.refresh()
            }
        case .snoozeTime:
            PickSecondsDialog(curSeconds: config.snoozeTime * 60, isSnoozePicker: true) { config.snoozeTime = max(1, $0 / 60) }
        case .defaultStartTime:
            RadioDialog(title: nil, items: [(DEFAULT_START_TIME_CURRENT_TIME, "Current time"), (DEFAULT_START_TIME_NEXT_FULL_HOUR, "Next full hour"),
                                            (0, "Other time")],
                        selected: config.defaultStartTime < 0 ? config.defaultStartTime : 0) { v in
                if v == 0 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { dialog = .otherStartTime }
                } else {
                    config.defaultStartTime = v
                }
            }
        case .otherStartTime:
            let cur = max(0, config.defaultStartTime)
            TimePickerDialog(date: JDate.now().withTime(cur / 60, cur % 60).date) { d in
                config.defaultStartTime = JDate(d).hourOfDay * 60 + JDate(d).minuteOfHour
            }
        case .defaultDuration:
            CustomIntervalPickerDialog(selectedSeconds: config.defaultDuration * 60) { config.defaultDuration = $0 / 60 }
        case .defaultCalendar:
            SelectCalendarDialog(current: config.defaultCalendarId, showCalDAVCalendars: true, addLastUsedOneAsFirstOption: true,
                                 showManageCalendars: false) { c in
                config.defaultCalendarId = c.id
                if c.id != -1 { config.lastUsedCaldavCalendarId = c.caldavCalendarId }
            }
        case .reminder1:
            ReminderPickerDialog(minutes: config.defaultReminder1) { config.defaultReminder1 = $0 }
        case .reminder2:
            ReminderPickerDialog(minutes: config.defaultReminder2) { config.defaultReminder2 = $0 }
        case .reminder3:
            ReminderPickerDialog(minutes: config.defaultReminder3) { config.defaultReminder3 = $0 }
        case .startWeeklyAt:
            RadioDialog(title: nil, items: (0...16).map { ($0, hoursString($0)) }, selected: config.startWeeklyAt) { config.startWeeklyAt = $0 }
        case .displayPastEvents:
            CustomIntervalPickerDialog(selectedSeconds: config.displayPastEvents * 60) { config.displayPastEvents = $0 / 60 }
        case .manageBackups:
            ManageAutomaticBackupsDialog { config.autoBackup = true }
        case .export:
            ExportEventsDialog { url in
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { exported = ShareItem(url: url) }
            }
        }
    }

    private var defaultStartTimeText: String {
        switch config.defaultStartTime {
        case DEFAULT_START_TIME_CURRENT_TIME: return "Current time"
        case DEFAULT_START_TIME_NEXT_FULL_HOUR: return "Next full hour"
        default: return Formatter.getTime(JDate.now().withTime(config.defaultStartTime / 60, config.defaultStartTime % 60))
        }
    }

    private var defaultCalendarText: String {
        if config.defaultCalendarId == -1 { return "Last used one" }
        return store.calendar(config.defaultCalendarId)?.title ?? "Last used one"
    }

    private func hoursString(_ h: Int) -> String {
        DateTimeFormat.shared.use24HourFormat ? String(format: "%02d:00", h) : Formatter.formatter("hh.mm a").string(from: JDate.now().withTime(h, 0).date)
    }

    /// onStop(): keep the default reminders sorted.
    private func sortDefaultReminders() {
        let r = [config.defaultReminder1, config.defaultReminder2, config.defaultReminder3].filter { $0 != REMINDER_OFF }
        let sorted = Array(Set(r)).sorted()
        config.defaultReminder1 = sorted.count > 0 ? sorted[0] : REMINDER_OFF
        config.defaultReminder2 = sorted.count > 1 ? sorted[1] : REMINDER_OFF
        config.defaultReminder3 = sorted.count > 2 ? sorted[2] : REMINDER_OFF
    }

    private func toggleCaldav(_ on: Bool) {
        if !on {
            store.setSyncedCalendars([])
            config.caldavSync = false
            return
        }
        store.requestCalendarAccess { granted in
            if granted {
                ReminderScheduler.shared.requestPermission()
                syncedPicker = true
            } else {
                store.toast = "Please grant the app access to your calendars"
            }
        }
    }

    // MARK: Export / import settings (key=value text, like Android)

    private static let settingsKeys = [
        "theme", "text_color", "background_color", "primary_color", "font_size", "use_24_hour_format", "first_day_of_week",
        "week_numbers", "start_weekly_at", "show_midnight_spanning_events_at_top", "allow_customise_day_count",
        "start_week_with_current_day", "view", "display_past_events", "display_description", "replace_description",
        "show_grid", "dim_past_events", "dim_completed_tasks", "use_previous_event_reminders", "default_reminder_1",
        "default_reminder_2", "default_reminder_3", "pull_to_refresh", "default_start_time", "default_duration",
        "allow_changing_time_zones", "highlight_weekends", "highlight_weekends_color", "allow_creating_tasks",
        "weekly_view_days", "use_same_snooze", "snooze_delay", "add_birthdays_automatically", "add_anniversaries_automatically",
    ]

    private func exportSettings() {
        let d = UserDefaults.standard
        let lines = Self.settingsKeys.compactMap { key -> String? in
            guard let v = d.object(forKey: key) else { return nil }
            return "\(key)=\(v)"
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("Calendar-settings_\(Formatter.formatter("yyyy_MM_dd_HH_mm_ss").string(from: Date())).txt")
        do {
            try lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
            exported = ShareItem(url: url)
        } catch {
            store.toast = "Exporting failed"
        }
    }

    private func importSettings(_ url: URL) {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            store.toast = "An unknown error occurred"
            return
        }
        let d = UserDefaults.standard
        var count = 0
        for line in text.split(separator: "\n") {
            let kv = line.split(separator: "=", maxSplits: 1).map(String.init)
            guard kv.count == 2, Self.settingsKeys.contains(kv[0]) else { continue }
            let (key, value) = (kv[0], kv[1])
            if value == "true" || value == "false" {
                d.set(value == "true", forKey: key)
            } else if let i = Int(value) {
                d.set(i, forKey: key)
            } else if let f = Double(value) {
                d.set(f, forKey: key)
            } else {
                d.set(value, forKey: key)
            }
            count += 1
        }
        store.toast = count > 0 ? "Settings imported successfully. Restart the app to apply them." : "No entries for importing have been found"
    }
}

extension AppInfo {
    public static let calendar = AppInfo(name: "Calendar", icon: "calendar", upstream: "Calendar", port: "calendar-ios", policy: "calendar", faq: [
        ("Can I sync my events via Google Calendar, or other service supporting CalDAV? Maybe even share calendars with other people?",
         "Yes, just toggle \"CalDAV sync\" in the app settings and select the calendars you want to sync. On iOS the accounts themselves are added in the system Settings › Calendar › Accounts."),
        ("The app shows no notifications, why is that?",
         "Check that notifications are allowed for the app in the system settings. iOS keeps only the next 64 scheduled reminders, opening the app schedules the following ones."),
        ("How can I modify or delete an existing calendar?",
         "You can do both of those in the app Settings - Manage calendars. Just click on the wanted one for changing the label and color, or use its menu for deleting."),
        ("How can I remove the holidays imported via the \"Manage holidays\" button?",
         "Holidays created that way are inserted in a new calendar called \"Holidays\". Unselect the countries in Manage holidays, or delete the Holidays calendar in Settings › Manage calendars."),
        ("Does the app support time zones?",
         "Yes, it does. By default all events are created in your current time zone. If you want to change an event's time zone, enable \"Allow changing event time zones\" in the app settings."),
    ])
}
