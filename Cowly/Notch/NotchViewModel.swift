import AppKit
import Observation
import SwiftUI

enum ShelfState: Equatable, Sendable {
    case closed
    case peek
    case open
}

enum ShelfTab: String, CaseIterable, Identifiable, Sendable {
    case home
    case tray
    case droplets

    var id: String { rawValue }

    var symbol: String {
        switch self {
        case .home: "house.fill"
        case .tray: "tray.fill"
        case .droplets: "square.grid.2x2.fill"
        }
    }

    var title: String {
        switch self {
        case .home: "Home"
        case .tray: "Tray"
        case .droplets: "Droplets"
        }
    }
}

/// Drives the shelf: what state it is in, which screen it lives on and what the
/// window should currently be swallowing clicks for.
@MainActor
@Observable
final class NotchViewModel {
    static let shared = NotchViewModel()

    private(set) var geometry: NotchGeometry = .fallback
    var state: ShelfState = .closed
    var tab: ShelfTab = .home
    /// Set while a file drag is hovering the shelf.
    var isDropTargeted = false
    /// A transient pill — a HUD, a battery alert, a finished timer. Outranks
    /// anything long-running, because it is a reaction to something you just
    /// did and it disappears on its own.
    private(set) var transientActivity: LiveActivity?

    /// What the closed shelf shows right now.
    var activity: LiveActivity? { transientActivity ?? persistentActivity }

    /// Long-running work that deserves to stay visible while the shelf is
    /// closed: a focus session, a countdown.
    var persistentActivity: LiveActivity? {
        let pomodoro = PomodoroEngine.shared
        if pomodoro.isRunning {
            return LiveActivity(
                id: Self.pomodoroActivityID,
                style: .expanded,
                leadingSymbol: "timer",
                leadingTint: pomodoro.phase.tint,
                title: pomodoro.phase.label,
                progress: pomodoro.progress,
                trailingText: pomodoro.remaining.clockLabel,
                duration: nil
            )
        }
        if let soonest = TimerEngine.shared.soonest {
            return LiveActivity(
                id: Self.timerActivityID,
                style: .expanded,
                leadingSymbol: "hourglass",
                leadingTint: Theme.Palette.warning,
                title: soonest.label,
                progress: soonest.progress,
                trailingText: soonest.remaining.clockLabel,
                duration: nil
            )
        }
        return nil
    }

    private static let pomodoroActivityID = UUID()
    private static let timerActivityID = UUID()

    private var hoverTask: Task<Void, Never>?
    private var closeTask: Task<Void, Never>?
    private var activityTask: Task<Void, Never>?

    /// Non-zero while something modal-ish is on screen (a pop-up menu, a share
    /// sheet, a Quick Look window, a drag in flight). The shelf must not close
    /// under any of those, even though the pointer has left its bounds.
    private(set) var interactionLock = 0
    private(set) var isPointerInside = false
    /// Pinned shelves stay open until you unpin or press Escape.
    var isPinned = false

    private init() {}

    // MARK: - Interaction locking

    func beginInteraction() {
        interactionLock += 1
        closeTask?.cancel()
    }

    func endInteraction() {
        interactionLock = max(0, interactionLock - 1)
        guard interactionLock == 0, !isPointerInside else { return }
        hoverEnded()
    }

    /// Runs `body` with the shelf pinned open, then re-evaluates hover.
    func holdingOpen(_ body: () -> Void) {
        beginInteraction()
        body()
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(250))
            self?.endInteraction()
        }
    }

    // MARK: - Geometry

    func refreshGeometry(for screen: NSScreen?, force: Bool = false) {
        guard let screen = screen ?? NSScreen.preferred else { return }
        // Per-display overrides win; anything left unset falls back to global.
        let profile = DisplayRegistry.shared.profile(for: screen)
        let next = NotchGeometry.measure(
            for: screen,
            widthScale: profile.widthScale ?? Preferences.shared.shelfWidthScale,
            islandFraction: profile.islandFraction ?? 0.11
        )
        if force || next != geometry { geometry = next }
        if let preferred = profile.tab, state == .closed, tab != preferred { tab = preferred }
        activeDisplayID = profile.id
    }

    /// Identifier of the display the shelf is currently on.
    private(set) var activeDisplayID: String = ""

    /// Glass dimming for the display the shelf is on.
    var glassDimming: Double {
        DisplayRegistry.shared.profile(forID: activeDisplayID).glassDimming
            ?? Preferences.shared.glassDimming
    }

    /// Size the shelf renders at right now.
    var currentSize: CGSize {
        switch state {
        case .closed:
            if let activity {
                return CGSize(
                    width: geometry.closedSize.width + activity.extraWidth,
                    height: max(geometry.closedSize.height, activity.height)
                )
            }
            if showsIdleMusic {
                // Just enough room for artwork on one side and bars on the other.
                return CGSize(
                    width: geometry.closedSize.width + 84,
                    height: max(geometry.closedSize.height, 30)
                )
            }
            return geometry.closedSize
        case .peek:
            // Grow downward only: widening here would slide the shelf out from
            // behind the bezel, which looks broken on a notched Mac.
            return CGSize(
                width: geometry.closedSize.width,
                height: geometry.closedSize.height + 5
            )
        case .open:
            // The detached tab bar hangs below the panel but is part of the
            // same interactive silhouette.
            return CGSize(
                width: geometry.openSize.width,
                height: openPanelHeight + Self.tabBarBlock
            )
        }
    }

    /// Gap + height of the floating tab switcher under the open shelf.
    static let tabBarBlock: CGFloat = 56

    var layout: ShelfLayout { ShelfLayout(width: geometry.openSize.width) }

    var topInset: CGFloat {
        geometry.hasHardwareNotch ? geometry.closedSize.height + 2 : 12
    }

    /// Height the open shelf needs for the tab that is showing.
    var openPanelHeight: CGFloat {
        layout.contentHeight(
            for: tab,
            topInset: topInset,
            hasShelfWidgets: !Preferences.shared.orderedShelfDroplets.isEmpty
        ).rounded()
    }

    var panelHeight: CGFloat {
        state == .open ? openPanelHeight : currentSize.height
    }

    /// Where the shelf sits inside the oversized panel, in SwiftUI coordinates.
    var currentRect: CGRect {
        let size = currentSize
        return CGRect(
            x: (geometry.windowFrame.width - size.width) / 2,
            y: 0,
            width: size.width,
            height: size.height
        )
    }

    /// Slightly larger than the shelf so the pointer does not fall through the
    /// gap between the notch and the shelf while it animates.
    var interactiveRect: CGRect {
        currentRect.insetBy(dx: -Theme.Metrics.hoverPadding, dy: -Theme.Metrics.hoverPadding)
            .offsetBy(dx: 0, dy: Theme.Metrics.hoverPadding)
    }

    /// Whether the closed shelf should peek artwork + bars around the notch.
    /// Off by default so the closed shelf stays exactly notch-shaped.
    var showsIdleMusic: Bool {
        Preferences.shared.showNowPlayingPeek
            && activity == nil
            && MediaController.shared.now.isPlaying
    }

    /// A closed shelf over a real notch has no shoulders at all — it is exactly
    /// the cut-out, so any flare would show as a dark wing in the menu bar. A
    /// floating island has no bezel to hide behind, so it keeps its corners.
    var cornerTop: CGFloat {
        switch state {
        case .open: Radius.shoulder
        case .peek: geometry.hasHardwareNotch ? 5 : 10
        case .closed: geometry.hasHardwareNotch ? 0 : 10
        }
    }

    var cornerBottom: CGFloat {
        switch state {
        case .open: Radius.shelf
        case .peek: 18
        case .closed: geometry.hasHardwareNotch ? 11 : 16
        }
    }

    // MARK: - State transitions

    func pointerMoved(inside: Bool) {
        guard isPointerInside != inside else { return }
        isPointerInside = inside
        inside ? hoverBegan() : hoverEnded()
    }

    func hoverBegan() {
        closeTask?.cancel()
        guard Preferences.shared.openOnHover else {
            if state == .closed { withAnimation(Motion.island) { state = .peek } }
            return
        }
        guard state != .open else { return }
        withAnimation(Motion.island) { state = .peek }
        hoverTask?.cancel()
        hoverTask = Task { [weak self] in
            let delay = Preferences.shared.hoverDelay
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled else { return }
            self?.open()
        }
    }

    func hoverEnded() {
        hoverTask?.cancel()
        guard !isDropTargeted, interactionLock == 0, !isPinned else { return }
        closeTask?.cancel()
        closeTask = Task { [weak self] in
            // Generous, so crossing a gap or overshooting a button is forgiven.
            try? await Task.sleep(for: .milliseconds(420))
            guard !Task.isCancelled else { return }
            guard let self, !self.isPointerInside, self.interactionLock == 0 else { return }
            self.close()
        }
    }

    func open(tab: ShelfTab? = nil) {
        hoverTask?.cancel()
        closeTask?.cancel()
        if let tab { self.tab = tab }
        guard state != .open else { return }
        Haptics.tap(.alignment)
        withAnimation(Motion.island) { state = .open }
    }

    func togglePin() {
        isPinned.toggle()
        Haptics.tap(.levelChange)
        if isPinned { open() } else if !isPointerInside { hoverEnded() }
    }

    func close(force: Bool = false) {
        if force { isPinned = false }
        hoverTask?.cancel()
        closeTask?.cancel()
        guard state != .closed else { return }
        withAnimation(Motion.island) {
            state = .closed
            isDropTargeted = false
        }
    }

    func toggle() {
        state == .open ? close() : open()
    }

    func select(_ tab: ShelfTab) {
        guard self.tab != tab else { return }
        Haptics.tap(.levelChange)
        withAnimation(Motion.snappy) { self.tab = tab }
    }

    // MARK: - Drag targeting

    func dragEntered() {
        guard Preferences.shared.openOnDrag else { return }
        isDropTargeted = true
        open(tab: .tray)
    }

    func dragExited() {
        isDropTargeted = false
        hoverEnded()
    }

    // MARK: - Live activities

    /// Shows a transient pill in the closed shelf (volume, charging, a timer
    /// that just finished).
    func present(_ activity: LiveActivity) {
        activityTask?.cancel()
        withAnimation(Motion.activity) { transientActivity = activity }
        guard let duration = activity.duration else { return }
        activityTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard !Task.isCancelled else { return }
            self?.dismissActivity(id: activity.id)
        }
    }

    func dismissActivity(id: UUID? = nil) {
        if let id, transientActivity?.id != id { return }
        activityTask?.cancel()
        withAnimation(Motion.activity) { transientActivity = nil }
    }
}
