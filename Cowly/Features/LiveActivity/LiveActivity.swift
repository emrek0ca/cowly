import SwiftUI

/// A transient pill that takes over the closed shelf, iPhone-island style.
struct LiveActivity: Identifiable, Equatable, Sendable {
    enum Style: Equatable, Sendable {
        /// Only a small glyph on each side of the notch.
        case compact
        /// Notch grows into a wide pill with a title and trailing detail.
        case expanded
    }

    let id: UUID
    var style: Style
    var leadingSymbol: String
    var leadingTint: Color
    var title: String
    var subtitle: String?
    /// Filled progress ring / bar, 0...1. Nil hides it.
    var progress: Double?
    var trailingText: String?
    /// Auto-dismiss after this many seconds. Nil keeps it until dismissed.
    var duration: Double?

    init(
        id: UUID = UUID(),
        style: Style = .expanded,
        leadingSymbol: String,
        leadingTint: Color = Theme.Palette.accent,
        title: String,
        subtitle: String? = nil,
        progress: Double? = nil,
        trailingText: String? = nil,
        duration: Double? = 3.5
    ) {
        self.id = id
        self.style = style
        self.leadingSymbol = leadingSymbol
        self.leadingTint = leadingTint
        self.title = title
        self.subtitle = subtitle
        self.progress = progress
        self.trailingText = trailingText
        self.duration = duration
    }

    var isExpanded: Bool { style == .expanded }
    /// Room for the content on both sides of the notch, plus the side padding.
    var extraWidth: CGFloat { style == .expanded ? 248 : 72 }
    var height: CGFloat { style == .expanded ? 50 : 36 }
}
