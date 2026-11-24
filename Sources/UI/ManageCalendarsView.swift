import FossifyCommons
import SwiftUI

/// ManageCalendarsActivity.
struct ManageCalendarsView: View {
    @Environment(CalendarStore.self) private var store
    @Environment(\.palette) private var palette
    @State private var editing: CalendarEntity?
    @State private var adding = false
    @State private var deleting: CalendarEntity?

    var body: some View {
        VStack(spacing: 0) {
            TopBar(title: "Calendars") {
                IconButton(icon: "plus") { adding = true }
            }
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(store.calendars) { c in
                        HStack(spacing: 16) {
                            Text(c.displayTitle).font(.system(size: palette.fontSize)).foregroundStyle(palette.textColor)
                            Spacer()
                            ColorDot(color: c.color)
                            Menu {
                                Button { editing = c } label: { Label("Edit", systemImage: "pencil") }
                                Button(role: .destructive) { delete(c) } label: { Label("Delete", systemImage: "trash") }
                            } label: {
                                Image(systemName: "ellipsis").rotationEffect(.degrees(90)).frame(width: 36, height: 44)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 6)
                        .contentShape(Rectangle())
                        .onTapGesture { editing = c }
                    }
                }
            }
        }
        .background(palette.backgroundColor.ignoresSafeArea())
        .sheet(item: $editing) { EditCalendarDialog(calendar: $0) }
        .sheet(isPresented: $adding) { EditCalendarDialog(calendar: nil) }
        .sheet(item: $deleting) { c in
            RadioDialog(title: nil, items: [(false, "Move affected events into the default calendar"), (true, "Permanently remove affected events")],
                        selected: false) { remove in store.deleteCalendars([c], deleteEvents: remove) }
        }
    }

    private func delete(_ c: CalendarEntity) {
        if c.isSyncedCalendar {
            store.toast = "To remove a CalDAV calendar you have to unsynchronize it"
        } else if c.id == LOCAL_CALENDAR_ID {
            store.toast = "Built-in calendar cannot be deleted"
        } else if store.doCalendarsContainEvents([c.id]) {
            deleting = c
        } else {
            store.deleteCalendars([c], deleteEvents: true)
        }
    }
}
