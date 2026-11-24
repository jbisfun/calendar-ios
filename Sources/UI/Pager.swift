import SwiftUI

/// MyViewPager: horizontally paged, lazily built pages around an anchor (offset 0).
struct Pager<Page: View>: View {
    @Binding var index: Int
    var range: ClosedRange<Int> = -600...600
    @ViewBuilder let page: (Int) -> Page
    @State private var position: Int?

    var body: some View {
        ScrollView(.horizontal) {
            LazyHStack(spacing: 0) {
                ForEach(range, id: \.self) { i in
                    page(i)
                        .containerRelativeFrame([.horizontal, .vertical])
                        .id(i)
                }
            }
            .scrollTargetLayout()
        }
        .scrollTargetBehavior(.paging)
        .scrollIndicators(.hidden)
        .scrollPosition(id: $position)
        .onAppear { position = index }
        .onChange(of: position) { _, p in
            if let p, p != index { index = p }
        }
        .onChange(of: index) { _, i in
            if position != i { withAnimation { position = i } }
        }
    }
}
