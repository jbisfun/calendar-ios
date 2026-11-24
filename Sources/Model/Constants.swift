import Foundation

// helpers/Constants.kt

let LOCAL_CALENDAR_ID: Int64 = 1
let FETCH_INTERVAL: Int64 = 3 * 2_592_000
let MAX_SEARCH_YEAR: Int64 = 2_051_218_800  // 2035, limit search results for events repeating indefinitely
let MIN_EVENTS_TRESHOLD = 30

enum CalendarViewType: Int, CaseIterable, Identifiable {
    case monthly = 1, yearly = 2, eventsList = 3, weekly = 4, daily = 5, last = 6, monthlyDaily = 7

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .daily: return "Daily view"
        case .weekly: return "Weekly view"
        case .monthly: return "Monthly view"
        case .monthlyDaily: return "Monthly and daily view"
        case .yearly: return "Yearly view"
        case .eventsList: return "Simple event list"
        case .last: return "Last view"
        }
    }

    /// Order of the "Change view" dialog.
    static let pickable: [CalendarViewType] = [.daily, .weekly, .monthly, .monthlyDaily, .yearly, .eventsList]
}

let REMINDER_OFF = -1

let OTHER_EVENT = 0
let BIRTHDAY_EVENT = 1
let ANNIVERSARY_EVENT = 2
let HOLIDAY_EVENT = 3

let DEFAULT_START_TIME_NEXT_FULL_HOUR = -1
let DEFAULT_START_TIME_CURRENT_TIME = -2

let TYPE_EVENT = 0
let TYPE_TASK = 1

let TWELVE_HOURS: Int64 = 43200
let HOUR: Int = 3600
let DAY = 86400
let WEEK = 604_800
let MONTH = 2_592_001  // exact value not taken into account, calendar math is used for adding months and years
let YEAR = 31_536_000

let EVENT_PERIOD_TODAY = -1
let EVENT_PERIOD_CUSTOM = -2

// repeat_rule for monthly and yearly repetition
let REPEAT_SAME_DAY = 1  // i.e. 25th every month, or 3rd june (if yearly repetition)
let REPEAT_ORDER_WEEKDAY_USE_LAST = 2  // i.e. every last sunday. 4th if a month has 4 sundays, 5th if 5
let REPEAT_LAST_DAY = 3  // i.e. every last day of the month
let REPEAT_ORDER_WEEKDAY = 4  // i.e. every 4th sunday, even if a month has 4 sundays only

let MONDAY_BIT = 1
let TUESDAY_BIT = 2
let WEDNESDAY_BIT = 4
let THURSDAY_BIT = 8
let FRIDAY_BIT = 16
let SATURDAY_BIT = 32
let SUNDAY_BIT = 64
let EVERY_DAY_BIT = 127

// special event and task flags
let FLAG_ALL_DAY = 1
let FLAG_IS_IN_PAST = 2
let FLAG_MISSING_YEAR = 4
let FLAG_TASK_COMPLETED = 8

let SOURCE_SIMPLE_CALENDAR = "simple-calendar"
let SOURCE_IMPORTED_ICS = "imported-ics"
let SOURCE_CONTACT_BIRTHDAY = "contact-birthday"
let SOURCE_CONTACT_ANNIVERSARY = "contact-anniversary"
let CALDAV = "Caldav"
let MANAGED_HOLIDAY_PREFIX = "managed-holiday:"

enum EditScope: Int {
    case selectedOccurrence = 0, futureOccurrences, allOccurrences
}

let REMINDER_NOTIFICATION = 0
let REMINDER_EMAIL = 1

// CalendarContract values, kept so exported/imported data and settings match Android.
let STATUS_TENTATIVE = 0
let STATUS_CONFIRMED = 1
let STATUS_CANCELED = 2

let AVAILABILITY_BUSY = 0
let AVAILABILITY_FREE = 1

let ACCESS_DEFAULT = 0
let ACCESS_CONFIDENTIAL = 1
let ACCESS_PRIVATE = 2
let ACCESS_PUBLIC = 3

let ATTENDEE_STATUS_NONE = 0
let ATTENDEE_STATUS_ACCEPTED = 1
let ATTENDEE_STATUS_DECLINED = 2
let ATTENDEE_STATUS_INVITED = 3
let ATTENDEE_STATUS_TENTATIVE = 4

// Default colors (colors.xml)
let DEFAULT_BIRTHDAYS_COLOR: UInt32 = 0xFF1565C0
let DEFAULT_HOLIDAYS_COLOR: UInt32 = 0xFF50A43B
let DEFAULT_ANNIVERSARIES_COLOR: UInt32 = 0xFFEC2E2A
let RED_TEXT_COLOR: UInt32 = 0xFFEC2E2A
let DEFAULT_PRIMARY_COLOR: UInt32 = 0xFF106D1F

func getNowSeconds() -> Int64 { Int64(Date().timeIntervalSince1970) }

func generateImportId() -> String {
    UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased() + String(Int64(Date().timeIntervalSince1970 * 1000))
}

func isXWeeklyRepetition(_ v: Int) -> Bool { v != 0 && v % WEEK == 0 }
func isXMonthlyRepetition(_ v: Int) -> Bool { v != 0 && v % MONTH == 0 }
func isXYearlyRepetition(_ v: Int) -> Bool { v != 0 && v % YEAR == 0 }

extension Int {
    func addBitIf(_ add: Bool, _ bit: Int) -> Int { add ? self | bit : self & ~bit }
}
