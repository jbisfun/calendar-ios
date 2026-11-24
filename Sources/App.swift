import FossifyCommons
import Observation
import SwiftUI
import UIKit
import UserNotifications

enum Route: Hashable {
    /// EventActivity: edit `ref`, or a new event starting at `newStart`.
    case event(ref: EventRef?, newStart: Int64, hourDuration: Bool, duplicate: Bool)
    /// TaskActivity.
    case task(ref: EventRef?, newStart: Int64, duplicate: Bool)
    case settings
    case customizeColors
    case about
    case manageCalendars
}

@MainActor
@Observable
final class Router {
    var path: [Route] = []
    var importURL: URL?

    func push(_ r: Route) { path.append(r) }
    func pop() { if !path.isEmpty { path.removeLast() } }

    func open(_ ref: EventRef) {
        push(ref.isTask ? .task(ref: ref, newStart: 0, duplicate: false) : .event(ref: ref, newStart: 0, hourDuration: false, duplicate: false))
    }

    /// launchNewEventIntent()
    func newEvent(dayCode: String = Formatter.getTodayCode(), allowChangingDay: Bool = false) {
        push(.event(ref: nil, newStart: getNewEventTimestampFromCode(dayCode, allowChangingDay: allowChangingDay), hourDuration: false, duplicate: false))
    }

    /// launchNewTaskIntent()
    func newTask(dayCode: String = Formatter.getTodayCode(), allowChangingDay: Bool = false) {
        push(.task(ref: nil, newStart: getNewEventTimestampFromCode(dayCode, allowChangingDay: allowChangingDay), duplicate: false))
    }
}

/// The whole app as one view: the standalone app's window content, and what the launcher
/// presents. `importURL` is an .ics file handed over by the launcher.
public struct CalendarRoot: View {
    @State private var store = CalendarStore.shared
    @State private var router = Router()
    private let importURL: URL?

    public init(importURL: URL? = nil) {
        self.importURL = importURL
    }

    public var body: some View {
        RootView()
            .environment(store)
            .environment(router)
            .environment(Config.shared)
            .fossifyTheme()
            .onOpenURL { url in router.importURL = url }
            .onAppear { if let importURL { router.importURL = importURL } }
    }
}

struct RootView: View {
    @Environment(CalendarStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(\.scenePhase) private var phase
    @Environment(\.palette) private var palette
    @State private var scheduler = ReminderScheduler.shared
    @State private var started = false

    var body: some View {
        @Bindable var router = router
        @Bindable var store = store
        @Bindable var scheduler = scheduler
        NavigationStack(path: $router.path) {
            MainView()
                .navigationDestination(for: Route.self) { route in
                    Group {
                        switch route {
                        case let .event(ref, newStart, hourDuration, duplicate):
                            EventEditView(ref: ref, newStartTS: newStart, setHourDuration: hourDuration, duplicate: duplicate)
                        case let .task(ref, newStart, duplicate):
                            TaskEditView(ref: ref, newStartTS: newStart, duplicate: duplicate)
                        case .settings: SettingsView()
                        case .customizeColors: CustomizeColorsView()
                        case .about: AboutView(app: .calendar)
                        case .manageCalendars: ManageCalendarsView()
                        }
                    }
                    .toolbar(.hidden, for: .navigationBar)
                    .paletteBackground()
                }
                .toolbar(.hidden, for: .navigationBar)
        }
        .toast($store.toast)
        .sheet(item: Binding(get: { router.importURL.map(IdentifiedURL.init) }, set: { router.importURL = $0?.url })) { item in
            ImportEventsDialog(url: item.url)
        }
        .sheet(item: Binding(get: { scheduler.pendingSnooze.map(SnoozeItem.init) }, set: { scheduler.pendingSnooze = $0?.content })) { item in
            PickSecondsDialog(curSeconds: Config.shared.snoozeTime * 60, isSnoozePicker: true) { seconds in
                Config.shared.snoozeTime = max(1, seconds / 60)
                scheduler.snooze(item.content, minutes: max(1, seconds / 60))
            }
        }
        .onChange(of: scheduler.pendingOpen) { _, ref in
            guard let ref else { return }
            scheduler.pendingOpen = nil
            router.open(ref)
        }
        .onAppear(perform: start)
        .onChange(of: phase) { _, p in
            if p == .active {
                store.systemCalendarsChanged()
                BackupScheduler.runIfDue(store)
            }
        }
    }

    private func start() {
        guard !started else { return }
        started = true
        scheduler.install(store)
        let config = Config.shared
        if config.caldavSync && !store.hasCalendarAccess {
            config.caldavSync = false
        }
        if config.caldavSync { store.refreshSystemCalendars(showToast: false) }
        // addBirthdaysAnniversariesAtStart()
        if ContactEvents.hasPermission {
            if config.addBirthdaysAutomatically, ContactEvents.add(store, birthdays: true, reminders: config.birthdayReminders) > 0 {
                store.toast = "Birthdays added successfully"
            }
            if config.addAnniversariesAutomatically, ContactEvents.add(store, birthdays: false, reminders: config.anniversaryReminders) > 0 {
                store.toast = "Anniversaries added successfully"
            }
        }
        _ = HolidayHelper.refreshIfNeeded(store)
        BackupScheduler.runIfDue(store)
        ReminderScheduler.shared.reschedule(store)
    }
}

struct IdentifiedURL: Identifiable {
    let url: URL
    var id: URL { url }
}

struct SnoozeItem: Identifiable {
    let content: UNNotificationContent
    var id: String { content.title + "\(content.userInfo["ts"] ?? "")" }
}
