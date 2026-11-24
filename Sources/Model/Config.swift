import FossifyCommons
import Observation
import SwiftUI

/// Port of the calendar Config (SharedPreferences -> UserDefaults, same keys); theme, font size,
/// 24-hour format and first day of week live in FossifyCommons.
@Observable
final class Config {
    static let shared = Config()

    @ObservationIgnored private let d = UserDefaults.standard

    // Views
    var storedView: Int { didSet { d.set(storedView, forKey: "view") } }
    var showWeekNumbers: Bool { didSet { d.set(showWeekNumbers, forKey: "week_numbers") } }
    var startWeeklyAt: Int { didSet { d.set(startWeeklyAt, forKey: "start_weekly_at") } }
    var startWeekWithCurrentDay: Bool { didSet { d.set(startWeekWithCurrentDay, forKey: "start_week_with_current_day") } }
    var showMidnightSpanningEventsAtTop: Bool { didSet { d.set(showMidnightSpanningEventsAtTop, forKey: "show_midnight_spanning_events_at_top") } }
    var allowCustomizeDayCount: Bool { didSet { d.set(allowCustomizeDayCount, forKey: "allow_customise_day_count") } }
    var weeklyViewItemHeightMultiplier: Double { didSet { d.set(weeklyViewItemHeightMultiplier, forKey: "weekly_view_item_height_multiplier") } }
    var weeklyViewDays: Int { didSet { d.set(weeklyViewDays, forKey: "weekly_view_days") } }
    var showGrid: Bool { didSet { d.set(showGrid, forKey: "show_grid") } }
    var highlightWeekends: Bool { didSet { d.set(highlightWeekends, forKey: "highlight_weekends") } }
    var highlightWeekendsColor: UInt32 { didSet { d.set(highlightWeekendsColor.asSignedInt, forKey: "highlight_weekends_color") } }
    var dimPastEvents: Bool { didSet { d.set(dimPastEvents, forKey: "dim_past_events") } }
    var dimCompletedTasks: Bool { didSet { d.set(dimCompletedTasks, forKey: "dim_completed_tasks") } }

    // Event lists
    var displayPastEvents: Int { didSet { d.set(displayPastEvents, forKey: "display_past_events") } }
    var displayDescription: Bool { didSet { d.set(displayDescription, forKey: "display_description") } }
    var replaceDescription: Bool { didSet { d.set(replaceDescription, forKey: "replace_description") } }

    // Calendars ("event types")
    var displayCalendars: Set<String> { didSet { d.set(Array(displayCalendars), forKey: "display_event_types") } }
    var quickFilterCalendars: Set<String> { didSet { d.set(Array(quickFilterCalendars), forKey: "quick_filter_event_types") } }
    var wasFilteredOutWarningShown: Bool { didSet { d.set(wasFilteredOutWarningShown, forKey: "was_filtered_out_warning_shown") } }

    // CalDAV (system calendars through EventKit)
    var caldavSync: Bool { didSet { d.set(caldavSync, forKey: "caldav_sync") } }
    var caldavSyncedCalendarIds: String { didSet { d.set(caldavSyncedCalendarIds, forKey: "caldav_synced_calendar_ids") } }
    var pullToRefresh: Bool { didSet { d.set(pullToRefresh, forKey: "pull_to_refresh") } }
    var lastUsedCaldavCalendarId: String { didSet { d.set(lastUsedCaldavCalendarId, forKey: "last_used_caldav_calendar") } }
    var lastUsedLocalCalendarId: Int64 { didSet { d.set(lastUsedLocalCalendarId, forKey: "last_used_local_event_type_id") } }
    var lastUsedIgnoreCalendarsState: Bool { didSet { d.set(lastUsedIgnoreCalendarsState, forKey: "last_used_ignore_event_types_state") } }

    // New events
    var defaultStartTime: Int { didSet { d.set(defaultStartTime, forKey: "default_start_time") } }
    var defaultDuration: Int { didSet { d.set(defaultDuration, forKey: "default_duration") } }
    var defaultCalendarId: Int64 { didSet { d.set(defaultCalendarId, forKey: "default_event_type_id") } }
    var usePreviousEventReminders: Bool { didSet { d.set(usePreviousEventReminders, forKey: "use_previous_event_reminders") } }
    var defaultReminder1: Int { didSet { d.set(defaultReminder1, forKey: "default_reminder_1") } }
    var defaultReminder2: Int { didSet { d.set(defaultReminder2, forKey: "default_reminder_2") } }
    var defaultReminder3: Int { didSet { d.set(defaultReminder3, forKey: "default_reminder_3") } }
    var lastEventReminderMinutes1: Int { didSet { d.set(lastEventReminderMinutes1, forKey: "reminder_minutes") } }
    var lastEventReminderMinutes2: Int { didSet { d.set(lastEventReminderMinutes2, forKey: "reminder_minutes_2") } }
    var lastEventReminderMinutes3: Int { didSet { d.set(lastEventReminderMinutes3, forKey: "reminder_minutes_3") } }
    var allowChangingTimeZones: Bool { didSet { d.set(allowChangingTimeZones, forKey: "allow_changing_time_zones") } }
    var allowCreatingTasks: Bool { didSet { d.set(allowCreatingTasks, forKey: "allow_creating_tasks") } }
    var lastUsedEventSpan: Int { didSet { d.set(lastUsedEventSpan, forKey: "last_used_event_span") } }

    // Reminders
    /// Shared with other apps' reminder settings (commons ReminderConfig, same keys).
    var useSameSnooze: Bool {
        get { ReminderConfig.shared.useSameSnooze }
        set { ReminderConfig.shared.useSameSnooze = newValue }
    }
    var snoozeTime: Int {
        get { ReminderConfig.shared.snoozeTime }
        set { ReminderConfig.shared.snoozeTime = newValue }
    }

    // Birthdays, anniversaries, holidays
    var addBirthdaysAutomatically: Bool { didSet { d.set(addBirthdaysAutomatically, forKey: "add_birthdays_automatically") } }
    var addAnniversariesAutomatically: Bool { didSet { d.set(addAnniversariesAutomatically, forKey: "add_anniversaries_automatically") } }
    var birthdayReminders: [Int] { didSet { d.set(birthdayReminders.map(String.init).joined(separator: ","), forKey: "birthday_reminders") } }
    var anniversaryReminders: [Int] { didSet { d.set(anniversaryReminders.map(String.init).joined(separator: ","), forKey: "anniversary_reminders") } }
    var holidayPaths: Set<String> { didSet { d.set(Array(holidayPaths), forKey: "holiday_paths") } }
    var holidayReminders: [Int] { didSet { d.set(holidayReminders.map(String.init).joined(separator: ","), forKey: "holiday_reminders") } }
    var holidayDataVersion: String { didSet { d.set(holidayDataVersion, forKey: "holiday_data_version") } }

    // Export / backups
    var exportEvents: Bool { didSet { d.set(exportEvents, forKey: "export_events") } }
    var exportTasks: Bool { didSet { d.set(exportTasks, forKey: "export_tasks") } }
    var exportPastEntries: Bool { didSet { d.set(exportPastEntries, forKey: "export_past_events") } }
    var lastExportFilename: String { didSet { d.set(lastExportFilename, forKey: "last_export_path") } }
    var autoBackup: Bool { didSet { d.set(autoBackup, forKey: "auto_backup") } }
    var autoBackupFilename: String { didSet { d.set(autoBackupFilename, forKey: "auto_backup_filename") } }
    var autoBackupCalendars: Set<String> { didSet { d.set(Array(autoBackupCalendars), forKey: "auto_backup_event_types") } }
    var autoBackupEvents: Bool { didSet { d.set(autoBackupEvents, forKey: "auto_backup_events") } }
    var autoBackupTasks: Bool { didSet { d.set(autoBackupTasks, forKey: "auto_backup_tasks") } }
    var autoBackupPastEntries: Bool { didSet { d.set(autoBackupPastEntries, forKey: "auto_backup_past_entries") } }
    var lastAutoBackupTime: Double { didSet { d.set(lastAutoBackupTime, forKey: "last_auto_backup_time") } }

    private static func ints(_ s: String?) -> [Int] {
        let v = (s ?? "-1,-1,-1").split(separator: ",").compactMap { Int($0) }
        return v.count == 3 ? v : [-1, -1, -1]
    }

    private init() {
        storedView = d.object(forKey: "view") as? Int ?? CalendarViewType.monthly.rawValue
        showWeekNumbers = d.object(forKey: "week_numbers") as? Bool ?? false
        startWeeklyAt = d.object(forKey: "start_weekly_at") as? Int ?? 7
        startWeekWithCurrentDay = d.object(forKey: "start_week_with_current_day") as? Bool ?? false
        showMidnightSpanningEventsAtTop = d.object(forKey: "show_midnight_spanning_events_at_top") as? Bool ?? true
        allowCustomizeDayCount = d.object(forKey: "allow_customise_day_count") as? Bool ?? true
        weeklyViewItemHeightMultiplier = d.object(forKey: "weekly_view_item_height_multiplier") as? Double ?? 1
        weeklyViewDays = d.object(forKey: "weekly_view_days") as? Int ?? 7
        showGrid = d.object(forKey: "show_grid") as? Bool ?? false
        highlightWeekends = d.object(forKey: "highlight_weekends") as? Bool ?? false
        highlightWeekendsColor = UInt32(signed: d.object(forKey: "highlight_weekends_color") as? Int ?? RED_TEXT_COLOR.asSignedInt)
        dimPastEvents = d.object(forKey: "dim_past_events") as? Bool ?? true
        dimCompletedTasks = d.object(forKey: "dim_completed_tasks") as? Bool ?? true
        displayPastEvents = d.object(forKey: "display_past_events") as? Int ?? 1440
        displayDescription = d.object(forKey: "display_description") as? Bool ?? true
        replaceDescription = d.object(forKey: "replace_description") as? Bool ?? false
        displayCalendars = Set(d.stringArray(forKey: "display_event_types") ?? [String(LOCAL_CALENDAR_ID)])
        quickFilterCalendars = Set(d.stringArray(forKey: "quick_filter_event_types") ?? [])
        wasFilteredOutWarningShown = d.object(forKey: "was_filtered_out_warning_shown") as? Bool ?? false
        caldavSync = d.object(forKey: "caldav_sync") as? Bool ?? false
        caldavSyncedCalendarIds = d.string(forKey: "caldav_synced_calendar_ids") ?? ""
        pullToRefresh = d.object(forKey: "pull_to_refresh") as? Bool ?? false
        lastUsedCaldavCalendarId = d.string(forKey: "last_used_caldav_calendar") ?? ""
        lastUsedLocalCalendarId = d.object(forKey: "last_used_local_event_type_id") as? Int64 ?? LOCAL_CALENDAR_ID
        lastUsedIgnoreCalendarsState = d.object(forKey: "last_used_ignore_event_types_state") as? Bool ?? false
        defaultStartTime = d.object(forKey: "default_start_time") as? Int ?? DEFAULT_START_TIME_NEXT_FULL_HOUR
        defaultDuration = d.object(forKey: "default_duration") as? Int ?? 0
        defaultCalendarId = d.object(forKey: "default_event_type_id") as? Int64 ?? -1
        usePreviousEventReminders = d.object(forKey: "use_previous_event_reminders") as? Bool ?? true
        defaultReminder1 = d.object(forKey: "default_reminder_1") as? Int ?? 10
        defaultReminder2 = d.object(forKey: "default_reminder_2") as? Int ?? REMINDER_OFF
        defaultReminder3 = d.object(forKey: "default_reminder_3") as? Int ?? REMINDER_OFF
        lastEventReminderMinutes1 = d.object(forKey: "reminder_minutes") as? Int ?? 10
        lastEventReminderMinutes2 = d.object(forKey: "reminder_minutes_2") as? Int ?? REMINDER_OFF
        lastEventReminderMinutes3 = d.object(forKey: "reminder_minutes_3") as? Int ?? REMINDER_OFF
        allowChangingTimeZones = d.object(forKey: "allow_changing_time_zones") as? Bool ?? false
        allowCreatingTasks = d.object(forKey: "allow_creating_tasks") as? Bool ?? true
        lastUsedEventSpan = d.object(forKey: "last_used_event_span") as? Int ?? YEAR
        addBirthdaysAutomatically = d.object(forKey: "add_birthdays_automatically") as? Bool ?? false
        addAnniversariesAutomatically = d.object(forKey: "add_anniversaries_automatically") as? Bool ?? false
        birthdayReminders = Config.ints(d.string(forKey: "birthday_reminders"))
        anniversaryReminders = Config.ints(d.string(forKey: "anniversary_reminders"))
        holidayPaths = Set(d.stringArray(forKey: "holiday_paths") ?? [])
        holidayReminders = Config.ints(d.string(forKey: "holiday_reminders"))
        holidayDataVersion = d.string(forKey: "holiday_data_version") ?? ""
        exportEvents = d.object(forKey: "export_events") as? Bool ?? true
        exportTasks = d.object(forKey: "export_tasks") as? Bool ?? true
        exportPastEntries = d.object(forKey: "export_past_events") as? Bool ?? true
        lastExportFilename = d.string(forKey: "last_export_path") ?? ""
        autoBackup = d.object(forKey: "auto_backup") as? Bool ?? false
        autoBackupFilename = d.string(forKey: "auto_backup_filename") ?? "events_%Y_%M_%D_%h_%m_%s"
        autoBackupCalendars = Set(d.stringArray(forKey: "auto_backup_event_types") ?? [])
        autoBackupEvents = d.object(forKey: "auto_backup_events") as? Bool ?? true
        autoBackupTasks = d.object(forKey: "auto_backup_tasks") as? Bool ?? true
        autoBackupPastEntries = d.object(forKey: "auto_backup_past_entries") as? Bool ?? true
        lastAutoBackupTime = d.double(forKey: "last_auto_backup_time")
    }

    var view: CalendarViewType { CalendarViewType(rawValue: storedView) ?? .monthly }

    var syncedCalendarIds: [String] {
        caldavSyncedCalendarIds.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    func addDisplayCalendar(_ id: Int64) { displayCalendars.insert(String(id)) }
    func addQuickFilterCalendar(_ id: Int64) { quickFilterCalendars.insert(String(id)) }
}
