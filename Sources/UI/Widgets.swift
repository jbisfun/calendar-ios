import FossifyCommons
import SwiftUI

/// The Calendar app's home-screen widgets (MyWidgetDateProvider, MyWidgetListProvider,
/// MyWidgetMonthlyProvider with their configure activities), drawn by launcher-ios.
public enum CalendarWidgets {
    public static let all: [HomeWidgetKind] = [
        // widget_date_info.xml: 1x1, min 40dp, resizable both ways.
        HomeWidgetKind(id: "calendar.date", title: "Date", defaultSize: CGSize(width: 1, height: 1),
                       minSize: CGSize(width: 1, height: 1), resizable: true,
                       configure: { ctx, done in MainActor.assumeIsolated { AnyView(DateWidgetConfigure(context: ctx, done: done)) } },
                       content: { ctx in MainActor.assumeIsolated { AnyView(DateWidget(context: ctx)) } }),
        // widget_list_info.xml: 4x4, min resize 40dp.
        HomeWidgetKind(id: "calendar.list", title: "Event list", defaultSize: CGSize(width: 4, height: 4),
                       minSize: CGSize(width: 1, height: 1), resizable: true,
                       configure: { ctx, done in MainActor.assumeIsolated { AnyView(ListWidgetConfigure(context: ctx, done: done)) } },
                       content: { ctx in MainActor.assumeIsolated { AnyView(ListWidget(context: ctx)) } }),
        // widget_monthly_info.xml: 4x4, min resize 110dp (2 cells).
        HomeWidgetKind(id: "calendar.monthly", title: "Monthly view", defaultSize: CGSize(width: 4, height: 4),
                       minSize: CGSize(width: 2, height: 2), resizable: true,
                       configure: { ctx, done in MainActor.assumeIsolated { AnyView(MonthlyWidgetConfigure(context: ctx, done: done)) } },
                       content: { ctx in MainActor.assumeIsolated { AnyView(MonthlyWidget(context: ctx)) } }),
    ]
}

// MARK: - Shared pieces

/// widget_round_background (normal_margin corners) tinted with the widget background color.
private struct WidgetBackground: View {
    let color: UInt32
    var body: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color(argb: color))
    }
}

/// Per-widget colors under context.key(...), seeded from the last configured ones.
private func bgStorage(_ context: HomeWidgetContext) -> AppStorage<Int> {
    AppStorage(wrappedValue: WidgetDefaults.bgColor.asSignedInt, context.key("bg_color"))
}

private func textStorage(_ context: HomeWidgetContext) -> AppStorage<Int> {
    AppStorage(wrappedValue: WidgetDefaults.textColor.asSignedInt, context.key("text_color"))
}

/// A tappable widget icon (ArrowStyle ImageView with medium_margin side padding).
private struct WidgetIcon: View {
    let systemName: String
    let color: Color
    var size: CGFloat = 18
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(color)
                .padding(.horizontal, 8)
                .frame(minHeight: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressedStyle())
    }
}

// MARK: - Date widget (widget_date.xml)

private struct DateWidgetFace: View {
    let date: Date
    let bg: UInt32
    let text: UInt32

    var body: some View {
        let d = JDate(date)
        ZStack {
            WidgetBackground(color: bg)
            GeometryReader { geo in
                let inner = max(0, geo.size.height - 4)
                VStack(spacing: 0) {
                    // TextClock "d", weight 2, autosized
                    Text("\(d.dayOfMonth)")
                        .font(.system(size: 300))
                        .minimumScaleFactor(0.01)
                        .lineLimit(1)
                        .padding(.top, 8)
                        .frame(width: geo.size.width - 8, height: inner * 2 / 3)
                    // TextClock "MMM", weight 1, autosized
                    Text(Formatter.getShortMonthName(d.monthOfYear))
                        .font(.system(size: 300))
                        .minimumScaleFactor(0.01)
                        .lineLimit(1)
                        .padding(.bottom, 8)
                        .frame(width: geo.size.width - 8, height: inner / 3)
                }
                .foregroundStyle(Color(argb: text))
                .frame(width: geo.size.width, height: geo.size.height, alignment: .top)
            }
        }
    }
}

struct DateWidget: View {
    let context: HomeWidgetContext
    @AppStorage private var bg: Int
    @AppStorage private var text: Int

    init(context: HomeWidgetContext) {
        self.context = context
        _bg = bgStorage(context)
        _text = textStorage(context)
    }

    var body: some View {
        TimelineView(.everyMinute) { tl in
            DateWidgetFace(date: tl.date, bg: UInt32(signed: bg), text: UInt32(signed: text))
        }
        .contentShape(Rectangle())
        .onTapGesture { context.openApp(nil) }
    }
}

// MARK: - Event list widget (widget_event_list.xml + EventListWidgetAdapter)

private struct ListWidgetBody: View {
    let items: [ListItem]
    let bg: UInt32
    let text: UInt32
    let showHeader: Bool
    let now: Date
    var onLaunch: () -> Void = {}
    var onNewEvent: () -> Void = {}
    var onOpen: () -> Void = {}
    @State private var scrollToken = 0

    var body: some View {
        let config = Config.shared
        let fontSize = widgetFontSize()
        let textColor = Color(argb: text)
        let weak = Color(argb: text.adjustAlpha(MEDIUM_ALPHA))
        ZStack(alignment: .top) {
            WidgetBackground(color: bg)
            VStack(spacing: 0) {
                if showHeader {
                    // widget_event_list_header.xml
                    HStack(spacing: 0) {
                        Text(Formatter.formatter("MMM d yyyy (EEEE)").string(from: now))
                            .font(.system(size: fontSize))
                            .foregroundStyle(textColor)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .padding(.horizontal, 8)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                            .onTapGesture(perform: onLaunch)
                        WidgetIcon(systemName: "calendar", color: textColor) { scrollToken += 1 }
                        WidgetIcon(systemName: "plus", color: textColor, action: onNewEvent)
                    }
                    .padding(.top, 8)
                }
                ZStack(alignment: .top) {
                    if items.isEmpty {
                        Text("No upcoming events.")
                            .font(.system(size: fontSize))
                            .foregroundStyle(textColor)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                            .frame(maxWidth: .infinity)
                    } else {
                        ScrollViewReader { proxy in
                            ScrollView(showsIndicators: false) {
                                LazyVStack(alignment: .leading, spacing: 0) {
                                    Color.clear.frame(height: 0).id("top")
                                    ForEach(items) { item in
                                        row(item, config: config, fontSize: fontSize, textColor: textColor, weak: weak)
                                    }
                                }
                                .padding(.bottom, 4)
                            }
                            .onChange(of: scrollToken) { _, _ in proxy.scrollTo("top", anchor: .top) }
                        }
                    }
                }
                .padding(.top, 4)
                .frame(maxHeight: .infinity, alignment: .top)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private func row(_ item: ListItem, config: Config, fontSize: CGFloat, textColor: Color, weak: Color) -> some View {
        switch item {
        case .month(let title):
            // event_list_section_month_widget.xml
            Text(title.uppercased())
                .font(.system(size: 16, weight: .light))
                .foregroundStyle(textColor)
                .padding(.leading, 8)
                .padding(.bottom, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
        case let .day(title, _, _, isPast):
            // event_list_section_day_widget.xml
            Text(title)
                .font(.system(size: fontSize - 3, weight: .bold))
                .foregroundStyle(config.dimPastEvents && isPast ? weak : textColor)
                .padding(.leading, 20)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture(perform: onOpen)
        case .event(let e):
            eventRow(e, config: config, fontSize: fontSize, textColor: textColor, weak: weak)
        }
    }

    /// event_list_item_widget.xml, EventListWidgetAdapter.setupListEvent()
    private func eventRow(_ e: Event, config: Config, fontSize: CGFloat, textColor: Color, weak: Color) -> some View {
        var time = e.isAllDay ? "All-day" : Formatter.getTimeFromTS(e.startTS)
        if e.startTS != e.endTS {
            if !e.isAllDay { time += " - \(Formatter.getTimeFromTS(e.endTS))" }
            let startCode = Formatter.getDayCodeFromTS(e.startTS)
            let endCode = Formatter.getDayCodeFromTS(e.endTS)
            if startCode != endCode { time += " (\(Formatter.getDateDayTitle(endCode)))" }
        }
        let desc = config.replaceDescription ? e.location : e.description.replacingOccurrences(of: "\n", with: " ")
        if config.displayDescription && !desc.isEmpty { time += "\n\(desc)" }
        let dim = (e.isTask && e.isTaskCompleted && config.dimCompletedTasks) || (config.dimPastEvents && e.isPastEvent && !e.isTask)
        let color = dim ? weak : textColor
        return HStack(alignment: .top, spacing: 0) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(argb: e.color))
                .frame(width: 4)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4) {
                    if e.isTask {
                        Image(systemName: "checkmark.circle").font(.system(size: fontSize - 2))
                    }
                    Text(e.title)
                        .font(.system(size: fontSize))
                        .strikethrough(e.shouldStrikeThrough)
                        .lineLimit(1)
                }
                Text(time)
                    .font(.system(size: fontSize))
                    .lineLimit(2)
                    .opacity(0.8)
            }
            .foregroundStyle(color)
            .padding(.leading, 8)
            .padding(.trailing, 4)
            Spacer(minLength: 0)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 4)
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
    }
}

struct ListWidget: View {
    let context: HomeWidgetContext
    @AppStorage private var bg: Int
    @AppStorage private var text: Int
    @AppStorage private var period: Int
    @AppStorage private var header: Bool

    init(context: HomeWidgetContext) {
        self.context = context
        _bg = bgStorage(context)
        _text = textStorage(context)
        _period = AppStorage(wrappedValue: Config.shared.lastUsedEventSpan, context.key("period"))
        _header = AppStorage(wrappedValue: WidgetDefaults.showListHeader, context.key("header"))
    }

    var body: some View {
        // updatePeriodMillis is 10 minutes upstream; once a minute keeps "past" dimming and the header date current.
        TimelineView(.everyMinute) { tl in
            let store = CalendarStore.shared
            let _ = store.revision
            ListWidgetBody(items: getEventListItems(widgetListEvents(store, period: period)),
                           bg: UInt32(signed: bg), text: UInt32(signed: text), showHeader: header, now: tl.date,
                           onLaunch: { context.openApp(nil) }, onNewEvent: { context.openApp(nil) }, onOpen: { context.openApp(nil) })
        }
    }
}

// MARK: - Monthly widget (fragment_month_widget[_grid].xml)

/// MyWidgetMonthlyProvider.targetDate: survives the launcher re-creating the widget view.
@MainActor
private enum MonthlyWidgetTargets {
    static var targets: [String: JDate] = [:]
}

private enum EventShape { case single, start, middle, end }

private struct MonthlyWidgetBody: View {
    let days: [DayMonthly]
    let title: String
    let bg: UInt32
    let text: UInt32
    let showGoToToday: Bool
    var onPrev: () -> Void = {}
    var onNext: () -> Void = {}
    var onToday: () -> Void = {}
    var onNewEvent: () -> Void = {}
    var onOpen: () -> Void = {}

    var body: some View {
        let config = Config.shared
        let fontSize = widgetFontSize()
        let textColor = Color(argb: text)
        ZStack(alignment: .top) {
            WidgetBackground(color: bg)
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    WidgetIcon(systemName: "chevron.left", color: textColor, action: onPrev)
                    Text(title)
                        .font(.system(size: fontSize + 3))
                        .foregroundStyle(textColor)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                        .contentShape(Rectangle())
                        .onTapGesture(perform: onOpen)
                    if showGoToToday {
                        WidgetIcon(systemName: "calendar", color: textColor, action: onToday)
                    }
                    WidgetIcon(systemName: "chevron.right", color: textColor, action: onNext)
                    WidgetIcon(systemName: "plus", color: textColor, action: onNewEvent)
                }
                labels(config: config, fontSize: fontSize)
                if days.count == 42 {
                    grid(config: config, fontSize: fontSize)
                } else {
                    Spacer()
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var gridColor: Color { Color(argb: 0xFF33_3333) }

    /// first_row_widget.xml, updateDayLabels()
    private func labels(config: Config, fontSize: CGFloat) -> some View {
        let letters = weekDayLettersShort()
        return HStack(spacing: 0) {
            if config.showWeekNumbers {
                Text("#").frame(maxWidth: .infinity).foregroundStyle(Color(argb: text))
            }
            ForEach(0..<7, id: \.self) { i in
                let c = config.highlightWeekends && isWeekendIndex(i) ? config.highlightWeekendsColor : text
                Text(letters[i]).frame(maxWidth: .infinity).foregroundStyle(Color(argb: c))
            }
        }
        .font(.system(size: fontSize, weight: .bold))
        .lineLimit(1)
        .minimumScaleFactor(0.5)
        .padding(.vertical, 4)
    }

    private func grid(config: Config, fontSize: CGFloat) -> some View {
        let smaller = fontSize - 3
        let eventFont = smaller - 3
        let rowH = ceil(eventFont * 1.25) + 2
        let slots = daySlotLists()
        return VStack(spacing: 0) {
            ForEach(0..<6, id: \.self) { row in
                if config.showGrid && row > 0 { gridColor.frame(height: 1) }
                HStack(spacing: 0) {
                    if config.showWeekNumbers {
                        // WeekNumberStyle: the fourth day of the week decides the week of the year
                        Text("\(days[row * 7 + 3].weekOfYear):")
                            .font(.system(size: smaller, weight: .light))
                            .foregroundStyle(Color(argb: text))
                            .lineLimit(1)
                            .minimumScaleFactor(0.5)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    }
                    ForEach(0..<7, id: \.self) { col in
                        if config.showGrid && col > 0 { gridColor.frame(width: 1) }
                        let i = row * 7 + col
                        dayCell(i, slots: slots[i], config: config, smaller: smaller, eventFont: eventFont, rowH: rowH)
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
    }

    private func dayCell(_ i: Int, slots: [Event?], config: Config, smaller: CGFloat, eventFont: CGFloat, rowH: CGFloat) -> some View {
        let day = days[i]
        let dayText = config.highlightWeekends && day.isWeekend ? config.highlightWeekendsColor : text
        let cur = day.isThisMonth ? dayText : dayText.adjustAlpha(MEDIUM_ALPHA)
        return VStack(spacing: 0) {
            // day_monthly_number_view.xml, addDayNumber()
            Text("\(day.value)")
                .font(.system(size: smaller))
                .foregroundStyle(day.isToday ? cur.contrastColor : Color(argb: cur))
                .lineLimit(1)
                .frame(minWidth: smaller * 1.7, minHeight: smaller * 1.7)
                .background { if day.isToday { Circle().fill(Color(argb: cur)) } }
                .padding(.vertical, 1)
            ForEach(Array(slots.enumerated()), id: \.offset) { _, slot in
                if let e = slot {
                    eventView(e, at: i, config: config, eventFont: eventFont, rowH: rowH)
                } else {
                    Color.clear.frame(height: rowH)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .clipped()
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
    }

    private func eventView(_ e: Event, at i: Int, config: Config, eventFont: CGFloat, rowH: CGFloat) -> some View {
        let indices = dayIndices[e.occurrenceKey] ?? []
        let prevInRun = i > 0 && i % 7 != 0 && indices.contains(i - 1)
        let nextInRun = i < days.count - 1 && (i + 1) % 7 != 0 && indices.contains(i + 1)
        let shape: EventShape = prevInRun && nextInRun ? .middle : prevInRun ? .end : nextInRun ? .start : .single
        let showTitle = !prevInRun
        let dim = (e.isTask && e.isTaskCompleted && config.dimCompletedTasks) || (config.dimPastEvents && e.isPastEvent && !e.isTask)
        let fg = e.color.contrastColor.opacity(dim ? MEDIUM_ALPHA : 1)
        let r: CGFloat = 2
        let radii: RectangleCornerRadii
        switch shape {
        case .single: radii = .init(topLeading: r, bottomLeading: r, bottomTrailing: r, topTrailing: r)
        case .start: radii = .init(topLeading: r, bottomLeading: r, bottomTrailing: 0, topTrailing: 0)
        case .middle: radii = .init()
        case .end: radii = .init(topLeading: 0, bottomLeading: 0, bottomTrailing: r, topTrailing: r)
        }
        let leading: CGFloat = shape == .single || shape == .start ? 1 : 0
        let trailing: CGFloat = shape == .single || shape == .end ? 1 : 0
        return ZStack(alignment: .leading) {
            UnevenRoundedRectangle(cornerRadii: radii)
                .fill(Color(argb: e.color))
                .padding(.vertical, 1)
                .padding(.leading, leading)
                .padding(.trailing, trailing)
            HStack(spacing: 1) {
                if showTitle && e.isTask {
                    Image(systemName: "checkmark.circle").font(.system(size: eventFont))
                }
                Text(showTitle ? e.title : " ")
                    .font(.system(size: eventFont))
                    .strikethrough(e.shouldStrikeThrough)
                    .lineLimit(1)
                    .fixedSize()
            }
            .foregroundStyle(fg)
            .padding(.horizontal, 2 + leading)
        }
        .frame(maxWidth: .infinity, minHeight: rowH, maxHeight: rowH, alignment: .leading)
        .clipped()
    }

    // MARK: Slot layout (MyWidgetMonthlyProvider.updateDays / buildDaySlotLists)

    private var dayIndices: [String: [Int]] {
        var map: [String: [Int]] = [:]
        for (i, day) in days.enumerated() {
            for e in day.dayEvents where map[e.occurrenceKey]?.last != i {
                map[e.occurrenceKey, default: []].append(i)
            }
        }
        return map
    }

    private func daySlotLists() -> [[Event?]] {
        let indices = dayIndices
        var byKey: [String: Event] = [:]
        for day in days { for e in day.dayEvents where byKey[e.occurrenceKey] == nil { byKey[e.occurrenceKey] = e } }
        let keys = indices.keys.sorted { a, b in
            let ea = byKey[a]!, eb = byKey[b]!
            let ca = indices[a]!.count, cb = indices[b]!.count
            if ca != cb { return ca > cb }
            if ea.isAllDay != eb.isAllDay { return ea.isAllDay }
            if ea.startTS != eb.startTS { return ea.startTS < eb.startTS }
            if ea.endTS != eb.endTS { return ea.endTS < eb.endTS }
            let fa = indices[a]!.first ?? 0, fb = indices[b]!.first ?? 0
            if fa != fb { return fa < fb }
            return ea.title < eb.title
        }
        var lists = Array(repeating: [Event?](), count: days.count)
        for key in keys {
            let event = byKey[key]!
            let weeks = Dictionary(grouping: indices[key]!) { $0 / 7 }
            for weekDays in weeks.keys.sorted().map({ weeks[$0]! }) {
                var slot = 0
                while weekDays.contains(where: { slot < lists[$0].count && lists[$0][slot] != nil }) { slot += 1 }
                for d in weekDays {
                    while lists[d].count <= slot { lists[d].append(nil) }
                    lists[d][slot] = event
                }
            }
        }
        return lists
    }
}

struct MonthlyWidget: View {
    let context: HomeWidgetContext
    @AppStorage private var bg: Int
    @AppStorage private var text: Int
    /// nil = the current month (follows the date rollover).
    @State private var target: JDate?

    init(context: HomeWidgetContext) {
        self.context = context
        _bg = bgStorage(context)
        _text = textStorage(context)
        _target = State(initialValue: MonthlyWidgetTargets.targets[context.instanceID])
    }

    var body: some View {
        TimelineView(.everyMinute) { tl in
            let current = JDate(tl.date).withTimeAtStartOfDay.withDayOfMonth(1)
            let month = target ?? current
            let store = CalendarStore.shared
            let _ = store.revision
            let _ = WeekDays.shared.firstDayOfWeek
            MonthlyWidgetBody(days: monthDays(store, month: month),
                              title: Formatter.getLongMonthYear(Formatter.getDayCodeFromDateTime(month)),
                              bg: UInt32(signed: bg), text: UInt32(signed: text),
                              showGoToToday: Formatter.getDayCodeFromDateTime(month) != Formatter.getDayCodeFromDateTime(current),
                              onPrev: { setTarget(month.plusMonths(-1), current: current) },
                              onNext: { setTarget(month.plusMonths(1), current: current) },
                              onToday: { setTarget(nil, current: current) },
                              onNewEvent: { context.openApp(nil) },
                              onOpen: { context.openApp(nil) })
        }
    }

    private func setTarget(_ month: JDate?, current: JDate) {
        var month = month
        if let m = month, Formatter.getDayCodeFromDateTime(m) == Formatter.getDayCodeFromDateTime(current) { month = nil }
        target = month
        MonthlyWidgetTargets.targets[context.instanceID] = month
    }
}

// MARK: - Configure screens (Widget*ConfigureActivity)

/// The shared part of the three configure activities: a preview, background color + alpha
/// seekbar, text color and Save.
private struct WidgetConfigureScreen<Preview: View, Extra: View>: View {
    @Environment(\.palette) private var palette
    let title: String
    @Binding var bgRGB: UInt32
    @Binding var bgAlpha: Double
    @Binding var textColor: UInt32
    let previewHeight: CGFloat
    let onCancel: () -> Void
    let onSave: () -> Void
    @ViewBuilder let preview: () -> Preview
    @ViewBuilder let extra: () -> Extra
    @State private var pickBg = false
    @State private var pickText = false

    var body: some View {
        VStack(spacing: 0) {
            TopBar(title: title, onBack: onCancel)
            ScrollView {
                VStack(spacing: 16) {
                    preview()
                        .frame(height: previewHeight)
                        .padding(16)
                        .frame(maxWidth: .infinity)
                        .background(RoundedRectangle(cornerRadius: 16).fill(Color.gray.opacity(0.35)))
                    extra()
                    HStack(spacing: 16) {
                        colorButton(combinedBg) { pickBg = true }
                        Slider(value: $bgAlpha, in: 0...1).tint(palette.primaryColor)
                        colorButton(textColor) { pickText = true }
                    }
                    .padding(.horizontal, 16)
                    Button(action: onSave) {
                        Text("OK")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(palette.onPrimary)
                            .padding(.horizontal, 32)
                            .padding(.vertical, 12)
                            .background(Capsule().fill(palette.primaryColor))
                    }
                    .buttonStyle(PressedStyle())
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.horizontal, 16)
                }
                .padding(16)
            }
        }
        .background(palette.backgroundColor.ignoresSafeArea())
        .sheet(isPresented: $pickBg) {
            ColorPickerDialog(title: "Background color", color: bgRGB) { bgRGB = $0 | 0xFF00_0000 }
        }
        .sheet(isPresented: $pickText) {
            ColorPickerDialog(title: "Text color", color: textColor) { textColor = $0 | 0xFF00_0000 }
        }
    }

    private var combinedBg: UInt32 { (bgRGB | 0xFF00_0000).adjustAlpha(bgAlpha) }

    private func colorButton(_ color: UInt32, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Circle()
                .fill(Color(argb: color))
                .overlay(Circle().stroke(palette.textColor.opacity(0.5), lineWidth: 1))
                .frame(width: 40, height: 40)
        }
        .buttonStyle(PressedStyle())
    }
}

/// Colors being edited: initVariables() / storeWidgetColors().
private struct EditedColors {
    var bgRGB: UInt32
    var bgAlpha: Double
    var text: UInt32

    init(_ context: HomeWidgetContext) {
        let d = UserDefaults.standard
        let bg = UInt32(signed: d.object(forKey: context.key("bg_color")) as? Int ?? WidgetDefaults.bgColor.asSignedInt)
        bgRGB = bg | 0xFF00_0000
        bgAlpha = Double((bg >> 24) & 0xFF) / 255
        text = UInt32(signed: d.object(forKey: context.key("text_color")) as? Int ?? WidgetDefaults.textColor.asSignedInt)
    }

    var bg: UInt32 { bgRGB.adjustAlpha(bgAlpha) }

    func store(_ context: HomeWidgetContext) {
        let d = UserDefaults.standard
        d.set(bg.asSignedInt, forKey: context.key("bg_color"))
        d.set(text.asSignedInt, forKey: context.key("text_color"))
        WidgetDefaults.bgColor = bg
        WidgetDefaults.textColor = text
    }
}

struct DateWidgetConfigure: View {
    let context: HomeWidgetContext
    let done: (Bool) -> Void
    @State private var colors: EditedColors

    init(context: HomeWidgetContext, done: @escaping (Bool) -> Void) {
        self.context = context
        self.done = done
        _colors = State(initialValue: EditedColors(context))
    }

    var body: some View {
        WidgetConfigureScreen(title: "Date", bgRGB: $colors.bgRGB, bgAlpha: $colors.bgAlpha, textColor: $colors.text,
                              previewHeight: 110, onCancel: { done(false) },
                              onSave: { colors.store(context); done(true) }) {
            DateWidgetFace(date: Date(), bg: colors.bg, text: colors.text).frame(width: 110)
        } extra: {
            EmptyView()
        }
        .fossifyTheme()
    }
}

struct ListWidgetConfigure: View {
    let context: HomeWidgetContext
    let done: (Bool) -> Void
    @Environment(\.palette) private var palette
    @State private var colors: EditedColors
    @State private var period: Int
    @State private var header: Bool
    @State private var pickPeriod = false
    @State private var customPeriod = false

    init(context: HomeWidgetContext, done: @escaping (Bool) -> Void) {
        self.context = context
        self.done = done
        _colors = State(initialValue: EditedColors(context))
        let d = UserDefaults.standard
        var p = d.object(forKey: context.key("period")) as? Int ?? Config.shared.lastUsedEventSpan
        if p == 0 { p = WIDGET_YEAR_SECONDS }
        _period = State(initialValue: p)
        _header = State(initialValue: d.object(forKey: context.key("header")) as? Bool ?? WidgetDefaults.showListHeader)
    }

    var body: some View {
        WidgetConfigureScreen(title: "Event list", bgRGB: $colors.bgRGB, bgAlpha: $colors.bgAlpha, textColor: $colors.text,
                              previewHeight: 320, onCancel: { done(false) }, onSave: save) {
            ListWidgetBody(items: getEventListItems(sampleEvents(), addSectionMonths: false), bg: colors.bg, text: colors.text,
                           showHeader: header, now: Date())
                .allowsHitTesting(false)
        } extra: {
            VStack(spacing: 0) {
                SettingsItem("Period", value: widgetPeriodText(period)) { pickPeriod = true }
                SettingsToggle("Show widget header", isOn: $header)
            }
        }
        .sheet(isPresented: $pickPeriod) {
            RadioDialog(title: nil, items: periodItems(), selected: period) { option in
                if option == EVENT_PERIOD_CUSTOM {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { customPeriod = true }
                } else {
                    period = option
                }
            }
            .fossifyTheme()
        }
        .sheet(isPresented: $customPeriod) {
            CustomPeriodPickerDialog { period = $0 }.fossifyTheme()
        }
        .fossifyTheme()
    }

    /// showPeriodSelector(): today, a week, a month, a year and the current value, plus "Within the next…".
    private func periodItems() -> [(Int, String)] {
        let values = Set([EVENT_PERIOD_TODAY, WIDGET_WEEK_SECONDS, WIDGET_MONTH_SECONDS, WIDGET_YEAR_SECONDS, period]).sorted()
        return values.map { ($0, widgetPeriodText($0)) } + [(EVENT_PERIOD_CUSTOM, "Within the next…")]
    }

    private func save() {
        colors.store(context)
        let d = UserDefaults.standard
        d.set(period, forKey: context.key("period"))
        d.set(header, forKey: context.key("header"))
        Config.shared.lastUsedEventSpan = period
        WidgetDefaults.showListHeader = header
        done(true)
    }

    /// getListItems(): the preview's sample events.
    private func sampleEvents() -> [Event] {
        let primary = BaseConfig.shared.customPrimaryColor
        let day1 = JDate.now().withTimeAtStartOfDay.plusDays(1)
        let day2 = day1.plusDays(1)
        func sample(_ id: Int64, _ start: JDate, minutes: Int, _ title: String, _ description: String) -> Event {
            var e = Event()
            e.id = id
            e.startTS = start.seconds
            e.endTS = start.plusMinutes(minutes).seconds
            e.title = title
            e.description = description
            e.color = primary
            return e
        }
        return [
            sample(1, day1.withHourOfDay(7), minutes: 30, "Workout", "Leg day"),
            sample(2, day1.withHourOfDay(8), minutes: 60, "Meeting with John", "In Rockstone garden"),
            sample(3, day2.withHourOfDay(8), minutes: 60, "Library", ""),
            sample(4, day2.withHourOfDay(13), minutes: 60, "Lunch with Mary", "In the Plaza"),
            sample(5, day2.withHourOfDay(18), minutes: 10, "Coffee time", ""),
        ]
    }
}

/// dialogs/CustomPeriodPickerDialog.kt: a number of days, weeks or months.
private struct CustomPeriodPickerDialog: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.palette) private var palette
    let onPick: (Int) -> Void
    @State private var value = ""
    @State private var unit = WIDGET_DAY_SECONDS
    @FocusState private var focused: Bool

    var body: some View {
        DialogFrame(title: nil, scroll: false) {
            TextField("", text: $value)
                .keyboardType(.numberPad)
                .focused($focused)
                .foregroundStyle(palette.textColor)
                .padding(.vertical, 8)
                .overlay(alignment: .bottom) { palette.primaryColor.frame(height: 1) }
            ForEach([(WIDGET_DAY_SECONDS, "Days"), (WIDGET_WEEK_SECONDS, "Weeks"), (WIDGET_MONTH_SECONDS, "Months")], id: \.0) { item in
                Button { unit = item.0 } label: { RadioRow(title: item.1, on: unit == item.0) }.buttonStyle(.plain)
            }
            DialogButtons {
                onPick((Int(value) ?? 0) * unit)
                dismiss()
            }
        }
        .onAppear { focused = true }
    }
}

struct MonthlyWidgetConfigure: View {
    let context: HomeWidgetContext
    let done: (Bool) -> Void
    @State private var colors: EditedColors

    init(context: HomeWidgetContext, done: @escaping (Bool) -> Void) {
        self.context = context
        self.done = done
        _colors = State(initialValue: EditedColors(context))
    }

    var body: some View {
        let month = JDate.now().withTimeAtStartOfDay.withDayOfMonth(1)
        WidgetConfigureScreen(title: "Monthly view", bgRGB: $colors.bgRGB, bgAlpha: $colors.bgAlpha, textColor: $colors.text,
                              previewHeight: 340, onCancel: { done(false) },
                              onSave: { colors.store(context); done(true) }) {
            MonthlyWidgetBody(days: monthDays(CalendarStore.shared, month: month),
                              title: Formatter.getLongMonthYear(Formatter.getDayCodeFromDateTime(month)),
                              bg: colors.bg, text: colors.text, showGoToToday: false)
                .allowsHitTesting(false)
        } extra: {
            EmptyView()
        }
        .fossifyTheme()
    }
}
