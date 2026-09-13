import SwiftUI

/// One place for every curve in the app so nothing feels out of step.
enum Motion {
    /// The main open/close of the shelf. Heavy but quick, like the iPhone island.
    static let island = Animation.spring(response: 0.30, dampingFraction: 0.82, blendDuration: 0.05)
    /// Smaller inner transitions: tab swaps, row inserts.
    static let snappy = Animation.spring(response: 0.22, dampingFraction: 0.88)
    /// Content fading in after geometry settled.
    static let content = Animation.easeOut(duration: 0.13)
    /// Live-activity pills sliding in and out of the closed notch.
    static let activity = Animation.spring(response: 0.38, dampingFraction: 0.84)
    /// The basket hopping onto screen.
    static let basket = Animation.spring(response: 0.30, dampingFraction: 0.72)
}

extension View {
    /// Scale + fade used everywhere content swaps inside the shelf.
    func islandTransition(anchor: UnitPoint = .top) -> some View {
        transition(
            .asymmetric(
                insertion: .scale(scale: 0.97, anchor: anchor).combined(with: .opacity),
                removal: .opacity
            )
        )
    }
}
