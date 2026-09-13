import AppKit
import SwiftUI

// Development diagnostics.
//
// This app has no regular window and lives on top of the menu bar, so the
// usual ways of checking it — screenshots, clicking around — are not always
// available. These modes let the shelf be inspected from the command line:
//
//     Cowly --hit-test    do clicks reach the controls?
//     Cowly --ai-usage    what do the agent logs actually say?
//
// Neither touches real preferences or the tray.

/// Verifies that clicks actually reach the controls inside the shelf.
///
/// The panel is much larger than the shelf and only swallows clicks inside the
/// live silhouette, so a mistake in that hit-test maths silently makes every
/// button dead. This walks the real view tree and reports what a click at each
/// control's centre would land on.
///
/// `Cowly.app/Contents/MacOS/Cowly --hit-test`
@MainActor
enum HitTestProbe {
    static var isRequested: Bool { CommandLine.arguments.contains("--hit-test") }

    static func run() {
        NotchWindowController.shared.install()
        let vm = NotchViewModel.shared
        vm.open(tab: .home)
        // Pin it: with no real pointer on screen the shelf would auto-close
        // before the probe runs, and every hit would look like a failure.
        vm.isPinned = true

        // Let SwiftUI lay the shelf out before probing it.
        Task {
            try? await Task.sleep(for: .milliseconds(700))
            probe()
            exit(0)
        }
    }

    private static func probe() {
        guard let panel = NotchWindowController.shared.panel,
              let host = panel.contentView else {
            print("FAIL: no panel"); return
        }
        let vm = NotchViewModel.shared
        NotchWindowController.shared.forceSync()

        let rect = vm.currentRect
        let panelHeight = vm.panelHeight
        let probes: [(String, CGPoint)] = [
            ("play/pause", CGPoint(x: rect.midX, y: panelHeight - 34)),
            ("previous", CGPoint(x: rect.midX - 44, y: panelHeight - 34)),
            ("output picker", CGPoint(x: rect.minX + 60, y: panelHeight - 34)),
            ("scrubber", CGPoint(x: rect.midX, y: panelHeight - 78)),
            ("tab: home", CGPoint(x: rect.midX - 18, y: panelHeight + 25)),
            ("tab: tray", CGPoint(x: rect.midX + 18, y: panelHeight + 25)),
            ("pin", CGPoint(x: rect.midX - 72, y: panelHeight + 25)),
            ("outside (should miss)", CGPoint(x: rect.minX - 80, y: panelHeight / 2))
        ]

        print("shelf rect: \(rect), panel height: \(panelHeight)")
        print("interactive rect: \(vm.interactiveRect)")
        var failures = 0
        for (name, point) in probes {
            // Convert the SwiftUI top-left point into the window's coordinates.
            let windowPoint = CGPoint(x: point.x, y: host.bounds.height - point.y)
            let hit = host.hitTest(windowPoint)
            let shouldHit = !name.contains("should miss")
            let didHit = hit != nil
            let ok = didHit == shouldHit
            if !ok { failures += 1 }
            print("\(ok ? "OK  " : "FAIL") \(name.padding(toLength: 22, withPad: " ", startingAt: 0)) -> \(hit.map { String(describing: type(of: $0)) } ?? "nil")")
        }
        print(failures == 0 ? "\nWindow-level hit tests behaved as expected." : "\n\(failures) probe(s) misbehaved.")
    }

}

/// Prints what the AI-limits droplet reads from the local agent logs.
///
/// `Cowly.app/Contents/MacOS/Cowly --ai-usage`
@MainActor
enum AIUsageProbe {
    static var isRequested: Bool { CommandLine.arguments.contains("--ai-usage") }

    static func run() {
        AIUsageMonitor.shared.refresh()
        Task {
            try? await Task.sleep(for: .seconds(6))
            for tool in AIUsageMonitor.shared.tools {
                print("\(tool.name): installed=\(tool.isInstalled) headline=\(tool.headline)")
                if let primary = tool.primary {
                    print("   primary  \(primary.label) used=\(primary.usedFraction.map { String(format: "%.0f%%", $0 * 100) } ?? "-") tokens=\(primary.tokens.map(String.init) ?? "-") \(primary.resetLabel ?? "")")
                }
                if let secondary = tool.secondary {
                    print("   secondary \(secondary.label) used=\(secondary.usedFraction.map { String(format: "%.0f%%", $0 * 100) } ?? "-") tokens=\(secondary.tokens.map(String.init) ?? "-") \(secondary.resetLabel ?? "")")
                }
                if let note = tool.note { print("   note: \(note)") }
            }
            exit(0)
        }
    }
}

/// Exercises the droplet/shelf preference layer end to end.
///
/// When a toggle looks dead there are two possible culprits — the model or the
/// control wired to it — and guessing between them wastes time. This drives the
/// model directly and checks the value survives a write to disk.
///
/// `Cowly.app/Contents/MacOS/Cowly --prefs-test`
@MainActor
enum PreferencesProbe {
    static var isRequested: Bool { CommandLine.arguments.contains("--prefs-test") }

    static func run() {
        let prefs = Preferences.shared
        let defaults = UserDefaults.standard
        var failures = 0

        func check(_ label: String, _ condition: Bool) {
            if !condition { failures += 1 }
            print("\(condition ? "OK  " : "FAIL") \(label)")
        }

        let original = prefs.enabledDroplets
        let originalOrder = prefs.shelfOrder
        defer {
            prefs.enabledDroplets = original
            prefs.shelfOrder = originalOrder
        }

        print("enabled at start: \(original.sorted().joined(separator: ", "))")

        // Enable
        prefs.setDroplet("weather", enabled: true)
        check("setDroplet(on) updates the set", prefs.isDropletEnabled("weather"))
        check(
            "setDroplet(on) reaches UserDefaults",
            (defaults.stringArray(forKey: "droplets.enabled") ?? []).contains("weather")
        )

        // Disable
        prefs.setDroplet("weather", enabled: false)
        check("setDroplet(off) updates the set", !prefs.isDropletEnabled("weather"))
        check(
            "setDroplet(off) reaches UserDefaults",
            !(defaults.stringArray(forKey: "droplets.enabled") ?? []).contains("weather")
        )

        // Ordering
        prefs.enabledDroplets = ["pomodoro", "timer", "notes", "stats"]
        prefs.shelfOrder = []
        let before = prefs.orderedShelfDroplets.map(\.id)
        print("rail order: \(before.joined(separator: " → "))")
        guard let first = before.first else {
            print("FAIL no shelf widgets to reorder"); exit(1)
        }
        let moved = prefs.moveDroplet(first, by: 2)
        let after = prefs.orderedShelfDroplets.map(\.id)
        check("moveDroplet reports success", moved)
        check("moveDroplet changes the order", after != before)
        check("moveDroplet lands at the right index", after.firstIndex(of: first) == 2)
        print("after move: \(after.joined(separator: " → "))")
        check("moving past the end is refused", !prefs.moveDroplet(first, by: 99))

        print(failures == 0 ? "\nPreference layer is sound." : "\n\(failures) check(s) failed.")
        exit(failures == 0 ? 0 : 1)
    }
}

/// Walks the real Core Animation tree behind the shelf.
///
/// Liquid Glass is drawn by the window server, so it never shows up in an
/// offscreen render and there is no way to eyeball it without screen recording.
/// The layer tree still tells the truth: whether the material layer exists, how
/// big it is, and whether anything is sitting on top of it.
///
/// `Cowly.app/Contents/MacOS/Cowly --layer-dump`
@MainActor
enum LayerDump {
    static var isRequested: Bool { CommandLine.arguments.contains("--layer-dump") }

    static func run() {
        NotchWindowController.shared.install()
        let vm = NotchViewModel.shared
        vm.open(tab: .home)
        vm.isPinned = true

        Task {
            try? await Task.sleep(for: .milliseconds(900))
            guard let host = NotchWindowController.shared.panel?.contentView,
                  let layer = host.layer else {
                print("no host layer"); exit(1)
            }
            print("style: \(Preferences.shared.glassStyle.rawValue), dimming: \(NotchViewModel.shared.glassDimming)")
            print("host bounds: \(host.bounds)")
            print("shelf rect:  \(vm.currentRect)\n")
            walk(layer, depth: 0)
            exit(0)
        }
    }

    private static func walk(_ layer: CALayer, depth: Int) {
        guard depth < 7 else { return }
        let pad = String(repeating: "  ", count: depth)
        var notes: [String] = []
        if let color = layer.backgroundColor, let components = color.components, components.count >= 4 {
            notes.append(String(
                format: "bg rgba(%.2f %.2f %.2f %.2f)",
                components[0], components[1], components[2], components[3]
            ))
        }
        if layer.opacity < 1 { notes.append(String(format: "opacity %.2f", layer.opacity)) }
        if layer.mask != nil { notes.append("masked") }
        if layer.isHidden { notes.append("HIDDEN") }
        if let filters = layer.value(forKey: "filters") as? [Any], !filters.isEmpty {
            notes.append("filters \(filters.count)")
        }
        if let backdrop = layer.value(forKey: "backdropFilters") as? [Any], !backdrop.isEmpty {
            notes.append("BACKDROP \(backdrop.count)")
        }
        if layer.compositingFilter != nil { notes.append("compositing") }

        let size = layer.frame
        print(String(
            format: "%@%@  %.0f,%.0f %.0f×%.0f  %@",
            pad, String(describing: type(of: layer)),
            size.origin.x, size.origin.y, size.width, size.height,
            notes.joined(separator: " · ")
        ))
        for sublayer in layer.sublayers ?? [] { walk(sublayer, depth: depth + 1) }
    }
}
