import SwiftUI

/// Metadata for one optional feature. Droplets are inert until switched on, so
/// turning everything off leaves nothing but the shelf itself running.
struct Droplet: Identifiable, Hashable, Sendable {
    enum Category: String, CaseIterable, Sendable {
        case productivity = "Productivity"
        case system = "System"
        case media = "Media"
        case tools = "Tools"
    }

    let id: String
    let name: String
    let summary: String
    let symbol: String
    let tint: Color
    let category: Category
    /// Droplets with a widget can be placed on the Home shelf.
    let hasWidget: Bool
    /// Droplets that want a full pane get one on the Droplets tab.
    let hasPane: Bool

    static let all: [Droplet] = [
        Droplet(id: "pomodoro", name: "Pomodoro", summary: "Focus timer with live progress in the notch.",
                symbol: "timer", tint: .red, category: .productivity, hasWidget: true, hasPane: true),
        Droplet(id: "timer", name: "Timers", summary: "Countdowns you start straight from the island.",
                symbol: "hourglass", tint: .orange, category: .productivity, hasWidget: true, hasPane: true),
        Droplet(id: "notes", name: "Notes", summary: "Quick notes that live on your shelf.",
                symbol: "note.text", tint: .yellow, category: .productivity, hasWidget: true, hasPane: true),
        Droplet(id: "calendar", name: "Calendar", summary: "Your next events, without leaving the notch.",
                symbol: "calendar", tint: .pink, category: .productivity, hasWidget: true, hasPane: true),
        Droplet(id: "clipboard", name: "Clipboard", summary: "Every copy you make, kept and searchable.",
                symbol: "doc.on.clipboard", tint: Theme.Palette.accent, category: .tools, hasWidget: true, hasPane: true),
        Droplet(id: "highalert", name: "High Alert", summary: "Keep your Mac awake on demand.",
                symbol: "cup.and.saucer.fill", tint: .brown, category: .system, hasWidget: true, hasPane: false),
        Droplet(id: "stats", name: "System Stats", summary: "Live CPU, memory and disk on your shelf.",
                symbol: "chart.bar.fill", tint: .mint, category: .system, hasWidget: true, hasPane: true),
        Droplet(id: "battery", name: "Battery", summary: "Charge alerts and time remaining.",
                symbol: "battery.100.bolt", tint: Theme.Palette.positive, category: .system, hasWidget: true, hasPane: false),
        Droplet(id: "weather", name: "Weather", summary: "Live local weather, no account needed.",
                symbol: "cloud.sun.fill", tint: .cyan, category: .tools, hasWidget: true, hasPane: true),
        Droplet(id: "audio", name: "Audio Output", summary: "Switch output device and volume in one tap.",
                symbol: "hifispeaker.2.fill", tint: .purple, category: .media, hasWidget: true, hasPane: true),
        Droplet(id: "emoji", name: "Emoji Picker", summary: "Your emoji, one click away.",
                symbol: "face.smiling", tint: .yellow, category: .tools, hasWidget: false, hasPane: true),
        Droplet(id: "camera", name: "Camera", summary: "A live camera preview in your notch.",
                symbol: "video.fill", tint: .indigo, category: .tools, hasWidget: false, hasPane: true),
        Droplet(id: "aiusage", name: "AI Limits", summary: "How much of your Claude, Codex and Gemini allowance is left.",
                symbol: "gauge.with.dots.needle.33percent", tint: Theme.Palette.accent, category: .tools, hasWidget: true, hasPane: true),
        Droplet(id: "shortcuts", name: "Quick Actions", summary: "Screenshot, lock, sleep and Finder in one row.",
                symbol: "bolt.square.fill", tint: .teal, category: .tools, hasWidget: true, hasPane: false)
    ]

    static func find(_ id: String) -> Droplet? { all.first { $0.id == id } }

    static var byCategory: [(Category, [Droplet])] {
        Category.allCases.compactMap { category in
            let items = all.filter { $0.category == category }
            return items.isEmpty ? nil : (category, items)
        }
    }
}

@MainActor
extension Preferences {
    /// Enabled droplets in the order the user arranged them.
    var orderedShelfDroplets: [Droplet] {
        let enabled = Droplet.all.filter { enabledDroplets.contains($0.id) && $0.hasWidget }
        guard !shelfOrder.isEmpty else { return enabled }
        let index = Dictionary(uniqueKeysWithValues: shelfOrder.enumerated().map { ($1, $0) })
        return enabled.sorted { (index[$0.id] ?? .max) < (index[$1.id] ?? .max) }
    }

    var enabledPanes: [Droplet] {
        Droplet.all.filter { enabledDroplets.contains($0.id) && $0.hasPane }
    }
}
