import SwiftUI

/// Measurement side of `ContentView.settleScroll`. `top` is the top edge of
/// the block being steered, in the document scroll view's coordinate space,
/// or nil while that block is not laid out; `generation` lets a newer settle
/// loop retire an older one. A plain reference box rather than observed
/// state: `onPreferenceChange` writes it on every layout pass, and those
/// writes must not re-evaluate the view body.
final class ScrollSettleProbe {
    static let coordinateSpace = "documentScroll"
    var top: CGFloat?
    var generation = 0
}

/// Top edge of the block the settle loop is steering. Only that block
/// reports it.
struct SettleTopKey: PreferenceKey {
    static let defaultValue: CGFloat? = nil
    static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) {
        value = value ?? nextValue()
    }
}
