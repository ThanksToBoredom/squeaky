import SwiftUI

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

/// The colour scheme for one module. Every screen is a full-bleed gradient that
/// shifts hue as you move between modules.
struct Palette: Equatable {
    let top: Color
    let bottom: Color
    let glow: Color
    let accent: Color
}

enum Module: String, CaseIterable, Identifiable {
    case sweep, cleanup, protection, performance, applications, declutter

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sweep: "Sweep"
        case .cleanup: "Cleanup"
        case .protection: "Protection"
        case .performance: "Performance"
        case .applications: "Applications"
        case .declutter: "Declutter"
        }
    }

    var symbol: String {
        switch self {
        case .sweep: "desktopcomputer"
        case .cleanup: "bubbles.and.sparkles.fill"
        case .protection: "svg:radar"
        case .performance: "bolt.fill"
        case .applications: "svg:apps"
        case .declutter: "folder.fill"
        }
    }

    var palette: Palette {
        switch self {
        case .sweep:
            Palette(top: Color(hex: 0x4B1FB0), bottom: Color(hex: 0x0A39A6), glow: Color(hex: 0x3F7BFF), accent: Color(hex: 0x5BA8FF))
        case .cleanup:
            Palette(top: Color(hex: 0x8A1CC0), bottom: Color(hex: 0x24095F), glow: Color(hex: 0xC423D6), accent: Color(hex: 0xE64BF5))
        case .protection:
            Palette(top: Color(hex: 0x2E7A1B), bottom: Color(hex: 0x08330F), glow: Color(hex: 0x5DBB2F), accent: Color(hex: 0x6EDB4C))
        case .performance:
            Palette(top: Color(hex: 0x0F8A86), bottom: Color(hex: 0x064A55), glow: Color(hex: 0x23B5A5), accent: Color(hex: 0x4FE0D0))
        case .applications:
            Palette(top: Color(hex: 0xB8440F), bottom: Color(hex: 0x561104), glow: Color(hex: 0xE8661E), accent: Color(hex: 0xFF9A4A))
        case .declutter:
            Palette(top: Color(hex: 0xA3174F), bottom: Color(hex: 0x3A0A28), glow: Color(hex: 0xE0407A), accent: Color(hex: 0xFF6FA5))
        }
    }

    var isAvailable: Bool { true }

    var welcomeTitle: String {
        self == .sweep ? "Welcome back!" : title
    }

    var welcomeSubtitle: String {
        switch self {
        case .sweep: "Start with a quick and extensive scan of your Mac."
        case .cleanup: "Get rid of caches, logs and other junk your Mac doesn't need."
        case .protection: "Check your apps, downloads and launch items with Apple's own malware signatures."
        case .performance: "See what's using your Mac and what starts in the background."
        case .applications: "Uninstall apps completely and sweep away what deleted apps left behind."
        case .declutter: "Find large files, old downloads and duplicates hiding in your folders."
        }
    }

    var scanningTitle: String {
        switch self {
        case .sweep: "Scanning your Mac…"
        case .cleanup: "Looking for junk…"
        case .applications: "Analyzing applications…"
        case .declutter: "Digging through…"
        case .protection: "Looking for threats…"
        default: "Scanning…"
        }
    }

    var actionVerb: String {
        switch self {
        case .cleanup: "Clean"
        case .applications, .declutter, .protection: "Remove"
        default: "Run"
        }
    }

    var reviewAllTitle: String {
        switch self {
        case .cleanup: "Review All Junk"
        case .applications: "Manage My Applications"
        case .declutter: "Review All Files"
        default: "Review All"
        }
    }

    var doneTitle: String {
        switch self {
        case .cleanup: "Cleanup complete!"
        case .applications: "Job done!"
        case .declutter: "All tidied up!"
        case .protection: "Threats removed!"
        default: "Well done!"
        }
    }

    func doneHeadline(_ summary: CleanSummary) -> String {
        switch self {
        case .cleanup, .sweep: "\(summary.freed.formattedBytes) of Junk"
        case .applications, .protection: summary.removed == 1 ? "1 item" : "\(summary.removed) items"
        default: summary.removed == 1 ? "1 file" : "\(summary.removed) files"
        }
    }

    var doneSubtitle: String {
        switch self {
        case .cleanup, .sweep: "successfully cleaned"
        case .applications: "successfully moved to the Trash"
        default: "moved to the Trash"
        }
    }
}
