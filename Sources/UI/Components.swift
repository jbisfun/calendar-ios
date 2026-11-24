import FossifyCommons
import SwiftUI
import UIKit

/// MyFloatingActionButton.
struct Fab: View {
    @Environment(\.palette) private var palette
    var icon = "plus"
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(palette.onPrimary)
                .frame(width: 56, height: 56)
                .background(Circle().fill(palette.primaryColor))
                .shadow(color: .black.opacity(0.3), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
    }
}

/// Placeholder text with an optional underlined action.
struct Placeholder: View {
    @Environment(\.palette) private var palette
    let text: String
    var action: String?
    var onAction: () -> Void = {}

    var body: some View {
        VStack(spacing: 16) {
            Text(text)
                .font(.system(size: 17).italic())
                .foregroundStyle(palette.textColor)
                .multilineTextAlignment(.center)
            if let action {
                Button(action: onAction) {
                    Text(action).font(.system(size: 17)).underline().foregroundStyle(palette.primaryColor)
                }
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct ShareItem: Identifiable {
    let url: URL
    var id: URL { url }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}

/// top_navigation.xml: previous / title / next.
struct TopNavigation: View {
    @Environment(\.palette) private var palette
    let title: String
    var titleColor: Color?
    let onPrevious: () -> Void
    let onTitle: () -> Void
    let onNext: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onPrevious) {
                Image(systemName: "chevron.left").font(.system(size: 18)).frame(width: 52, height: 44)
            }
            Spacer()
            Button(action: onTitle) {
                Text(title).font(.system(size: 20, weight: .medium)).foregroundStyle(titleColor ?? palette.textColor).lineLimit(1)
            }
            Spacer()
            Button(action: onNext) {
                Image(systemName: "chevron.right").font(.system(size: 18)).frame(width: 52, height: 44)
            }
        }
        .foregroundStyle(palette.textColor)
        .buttonStyle(.plain)
    }
}

/// Filled color circle with a stroke (setFillWithStroke).
struct ColorDot: View {
    @Environment(\.palette) private var palette
    let color: UInt32
    var size: CGFloat = 24

    var body: some View {
        Circle().fill(Color(argb: color))
            .overlay(Circle().stroke(palette.textColor.opacity(0.4), lineWidth: 1))
            .frame(width: size, height: size)
    }
}

// MARK: Event list rows (event_list_item.xml, event_list_section_*.xml)

enum ListItem: Identifiable {
    case month(String)
    case day(title: String, code: String, isToday: Bool, isPast: Bool)
    case event(Event)

    var id: String {
        switch self {
        case .month(let t): return "m-\(t)"
        case .day(_, let code, _, _): return "d-\(code)"
        case .event(let e): return "e-\(e.occurrenceKey)"
        }
    }
}

/// Context.getEventListItems()
func getEventListItems(_ events: [Event], addSectionDays: Bool = true, addSectionMonths: Bool = true) -> [ListItem] {
    let replace = Config.shared.replaceDescription
    func sortStart(_ e: Event) -> Int64 { e.isAllDay ? Formatter.getDayStartTS(Formatter.getDayCodeFromTS(e.startTS)) - 1 : e.startTS }
    func sortEnd(_ e: Event) -> Int64 { e.isAllDay ? Formatter.getDayEndTS(Formatter.getDayCodeFromTS(e.endTS)) : e.endTS }
    let sorted = events.sorted { a, b in
        if sortStart(a) != sortStart(b) { return sortStart(a) < sortStart(b) }
        if sortEnd(a) != sortEnd(b) { return sortEnd(a) < sortEnd(b) }
        if a.title != b.title { return a.title < b.title }
        return (replace ? a.location : a.description) < (replace ? b.location : b.description)
    }
    var items: [ListItem] = []
    var prevCode = ""
    var prevMonth = ""
    let now = getNowSeconds()
    let todayCode = Formatter.getDayCodeFromTS(now)
    for e in sorted {
        let code = Formatter.getDayCodeFromTS(e.startTS)
        if addSectionMonths {
            let label = Formatter.getLongMonthYear(code)
            if label != prevMonth {
                items.append(.month(label))
                prevMonth = label
            }
        }
        if code != prevCode && addSectionDays {
            let isToday = code == todayCode
            items.append(.day(title: Formatter.getDateDayTitle(code), code: code, isToday: isToday, isPast: !isToday && e.startTS < now))
            prevCode = code
        }
        items.append(.event(e))
    }
    return items
}

struct EventRow: View {
    @Environment(\.palette) private var palette
    @Environment(Config.self) private var config
    let event: Event
    var selected = false

    var body: some View {
        let now = getNowSeconds()
        var color = palette.textColor
        if event.isAllDay || (event.startTS <= now && event.endTS <= now) {
            if event.isAllDay && Formatter.getDayCodeFromTS(event.startTS) == Formatter.getDayCodeFromTS(now) {
                color = palette.primaryColor
            }
            let dim = event.isTask ? config.dimCompletedTasks && event.isTaskCompleted : config.dimPastEvents && event.isPastEvent
            if dim { color = color.opacity(MEDIUM_ALPHA) }
        } else if event.startTS <= now && event.endTS >= now {
            color = palette.primaryColor
        }
        let desc = config.replaceDescription ? event.location : event.description.replacingOccurrences(of: "\n", with: " ")
        let size = palette.fontSize
        return HStack(spacing: 0) {
            RoundedRectangle(cornerRadius: 2).fill(Color(argb: event.color)).frame(width: 5).padding(.vertical, 2)
            if event.isTask {
                Image(systemName: "checkmark.circle").font(.system(size: size)).foregroundStyle(color).padding(.leading, 8)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title)
                    .font(.system(size: size))
                    .strikethrough(event.shouldStrikeThrough)
                    .lineLimit(1)
                Text(timeText)
                    .font(.system(size: size - 2))
                if config.displayDescription && !desc.isEmpty {
                    Text(desc).font(.system(size: size - 2)).lineLimit(1)
                }
            }
            .foregroundStyle(color)
            .padding(.leading, event.isTask ? 6 : 12)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(selected ? palette.primaryColor.opacity(0.25) : Color.clear)
        .contentShape(Rectangle())
    }

    private var timeText: String {
        var text = event.isAllDay ? "All-day" : Formatter.getTimeFromTS(event.startTS)
        if event.startTS != event.endTS {
            if !event.isAllDay { text += " - \(Formatter.getTimeFromTS(event.endTS))" }
            let start = Formatter.getDayCodeFromTS(event.startTS)
            let end = Formatter.getDayCodeFromTS(event.endTS)
            if start != end { text += " (\(Formatter.getDateDayTitle(end)))" }
        }
        return text
    }
}

/// EventListAdapter: sections and events with tap / long-press selection.
struct EventListItems: View {
    @Environment(\.palette) private var palette
    let items: [ListItem]
    @Binding var selection: Set<String>
    let onOpen: (Event) -> Void

    var body: some View {
        ForEach(items) { item in
            switch item {
            case .month(let title):
                Text(title)
                    .font(.system(size: palette.fontSize + 2, weight: .bold))
                    .foregroundStyle(palette.primaryColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 4)
            case .day(let title, _, let isToday, _):
                Text(title)
                    .font(.system(size: palette.fontSize, weight: .medium))
                    .foregroundStyle(isToday ? palette.primaryColor : palette.textColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 2)
            case .event(let e):
                EventRow(event: e, selected: selection.contains(e.occurrenceKey))
                    .onTapGesture {
                        if selection.isEmpty { onOpen(e) } else { toggle(e) }
                    }
                    .onLongPressGesture { toggle(e) }
            }
        }
    }

    private func toggle(_ e: Event) {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        if selection.contains(e.occurrenceKey) { selection.remove(e.occurrenceKey) } else { selection.insert(e.occurrenceKey) }
    }
}

// MARK: Date / time pickers (DatePickerDialog, TimePickerDialog)

struct DatePickerDialog: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    @State var date: Date
    var title: String? = nil
    let onPick: (Date) -> Void

    var body: some View {
        DialogFrame(title: title, scroll: false) {
            DatePicker("", selection: $date, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .environment(\.calendar, weekCalendar)
                .labelsHidden()
            DialogButtons {
                onPick(date)
                dismiss()
            }
        }
        .presentationDetents([.large])
    }
}

struct TimePickerDialog: View {
    @Environment(\.dismiss) private var dismiss
    @State var date: Date
    let onPick: (Date) -> Void

    var body: some View {
        DialogFrame(title: nil, scroll: false) {
            DatePicker("", selection: $date, displayedComponents: .hourAndMinute)
                .datePickerStyle(.wheel)
                .labelsHidden()
                .environment(\.locale, Locale(identifier: DateTimeFormat.shared.use24HourFormat ? "en_GB" : "en_US"))
                .frame(maxWidth: .infinity)
            DialogButtons {
                onPick(date)
                dismiss()
            }
        }
        .presentationDetents([.medium])
    }
}

/// Gregorian calendar starting on the configured first day of the week.
var weekCalendar: Calendar {
    var c = Calendar.current
    c.firstWeekday = WeekDays.shared.firstDayOfWeek % 7 + 1
    return c
}

// MARK: Printing (printBitmap)

@MainActor
enum PrintHelper {
    static func print<V: View>(_ view: V, size: CGSize) {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
        renderer.scale = 2
        guard let image = renderer.uiImage else { return }
        let info = UIPrintInfo(dictionary: nil)
        info.outputType = .photo
        info.jobName = "Calendar"
        info.orientation = .portrait
        let controller = UIPrintInteractionController.shared
        controller.printInfo = info
        controller.printingItem = image
        controller.present(animated: true)
    }
}
