import FossifyCommons
import Foundation

/// Automatic backups (AutomaticBackupReceiver / backupEventsAndTasks). Android schedules an alarm
/// at 6 AM; iOS has no such alarm for this app, so a backup is written the first time the app
/// runs after the scheduled time has passed. Files go to Files › On My iPhone › Calendar › Backups.
@MainActor
enum BackupScheduler {
    static var folder: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("Backups", isDirectory: true)
    }

    /// getPreviousAutoBackupTime(): today's 6 AM if already passed, else yesterday's.
    static func previousBackupTime(now: Date = Date()) -> Date {
        let cal = Calendar.current
        let six = cal.date(bySettingHour: 6, minute: 0, second: 0, of: now)!
        return now >= six ? six : cal.date(byAdding: .day, value: -1, to: six)!
    }

    static func runIfDue(_ store: CalendarStore) {
        let config = Config.shared
        guard config.autoBackup else { return }
        guard config.lastAutoBackupTime < previousBackupTime().timeIntervalSince1970 else { return }
        backup(store)
    }

    static func backup(_ store: CalendarStore) {
        let config = Config.shared
        let events = store.eventsToExport(calendars: Set(config.autoBackupCalendars.compactMap { Int64($0) }),
                                          events: config.autoBackupEvents, tasks: config.autoBackupTasks,
                                          pastEntries: config.autoBackupPastEntries)
        config.lastAutoBackupTime = Date().timeIntervalSince1970
        if events.isEmpty {
            store.toast = "No entries for exporting have been found"
            return
        }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appendingPathComponent(filename(config.autoBackupFilename) + ".ics")
            try IcsExporter.export(events, store: store).data(using: .utf8)?.write(to: url, options: .atomic)
        } catch {
            store.toast = "Exporting failed"
        }
    }

    /// Expands Fossify's %Y %M %D %h %m %s filename pattern.
    static func filename(_ pattern: String, date: Date = Date()) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        func two(_ v: Int?) -> String { String(format: "%02d", v ?? 0) }
        return pattern
            .replacingOccurrences(of: "%Y", with: String(c.year ?? 0))
            .replacingOccurrences(of: "%M", with: two(c.month))
            .replacingOccurrences(of: "%D", with: two(c.day))
            .replacingOccurrences(of: "%h", with: two(c.hour))
            .replacingOccurrences(of: "%m", with: two(c.minute))
            .replacingOccurrences(of: "%s", with: two(c.second))
    }
}
