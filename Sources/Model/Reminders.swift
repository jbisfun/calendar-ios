import FossifyCommons
import Foundation
import Observation
import UserNotifications

/// Reminder notifications (scheduleNextEventReminder / NotificationReceiver / SnoozeService).
/// Android sets an exact alarm per event and schedules the next one when it fires; iOS can't run
/// code at that point, so the upcoming reminders of local events are queued as local notifications
/// (iOS keeps at most 64). Events of synced calendars use their EventKit alarms instead.
@MainActor
@Observable
final class ReminderScheduler {
    static let shared = ReminderScheduler()

    static let prefix = "fossify-calendar-"
    static let snoozeAction = "SNOOZE"
    static let snoozePickAction = "SNOOZE_PICK"
    static let completeAction = "MARK_COMPLETED"

    /// A notification was tapped: open this event.
    var pendingOpen: EventRef?
    /// "Snooze" with "Use the same snooze" off: let the user pick the time (SnoozeReminderActivity).
    var pendingSnooze: UNNotificationContent?

    @ObservationIgnored weak var store: CalendarStore?
    @ObservationIgnored private var workItem: DispatchWorkItem?

    private let center = UNUserNotificationCenter.current()

    func install(_ store: CalendarStore) {
        self.store = store
        NotificationHub.register("calendar", .init(
            willPresent: { $0.request.identifier.hasPrefix(Self.prefix) ? [.banner, .list, .sound] : nil },
            didReceive: { [weak self] r in
                guard let self, r.notification.request.identifier.hasPrefix(Self.prefix) else { return false }
                self.handle(r)
                return true
            }))
        registerCategories()
    }

    private func registerCategories() {
        let sameSnooze = Config.shared.useSameSnooze
        let snooze = sameSnooze
            ? UNNotificationAction(identifier: Self.snoozeAction, title: "Snooze", options: [])
            : UNNotificationAction(identifier: Self.snoozePickAction, title: "Snooze", options: [.foreground])
        let complete = UNNotificationAction(identifier: Self.completeAction, title: "Mark completed", options: [])
        NotificationHub.setCategories("calendar", [
            UNNotificationCategory(identifier: "event", actions: [snooze], intentIdentifiers: []),
            UNNotificationCategory(identifier: "task", actions: [snooze, complete], intentIdentifiers: []),
        ])
    }

    func requestPermission(_ done: @escaping (Bool) -> Void = { _ in }) {
        center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
            DispatchQueue.main.async { done(granted) }
        }
    }

    /// scheduleAllEvents(), debounced.
    func reschedule(_ store: CalendarStore) {
        self.store = store
        workItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.rescheduleNow() }
        }
        workItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: item)
    }

    func rescheduleNow() {
        guard let store else { return }
        registerCategories()
        let now = getNowSeconds()
        var pending: [(Int64, Event)] = []
        let hasReminders = store.db.events.contains { !$0.reminders.isEmpty }
        if hasReminders {
            for e in store.getEvents(from: now - Int64(DAY), to: now + Int64(YEAR), applyTypeFilter: false) where !e.isSynced {
                if e.isTask && e.isTaskCompleted { continue }
                for r in e.reminders where r.type == REMINDER_NOTIFICATION {
                    let fire = r.minutes < -1 ? e.eventStartTS + Int64(-r.minutes * 60) : e.eventStartTS - Int64(r.minutes * 60)
                    if fire > now { pending.append((fire, e)) }
                }
            }
        }
        pending.sort { $0.0 < $1.0 }
        let requests = pending.prefix(60).map { fire, e in
            request(for: e, at: fire, id: "\(Self.prefix)\(e.id ?? 0)-\(e.startTS)-\(fire)")
        }
        center.getPendingNotificationRequests { existing in
            let ours = existing.map(\.identifier).filter { $0.hasPrefix(Self.prefix) && !$0.contains("snooze") }
            DispatchQueue.main.async {
                self.center.removePendingNotificationRequests(withIdentifiers: ours)
                requests.forEach { self.center.add($0) }
            }
        }
    }

    /// Context.notifyEvent(): title plus "Tomorrow 10:00 - 11:00 description".
    private func content(for event: Event) -> UNMutableNotificationContent {
        let c = UNMutableNotificationContent()
        c.title = event.title
        let startCode = Formatter.getDayCodeFromTS(event.startTS)
        let today = Formatter.getTodayCode()
        let tomorrow = Formatter.getDayCodeFromDateTime(JDate.now().plusDays(1))
        let date = startCode == today ? "" : startCode == tomorrow ? "Tomorrow" : "\(Formatter.getDateFromCode(startCode)),"
        let range = event.isAllDay ? "All-day" : "\(Formatter.getTimeFromTS(event.startTS)) - \(Formatter.getTimeFromTS(event.endTS))"
        let extra = Config.shared.replaceDescription ? event.location : event.description
        c.body = "\(date) \(range) \(extra)".trimmingCharacters(in: .whitespaces)
        c.sound = .default
        c.categoryIdentifier = event.isTask ? "task" : "event"
        c.userInfo = ["id": event.id ?? 0, "ts": event.startTS, "task": event.isTask]
        return c
    }

    private func request(for event: Event, at fire: Int64, id: String) -> UNNotificationRequest {
        let date = Date(timeIntervalSince1970: TimeInterval(fire))
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        return UNNotificationRequest(identifier: id, content: content(for: event),
                                     trigger: UNCalendarNotificationTrigger(dateMatching: comps, repeats: false))
    }

    /// rescheduleReminder(): show the same notification again in `minutes`.
    func snooze(_ content: UNNotificationContent, minutes: Int) {
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: TimeInterval(max(1, minutes) * 60), repeats: false)
        center.add(UNNotificationRequest(identifier: "\(Self.prefix)snooze-\(UUID().uuidString)", content: content, trigger: trigger))
    }

    private func ref(_ info: [AnyHashable: Any]) -> EventRef? {
        guard let id = (info["id"] as? NSNumber)?.int64Value, let ts = (info["ts"] as? NSNumber)?.int64Value else { return nil }
        return EventRef(id: id, ekID: nil, occurrenceTS: ts, isTask: (info["task"] as? Bool) ?? false)
    }

    // MARK: Notification responses (through NotificationHub)

    private func handle(_ response: UNNotificationResponse) {
        let content = response.notification.request.content
        switch response.actionIdentifier {
        case Self.snoozeAction: snooze(content, minutes: Config.shared.snoozeTime)
        case Self.snoozePickAction: pendingSnooze = content
        case Self.completeAction:
            if let r = ref(content.userInfo), let store, var task = store.event(for: r) {
                task.startTS = r.occurrenceTS
                store.updateTaskCompletion(task, completed: true)
            }
        case UNNotificationDefaultActionIdentifier: pendingOpen = ref(content.userInfo)
        default: break
        }
    }
}
