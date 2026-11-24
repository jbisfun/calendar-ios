import Contacts
import Foundation

/// models/HolidayMetadata.kt
struct HolidayInfo: Codable, Hashable {
    var code: String
    var country: String
    var `public`: String?
    var regional: String?
    var other: String?

    var paths: [String] { [`public`, regional, other].compactMap { $0 }.filter { !$0.isEmpty } }
}

struct HolidayMetadata: Codable {
    var version: String
    var countries: [HolidayInfo]
}

/// helpers/HolidayHelper.kt. The bundled holiday .ics files (assets/holidays) ship in the
/// Holidays.bundle resource.
@MainActor
enum HolidayHelper {
    static func url(_ path: String) -> URL {
        let root = Bundle.main.url(forResource: "Holidays", withExtension: "bundle") ?? Bundle.main.bundleURL
        return root.appendingPathComponent(path)
    }

    static func load() -> HolidayMetadata? {
        guard let data = try? Data(contentsOf: url("holidays/metadata.json")) else { return nil }
        return try? JSONDecoder().decode(HolidayMetadata.self, from: data)
    }

    static func refreshIfNeeded(_ store: CalendarStore) -> ImportResult {
        let config = Config.shared
        if config.holidayPaths.isEmpty { return .nothingNew }
        return updateSelection(store, paths: config.holidayPaths, reminders: config.holidayReminders)
    }

    static func updateSelection(_ store: CalendarStore, paths: Set<String>, reminders: [Int]) -> ImportResult {
        let config = Config.shared
        guard let metadata = load() else { return .fail }
        let available = Set(metadata.countries.flatMap(\.paths))
        let selected = paths.intersection(available)
        if selected == config.holidayPaths && reminders == config.holidayReminders && metadata.version == config.holidayDataVersion {
            return .nothingNew
        }
        var calendarId = store.localCalendarIdWithType(HOLIDAY_EVENT)
        var incoming: [Event] = []
        for path in selected.sorted() {
            guard let text = try? String(contentsOf: url(path), encoding: .utf8),
                  let events = IcsImporter(store: store).parseHolidays(text, calendarId: calendarId, reminders: reminders) else {
                return .fail
            }
            incoming += events
        }
        var seen = Set<String>()
        let holidays = incoming.filter { seen.insert(store.holidayKey($0)).inserted }
        config.holidayPaths = selected
        config.holidayReminders = reminders
        config.holidayDataVersion = ""
        if calendarId == -1 && !holidays.isEmpty {
            calendarId = store.createPredefinedCalendar("Holidays", color: DEFAULT_HOLIDAYS_COLOR, type: HOLIDAY_EVENT)
        }
        if calendarId != -1 { store.replaceHolidays(calendarId: calendarId, holidays: holidays) }
        config.holidayDataVersion = metadata.version
        return .ok
    }
}

/// MainActivity.addContactEvents(): contact birthdays and anniversaries as yearly all-day events.
@MainActor
enum ContactEvents {
    static var hasPermission: Bool { CNContactStore.authorizationStatus(for: .contacts) == .authorized }

    static func requestPermission(_ done: @escaping (Bool) -> Void) {
        CNContactStore().requestAccess(for: .contacts) { granted, _ in DispatchQueue.main.async { done(granted) } }
    }

    /// Returns the number of added events, -1 when all found ones already existed (like Android).
    static func add(_ store: CalendarStore, birthdays: Bool, reminders: [Int]) -> Int {
        let keys: [CNKeyDescriptor] = [CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
                                       CNContactBirthdayKey as CNKeyDescriptor, CNContactDatesKey as CNKeyDescriptor,
                                       CNContactIdentifierKey as CNKeyDescriptor]
        let source = birthdays ? SOURCE_CONTACT_BIRTHDAY : SOURCE_CONTACT_ANNIVERSARY
        let existing = store.contactEvents(source: source)
        var importIDs = Dictionary(existing.map { ($0.importId, $0.startTS) }, uniquingKeysWith: { a, _ in a })
        let calendarId = birthdays ? store.birthdaysCalendarId() : store.anniversariesCalendarId()
        var found = 0
        var toAdd: [Event] = []
        let fetch = CNContactFetchRequest(keysToFetch: keys)
        try? CNContactStore().enumerateContacts(with: fetch) { contact, _ in
            let name = CNContactFormatter.string(from: contact, style: .fullName) ?? ""
            var dates: [DateComponents] = []
            if birthdays {
                if let b = contact.birthday { dates.append(b) }
            } else {
                dates = contact.dates.filter { $0.label == CNLabelDateAnniversary }.map { $0.value as DateComponents }
            }
            for comps in dates {
                guard let month = comps.month, let day = comps.day else { continue }
                let missingYear = comps.year == nil || comps.year == 1604
                var c = DateComponents()
                c.year = missingYear ? 1970 : comps.year
                c.month = month
                c.day = day
                guard let date = Calendar.current.date(from: c) else { continue }
                let ts = Int64(date.timeIntervalSince1970)
                var e = Event()
                e.startTS = ts
                e.endTS = ts
                e.title = name
                e.reminder1Minutes = reminders[0]
                e.reminder2Minutes = reminders[1]
                e.reminder3Minutes = reminders[2]
                e.importId = contact.identifier
                e.timeZone = TimeZone.current.identifier
                e.flags = missingYear ? FLAG_ALL_DAY | FLAG_MISSING_YEAR : FLAG_ALL_DAY
                e.repeatInterval = YEAR
                e.repeatRule = REPEAT_SAME_DAY
                e.calendarId = calendarId
                e.source = source
                e.lastUpdated = Int64(Date().timeIntervalSince1970 * 1000)

                if let old = importIDs[contact.identifier], old != ts {
                    store.deleteContactEvent(source: source, importId: contact.identifier)
                    importIDs.removeValue(forKey: contact.identifier)
                }
                found += 1
                if importIDs[contact.identifier] == nil && !existing.contains(where: { $0.title == e.title && $0.startTS == e.startTS }) {
                    toAdd.append(e)
                    importIDs[contact.identifier] = ts
                }
            }
        }
        if !toAdd.isEmpty { store.insertEvents(toAdd) }
        return toAdd.isEmpty && found > 0 ? -1 : toAdd.count
    }
}
