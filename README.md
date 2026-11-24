# calendar-ios

[Fossify Calendar](https://github.com/FossifyOrg/Calendar) re-created for iOS in SwiftUI, with system calendars through `EventKit`.

    idl build -c release     # -> build/release/FossifyCalendar.ipa (ad-hoc signed; re-sign to install)
    idl install "<device>" FossifyCalendar

Ported: daily, weekly (adjustable day count), monthly, monthly + daily, yearly and event list views with swiping, go to today/date, search and quick calendar filter; events and tasks with all-day, time zones, three reminders, every repetition rule (incl. Nth/last weekday, limits and per-occurrence edits), status, availability, colors, duplicate/share/delete; local calendars (manage, colors) and synced calendars ("CalDAV sync" = the accounts in iOS Settings, read and written live); task completion; holidays for every upstream country, contact birthdays and anniversaries; .ics import/export/share; reminder notifications with snooze and mark completed; automatic backups (Files › On My iPhone › Calendar › Backups); settings export/import; colors, font size and every applicable setting.

Differences forced by iOS: no home-screen widgets (they would need a WidgetKit extension plus an App Group); synced-calendar reminders come from the calendar's own alerts, and only the next 64 app reminders are scheduled (refreshed whenever the app opens); reminder sound, audio stream, vibration and looping follow the system notification settings; automatic backups run when the app is opened after 6 AM instead of from an alarm; no in-app language switch or launcher shortcuts.

GPL-3.0, like the original.
