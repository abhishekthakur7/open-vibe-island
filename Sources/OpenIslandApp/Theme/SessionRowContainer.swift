import SwiftUI

/// Where a session row is being rendered: as one entry of the opened panel's
/// list, or as the single card shown when a notification opened the notch.
enum IslandSessionRowPresentation {
    case list
    case notification
}

/// Owns the hover-highlight state shared by every session row (AB-297).
///
/// Hover used to be `@State` inside `IslandSessionRow`, which would force
/// each themed row to re-implement the same tracking. The container instead
/// wraps whatever row view is being rendered and hands the current highlight
/// down as a plain value.
///
/// Two things are load-bearing and deliberately unchanged from the row-owned
/// version: `.onHover` is attached directly to the row with no layout in
/// between, so the hover hit-area is still the row's own `contentShape`; and
/// the guard is evaluated inside the callback, so turning `isInteractive` off
/// stops further updates without clearing an already-set highlight.
/// `.notification` never highlights.
struct SessionRowContainer<Row: View>: View {
    var presentation: IslandSessionRowPresentation = .list
    var isInteractive: Bool = true
    @ViewBuilder let row: (Bool) -> Row

    @State private var isHighlighted = false

    var body: some View {
        row(isHighlighted)
            .onHover { hovering in
                guard isInteractive, presentation != .notification else { return }
                isHighlighted = hovering
            }
    }
}
