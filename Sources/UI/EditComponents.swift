import FossifyCommons
import SwiftUI

/// The repetition rows shared by EventActivity and TaskActivity: interval, rule and limit.
struct RepetitionRows: View {
    @Environment(\.palette) private var palette
    @Binding var interval: Int
    @Binding var rule: Int
    @Binding var limit: Int64
    let start: JDate
    var disabled = false

    @State private var pickInterval = false
    @State private var pickRule = false
    @State private var pickLimit = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { pickInterval = true } label: { valueText(getRepetitionText(interval)) }
                .buttonStyle(.plain)
            if isXWeeklyRepetition(interval) || isXMonthlyRepetition(interval) || isXYearlyRepetition(interval) {
                Button { pickRule = true } label: { labeled(ruleLabel, ruleText) }.buttonStyle(.plain)
            }
            if interval != 0 {
                Button { pickLimit = true } label: { labeled(limit > 0 ? "Repeat till" : "Repeat", limitText) }.buttonStyle(.plain)
            }
        }
        .disabled(disabled)
        .sheet(isPresented: $pickInterval) { RepeatIntervalDialog(current: interval) { setInterval($0) } }
        .sheet(isPresented: $pickLimit) { RepeatLimitTypePickerDialog(limit: limit, startTS: start.seconds) { limit = $0 } }
        .sheet(isPresented: $pickRule) {
            if isXWeeklyRepetition(interval) {
                RepeatRuleWeeklyDialog(rule: rule) { setRule($0) }
            } else if isXMonthlyRepetition(interval) {
                RadioDialog(title: nil, items: monthlyRules, selected: rule) { setRule($0) }
            } else {
                RadioDialog(title: nil, items: yearlyRules, selected: rule) { setRule($0) }
            }
        }
    }

    private func valueText(_ s: String) -> some View {
        Text(s).foregroundStyle(palette.textColor).frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 12).contentShape(Rectangle())
    }

    private func labeled(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(palette.textColor)
            Spacer()
            Text(value).foregroundStyle(palette.textColor)
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    /// setRepeatInterval()
    private func setInterval(_ v: Int) {
        interval = v
        if isXWeeklyRepetition(v) {
            setRule(1 << (start.dayOfWeek - 1))
        } else if isXMonthlyRepetition(v) || isXYearlyRepetition(v) {
            setRule(REPEAT_SAME_DAY)
        }
    }

    private func setRule(_ r: Int) {
        rule = r
        if r == 0 { setInterval(0) }
    }

    private var limitText: String {
        if limit == 0 { return "Forever" }
        if limit > 0 { return Formatter.getFullDate(JDate(ts: limit)) }
        return "\(-limit) times"
    }

    private var ruleLabel: String {
        if isXWeeklyRepetition(interval) { return "Repeat on" }
        return rule == REPEAT_ORDER_WEEKDAY || rule == REPEAT_ORDER_WEEKDAY_USE_LAST ? "Repeat" : "Repeat on"
    }

    private var ruleText: String {
        if isXWeeklyRepetition(interval) { return rule == EVERY_DAY_BIT ? "Every day" : getShortDaysFromBitmask(rule) }
        if isXMonthlyRepetition(interval) {
            switch rule {
            case REPEAT_SAME_DAY: return "The same day"
            case REPEAT_LAST_DAY: return "The last day"
            default: return xthDay(includeBase: false, rule)
            }
        }
        return rule == REPEAT_SAME_DAY ? "The same day" : xthDayInMonth(includeBase: false, rule)
    }

    private var isLastWeekDayOfMonth: Bool { start.monthOfYear != start.plusDays(7).monthOfYear }

    private var monthlyRules: [(Int, String)] {
        var items = [(REPEAT_SAME_DAY, "Repeat on the same day each month"), (REPEAT_ORDER_WEEKDAY, xthDay(includeBase: true, REPEAT_ORDER_WEEKDAY))]
        if isLastWeekDayOfMonth { items.append((REPEAT_ORDER_WEEKDAY_USE_LAST, xthDay(includeBase: true, REPEAT_ORDER_WEEKDAY_USE_LAST))) }
        if start.dayOfMonth == start.maxDayOfMonth { items.append((REPEAT_LAST_DAY, "Repeat on the last day of the month")) }
        return items
    }

    private var yearlyRules: [(Int, String)] {
        var items = [(REPEAT_SAME_DAY, "Repeat on the same day every year"), (REPEAT_ORDER_WEEKDAY, xthDayInMonth(includeBase: true, REPEAT_ORDER_WEEKDAY))]
        if isLastWeekDayOfMonth { items.append((REPEAT_ORDER_WEEKDAY_USE_LAST, xthDayInMonth(includeBase: true, REPEAT_ORDER_WEEKDAY_USE_LAST))) }
        return items
    }

    /// getRepeatXthDayString(): "Repeat every first Monday" / "Every last Friday".
    private func xthDay(includeBase: Bool, _ r: Int) -> String {
        var order = (start.dayOfMonth - 1) / 7 + 1
        if isLastWeekDayOfMonth && r == REPEAT_ORDER_WEEKDAY_USE_LAST { order = -1 }
        let orders = [1: "first", 2: "second", 3: "third", 4: "fourth", 5: "fifth"]
        let day = WeekDays.names[start.dayOfWeek - 1]
        return "\(includeBase ? "Repeat every" : "Every") \(orders[order] ?? "last") \(day)"
    }

    private func xthDayInMonth(includeBase: Bool, _ r: Int) -> String {
        "\(xthDay(includeBase: includeBase, r)) \(Formatter.inMonths[start.monthOfYear - 1])"
    }
}

/// A row with a leading icon, like the activity_event.xml sections.
struct IconSection<Content: View>: View {
    @Environment(\.palette) private var palette
    let icon: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 16) {
                Image(systemName: icon).font(.system(size: 18)).foregroundStyle(palette.textColor).frame(width: 24).padding(.top, 12)
                VStack(alignment: .leading, spacing: 0, content: content)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
            Divider().overlay(palette.divider)
        }
    }
}

/// An underlined single-line field (MyEditText).
struct FieldText: View {
    @Environment(\.palette) private var palette
    let hint: String
    @Binding var text: String
    var multiline = false

    var body: some View {
        Group {
            if multiline {
                TextField("", text: $text, prompt: Text(hint).foregroundStyle(palette.secondaryText), axis: .vertical)
                    .lineLimit(1...10)
            } else {
                TextField("", text: $text, prompt: Text(hint).foregroundStyle(palette.secondaryText))
            }
        }
        .font(.system(size: palette.fontSize))
        .padding(.vertical, 10)
        .overlay(alignment: .bottom) { Rectangle().fill(palette.divider).frame(height: 1) }
    }
}
