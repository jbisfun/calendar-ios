import FossifyCommons
import SwiftUI
import UIKit

/// A screen of the main fragment stack: a view type opened at `anchor` (a day code, or the week
/// start for the weekly view). Opening a day from the monthly view pushes another one, like
/// Android's fragment back stack.
struct MainPage: Identifiable, Equatable {
    var view: CalendarViewType
    var anchor: String
    var id = UUID()
}

/// MainActivity.
struct MainView: View {
    @Environment(CalendarStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(Config.self) private var config
    @Environment(\.palette) private var palette

    @State private var stack: [MainPage] = []
    @State private var currentCode = Formatter.getTodayCode()
    @State private var query = ""
    @State private var searching = false
    @FocusState private var searchFocused: Bool
    @State private var fabExtended = false
    @State private var searchSelection = Set<String>()

    @State private var showChangeView = false
    @State private var showFilter = false
    @State private var showGoToDate = false
    @State private var showHolidays = false
    @State private var showHolidayReminders: Set<String>?
    @State private var contactReminders: Int?  // BIRTHDAY_EVENT / ANNIVERSARY_EVENT

    private var top: MainPage { stack.last ?? MainPage(view: config.view, anchor: Formatter.getTodayCode()) }

    var body: some View {
        VStack(spacing: 0) {
            if !searchSelection.isEmpty {
                SelectionBar(selection: $searchSelection, events: searchEvents)
            } else {
                searchBar
            }
            ZStack(alignment: .bottomTrailing) {
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                if query.isEmpty { fab }
            }
            if query.isEmpty { QuickFilterBar() }
        }
        .background(palette.backgroundColor.ignoresSafeArea())
        .onAppear {
            if stack.isEmpty { stack = [MainPage(view: config.view, anchor: initialAnchor(config.view, from: JDate.now()))] }
        }
        .sheet(isPresented: $showChangeView) {
            RadioDialog(title: nil, items: CalendarViewType.pickable.map { ($0, $0.title) }, selected: config.view) { updateView($0) }
        }
        .sheet(isPresented: $showFilter) {
            SelectCalendarsDialog(selected: config.displayCalendars) { new in
                if config.displayCalendars != new {
                    config.displayCalendars = new
                    store.refresh()
                }
            }
        }
        .sheet(isPresented: $showGoToDate) {
            DatePickerDialog(date: dateForCode(currentCode)) { date in goTo(JDate(date)) }
        }
        .sheet(isPresented: $showHolidays) {
            ManageHolidaysDialog { paths in
                if paths.isEmpty {
                    refreshHolidays(paths, reminders: config.holidayReminders)
                } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { showHolidayReminders = paths }
                }
            }
        }
        .sheet(item: Binding(get: { showHolidayReminders.map { HolidaySelection(paths: $0) } }, set: { showHolidayReminders = $0?.paths })) { sel in
            SetRemindersDialog(eventType: OTHER_EVENT, initial: config.holidayReminders) { refreshHolidays(sel.paths, reminders: $0) }
        }
        .sheet(item: Binding(get: { contactReminders.map(IntItem.init) }, set: { contactReminders = $0?.value })) { item in
            SetRemindersDialog(eventType: item.value, initial: item.value == BIRTHDAY_EVENT ? config.birthdayReminders : config.anniversaryReminders) {
                addContactEvents(birthdays: item.value == BIRTHDAY_EVENT, reminders: $0)
            }
        }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if !query.isEmpty {
            SearchResults(query: query, selection: $searchSelection)
        } else {
            let page = top
            Group {
                switch page.view {
                case .monthly:
                    MonthHolder(anchor: page.anchor, current: $currentCode, onOpenDay: { openDay($0) }, onTitle: { showGoToDate = true })
                case .monthlyDaily:
                    MonthDayHolder(anchor: page.anchor, current: $currentCode, onTitle: { showGoToDate = true })
                case .daily:
                    DayHolder(anchor: page.anchor, current: $currentCode, onTitle: { showGoToDate = true })
                case .weekly:
                    WeekHolder(anchor: page.anchor, current: $currentCode, onOpenDay: { openDay($0) })
                case .yearly:
                    YearHolder(anchor: page.anchor, current: $currentCode, onOpenMonth: { openMonth($0) }, onTitle: { showGoToDate = true })
                default:
                    EventListHolder()
                }
            }
            .id(page.id)
        }
    }

    private var fab: some View {
        let hidden = stack.count <= 1 && (top.view == .yearly || top.view == .weekly)
        return ZStack(alignment: .bottomTrailing) {
            if fabExtended {
                palette.backgroundColor.opacity(0.8).ignoresSafeArea()
                    .onTapGesture { withAnimation { fabExtended = false } }
                VStack(alignment: .trailing, spacing: 20) {
                    Button { fabExtended = false; openNew(task: true) } label: {
                        HStack(spacing: 16) {
                            Text("Task").foregroundStyle(palette.textColor)
                            Image(systemName: "checkmark.circle").font(.system(size: 18)).foregroundStyle(palette.onPrimary)
                                .frame(width: 44, height: 44).background(Circle().fill(palette.primaryColor))
                        }
                    }
                    HStack(spacing: 16) {
                        Text("Event").foregroundStyle(palette.textColor).onTapGesture { fabExtended = false; openNew(task: false) }
                        Color.clear.frame(width: 56, height: 56)
                    }
                }
                .buttonStyle(.plain)
                .padding(.trailing, 22)
                .padding(.bottom, 16)
            }
            if !hidden {
                Fab(icon: fabExtended ? "calendar" : "plus") {
                    if config.allowCreatingTasks && !fabExtended {
                        withAnimation { fabExtended = true }
                    } else {
                        fabExtended = false
                        openNew(task: false)
                    }
                }
                .padding(16)
            }
        }
    }

    // MARK: Search menu

    private var searchBar: some View {
        HStack(spacing: 0) {
            if stack.count > 1 && !searching {
                IconButton(icon: "arrow.left") { stack.removeLast() }
            } else if !searching {
                CloseAppButton()
            }
            Button {
                if searching {
                    query = ""
                    searching = false
                    searchFocused = false
                } else {
                    searching = true
                    searchFocused = true
                }
            } label: {
                Image(systemName: searching ? "arrow.left" : "magnifyingglass").font(.system(size: 18)).frame(width: 48, height: 48)
            }
            TextField("", text: $query, prompt: Text("Search").foregroundStyle(palette.secondaryText))
                .focused($searchFocused)
                .submitLabel(.search)
                .autocorrectionDisabled()
                .onChange(of: searchFocused) { _, f in if f { searching = true } }
            if !query.isEmpty {
                IconButton(icon: "xmark") { query = "" }
            } else {
                if shouldGoToTodayBeVisible && !searching {
                    IconButton(icon: "calendar.badge.clock") { goTo(JDate.now()) }
                }
                IconButton(icon: "square.grid.2x2") { showChangeView = true }
            }
            menu
        }
        .foregroundStyle(palette.textColor)
        .background(Capsule().fill(palette.surface))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var menu: some View {
        Menu {
            if store.calendars.count > 1 || config.displayCalendars.isEmpty {
                Button { showFilter = true } label: { Label("Filter events by calendar", systemImage: "line.3.horizontal.decrease") }
            }
            if config.caldavSync {
                Button { store.refreshSystemCalendars(showToast: true) } label: { Label("Refresh CalDAV calendars", systemImage: "arrow.clockwise") }
            }
            if top.view != .eventsList {
                Button { showGoToDate = true } label: { Label("Go to date", systemImage: "calendar") }
            }
            if top.view != .monthlyDaily {
                Button { printView() } label: { Label("Print", systemImage: "printer") }
            }
            Button { showHolidays = true } label: { Label("Manage holidays", systemImage: "globe") }
            Button { tryAddContactEvents(BIRTHDAY_EVENT) } label: { Label("Add contact birthdays", systemImage: "gift") }
            Button { tryAddContactEvents(ANNIVERSARY_EVENT) } label: { Label("Add contact anniversaries", systemImage: "heart") }
            Button { router.push(.settings) } label: { Label("Settings", systemImage: "gearshape") }
            Button { router.push(.about) } label: { Label("About", systemImage: "info.circle") }
        } label: {
            Image(systemName: "ellipsis").rotationEffect(.degrees(90)).font(.system(size: 18)).frame(width: 44, height: 48)
        }
    }

    // MARK: Navigation

    private func initialAnchor(_ view: CalendarViewType, from date: JDate) -> String {
        switch view {
        case .weekly: return Formatter.getDayCodeFromDateTime(getFirstDayOfWeekDt(date))
        case .yearly: return "\(date.year)0101"
        default: return Formatter.getDayCodeFromDateTime(date)
        }
    }

    private func dateForCode(_ code: String) -> Date { Formatter.getLocalDateTimeFromCode(code).date }

    private var shouldGoToTodayBeVisible: Bool {
        let today = JDate.now()
        switch top.view {
        case .monthly, .monthlyDaily: return currentCode.prefix(6) != Formatter.getTodayCode().prefix(6)
        case .daily: return currentCode != Formatter.getTodayCode()
        case .weekly: return currentCode != initialAnchor(.weekly, from: today)
        case .yearly: return currentCode.prefix(4) != String(today.year)
        default: return false
        }
    }

    private func goTo(_ date: JDate) {
        guard !stack.isEmpty else { return }
        var page = stack[stack.count - 1]
        page.anchor = initialAnchor(page.view, from: date)
        page.id = UUID()
        stack[stack.count - 1] = page
        currentCode = page.anchor
    }

    /// updateView() + getDateCodeToDisplay()
    private func updateView(_ view: CalendarViewType) {
        query = ""
        searching = false
        let order: [CalendarViewType] = [.daily, .weekly, .monthly, .yearly]
        let cur = order.firstIndex(of: top.view == .monthlyDaily ? .monthly : top.view)
        let new = order.firstIndex(of: view == .monthlyDaily ? .monthly : view)
        var date = JDate.now()
        if top.view != .eventsList && view != .eventsList, let cur, let new, cur <= new {
            date = Formatter.getLocalDateTimeFromCode(currentCode)
        }
        config.storedView = view.rawValue
        let page = MainPage(view: view, anchor: initialAnchor(view, from: date))
        stack = [page]
        currentCode = page.anchor
    }

    private func openDay(_ code: String) {
        guard top.view != .daily else { return }
        stack.append(MainPage(view: .daily, anchor: code))
        currentCode = code
    }

    private func openMonth(_ code: String) {
        guard top.view != .monthly else { return }
        stack.append(MainPage(view: .monthly, anchor: code))
        currentCode = code
    }

    private func newEventDayCode() -> String {
        switch top.view {
        case .weekly:
            let start = Formatter.getDayStartTS(currentCode)
            let now = getNowSeconds()
            return now > start && now < start + Int64(WEEK) ? Formatter.getTodayCode() : currentCode
        case .monthly:
            return currentCode.prefix(6) == Formatter.getTodayCode().prefix(6) ? Formatter.getTodayCode() : String(currentCode.prefix(6)) + "01"
        case .eventsList: return Formatter.getTodayCode()
        default: return currentCode
        }
    }

    private func openNew(task: Bool) {
        let allowChangingDay = top.view != .daily && top.view != .monthlyDaily
        if task {
            router.newTask(dayCode: newEventDayCode(), allowChangingDay: allowChangingDay)
        } else {
            router.newEvent(dayCode: newEventDayCode(), allowChangingDay: allowChangingDay)
        }
    }

    private func printView() {
        let size = CGSize(width: 794, height: 1123)
        let page = top
        let view: AnyView
        switch page.view {
        case .monthly: view = AnyView(PrintableMonth(code: currentCode))
        case .yearly: view = AnyView(PrintableYear(year: Int(currentCode.prefix(4)) ?? JDate.now().year))
        case .weekly: view = AnyView(PrintableWeek(startCode: currentCode))
        case .daily: view = AnyView(PrintableList(title: Formatter.getDayTitle(currentCode),
                                                  from: Formatter.getDayStartTS(currentCode), to: Formatter.getDayEndTS(currentCode)))
        default: view = AnyView(PrintableList(title: "Events", from: getNowSeconds() - Int64(config.displayPastEvents * 60),
                                              to: getNowSeconds() + Int64(YEAR)))
        }
        PrintHelper.print(view.environment(store).environment(config)
            .environment(\.palette, Palette(text: 0xFF2D2D2D, background: 0xFFFFFFFF, primary: palette.primary, fontSize: palette.fontSize, dark: false))
            .background(Color.white), size: size)
    }

    // MARK: Holidays, birthdays, anniversaries

    private func refreshHolidays(_ paths: Set<String>, reminders: [Int]) {
        let result = HolidayHelper.updateSelection(store, paths: paths, reminders: reminders)
        store.toast = result == .fail ? "Importing holidays failed" : "Holidays updated"
        store.refresh()
    }

    private func tryAddContactEvents(_ type: Int) {
        ContactEvents.requestPermission { granted in
            if granted { contactReminders = type } else { store.toast = "Please grant the app access to your contacts" }
        }
    }

    private func addContactEvents(birthdays: Bool, reminders: [Int]) {
        let added = ContactEvents.add(store, birthdays: birthdays, reminders: reminders)
        let kind = birthdays ? "birthdays" : "anniversaries"
        switch added {
        case let n where n > 0: store.toast = birthdays ? "Birthdays added successfully" : "Anniversaries added successfully"
        case -1: store.toast = "No new \(kind) have been found"
        default: store.toast = "No \(kind) have been found"
        }
    }

    private var searchEvents: [Event] {
        query.count >= 2 ? store.getEvents(from: 0, to: MAX_SEARCH_YEAR, searchQuery: query) : []
    }
}

struct HolidaySelection: Identifiable {
    let paths: Set<String>
    var id: String { paths.sorted().joined() }
}

struct IntItem: Identifiable {
    let value: Int
    var id: Int { value }
}

/// quick_calendar_filter: toggles the calendars picked in "Manage quick filter calendars".
struct QuickFilterBar: View {
    @Environment(CalendarStore.self) private var store
    @Environment(Config.self) private var config
    @Environment(\.palette) private var palette

    var body: some View {
        let cals = store.calendars.filter { config.quickFilterCalendars.contains(String($0.id)) }
        if !cals.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(cals) { c in
                        let on = config.displayCalendars.contains(String(c.id))
                        Button {
                            if on { config.displayCalendars.remove(String(c.id)) } else { config.displayCalendars.insert(String(c.id)) }
                            if config.displayCalendars.isEmpty && !config.wasFilteredOutWarningShown {
                                store.toast = "You have filtered out all calendars"
                                config.wasFilteredOutWarningShown = true
                            }
                            store.refresh()
                        } label: {
                            VStack(spacing: 4) {
                                Text(c.displayTitle).font(.system(size: 14)).lineLimit(1)
                                Rectangle().fill(Color(argb: c.color)).frame(height: 4)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .opacity(on ? 1 : 0.4)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 8)
            }
            .background(palette.backgroundColor)
        }
    }
}

/// Action mode for event lists (cab_event_list.xml / cab_day.xml): share, delete.
struct SelectionBar: View {
    @Environment(CalendarStore.self) private var store
    @Environment(\.palette) private var palette
    @Binding var selection: Set<String>
    let events: [Event]
    @State private var share: ShareItem?
    @State private var confirmDelete = false

    var body: some View {
        let selected = events.filter { selection.contains($0.occurrenceKey) }
        HStack(spacing: 0) {
            IconButton(icon: "xmark") { selection.removeAll() }
            Text("\(selection.count)").font(.system(size: 20, weight: .medium)).padding(.leading, 8)
            Spacer()
            IconButton(icon: "checklist") { selection = Set(events.map(\.occurrenceKey)) }
            IconButton(icon: "square.and.arrow.up") {
                let unique = Dictionary(selected.map { ($0.ekID ?? "\($0.id ?? 0)", $0) }, uniquingKeysWith: { a, _ in a }).values
                if let url = IcsExporter.temporaryFile(Array(unique), store: store) { share = ShareItem(url: url) }
            }
            IconButton(icon: "trash") { confirmDelete = true }
        }
        .foregroundStyle(palette.onPrimary)
        .padding(.horizontal, 4)
        .frame(height: 64)
        .background(palette.primaryColor.ignoresSafeArea(edges: .top))
        .sheet(item: $share) { ShareSheet(items: [$0.url]) }
        .sheet(isPresented: $confirmDelete) {
            DeleteEventDialog(hasRepeatable: selected.contains { $0.repeatInterval > 0 }) { scope in
                store.delete(selected, scope: scope)
                selection.removeAll()
            }
        }
    }
}

/// MainActivity search: events matching the query, grouped like the event list.
struct SearchResults: View {
    @Environment(CalendarStore.self) private var store
    @Environment(Router.self) private var router
    @Environment(Config.self) private var config
    let query: String
    @Binding var selection: Set<String>

    var body: some View {
        if query.count < 2 {
            Placeholder(text: "Type at least 2 characters to start the search.")
        } else {
            let _ = store.revision
            let events = store.getEvents(from: 0, to: MAX_SEARCH_YEAR, searchQuery: query)
            if events.isEmpty {
                Placeholder(text: config.displayCalendars.isEmpty ? "You have filtered out all calendars" : "No items found.")
            } else {
                let items = getEventListItems(events)
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            EventListItems(items: items, selection: $selection) { router.open($0.ref) }
                        }
                        .padding(.bottom, 32)
                    }
                    .onAppear {
                        if let first = items.first(where: { if case let .day(_, _, _, past) = $0 { return !past } else { return false } }) {
                            proxy.scrollTo(first.id, anchor: .top)
                        }
                    }
                }
            }
        }
    }
}
