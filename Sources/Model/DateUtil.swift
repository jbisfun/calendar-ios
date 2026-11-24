import FossifyCommons
import Foundation

/// Joda-time style helpers over Foundation (DateTime in the device time zone).
/// Day of week follows ISO / Joda: Monday = 1 ... Sunday = 7.
struct JDate: Comparable, Hashable {
    var date: Date

    init(_ date: Date) { self.date = date }
    init(ts: Int64) { date = Date(timeIntervalSince1970: TimeInterval(ts)) }
    static func now() -> JDate { JDate(Date()) }

    static var cal: Calendar { Calendar.current }

    var seconds: Int64 { Int64(date.timeIntervalSince1970.rounded(.down)) }
    private var comps: DateComponents {
        JDate.cal.dateComponents([.year, .month, .day, .hour, .minute, .second, .weekday], from: date)
    }
    var year: Int { JDate.cal.component(.year, from: date) }
    var monthOfYear: Int { JDate.cal.component(.month, from: date) }
    var dayOfMonth: Int { JDate.cal.component(.day, from: date) }
    var hourOfDay: Int { JDate.cal.component(.hour, from: date) }
    var minuteOfHour: Int { JDate.cal.component(.minute, from: date) }
    var secondOfMinute: Int { JDate.cal.component(.second, from: date) }
    var minuteOfDay: Int { hourOfDay * 60 + minuteOfHour }
    /// Monday = 1 ... Sunday = 7.
    var dayOfWeek: Int { (JDate.cal.component(.weekday, from: date) + 5) % 7 + 1 }
    var maxDayOfMonth: Int { JDate.cal.range(of: .day, in: .month, for: date)?.count ?? 30 }
    /// ISO week of week-year (fourth day rule).
    var weekOfWeekyear: Int {
        var iso = Calendar(identifier: .iso8601)
        iso.timeZone = TimeZone.current
        return iso.component(.weekOfYear, from: date)
    }

    func plusDays(_ n: Int) -> JDate { JDate(JDate.cal.date(byAdding: .day, value: n, to: date) ?? date) }
    func plusWeeks(_ n: Int) -> JDate { plusDays(7 * n) }
    func plusMonths(_ n: Int) -> JDate { JDate(JDate.cal.date(byAdding: .month, value: n, to: date) ?? date) }
    func plusYears(_ n: Int) -> JDate { JDate(JDate.cal.date(byAdding: .year, value: n, to: date) ?? date) }
    func plusHours(_ n: Int) -> JDate { JDate(date.addingTimeInterval(TimeInterval(n * 3600))) }
    func plusMinutes(_ n: Int) -> JDate { JDate(date.addingTimeInterval(TimeInterval(n * 60))) }
    func plusSeconds(_ n: Int) -> JDate { JDate(date.addingTimeInterval(TimeInterval(n))) }
    func minusDays(_ n: Int) -> JDate { plusDays(-n) }

    func withDayOfMonth(_ d: Int) -> JDate {
        var c = comps
        c.day = min(max(d, 1), maxDayOfMonth)
        c.weekday = nil
        return JDate(JDate.cal.date(from: c) ?? date)
    }

    func withDate(_ y: Int, _ m: Int, _ d: Int) -> JDate {
        var c = comps
        c.year = y
        c.month = m
        c.day = 1
        c.weekday = nil
        let base = JDate(JDate.cal.date(from: c) ?? date)
        return base.withDayOfMonth(d)
    }

    /// Joda withDayOfWeek: the given day inside the same Monday-based week.
    func withDayOfWeek(_ iso: Int) -> JDate { plusDays(iso - dayOfWeek) }

    func withTime(_ h: Int, _ m: Int, _ s: Int = 0) -> JDate {
        var c = comps
        c.hour = h
        c.minute = m
        c.second = s
        c.weekday = nil
        return JDate(JDate.cal.date(from: c) ?? date)
    }

    func withHourOfDay(_ h: Int) -> JDate { withTime(h, minuteOfHour, secondOfMinute) }
    func withMinuteOfHour(_ m: Int) -> JDate { withTime(hourOfDay, m, secondOfMinute) }
    var withTimeAtStartOfDay: JDate { JDate(JDate.cal.startOfDay(for: date)) }

    static func < (a: JDate, b: JDate) -> Bool { a.date < b.date }

    /// Days between the local dates (ignores time).
    static func daysBetween(_ a: JDate, _ b: JDate) -> Int {
        cal.dateComponents([.day], from: a.withTimeAtStartOfDay.date, to: b.withTimeAtStartOfDay.date).day ?? 0
    }
}

/// helpers/Formatter.kt
enum Formatter {
    static let monthNames = ["January", "February", "March", "April", "May", "June", "July", "August",
                             "September", "October", "November", "December"]
    static let monthShortNames = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    /// commons in_months array, used by "every first Monday in March".
    static let inMonths = ["in January", "in February", "in March", "in April", "in May", "in June", "in July",
                           "in August", "in September", "in October", "in November", "in December"]

    private static var cache: [String: DateFormatter] = [:]

    static func formatter(_ pattern: String, utc: Bool = false) -> DateFormatter {
        let key = pattern + (utc ? "Z" : TimeZone.current.identifier)
        if let f = cache[key] { return f }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = utc ? TimeZone(identifier: "UTC") : TimeZone.current
        f.dateFormat = pattern
        cache[key] = f
        return f
    }

    static func getDayCodeFromTS(_ ts: Int64, tz: TimeZone? = nil) -> String {
        let f = DateFormatter()
        if let tz {
            f.locale = Locale(identifier: "en_US_POSIX")
            f.calendar = Calendar(identifier: .gregorian)
            f.timeZone = tz
            f.dateFormat = "yyyyMMdd"
            return f.string(from: Date(timeIntervalSince1970: TimeInterval(ts)))
        }
        return formatter("yyyyMMdd").string(from: Date(timeIntervalSince1970: TimeInterval(ts)))
    }

    static func getDayCodeFromDateTime(_ d: JDate) -> String { formatter("yyyyMMdd").string(from: d.date) }
    static func getTodayCode() -> String { getDayCodeFromTS(getNowSeconds()) }

    /// Local midnight of the day code.
    static func getLocalDateTimeFromCode(_ code: String) -> JDate {
        JDate(formatter("yyyyMMdd").date(from: code).map { Calendar.current.startOfDay(for: $0) } ?? Date())
    }

    static func getDayStartTS(_ code: String) -> Int64 { getLocalDateTimeFromCode(code).seconds }
    static func getDayEndTS(_ code: String) -> Int64 { getLocalDateTimeFromCode(code).plusDays(1).seconds - 60 }

    static func dayParts(_ code: String) -> (year: Int, month: Int, day: Int) {
        (Int(code.prefix(4)) ?? 2000, Int(code.dropFirst(4).prefix(2)) ?? 1, Int(code.dropFirst(6).prefix(2)) ?? 1)
    }

    static func getMonthName(_ id: Int) -> String { monthNames[max(0, min(11, id - 1))] }
    static func getShortMonthName(_ id: Int) -> String { monthShortNames[max(0, min(11, id - 1))] }

    /// "January 5" (+ year when not the current one).
    static func getDateFromCode(_ code: String, shortMonth: Bool = false) -> String {
        let p = dayParts(code)
        var month = getMonthName(p.month)
        if shortMonth { month = String(month.prefix(3)) }
        var date = "\(month) \(p.day)"
        if p.year != JDate.now().year { date += " \(p.year)" }
        return date
    }

    /// "January 5 (Mon)".
    static func getDayTitle(_ code: String, addDayOfWeek: Bool = true) -> String {
        let date = getDateFromCode(code)
        guard addDayOfWeek else { return date }
        let day = formatter("EEE").string(from: getLocalDateTimeFromCode(code).date)
        return "\(date) (\(day))"
    }

    /// "5 Monday".
    static func getDateDayTitle(_ code: String) -> String {
        formatter("d EEEE").string(from: getLocalDateTimeFromCode(code).date)
    }

    /// "January" or "January 2027".
    static func getLongMonthYear(_ code: String) -> String {
        let p = dayParts(code)
        var date = getMonthName(p.month)
        if p.year != JDate.now().year { date += " \(p.year)" }
        return date
    }

    static func getDate(_ d: JDate, addDayOfWeek: Bool = true) -> String {
        getDayTitle(getDayCodeFromDateTime(d), addDayOfWeek: addDayOfWeek)
    }

    static func getFullDate(_ d: JDate) -> String { "\(getMonthName(d.monthOfYear)) \(d.dayOfMonth) \(d.year)" }

    static var timePattern: String { DateTimeFormat.shared.use24HourFormat ? "HH:mm" : "hh:mm a" }
    static var hourPattern: String { DateTimeFormat.shared.use24HourFormat ? "HH" : "h a" }

    static func getTime(_ d: JDate) -> String { formatter(timePattern).string(from: d.date) }
    static func getTimeFromTS(_ ts: Int64) -> String { getTime(JDate(ts: ts)) }
    static func getHours(_ d: JDate) -> String { formatter(hourPattern).string(from: d.date) }

    /// "20250105T103000Z".
    static func getExportedTime(_ millis: Int64) -> String {
        formatter("yyyyMMdd'T'HHmmss'Z'", utc: true).string(from: Date(timeIntervalSince1970: TimeInterval(millis) / 1000))
    }

    static func getYearFromDayCode(_ code: String) -> String { String(code.prefix(4)) }

    /// getShiftedTS: the same wall-clock midnight moved to another zone.
    static func shiftedMidnight(_ ts: Int64, from: TimeZone, to: TimeZone) -> Int64 {
        var fromCal = Calendar(identifier: .gregorian)
        fromCal.timeZone = from
        var toCal = Calendar(identifier: .gregorian)
        toCal.timeZone = to
        let c = fromCal.dateComponents([.year, .month, .day], from: Date(timeIntervalSince1970: TimeInterval(ts)))
        return Int64(toCal.date(from: c)?.timeIntervalSince1970 ?? TimeInterval(ts))
    }
}

/// Context.getRepetitionText()
func getRepetitionText(_ seconds: Int) -> String {
    func plural(_ n: Int, _ unit: String) -> String { "\(n) \(unit)\(n == 1 ? "" : "s")" }
    switch seconds {
    case 0: return "No repetition"
    case DAY: return "Daily"
    case WEEK: return "Weekly"
    case MONTH: return "Monthly"
    case YEAR: return "Yearly"
    default:
        if seconds % YEAR == 0 { return plural(seconds / YEAR, "year") }
        if seconds % MONTH == 0 { return plural(seconds / MONTH, "month") }
        if seconds % WEEK == 0 { return plural(seconds / WEEK, "week") }
        return plural(seconds / DAY, "day")
    }
}

/// getShortDaysFromBitmask(): "Mon, Tue, Wed".
func getShortDaysFromBitmask(_ mask: Int) -> String { WeekDays.shared.selectedDaysString(mask) }

/// getFirstDayOfWeekDt()
func getFirstDayOfWeekDt(_ date: JDate) -> JDate {
    let config = Config.shared
    let today = date.withTimeAtStartOfDay
    var current = today
    if !config.startWeekWithCurrentDay {
        let first = WeekDays.shared.firstDayOfWeek
        let currentDow = current.dayOfWeek
        if currentDow != first {
            current = first < currentDow ? current.withDayOfWeek(first) : current.plusWeeks(-1).withDayOfWeek(first)
            if config.weeklyViewDays < 7 {
                let diff = abs(JDate.daysBetween(current, today))
                current = current.plusDays((diff / config.weeklyViewDays) * config.weeklyViewDays)
            }
        }
    }
    return current
}

/// getProperDayIndexInWeek()
func getProperDayIndexInWeek(_ date: JDate) -> Int {
    let first = WeekDays.shared.firstDayOfWeek
    let dow = date.dayOfWeek
    return dow >= first ? dow - first : dow + (7 - first)
}

/// isWeekendIndex(): index into a week starting at firstDayOfWeek.
func isWeekendIndex(_ index: Int) -> Bool {
    let shifted = (index + WeekDays.shared.firstDayOfWeek) % 7
    let dow = shifted == 0 ? 7 : shifted
    return dow == 6 || dow == 7
}

/// Short weekday names rotated to start at the first day of the week.
func weekDayLettersShort() -> [String] { WeekDays.shared.rotated().map { WeekDays.shortNames[$0] } }

/// getNewEventTimestampFromCode()
func getNewEventTimestampFromCode(_ dayCode: String, allowChangingDay: Bool = false) -> Int64 {
    let now = JDate.now()
    let defaultStart = Config.shared.defaultStartTime
    let dateTime = Formatter.getLocalDateTimeFromCode(dayCode).withTime(now.hourOfDay, 0)
    var newDateTime = dateTime.plusHours(1)
    if !allowChangingDay && dateTime.dayOfMonth != newDateTime.dayOfMonth {
        newDateTime = newDateTime.minusDays(1)
    }
    switch defaultStart {
    case DEFAULT_START_TIME_CURRENT_TIME: return dateTime.withTime(now.hourOfDay, now.minuteOfHour).seconds
    case DEFAULT_START_TIME_NEXT_FULL_HOUR: return newDateTime.seconds
    default:
        return Formatter.getLocalDateTimeFromCode(dayCode).withTime(defaultStart / 60, defaultStart % 60).seconds
    }
}

extension UInt32 {
    /// adjustAlpha()
    func adjustAlpha(_ factor: Double) -> UInt32 {
        let a = Double((self >> 24) & 0xFF) * factor
        return UInt32(Swift.max(0, Swift.min(255, a.rounded()))) << 24 | (self & 0xFFFFFF)
    }

    var asSignedInt: Int { Int(Int32(bitPattern: self)) }
    init(signed: Int) { self = UInt32(truncatingIfNeeded: signed) }
}

let LOWER_ALPHA = 0.25
let MEDIUM_ALPHA = 0.5
let HIGHER_ALPHA = 0.75
