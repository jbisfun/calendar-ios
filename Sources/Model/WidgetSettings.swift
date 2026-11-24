import FossifyCommons
import Foundation

// Widget settings. Upstream keeps the colors in the shared config (widgetBgColor /
// widgetTextColor, the last configured values) and the event list's period + header per widget
// in the `widgets` table. Here every placed widget keeps its own values under
// HomeWidgetContext.key(...); the last saved ones seed the next configure screen.

let WIDGET_DAY_SECONDS = 86_400
let WIDGET_WEEK_SECONDS = 604_800
let WIDGET_MONTH_SECONDS = 2_592_000
let WIDGET_YEAR_SECONDS = 31_536_000

/// default_widget_bg_color (#AA000000).
let DEFAULT_WIDGET_BG_COLOR: UInt32 = 0xAA00_0000

enum WidgetDefaults {
    private static var d: UserDefaults { .standard }

    /// config.widgetBgColor (last used, with alpha).
    static var bgColor: UInt32 {
        get { UInt32(signed: d.object(forKey: "calendar_widget_bg_color") as? Int ?? DEFAULT_WIDGET_BG_COLOR.asSignedInt) }
        set { d.set(newValue.asSignedInt, forKey: "calendar_widget_bg_color") }
    }

    /// config.widgetTextColor (last used); default_widget_text_color is the primary color.
    static var textColor: UInt32 {
        get { UInt32(signed: d.object(forKey: "calendar_widget_text_color") as? Int ?? BaseConfig.shared.customPrimaryColor.asSignedInt) }
        set { d.set(newValue.asSignedInt, forKey: "calendar_widget_text_color") }
    }

    /// config.lastUsedShowListWidgetHeader
    static var showListHeader: Bool {
        get { d.object(forKey: "calendar_last_used_show_list_widget_header") as? Bool ?? true }
        set { d.set(newValue, forKey: "calendar_last_used_show_list_widget_header") }
    }
}

/// Context.getWidgetFontSize(): day_text_size (17sp) shifted by the app's font size setting.
func widgetFontSize() -> CGFloat {
    switch BaseConfig.shared.fontSize {
    case .small: return 14
    case .medium: return 17
    case .large: return 20
    case .extraLarge: return 23
    }
}

/// WidgetListConfigureActivity.getFormattedSeconds()
func widgetPeriodText(_ seconds: Int) -> String {
    if seconds == EVENT_PERIOD_TODAY { return "Today only" }
    if seconds == 0 || seconds == WIDGET_YEAR_SECONDS { return "Within the next 1 year" }
    func plural(_ n: Int, _ unit: String) -> String { "Within the next \(n) \(unit)\(n == 1 ? "" : "s")" }
    if seconds % WIDGET_MONTH_SECONDS == 0 { return plural(seconds / WIDGET_MONTH_SECONDS, "month") }
    if seconds % WIDGET_WEEK_SECONDS == 0 { return plural(seconds / WIDGET_WEEK_SECONDS, "week") }
    return plural(seconds / WIDGET_DAY_SECONDS, "day")
}

/// EventListWidgetAdapter.onDataSetChanged(): the events a list widget shows for its period.
@MainActor
func widgetListEvents(_ store: CalendarStore, period: Int) -> [Event] {
    let now = JDate.now()
    let fromTS = now.seconds - Int64(Config.shared.displayPastEvents * 60)
    let toTS: Int64
    switch period {
    case 0: toTS = now.plusYears(1).seconds
    case EVENT_PERIOD_TODAY: toTS = now.withTimeAtStartOfDay.withTime(23, 59, 59).seconds
    default: toTS = now.seconds + Int64(period)
    }
    return store.getEvents(from: fromTS, to: toTS, applyTypeFilter: true)
}
